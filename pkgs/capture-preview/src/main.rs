//! capture-preview: a screen recording or screenshot in a glass panel in the
//! middle of the screen, with what to do with it. screen-record and
//! screenshot open it as soon as a recording or shot is done (and the bar's
//! "Saved" opens a recording again).
//!
//! An MP4 plays in GtkVideo (GStreamer, decoded on the GPU through VA-API),
//! with play/pause and a seek bar on hover; Convert to GIF makes the GIF next
//! to it, after which Copy GIF takes the button's place. The bar under it
//! has a handle at each end: drag them in and Trim cuts the recording down
//! to the part between them, in place. A GIF is decoded
//! frame by frame as it plays (gif + gif-dispose), so a long one costs one
//! frame of memory, not all of them. A screenshot (PNG, JPEG or WebP) offers
//! Annotate, which opens it in Satty.
//!
//! Usage: capture-preview [--css FILE] [--gif-size WxH] [--save-dir DIR] FILE
//!   --gif-size  the GIF's size, normally the recorded area's on-screen
//!               size (the MP4 is at the monitor's scale); default the MP4's
//!   --save-dir  FILE is a screenshot not kept yet: Copy, or Save… with a
//!               dialog that starts in DIR, in place of a file's actions

use std::cell::{Cell, RefCell};
use std::fs::File;
use std::io::BufReader;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::time::Duration;

use gtk::prelude::*;
use gtk::{gdk, gio, glib};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

/// The preview's largest size, in logical pixels.
const MAX_W: f64 = 720.0;
const MAX_H: f64 = 440.0;

/// The same conversion screen-record used to run on every recording: 30 fps,
/// ordered dithering and a palette from what changes between frames, about a
/// second for a 5 s clip with text staying sharp.
const GIF_FILTER: &str = "fps=30,scale={w}:{h}:flags=lanczos,split[s0][s1];\
    [s0]palettegen=stats_mode=diff[p];\
    [s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle";

/// The shortest part a trim keeps, in seconds.
const MIN_KEEP: f64 = 0.2;
/// The trim bar's handles, in logical pixels.
const HANDLE_W: f64 = 8.0;

/// The ffmpeg job running for Convert to GIF or Trim, with the hidden file it
/// writes. Only one runs at a time.
type Job = Rc<RefCell<Option<(Child, PathBuf)>>>;

/// What the file is, from its extension.
#[derive(Clone, Copy, PartialEq)]
enum Kind {
    /// A recording: an MP4, or anything else GStreamer plays
    Video,
    Gif,
    /// A screenshot
    Image,
}

impl Kind {
    fn of(path: &Path) -> Self {
        match extension(path).as_deref() {
            Some("gif") => Self::Gif,
            Some("png" | "jpg" | "jpeg" | "webp") => Self::Image,
            _ => Self::Video,
        }
    }
}

/// The file's extension in lower case.
fn extension(path: &Path) -> Option<String> {
    path.extension()
        .and_then(|e| e.to_str())
        .map(str::to_ascii_lowercase)
}

struct Options {
    css: Option<PathBuf>,
    gif_size: Option<(u32, u32)>,
    save_dir: Option<PathBuf>,
    file: PathBuf,
}

fn parse_args() -> Result<Options, String> {
    let mut css = None;
    let mut gif_size = None;
    let mut save_dir = None;
    let mut file = None;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--css" => css = Some(PathBuf::from(args.next().ok_or("--css needs a file")?)),
            "--gif-size" => {
                let value = args.next().ok_or("--gif-size needs WxH")?;
                gif_size = Some(parse_size(&value).ok_or("--gif-size needs WxH")?);
            }
            "--save-dir" => {
                save_dir = Some(PathBuf::from(
                    args.next().ok_or("--save-dir needs a folder")?,
                ));
            }
            "-h" | "--help" => return Err(String::new()),
            _ if file.is_none() => file = Some(PathBuf::from(arg)),
            _ => return Err(format!("unexpected argument: {arg}")),
        }
    }
    let file = file.ok_or("no file given")?;
    Ok(Options {
        css,
        gif_size,
        save_dir,
        file,
    })
}

fn parse_size(s: &str) -> Option<(u32, u32)> {
    let (w, h) = s.split_once('x')?;
    Some((w.parse().ok()?, h.parse().ok()?))
}

fn main() -> glib::ExitCode {
    let opts = match parse_args() {
        Ok(opts) => opts,
        Err(e) => {
            if !e.is_empty() {
                eprintln!("capture-preview: {e}");
            }
            eprintln!("usage: capture-preview [--css FILE] [--gif-size WxH] [--save-dir DIR] FILE");
            return glib::ExitCode::from(2);
        }
    };
    let app = gtk::Application::builder()
        .application_id("io.github.capture-preview")
        .flags(gio::ApplicationFlags::NON_UNIQUE)
        .build();
    let opts = Rc::new(opts);
    app.connect_activate(move |app| build(app, &opts));
    // GTK must not see our arguments
    app.run_with_args::<&str>(&[])
}

/// A GIF played from the file, one composited frame at a time.
struct Player {
    path: PathBuf,
    decoder: gif::Decoder<BufReader<File>>,
    screen: gif_dispose::Screen,
    /// Whether this pass through the file has shown a frame.
    played: bool,
}

impl Player {
    fn open(path: &Path) -> Result<Self, gif::DecodingError> {
        let mut options = gif::DecodeOptions::new();
        options.set_color_output(gif::ColorOutput::Indexed);
        let decoder = options.read_info(BufReader::new(File::open(path)?))?;
        let screen = gif_dispose::Screen::new_decoder(&decoder);
        Ok(Self {
            path: path.to_owned(),
            decoder,
            screen,
            played: false,
        })
    }

    fn size(&self) -> (u32, u32) {
        (
            u32::from(self.decoder.width()),
            u32::from(self.decoder.height()),
        )
    }

    /// The next frame as a texture and how long to show it; at the end the
    /// file is opened again, so the GIF loops (unless it has no frames).
    fn next(&mut self) -> Option<(gdk::MemoryTexture, Duration)> {
        let delay = match self.decoder.read_next_frame() {
            Ok(Some(frame)) => {
                let delay = frame.delay;
                self.screen.blit_frame(frame).ok()?;
                self.played = true;
                delay
            }
            Ok(None) => {
                if !self.played {
                    return None;
                }
                *self = Self::open(&self.path).ok()?;
                return self.next();
            }
            Err(_) => return None,
        };
        let pixels = self.screen.pixels_rgba();
        let (w, h) = (pixels.width(), pixels.height());
        let mut bytes = Vec::with_capacity(w * h * 4);
        for row in pixels.rows() {
            for px in row {
                bytes.extend_from_slice(&[px.r, px.g, px.b, px.a]);
            }
        }
        let texture = gdk::MemoryTexture::new(
            i32::try_from(w).ok()?,
            i32::try_from(h).ok()?,
            gdk::MemoryFormat::R8g8b8a8,
            &glib::Bytes::from_owned(bytes),
            w * 4,
        );
        // GIF delays are in hundredths of a second; browsers treat 0 and 1
        // as 10, and so does this
        let cs = if delay < 2 { 10 } else { u64::from(delay) };
        Some((texture, Duration::from_millis(cs * 10)))
    }
}

/// An MP4's size and length, from ffprobe.
fn probe(path: &Path) -> Option<(u32, u32, f64)> {
    let out = Command::new("ffprobe")
        .args([
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height:format=duration",
            "-of",
            "default=noprint_wrappers=1",
        ])
        .arg(path)
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let field = |key: &str| {
        text.lines()
            .find_map(|l| l.strip_prefix(key)?.strip_prefix('='))
            .map(str::to_owned)
    };
    Some((
        field("width")?.parse().ok()?,
        field("height")?.parse().ok()?,
        field("duration")
            .and_then(|d| d.parse().ok())
            .unwrap_or(0.0),
    ))
}

fn build(app: &gtk::Application, opts: &Options) {
    load_css(opts.css.as_deref());

    let window = gtk::ApplicationWindow::builder()
        .application(app)
        .title("Preview")
        .build();
    window.add_css_class("capture-preview");
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_namespace(Some("capture-preview"));
    window.set_keyboard_mode(KeyboardMode::Exclusive);
    // The whole monitor, dimmed a touch around the panel: a click anywhere
    // outside the panel closes it
    for edge in [Edge::Top, Edge::Right, Edge::Bottom, Edge::Left] {
        window.set_anchor(edge, true);
    }
    window.set_exclusive_zone(-1);

    let file = opts.file.clone();
    let kind = Kind::of(&file);
    let is_video = kind == Kind::Video;
    // A recording's GIF, from Convert to GIF (or a GIF itself)
    let gif = file.with_extension("gif");

    // The media, its size and a recording's length
    let mut recording = None;
    let (preview, (w, h), secs): (gtk::Widget, _, f64) = match kind {
        Kind::Gif => {
            let player = match Player::open(&file) {
                Ok(player) => player,
                Err(e) => return fail(app, &file, &e.to_string()),
            };
            let size = player.size();
            let picture = gtk::Picture::new();
            picture.set_content_fit(gtk::ContentFit::Contain);
            picture.set_can_shrink(true);
            play(Rc::new(RefCell::new(player)), picture.clone(), &window);
            (picture.upcast(), size, 0.0)
        }
        Kind::Image => {
            let texture = match gdk::Texture::from_filename(&file) {
                Ok(texture) => texture,
                Err(e) => return fail(app, &file, &e.to_string()),
            };
            let size = (
                texture.width().unsigned_abs(),
                texture.height().unsigned_abs(),
            );
            let picture = gtk::Picture::for_paintable(&texture);
            picture.set_content_fit(gtk::ContentFit::Contain);
            picture.set_can_shrink(true);
            (picture.upcast(), size, 0.0)
        }
        Kind::Video => {
            let Some((w, h, secs)) = probe(&file) else {
                return fail(app, &file, "not a video ffprobe can read");
            };
            let video = gtk::Video::for_file(Some(&gio::File::for_path(&file)));
            video.set_autoplay(true);
            // Its controls show only on hover; Tab would otherwise move the
            // focus into them while hidden, where it can't be seen
            video.set_can_focus(false);
            // (the trim bar loops it)
            recording = Some(video.clone());
            (video.upcast(), (w, h), secs)
        }
    };
    let length = Rc::new(Cell::new(secs));

    let panel = gtk::Box::new(gtk::Orientation::Vertical, 12);
    panel.add_css_class("panel");
    panel.set_halign(gtk::Align::Center);
    panel.set_valign(gtk::Align::Center);

    // Header: the file's name and what it is
    let name = file
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let title = gtk::Label::new(Some(&name));
    title.add_css_class("title");
    title.set_xalign(0.0);
    title.set_hexpand(true);
    title.set_ellipsize(gtk::pango::EllipsizeMode::Middle);
    // The name takes the room the video leaves it rather than widening the
    // panel past the video
    title.set_max_width_chars(1);
    let info = gtk::Label::new(None);
    info.add_css_class("dim");
    // The size, a recording's length, the file's size and its GIF's; again
    // after a conversion or a trim
    let describe = {
        let (info, file, gif, length) = (info.clone(), file.clone(), gif.clone(), length.clone());
        move || {
            let mut text = format!("{w} × {h}  ·  ");
            if is_video {
                let secs = length.get().round() as u64;
                text += &format!("{}:{:02}  ·  ", secs / 60, secs % 60);
            }
            text += &human_size(file_size(&file));
            if is_video && gif.exists() {
                text += &format!("  ·  GIF {}", human_size(file_size(&gif)));
            }
            info.set_text(&text);
        }
    };
    describe();
    let header = gtk::Box::new(gtk::Orientation::Horizontal, 12);
    header.append(&title);
    header.append(&info);
    panel.append(&header);

    // The media, fitted into MAX_W × MAX_H. A picture or video asks for its
    // full size, so it sits in a viewport that doesn't pass that up: the
    // viewport's size request is the size, and the media scales to it. It
    // keeps that size in a wider panel (a small recording) instead of
    // stretching, which GtkVideo fills with black bars.
    let scale = (MAX_W / f64::from(w)).min(MAX_H / f64::from(h)).min(1.0);
    let frame = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .vscrollbar_policy(gtk::PolicyType::Never)
        .propagate_natural_width(false)
        .propagate_natural_height(false)
        .width_request((f64::from(w) * scale).round() as i32)
        .height_request((f64::from(h) * scale).round() as i32)
        .child(&preview)
        .build();
    frame.add_css_class("preview-frame");
    frame.set_overflow(gtk::Overflow::Hidden);
    frame.set_halign(gtk::Align::Center);
    panel.append(&frame);

    // The actions: Delete set apart at the left; at the right, icons for the
    // quick ones, then the main one (Annotate, or the GIF button), the one
    // with words. The row is narrower than most media, so the media sets the
    // panel's width.
    let actions = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    panel.append(&actions);
    window.set_child(Some(&panel));

    let close = {
        let window = window.clone();
        move || window.close()
    };
    // Escape closes, and so does a click outside the panel
    let keys = gtk::EventControllerKey::new();
    keys.connect_key_pressed({
        let close = close.clone();
        move |_, key, _, _| {
            if key == gdk::Key::Escape {
                close();
                glib::Propagation::Stop
            } else {
                glib::Propagation::Proceed
            }
        }
    });
    window.add_controller(keys);
    let outside = gtk::GestureClick::new();
    outside.set_button(0);
    outside.connect_pressed({
        let (window, panel) = (window.clone(), panel.clone());
        move |gesture, _, x, y| {
            let inside = panel
                .compute_bounds(&window)
                .is_some_and(|b| b.contains_point(&gtk::graphene::Point::new(x as f32, y as f32)));
            if !inside {
                gesture.set_state(gtk::EventSequenceState::Claimed);
                window.close();
            }
        }
    });
    window.add_controller(outside);

    let copied = {
        let close = close.clone();
        move |button: &gtk::Button| {
            // a tick in place of the icon, or the word
            if button.icon_name().is_some() {
                button.set_icon_name("object-select-symbolic");
            } else {
                button.set_label("Copied");
            }
            let close = close.clone();
            glib::timeout_add_local_once(Duration::from_millis(600), close);
        }
    };
    // The image itself, for pasting into chat or a document
    let copy_image = {
        let copied = copied.clone();
        move |path: &Path, button: &gtk::Button| {
            if let Ok(f) = File::open(path) {
                spawn(
                    Command::new("wl-copy")
                        .args(["--type", image_type(path)])
                        .stdin(f),
                );
                copied(button);
            }
        }
    };
    let copy_gif = {
        let (gif, copy_image) = (gif.clone(), copy_image.clone());
        move |button: &gtk::Button| copy_image(&gif, button)
    };

    // A screenshot not kept yet (screenshot passes --save-dir): Copy, or
    // Save… where you choose; Annotate; Discard. Copy is the same icon as a
    // saved shot's, and Enter still presses it, so Save… isn't the accent.
    if let Some(dir) = opts.save_dir.clone().filter(|_| kind == Kind::Image) {
        let discard = icon_action("user-trash-symbolic", "Discard", &["destructive"], {
            let (file, close) = (file.clone(), close.clone());
            move |_| {
                let _ = std::fs::remove_file(&file);
                close();
            }
        });
        let annotate = icon_action("document-edit-symbolic", "Annotate", &[], {
            let (file, close) = (file.clone(), close.clone());
            move |_| {
                satty(&file, None);
                close();
            }
        });
        let copy = icon_action("edit-copy-symbolic", "Copy image", &[], {
            let (file, copy_image) = (file.clone(), copy_image.clone());
            move |button| copy_image(&file, button)
        });
        let save = action("Save…", &[], {
            let (window, file) = (window.clone(), file.clone());
            move |_| save_as(&window, &file, &dir)
        });
        place_actions(&actions, &[discard, annotate, copy.clone(), save]);
        copy.grab_focus();
        window.present();
        return;
    }

    let show = icon_action("folder-open-symbolic", "Show in folder", &[], {
        let (file, gif, close) = (file.clone(), gif.clone(), close.clone());
        move |_| {
            // the file, and a recording's GIF if there is one
            let mut uris = vec![file_uri(&file)];
            if is_video && gif.exists() {
                uris.push(file_uri(&gif));
            }
            let count = uris.len().to_string();
            spawn(
                Command::new("busctl")
                    .args([
                        "--user",
                        "call",
                        "org.freedesktop.FileManager1",
                        "/org/freedesktop/FileManager1",
                        "org.freedesktop.FileManager1",
                        "ShowItems",
                        "ass",
                        &count,
                    ])
                    .args(&uris)
                    .arg(""),
            );
            close();
        }
    });

    // A job still running when the panel closes would have no one to rename
    // its file: stop it
    let job: Job = Rc::default();
    window.connect_close_request({
        let job = job.clone();
        move |_| {
            if let Some((mut child, part)) = job.borrow_mut().take() {
                let _ = child.kill();
                let _ = child.wait();
                let _ = std::fs::remove_file(&part);
            }
            glib::Propagation::Proceed
        }
    });

    let primary = match kind {
        Kind::Image => action("Annotate", &["suggested"], {
            let (file, close) = (file.clone(), close.clone());
            move |_| {
                // its Ctrl+S saving over the shot
                satty(&file, Some(&file));
                close();
            }
        }),
        Kind::Gif => action("Copy GIF", &["suggested"], copy_gif.clone()),
        Kind::Video => {
            // Convert, then the same button copies the GIF. ffmpeg writes beside
            // it under a hidden name, renamed once it's done, so a GIF that
            // exists is a whole one.
            let gif_size = opts.gif_size.unwrap_or((w, h));
            let label = if gif.exists() {
                "Copy GIF"
            } else {
                "Convert to GIF"
            };
            action(label, &["suggested"], {
                let (file, gif, job, describe) =
                    (file.clone(), gif.clone(), job.clone(), describe.clone());
                move |button| {
                    if job.borrow().is_some() {
                        return;
                    }
                    if gif.exists() {
                        copy_gif(button);
                        return;
                    }
                    let filter = GIF_FILTER
                        .replace("{w}", &gif_size.0.to_string())
                        .replace("{h}", &gif_size.1.to_string());
                    let part = part_path(&gif);
                    let child = Command::new("ffmpeg")
                        .args(["-y", "-loglevel", "error", "-i"])
                        .arg(&file)
                        .args(["-vf", &filter, "-loop", "0", "-f", "gif"])
                        .arg(&part)
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .spawn();
                    let Ok(child) = child else {
                        button.set_label("Can't convert");
                        return;
                    };
                    *job.borrow_mut() = Some((child, part.clone()));
                    button.set_label("Converting…");
                    button.set_sensitive(false);
                    let (button, gif, describe) = (button.clone(), gif.clone(), describe.clone());
                    watch(&job, move |done| {
                        if done && std::fs::rename(&part, &gif).is_ok() {
                            button.set_label("Copy GIF");
                            describe();
                        } else {
                            let _ = std::fs::remove_file(&part);
                            button.set_label("Convert failed");
                        }
                        button.set_sensitive(true);
                    });
                }
            })
        }
    };

    // A recording's trim: the bar under the video picks the part to keep,
    // and Trim, there once that's less than all of it, cuts the recording
    // down to it in place. The GIF of the whole recording goes with it.
    let trim = recording.as_ref().map(|video| {
        let range = Rc::new(Cell::new((0.0, length.get())));
        let button = action("Trim", &[], {
            let (file, gif, job, length, range, video, primary, describe) = (
                file.clone(),
                gif.clone(),
                job.clone(),
                length.clone(),
                range.clone(),
                video.clone(),
                primary.clone(),
                describe.clone(),
            );
            move |button| {
                if job.borrow().is_some() {
                    return;
                }
                let (start, end) = range.get();
                let part = part_path(&file);
                // Re-encoded, so it starts on the frame the handle showed
                // rather than the keyframe before it (wl-screenrec's are about
                // a second apart); frame times stay as recorded
                let (ss, t) = (format!("{start:.3}"), format!("{:.3}", end - start));
                let child = Command::new("ffmpeg")
                    .args(["-y", "-loglevel", "error", "-ss", &ss, "-i"])
                    .arg(&file)
                    .args(["-t", &t])
                    .args(["-c:v", "libx264", "-preset", "veryfast", "-crf", "18"])
                    .args(["-fps_mode", "passthrough"])
                    .args(["-movflags", "+faststart", "-f", "mp4"])
                    .arg(&part)
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn();
                let Ok(child) = child else {
                    button.set_label("Can't trim");
                    return;
                };
                *job.borrow_mut() = Some((child, part.clone()));
                button.set_label("Trimming…");
                button.set_sensitive(false);
                primary.set_sensitive(false);
                let (button, file, gif, length, range, video, primary, describe) = (
                    button.clone(),
                    file.clone(),
                    gif.clone(),
                    length.clone(),
                    range.clone(),
                    video.clone(),
                    primary.clone(),
                    describe.clone(),
                );
                watch(&job, move |done| {
                    if done && std::fs::rename(&part, &file).is_ok() {
                        let _ = std::fs::remove_file(&gif);
                        primary.set_label("Convert to GIF");
                        let secs = probe(&file).map_or(end - start, |(_, _, secs)| secs);
                        length.set(secs);
                        range.set((0.0, secs));
                        video.set_file(Some(&gio::File::for_path(&file)));
                        describe();
                        button.set_visible(false);
                    } else {
                        let _ = std::fs::remove_file(&part);
                        button.set_label("Trim failed");
                    }
                    button.set_sensitive(true);
                    primary.set_sensitive(true);
                });
            }
        });
        button.set_visible(false);
        let bar = trim_bar(video, &length, &range, {
            let (button, length, range) = (button.clone(), length.clone(), range.clone());
            move || {
                let (start, end) = range.get();
                button.set_visible(start > 0.0 || end < length.get());
                button.set_label(&format!("Trim to {}", short_time(end - start)));
            }
        });
        // as wide as the video
        bar.set_width_request(frame.width_request());
        bar.set_halign(gtk::Align::Center);
        panel.insert_child_after(&bar, Some(&frame));
        button
    });

    let copy = if kind == Kind::Image {
        icon_action("edit-copy-symbolic", "Copy image", &[], {
            let file = file.clone();
            move |button| copy_image(&file, button)
        })
    } else {
        icon_action("edit-copy-symbolic", "Copy file", &[], {
            let file = file.clone();
            move |button| {
                // as a file, for upload fields and file managers
                spawn(Command::new("wl-copy").args(["--type", "text/uri-list", &file_uri(&file)]));
                copied(button);
            }
        })
    };
    let delete = icon_action("user-trash-symbolic", "Delete", &["destructive"], {
        let (file, gif, close) = (file.clone(), gif.clone(), close.clone());
        move |_| {
            // what's shown, and the GIF made from a recording
            let _ = std::fs::remove_file(&file);
            if is_video {
                let _ = std::fs::remove_file(&gif);
            }
            close();
        }
    });
    let mut buttons = vec![delete, show, copy];
    buttons.extend(trim);
    buttons.push(primary);
    place_actions(&actions, &buttons);
    window.present();
}

/// Show a GIF's frames in turn until the window closes.
fn play(player: Rc<RefCell<Player>>, picture: gtk::Picture, window: &gtk::ApplicationWindow) {
    let playing = Rc::new(Cell::new(true));
    window.connect_close_request({
        let playing = playing.clone();
        move |_| {
            playing.set(false);
            glib::Propagation::Proceed
        }
    });
    next_frame(player, picture, playing);
}

fn next_frame(player: Rc<RefCell<Player>>, picture: gtk::Picture, playing: Rc<Cell<bool>>) {
    if !playing.get() {
        return;
    }
    let Some((texture, delay)) = player.borrow_mut().next() else {
        return;
    };
    picture.set_paintable(Some(&texture));
    glib::timeout_add_local_once(delay, move || next_frame(player, picture, playing));
}

/// The trim bar under a recording: its whole length, with a handle at each
/// end of `range` (the part to keep, in seconds). Dragging a handle shows
/// the frame there; playback loops over the part kept. `changed` hears of
/// each move.
fn trim_bar(
    video: &gtk::Video,
    length: &Rc<Cell<f64>>,
    range: &Rc<Cell<(f64, f64)>>,
    changed: impl Fn() + 'static,
) -> gtk::DrawingArea {
    let bar = gtk::DrawingArea::new();
    bar.add_css_class("trim");
    bar.set_content_height(26);
    // The handle being dragged: false the start, true the end
    let held: Rc<Cell<Option<bool>>> = Rc::default();

    bar.set_draw_func({
        let (video, length, range) = (video.clone(), length.clone(), range.clone());
        move |bar, cr, w, h| {
            let (w, h) = (f64::from(w), f64::from(h));
            let len = length.get();
            if len <= 0.0 {
                return;
            }
            let x = |t: f64| HANDLE_W / 2.0 + (w - HANDLE_W) * (t / len).clamp(0.0, 1.0);
            // The handles in the bar's colour (the accent, from CSS), the rest
            // in the panel's text colour
            let accent = bar.color();
            let fg = bar.parent().map_or(accent, |p| p.color());
            let paint = |c: &gdk::RGBA, alpha: f32| {
                cr.set_source_rgba(
                    c.red().into(),
                    c.green().into(),
                    c.blue().into(),
                    (c.alpha() * alpha).into(),
                );
            };
            let (start, end) = range.get();
            // the whole recording, then the part kept
            paint(&fg, 0.1);
            rounded_rect(cr, 0.0, 0.0, w, h, 6.0);
            let _ = cr.fill();
            paint(&accent, 0.3);
            cr.rectangle(x(start), 0.0, x(end) - x(start), h);
            let _ = cr.fill();
            paint(&accent, 1.0);
            for t in [start, end] {
                rounded_rect(cr, x(t) - HANDLE_W / 2.0, 0.0, HANDLE_W, h, 3.0);
                let _ = cr.fill();
            }
            // where playback is
            if let Some(stream) = video.media_stream() {
                paint(&fg, 0.9);
                cr.rectangle(x(stream.timestamp() as f64 / 1e6) - 1.0, 4.0, 2.0, h - 8.0);
                let _ = cr.fill();
            }
        }
    });

    let time_at = {
        let (bar, length) = (bar.clone(), length.clone());
        move |x: f64| {
            let span = (f64::from(bar.width()) - HANDLE_W).max(1.0);
            (x - HANDLE_W / 2.0) / span * length.get()
        }
    };
    // Moves a handle to `t`, keeping at least MIN_KEEP between them, and
    // shows the frame there
    let move_to = Rc::new({
        let (video, length, range) = (video.clone(), length.clone(), range.clone());
        move |end: bool, t: f64| {
            let (start, stop) = range.get();
            let (start, stop) = if end {
                (start, t.max(start + MIN_KEEP).min(length.get()))
            } else {
                (t.min(stop - MIN_KEEP).max(0.0), stop)
            };
            range.set((start, stop));
            if let Some(stream) = video.media_stream() {
                stream.pause();
                stream.seek(micros(if end { stop } else { start }));
            }
            changed();
        }
    });
    // A press takes the nearer handle there; a drag moves it
    let drag = gtk::GestureDrag::new();
    drag.connect_drag_begin({
        let (held, range, move_to, time_at) = (
            held.clone(),
            range.clone(),
            move_to.clone(),
            time_at.clone(),
        );
        move |gesture, x, _| {
            gesture.set_state(gtk::EventSequenceState::Claimed);
            let t = time_at(x);
            let (start, end) = range.get();
            let end = (t - end).abs() < (t - start).abs();
            held.set(Some(end));
            move_to(end, t);
        }
    });
    drag.connect_drag_update({
        let held = held.clone();
        move |gesture, dx, _| {
            if let (Some(end), Some((x, _))) = (held.get(), gesture.start_point()) {
                move_to(end, time_at(x + dx));
            }
        }
    });
    drag.connect_drag_end({
        let (video, range, held) = (video.clone(), range.clone(), held.clone());
        move |_, _, _| {
            held.set(None);
            if let Some(stream) = video.media_stream() {
                stream.seek(micros(range.get().0));
                stream.play();
            }
        }
    });
    bar.add_controller(drag);

    // Each frame: loop playback over the part kept (GtkVideo's own loop
    // doesn't take with the GStreamer backend on these files: the stream
    // just ends) and move the playhead. The stream is looked up each time,
    // as a trim loads a new one.
    bar.add_tick_callback({
        let (video, length, range) = (video.clone(), length.clone(), range.clone());
        move |bar, _| {
            if let (Some(stream), None) = (video.media_stream(), held.get()) {
                let (start, end) = range.get();
                let past_end =
                    stream.is_playing() && end < length.get() && stream.timestamp() >= micros(end);
                if !stream.is_seeking() && (stream.is_ended() || past_end) {
                    stream.seek(micros(start));
                    stream.play();
                }
            }
            bar.queue_draw();
            glib::ControlFlow::Continue
        }
    });
    bar
}

fn micros(secs: f64) -> i64 {
    (secs * 1e6).round() as i64
}

/// A length for the Trim button: 3.6 s, or 1:05 from a minute up.
fn short_time(secs: f64) -> String {
    if secs < 60.0 {
        format!("{secs:.1} s")
    } else {
        let secs = secs.round() as u64;
        format!("{}:{:02}", secs / 60, secs % 60)
    }
}

fn rounded_rect(cr: &gtk::cairo::Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    use std::f64::consts::{FRAC_PI_2, PI};
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -FRAC_PI_2, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, FRAC_PI_2);
    cr.arc(x + r, y + h - r, r, FRAC_PI_2, PI);
    cr.arc(x + r, y + r, r, PI, 3.0 * FRAC_PI_2);
    cr.close_path();
}

/// Waits for the job to finish, then clears it and tells `done` whether it
/// succeeded (false too if the panel stopped it).
fn watch(job: &Job, done: impl FnOnce(bool) + 'static) {
    let job = job.clone();
    let mut done = Some(done);
    glib::timeout_add_local(Duration::from_millis(100), move || {
        let status = job.borrow_mut().as_mut().map(|(child, _)| child.try_wait());
        if let Some(Ok(None)) = status {
            return glib::ControlFlow::Continue;
        }
        *job.borrow_mut() = None;
        if let Some(done) = done.take() {
            done(matches!(status, Some(Ok(Some(s))) if s.success()));
        }
        glib::ControlFlow::Break
    });
}

/// The hidden name a job writes `path` under until it's done: .NAME.part
fn part_path(path: &Path) -> PathBuf {
    let mut name = std::ffi::OsString::from(".");
    name.push(path.file_name().unwrap_or_default());
    name.push(".part");
    path.with_file_name(name)
}
fn fail(app: &gtk::Application, file: &Path, why: &str) {
    eprintln!("capture-preview: {}: {why}", file.display());
    app.quit();
}

/// Puts the buttons in the row: the first (Delete or Discard) set apart at
/// the left, the last (the main one) focused, so Enter presses it. GTK would
/// otherwise focus the first.
fn place_actions(row: &gtk::Box, buttons: &[gtk::Button]) {
    for button in buttons {
        row.append(button);
    }
    if let Some(first) = buttons.first() {
        first.set_hexpand(true);
        first.set_halign(gtk::Align::Start);
    }
    if let Some(last) = buttons.last() {
        last.grab_focus();
    }
}

/// Opens an image in Satty, which copies it on Enter; with `output`, its
/// Ctrl+S saves there (otherwise to its configured folder).
fn satty(file: &Path, output: Option<&Path>) {
    let mut command = Command::new("satty");
    command.arg("--filename").arg(file);
    if let Some(output) = output {
        command.arg("--output-filename").arg(output);
    }
    spawn(&mut command);
}

/// Save… for a screenshot: a save dialog starting in `dir`. The panel covers
/// the screen above every window, so it hides while the dialog is up, and
/// comes back if the dialog is cancelled.
fn save_as(window: &gtk::ApplicationWindow, file: &Path, dir: &Path) {
    let _ = std::fs::create_dir_all(dir);
    let name = file
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let dialog = gtk::FileDialog::builder()
        .title("Save Screenshot")
        .initial_folder(&gio::File::for_path(dir))
        .initial_name(name.as_str())
        .build();
    window.set_visible(false);
    let (window, file) = (window.clone(), file.to_owned());
    dialog.save(
        None::<&gtk::Window>,
        None::<&gio::Cancellable>,
        move |result| match result.ok().and_then(|f| f.path()) {
            Some(dest) if std::fs::copy(&file, &dest).is_ok() => {
                let _ = std::fs::remove_file(&file);
                window.close();
            }
            _ => window.set_visible(true),
        },
    );
}

fn action(label: &str, classes: &[&str], on_click: impl Fn(&gtk::Button) + 'static) -> gtk::Button {
    let button = gtk::Button::with_label(label);
    button.add_css_class("action");
    for class in classes {
        button.add_css_class(class);
    }
    button.connect_clicked(on_click);
    button
}

/// An action shown as an icon, named in its tooltip.
fn icon_action(
    icon: &str,
    name: &str,
    classes: &[&str],
    on_click: impl Fn(&gtk::Button) + 'static,
) -> gtk::Button {
    let button = action("", classes, on_click);
    button.set_icon_name(icon);
    button.add_css_class("icon");
    button.set_tooltip_text(Some(name));
    button.update_property(&[gtk::accessible::Property::Label(name)]);
    button
}

/// Run a helper without waiting for it or letting it hold our stdout.
fn spawn(command: &mut Command) {
    if let Err(e) = command.stdout(Stdio::null()).stderr(Stdio::null()).spawn() {
        eprintln!("capture-preview: {command:?}: {e}");
    }
}

/// An image's MIME type, for the clipboard.
fn image_type(path: &Path) -> &'static str {
    match extension(path).as_deref() {
        Some("gif") => "image/gif",
        Some("jpg" | "jpeg") => "image/jpeg",
        Some("webp") => "image/webp",
        _ => "image/png",
    }
}

fn file_uri(path: &Path) -> String {
    gio::File::for_path(path).uri().into()
}

fn file_size(path: &Path) -> u64 {
    std::fs::metadata(path).map(|m| m.len()).unwrap_or(0)
}

fn human_size(bytes: u64) -> String {
    match bytes {
        b if b >= 1 << 20 => format!("{:.1} MB", b as f64 / f64::from(1 << 20)),
        b if b >= 1 << 10 => format!("{:.0} KB", b as f64 / f64::from(1 << 10)),
        b => format!("{b} B"),
    }
}

fn load_css(theme: Option<&Path>) {
    let Some(display) = gdk::Display::default() else {
        return;
    };
    let base = gtk::CssProvider::new();
    base.load_from_string(include_str!("style.css"));
    gtk::style_context_add_provider_for_display(
        &display,
        &base,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    if let Some(path) = theme {
        let provider = gtk::CssProvider::new();
        provider.load_from_path(path);
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION + 1,
        );
    }
}
