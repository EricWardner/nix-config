//! waybar `custom/volume`: prints the default output's volume and mute state
//! whenever either changes, showing the percentage for a moment after each
//! change. Sleeps on the audio server socket in between.

use std::convert::Infallible;
use std::time::{Duration, Instant};

use bar_tools::pa::{self, Conn, DeviceVolume, Frame};
use bar_tools::sf;
use bar_tools::waybar::{self, Emitter};
use pulseaudio::protocol::{Command, DEFAULT_SINK, GetSinkInfo, PulseError, SubscriptionMask};
use rustix::event::{PollFd, PollFlags};

/// How long the percentage stays visible after a change.
const FLASH: Duration = Duration::from_secs(2);
/// An event burst ends after this much quiet, or after `SETTLE_MAX`, so a
/// burst costs one query but dragging a slider still updates the bar.
const SETTLE: Duration = Duration::from_millis(15);
const SETTLE_MAX: Duration = Duration::from_millis(100);
const RECONNECT: Duration = Duration::from_secs(2);

#[derive(Clone, PartialEq)]
struct Volume {
    /// The output's description, shown in the tooltip; switching outputs
    /// counts as a change, so it flashes the new output's level.
    device: String,
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
        out.emit(sf::SPEAKER_SLASH, "Audio server unavailable", "muted");
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
            if shown.as_ref().is_some_and(|prev| *prev != reading) {
                flash_until = Some(Instant::now() + FLASH);
            }
            shown = Some(reading);
        }

        // Expire the flash here, whatever woke us, so a stream of unrelated
        // events can't keep it on screen.
        let now = Instant::now();
        flash_until = flash_until.filter(|&t| t > now);
        let reading = shown.as_ref().and_then(Option::as_ref);
        render(out, reading, flash_until.is_some());
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
            device: dev.description,
            percent: dev.percent,
            muted: dev.muted,
        })),
        Err(pa::Error::Server(PulseError::NoEntity)) => Ok(None),
        Err(e) => Err(e),
    }
}

fn render(out: &mut Emitter, reading: Option<&Volume>, flash: bool) {
    let Some(v) = reading else {
        return out.emit(sf::SPEAKER_SLASH, "No output device", "muted");
    };
    let icon = match v.percent {
        _ if v.muted => sf::SPEAKER_SLASH,
        0..33 => sf::SPEAKER_WAVE_1,
        33..67 => sf::SPEAKER_WAVE_2,
        _ => sf::SPEAKER_WAVE_3,
    };
    let class = if v.muted { "muted" } else { "" };
    let tooltip = if v.device.is_empty() {
        format!("Volume: {}%", v.percent)
    } else {
        format!("{}\nVolume: {}%", v.device, v.percent)
    };
    if flash {
        let text = format!("{icon} {}", waybar::number(&format!("{}%", v.percent)));
        out.emit_markup(&text, &tooltip, class);
    } else {
        out.emit(icon, &tooltip, class);
    }
}
