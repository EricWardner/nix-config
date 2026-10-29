//! webcam-watch: tells the bar whether cameras are present, enabled (see
//! webcam-toggle) and streaming, whenever that changes.
//!
//! "Streaming" comes from sysfs: a UVC camera moves its VideoStreaming
//! interface (class 0e, subclass 02) off alternate setting 0 only while it
//! captures. The kernel sends no notification for that, so it is checked
//! once a second, but only while a camera is enabled. Cameras coming and
//! going (hotplug, webcam-toggle) are seen at once through inotify on /dev.
//! Unplugging a toggled-off camera touches only /dev/bus/usb, so while
//! cameras are off a slow poll notices that. Bulk-transfer cameras stream
//! on alt 0 and never show in use.

use std::fs;
use std::os::fd::OwnedFd;
use std::path::{Path, PathBuf};
use std::time::Duration;

use bar_tools::inotify::{self, WatchFlags};
use bar_tools::state::Emitter;
use rustix::event::{PollFd, PollFlags};

/// How often to look for streaming while a camera is enabled.
const POLL: Duration = Duration::from_secs(1);
/// How often to look for unplugged cameras while they are toggled off.
const OFF_POLL: Duration = Duration::from_secs(10);
/// webcam-toggle (root, via sudo) records the cameras it deauthorized here;
/// their video4linux entries disappear while they are off.
const STATE_FILE: &str = "/run/webcam-toggle/usb-paths";

/// A USB camera: its device directory and VideoStreaming interfaces.
struct Camera {
    device: PathBuf,
    streaming: Vec<PathBuf>,
}

#[derive(Clone, Copy)]
enum State {
    NoCamera,
    Off,
    Available,
    InUse,
}

fn main() {
    let mut out = Emitter::default();
    // Any node appearing or disappearing in /dev means "rescan".
    let dev_events = inotify::watch(Path::new("/dev"), WatchFlags::CREATE | WatchFlags::DELETE)
        .inspect_err(|e| {
            bar_tools::warn!("webcam-watch: can't watch /dev ({e}); rescanning every poll");
        })
        .ok();

    let mut cameras = scan();
    loop {
        // A camera unplugged just as we rescanned can linger in the list:
        // the kernel drops its /dev node before its video4linux link.
        if cameras.iter().any(|c| !c.device.exists()) {
            cameras = scan();
        }
        let state = probe(&cameras);
        render(&mut out, state);

        let timeout = match state {
            State::Available | State::InUse => Some(POLL),
            State::Off => Some(OFF_POLL),
            State::NoCamera => None,
        };
        if wait(dev_events.as_ref(), timeout) {
            cameras = scan();
        }
    }
}

/// Sleep until /dev changes or `timeout` passes. Returns whether to rescan.
/// Without inotify, rescan every `POLL` instead.
fn wait(dev_events: Option<&OwnedFd>, timeout: Option<Duration>) -> bool {
    let Some(fd) = dev_events else {
        std::thread::sleep(POLL);
        return true;
    };
    let mut fds = [PollFd::new(fd, PollFlags::IN)];
    match bar_tools::poll(&mut fds, timeout) {
        Ok(0) => false,
        Ok(_) => {
            inotify::drain(fd);
            true
        }
        Err(e) => {
            bar_tools::warn!("webcam-watch: poll: {e}");
            std::thread::sleep(POLL);
            true
        }
    }
}

/// Find the USB cameras behind /sys/class/video4linux. Deauthorized cameras
/// have no video4linux entries, so fall back to webcam-toggle's record.
fn scan() -> Vec<Camera> {
    let mut cameras: Vec<Camera> = Vec::new();
    let nodes = fs::read_dir("/sys/class/video4linux").into_iter().flatten();
    // video* only, matching what webcam-toggle switches (not radio*, vbi*, ...)
    let nodes = nodes
        .flatten()
        .filter(|n| n.file_name().to_string_lossy().starts_with("video"));
    for node in nodes {
        let Ok(node) = fs::canonicalize(node.path().join("device")) else {
            continue; // virtual device (e.g. v4l2loopback)
        };
        let Some(device) = node
            .ancestors()
            .find(|d| d.join("authorized").exists() && d.join("idVendor").exists())
        else {
            continue; // not a USB camera
        };
        if cameras.iter().all(|c| c.device != device) {
            cameras.push(Camera {
                streaming: streaming_interfaces(device),
                device: device.to_owned(),
            });
        }
    }

    if cameras.is_empty()
        && let Ok(saved) = fs::read_to_string(STATE_FILE)
    {
        cameras = saved
            .lines()
            .map(Path::new)
            .filter(|p| p.join("authorized").exists())
            .map(|p| Camera {
                device: p.to_owned(),
                streaming: Vec::new(),
            })
            .collect();
    }
    cameras
}

/// The camera's UVC VideoStreaming interfaces (class 0e, subclass 02).
fn streaming_interfaces(device: &Path) -> Vec<PathBuf> {
    let Some(name) = device.file_name() else {
        return Vec::new();
    };
    let prefix = format!("{}:", name.to_string_lossy());
    let entries = fs::read_dir(device).into_iter().flatten().flatten();
    entries
        .filter(|e| e.file_name().to_string_lossy().starts_with(&prefix))
        .map(|e| e.path())
        .filter(|i| {
            attr(i, "bInterfaceClass").as_deref() == Some("0e")
                && attr(i, "bInterfaceSubClass").as_deref() == Some("02")
        })
        .collect()
}

fn probe(cameras: &[Camera]) -> State {
    if cameras.is_empty() {
        return State::NoCamera;
    }
    let mut enabled = cameras
        .iter()
        .filter(|c| attr(&c.device, "authorized").as_deref() == Some("1"))
        .peekable();
    if enabled.peek().is_none() {
        return State::Off;
    }
    let streaming = enabled
        .flat_map(|c| &c.streaming)
        .any(|i| attr(i, "bAlternateSetting").is_some_and(|alt| alt != "0"));
    if streaming {
        State::InUse
    } else {
        State::Available
    }
}

/// A sysfs attribute's value, trimmed (`bAlternateSetting` is space-padded).
fn attr(dir: &Path, name: &str) -> Option<String> {
    fs::read_to_string(dir.join(name))
        .ok()
        .map(|s| s.trim().to_owned())
}

fn render(out: &mut Emitter, state: State) {
    out.emit(match state {
        State::NoCamera => "disconnected",
        State::Off => "muted",
        State::InUse => "in-use",
        State::Available => "available",
    });
}
