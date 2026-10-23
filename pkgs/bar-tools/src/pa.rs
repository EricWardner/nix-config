//! Minimal blocking client for the PulseAudio native protocol, as served by
//! pipewire-pulse. It speaks the wire format directly (through the
//! `pulseaudio` crate's protocol layer), so the tools link no C audio
//! libraries and stay single-threaded.
//!
//! Requests and subscription events share one socket. Callers either block in
//! [`Conn::request`] or drive their own `poll` loop with [`Conn::read_frame`]
//! (the connection is `AsFd`).

use std::ffi::CString;
use std::fmt;
use std::io::{self, Cursor, Read, Write};
use std::os::fd::{AsFd, BorrowedFd};
use std::os::unix::net::UnixStream;
use std::time::{Duration, Instant};

use pulseaudio::protocol::{
    self, ChannelMap, ChannelVolume, Command, CommandTag, ProtocolError, PulseError, SampleSpec,
    TagStructRead, TagStructReader,
};
use rustix::event::{PollFd, PollFlags};

/// A server that stops answering mid-message is treated as gone.
const IO_TIMEOUT: Duration = Duration::from_secs(5);
/// Upper bound on one message, so a corrupt length can't make us allocate
/// gigabytes. Info replies are a few KiB.
const MAX_FRAME: usize = protocol::MAX_MEMBLOCKQ_LENGTH;

#[derive(Debug)]
pub enum Error {
    /// The socket failed, closed or timed out; reconnect.
    Io(io::Error),
    /// A message was malformed at the framing level; reconnect.
    Protocol(ProtocolError),
    /// A reply's body could not be decoded. The message was consumed whole,
    /// so the connection is still usable; retry the request later.
    Decode(ProtocolError),
    /// The server rejected a request (e.g. no such device).
    Server(PulseError),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "audio server connection: {e}"),
            Error::Protocol(e) => write!(f, "audio server protocol: {e}"),
            Error::Decode(e) => write!(f, "undecodable reply: {e}"),
            Error::Server(e) => write!(f, "audio server refused request: {e}"),
        }
    }
}

impl From<io::Error> for Error {
    fn from(e: io::Error) -> Self {
        Error::Io(e)
    }
}

impl From<ProtocolError> for Error {
    fn from(e: ProtocolError) -> Self {
        Error::Protocol(e)
    }
}

impl From<rustix::io::Errno> for Error {
    fn from(e: rustix::io::Errno) -> Self {
        Error::Io(e.into())
    }
}

/// One message from the server.
pub enum Frame {
    /// Reply to the request with sequence number `seq`; decode with
    /// [`Conn::parse`].
    Reply { seq: u32, payload: Vec<u8> },
    /// The request with sequence number `seq` failed.
    Error { seq: u32, error: Option<PulseError> },
    /// A subscription event.
    Event(protocol::SubscriptionEvent),
    /// Anything else the server may push; safe to ignore.
    Other,
}

pub struct Conn {
    sock: UnixStream,
    version: u16,
    next_seq: u32,
    /// Encoded commands waiting for [`Conn::flush`].
    outbox: Vec<u8>,
    missed_events: bool,
}

impl AsFd for Conn {
    fn as_fd(&self) -> BorrowedFd<'_> {
        self.sock.as_fd()
    }
}

impl Conn {
    /// Connect to the user's audio server and complete the handshake.
    pub fn connect(client_name: &str) -> Result<Conn, Error> {
        let path = pulseaudio::socket_path_from_env()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no PulseAudio socket"))?;
        let sock = UnixStream::connect(path)?;
        sock.set_read_timeout(Some(IO_TIMEOUT))?;
        sock.set_write_timeout(Some(IO_TIMEOUT))?;
        let mut conn = Conn {
            sock,
            version: protocol::MAX_VERSION,
            next_seq: 0,
            outbox: Vec::new(),
            missed_events: false,
        };

        // pipewire-pulse doesn't check the cookie, but send it if one exists
        // so this also works against a real PulseAudio.
        let cookie = pulseaudio::cookie_path_from_env()
            .and_then(|p| std::fs::read(p).ok())
            .unwrap_or_default();
        let auth: protocol::AuthReply = conn.request(&Command::Auth(protocol::AuthParams {
            version: protocol::MAX_VERSION,
            supports_shm: false,
            supports_memfd: false,
            cookie,
        }))?;
        conn.version = auth.version.min(protocol::MAX_VERSION);

        let mut props = protocol::Props::new();
        let name = CString::new(client_name).map_err(io::Error::other)?;
        props.set(protocol::Prop::ApplicationName, name);
        let _: protocol::SetClientNameReply = conn.request(&Command::SetClientName(props))?;
        Ok(conn)
    }

    /// Encode a command into the outbox without sending it, so a batch of
    /// commands goes out in one write. Returns its sequence number.
    pub fn queue(&mut self, cmd: &Command) -> Result<u32, Error> {
        let seq = self.next_seq;
        self.next_seq = self.next_seq.wrapping_add(1);
        let mut buf = Vec::new();
        let len = protocol::encode_command_message(&mut buf, seq, cmd, self.version)?;
        self.outbox.extend_from_slice(&buf[..len]);
        Ok(seq)
    }

    pub fn flush(&mut self) -> Result<(), Error> {
        self.sock.write_all(&self.outbox)?;
        self.outbox.clear();
        Ok(())
    }

    pub fn send(&mut self, cmd: &Command) -> Result<u32, Error> {
        let seq = self.queue(cmd)?;
        self.flush()?;
        Ok(seq)
    }

    /// Send a request and block until its reply arrives. Replies to any
    /// other outstanding requests are discarded (errors are logged), so read
    /// those through [`Conn::read_frame`] instead of mixing the two.
    pub fn request<T: TagStructRead>(&mut self, cmd: &Command) -> Result<T, Error> {
        self.missed_events = false;
        let seq = self.send(cmd)?;
        loop {
            match self.read_frame()? {
                Frame::Reply { seq: s, payload } if s == seq => return self.parse(&payload),
                Frame::Error { seq: s, error } if s == seq => {
                    return Err(Error::Server(error.unwrap_or(PulseError::Unknown)));
                }
                Frame::Error { seq: s, error } => crate::warn!("request {s} failed: {error:?}"),
                Frame::Event(_) => self.missed_events = true,
                _ => {}
            }
        }
    }

    /// Like [`Conn::request`] for commands whose reply is a bare ack.
    pub fn request_ack(&mut self, cmd: &Command) -> Result<(), Error> {
        self.request::<Ack>(cmd).map(|_| ())
    }

    /// The capture sources, i.e. every source except sink monitors.
    pub fn capture_sources(&mut self) -> Result<Vec<CaptureSource>, Error> {
        let CaptureSourceList(sources) = self.request(&Command::GetSourceInfoList)?;
        Ok(sources)
    }

    /// Queue a mute change for the source with this index.
    pub fn queue_source_mute(&mut self, index: u32, mute: bool) -> Result<u32, Error> {
        self.queue(&source_mute(index, mute))
    }

    /// Whether subscription events arrived while the last [`Conn::request`]
    /// waited, i.e. whether its answer may already be stale.
    pub fn missed_events(&self) -> bool {
        self.missed_events
    }

    /// Discard incoming messages until the server has been quiet for
    /// `quiet`, or `max` has passed, so a burst of events costs one
    /// re-query. Only call with no requests outstanding.
    pub fn drain_burst(&mut self, quiet: Duration, max: Duration) -> Result<(), Error> {
        let deadline = Instant::now() + max;
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            if left.is_zero() {
                return Ok(());
            }
            let mut fds = [PollFd::new(&self.sock, PollFlags::IN)];
            if crate::poll(&mut fds, Some(quiet.min(left)))? == 0 {
                return Ok(());
            }
            self.read_frame()?;
        }
    }

    /// Read one whole message. Blocks until it arrives.
    pub fn read_frame(&mut self) -> Result<Frame, Error> {
        let mut desc = [0u8; protocol::DESCRIPTOR_SIZE];
        self.sock.read_exact(&mut desc)?;
        let desc = protocol::read_descriptor(&mut &desc[..])?;
        let len = desc.length as usize;
        if len > MAX_FRAME {
            return Err(Error::Protocol(ProtocolError::Invalid(format!(
                "{len}-byte message"
            ))));
        }
        let mut payload = vec![0u8; len];
        self.sock.read_exact(&mut payload)?;
        if desc.channel != u32::MAX {
            // audio data for a stream; we never open one
            return Ok(Frame::Other);
        }

        let mut cur = Cursor::new(&payload[..]);
        let mut ts = TagStructReader::new(&mut cur, self.version);
        let (Ok(tag), Ok(seq)) = (ts.read_enum::<CommandTag>(), ts.read_u32()) else {
            return Ok(Frame::Other);
        };
        Ok(match tag {
            CommandTag::Reply => Frame::Reply { seq, payload },
            CommandTag::Error => Frame::Error {
                seq,
                error: ts.read_enum().ok(),
            },
            CommandTag::SubscribeEvent => ts.read().map_or(Frame::Other, Frame::Event),
            _ => Frame::Other,
        })
    }

    /// Decode the body of a [`Frame::Reply`].
    pub fn parse<T: TagStructRead>(&self, payload: &[u8]) -> Result<T, Error> {
        decode(payload, self.version).map_err(Error::Decode)
    }
}

fn decode<T: TagStructRead>(payload: &[u8], version: u16) -> Result<T, ProtocolError> {
    let mut cur = Cursor::new(payload);
    let mut ts = TagStructReader::new(&mut cur, version);
    ts.read_enum::<CommandTag>()?;
    ts.read_u32()?;
    T::read(&mut ts, version)
}

pub fn source_mute(index: u32, mute: bool) -> Command {
    Command::SetSourceMute(protocol::SetDeviceMuteParams {
        device_index: Some(index),
        device_name: None,
        mute,
    })
}

pub struct CaptureSource {
    pub index: u32,
    pub muted: bool,
}

/// A source list reply, keeping only the capture sources. It is decoded
/// without the `pulseaudio` crate's strict checks, which reject the states
/// pipewire-pulse reports for devices being created or in error (exactly
/// when a mic is hotplugged) and unknown port or format values, failing the
/// whole list. This walks the same fields as the crate's `SourceInfo`, gated
/// by protocol version the same way, but reads those values as raw numbers.
struct CaptureSourceList(Vec<CaptureSource>);

impl TagStructRead for CaptureSourceList {
    fn read(ts: &mut TagStructReader<'_>, version: u16) -> Result<Self, ProtocolError> {
        let mut sources = Vec::new();
        while ts.has_data_left()? {
            let index = ts
                .read_index()?
                .ok_or_else(|| ProtocolError::Invalid("invalid source index".into()))?;
            ts.read_string()?; // name
            ts.read_string()?; // description
            ts.read::<SampleSpec>()?;
            ts.read::<ChannelMap>()?;
            ts.read_index()?; // owner module
            ts.read::<ChannelVolume>()?;
            let muted = ts.read_bool()?;
            let monitor_of_sink = ts.read_index()?;
            ts.read_string()?; // monitored sink's name
            ts.read_usec()?; // latency
            ts.read_string()?; // driver
            ts.read_u32()?; // flags
            if version >= 13 {
                ts.read::<protocol::Props>()?;
                ts.read_usec()?; // configured latency
            }
            if version >= 15 {
                ts.read::<protocol::Volume>()?; // base volume
                ts.read_u32()?; // state
                ts.read_u32()?; // volume steps
                ts.read_index()?; // card
            }
            if version >= 16 {
                for _ in 0..ts.read_u32()? {
                    ts.read_string()?; // port name
                    ts.read_string()?; // port description
                    ts.read_u32()?; // priority
                    if version >= 24 {
                        ts.read_u32()?; // availability
                    }
                    if version >= 34 {
                        ts.read_string()?; // availability group
                        ts.read_u32()?; // port type
                    }
                }
                ts.read_string()?; // active port
            }
            if version >= 21 {
                for _ in 0..ts.read_u8()? {
                    if ts.read_tag()? != protocol::Tag::FormatInfo {
                        return Err(ProtocolError::Invalid("expected format info".into()));
                    }
                    ts.read_u8()?; // encoding
                    ts.read::<protocol::Props>()?;
                }
            }
            if monitor_of_sink.is_none() {
                sources.push(CaptureSource { index, muted });
            }
        }
        Ok(CaptureSourceList(sources))
    }
}

/// An empty reply body.
struct Ack;

impl TagStructRead for Ack {
    fn read(_: &mut TagStructReader<'_>, _: u16) -> Result<Self, ProtocolError> {
        Ok(Ack)
    }
}

/// The leading fields of a sink or source info reply (identical for both),
/// which is all the tools need. They come before the state and format
/// fields that the `pulseaudio` crate decodes strictly: it rejects the
/// states pipewire-pulse reports for devices being created or in error, and
/// newer passthrough formats. Reading only this prefix sidesteps both.
pub struct DeviceVolume {
    pub index: u32,
    /// Average channel volume on the user-facing scale (pavucontrol /
    /// wpctl), where 100% is unamplified.
    pub percent: u32,
    pub muted: bool,
    /// For a source, the sink it monitors (sink monitors aren't
    /// microphones); for a sink, its monitor source.
    pub monitor: Option<u32>,
}

impl TagStructRead for DeviceVolume {
    fn read(ts: &mut TagStructReader<'_>, _: u16) -> Result<Self, ProtocolError> {
        let index = ts
            .read_index()?
            .ok_or_else(|| ProtocolError::Invalid("invalid device index".into()))?;
        ts.read_string()?; // name
        ts.read_string()?; // description
        ts.read::<SampleSpec>()?;
        ts.read::<ChannelMap>()?;
        ts.read_index()?; // owner module
        let volume: ChannelVolume = ts.read()?;
        let muted = ts.read_bool()?;
        let monitor = ts.read_index()?;
        Ok(DeviceVolume {
            index,
            percent: percent(&volume),
            muted,
            monitor,
        })
    }
}

fn percent(volume: &ChannelVolume) -> u32 {
    let channels = volume.channels();
    if channels.is_empty() {
        return 0;
    }
    let sum: u64 = channels.iter().map(|v| u64::from(v.as_u32())).sum();
    let avg = sum / channels.len() as u64;
    let norm = u64::from(protocol::Volume::NORM.as_u32());
    ((avg * 100 + norm / 2) / norm) as u32
}
