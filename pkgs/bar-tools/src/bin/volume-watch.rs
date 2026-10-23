//! waybar `custom/volume`: prints the default output's volume and mute state
//! whenever either changes, showing the percentage for a moment after each
//! change. Sleeps on the audio server socket in between.

use std::convert::Infallible;
use std::time::{Duration, Instant};

use bar_tools::pa::{self, Conn, DeviceVolume, Frame};
use bar_tools::waybar::Emitter;
use pulseaudio::protocol::{Command, DEFAULT_SINK, GetSinkInfo, PulseError, SubscriptionMask};
use rustix::event::{PollFd, PollFlags};

/// How long the percentage stays visible after a change.
const FLASH: Duration = Duration::from_secs(2);
/// An event burst ends after this much quiet, or after `SETTLE_MAX`, so a
/// burst costs one query but dragging a slider still updates the bar.
const SETTLE: Duration = Duration::from_millis(15);
const SETTLE_MAX: Duration = Duration::from_millis(100);
const RECONNECT: Duration = Duration::from_secs(2);

#[derive(Clone, Copy, PartialEq)]
struct Volume {
    percent: u32,
    muted: bool,
}

/// `None` means there is no default output device.
type Reading = Option<Volume>;

fn main() {
    let mut out = Emitter::default();
    loop {
        let Err(err) = run(&mut out);
        bar_tools::warn!("volume-watch: {err}; reconnecting");
        out.emit("󰝟", "Audio server unavailable", "muted");
        std::thread::sleep(RECONNECT);
    }
}

fn run(out: &mut Emitter) -> Result<Infallible, pa::Error> {
    let mut conn = Conn::connect("volume-watch")?;
    // Sink events cover volume/mute; server events cover the default
    // output changing.
    conn.request_ack(&Command::Subscribe(
        SubscriptionMask::SINK | SubscriptionMask::SERVER,
    ))?;

    // The first reading after (re)connecting never flashes.
    let mut shown: Option<Reading> = None;
    let mut flash_until: Option<Instant> = None;
    let mut dirty = true;
    loop {
        if dirty {
            conn.drain_burst(SETTLE, SETTLE_MAX)?;
            let reading = query(&mut conn)?;
            dirty = conn.missed_events();
            if shown.is_some_and(|prev| prev != reading) {
                flash_until = Some(Instant::now() + FLASH);
            }
            shown = Some(reading);
        }

        // Expire the flash here, whatever woke us, so a stream of unrelated
        // events can't keep it on screen.
        let now = Instant::now();
        flash_until = flash_until.filter(|&t| t > now);
        render(out, shown.flatten(), flash_until.is_some());
        if dirty {
            continue;
        }

        let timeout = flash_until.map(|t| t - now);
        let mut fds = [PollFd::new(&conn, PollFlags::IN)];
        if bar_tools::poll(&mut fds, timeout)? > 0 {
            dirty = matches!(conn.read_frame()?, Frame::Event(_));
        }
    }
}

fn query(conn: &mut Conn) -> Result<Reading, pa::Error> {
    let req = Command::GetSinkInfo(GetSinkInfo {
        index: None,
        name: Some(DEFAULT_SINK.to_owned()),
    });
    match conn.request::<DeviceVolume>(&req) {
        Ok(dev) => Ok(Some(Volume {
            percent: dev.percent,
            muted: dev.muted,
        })),
        Err(pa::Error::Server(PulseError::NoEntity)) => Ok(None),
        Err(e) => Err(e),
    }
}

fn render(out: &mut Emitter, reading: Reading, flash: bool) {
    let Some(v) = reading else {
        return out.emit("󰝟", "No output device", "muted");
    };
    let icon = match v.percent {
        _ if v.muted => "󰝟",
        0..33 => "󰕿",
        33..67 => "󰖀",
        _ => "󰕾",
    };
    let class = if v.muted { "muted" } else { "" };
    let tooltip = format!("Volume: {}%", v.percent);
    if flash {
        out.emit(&format!("{icon}  {}%", v.percent), &tooltip, class);
    } else {
        out.emit(icon, &tooltip, class);
    }
}
