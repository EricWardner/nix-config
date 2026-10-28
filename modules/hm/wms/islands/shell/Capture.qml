pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Capturing the screen, one way in for all of it (Print): every monitor's
// screen freezes and its overlay (CaptureOverlay) comes up for choosing an
// area, a window or a screen, and what to do with it: a screenshot (to the
// preview), a recording, its text, or a colour. islands-capture does the
// work. A recording counts down and runs in the centre island (RecordMode),
// in a scope of its own, so restarting the shell doesn't end it.
Singleton {
	id: root

	property string kind: "screenshot" // screenshot, record, text, colour
	property string target: "area" // area, screen
	property string phase: "idle" // idle, freezing, choosing, countdown, recording

	readonly property bool choosing: phase === "choosing"
	// New for each capture: the overlays' images are cached by name
	property string stamp: ""
	readonly property string frames: Quickshell.env("XDG_RUNTIME_DIR") + "/islands/capture/frames/" + stamp

	function frozenFile(output: string): string {
		return frames + "/" + output + ".png";
	}

	// The frozen frames, when nothing more will read them (islands-capture
	// drops them itself once it's cropped one)
	function dropFrames() {
		if (stamp !== "")
			Quickshell.execDetached(["rm", "-rf", frames]);
	}

	// Freezes the screens and brings up the overlays
	function open(newKind: string, newTarget: string) {
		if (phase !== "idle")
			return;
		kind = newKind;
		target = newTarget;
		stamp = String(Date.now());
		phase = "freezing";
		// Where the windows are now, for clicking one
		Hyprland.refreshToplevels();
		Hyprland.refreshMonitors();
		freeze.command = ["islands-capture", "freeze", frames].concat(Quickshell.screens.map(s => s.name));
		freeze.running = true;
	}

	function cancel() {
		if (phase === "freezing" || phase === "choosing")
			dropFrames();
		if (phase === "countdown")
			countdownTimer.stop();
		if (phase !== "recording")
			phase = "idle";
	}

	// The overlay's choice: `rect` in its monitor's logical pixels, and the
	// window clicked, if one was
	function take(monitor: HyprlandMonitor, screen: ShellScreen, rect: rect, window: var) {
		const scale = monitor.scale;
		const pixels = [rect.x, rect.y, rect.width, rect.height].map(v => Math.round(v * scale));
		const frozen = frozenFile(screen.name);
		phase = "idle";
		if (kind === "screenshot") {
			// From the window itself, so the parts covered or off screen are in it
			if (window) {
				dropFrames();
				run(["window", window.stableId]);
			} else {
				run(["area", frozen].concat(pixels));
			}
		} else if (kind === "text") {
			run(["text", frozen].concat(pixels, [scale]));
		} else if (kind === "colour") {
			run(["colour", frozen, pixels[0], pixels[1]]);
		} else if (kind === "record") {
			dropFrames();
			const area = target === "screen" ? rect : encodable(rect, scale, screen);
			const size = Math.round(area.width) + "x" + Math.round(area.height);
			const geometry = target === "screen" ? "" : (monitor.x + Math.round(area.x)) + "," + (monitor.y + Math.round(area.y)) + " " + size;
			startRecording(screen.name, geometry, size);
		}
	}

	// The Radeon's encoder takes nothing under 128 pixels a side (wl-screenrec
	// fails, leaving an empty file): a smaller area grows to that round its
	// middle, staying on the screen
	function encodable(rect: rect, scale: real, screen: ShellScreen): rect {
		const least = Math.ceil(128 / scale);
		const grow = (start, length, limit) => {
			const grown = Math.min(limit, Math.max(length, least));
			return [Math.max(0, Math.min(limit - grown, start - (grown - length) / 2)), grown];
		};
		const [x, width] = grow(rect.x, rect.width, screen.width);
		const [y, height] = grow(rect.y, rect.height, screen.height);
		return Qt.rect(x, y, width, height);
	}

	// Without the overlay (Shift+Print, Ctrl+Print): the focused window, or
	// the focused monitor
	function now(what: string) {
		if (what === "window") {
			const id = Hyprland.activeToplevel?.lastIpcObject?.stableId;
			if (id)
				run(["window", id]);
		} else {
			run(["output", Hyprland.focusedMonitor.name]);
		}
	}

	// In a scope of its own, as the preview is a window that should outlive
	// a restart of the shell
	function run(args: list<var>) {
		Desktop.launch(["islands-capture"].concat(args.map(String)));
	}

	Process {
		id: freeze

		onExited: code => {
			if (root.phase !== "freezing")
				return;
			if (code === 0) {
				root.phase = "choosing";
			} else {
				root.dropFrames();
				root.phase = "idle";
			}
		}
	}

	// Recording: a countdown, then wl-screenrec until it's stopped
	property int countdown: 0
	property real since: 0
	property string size: ""
	property var pending: null

	function startRecording(output: string, geometry: string, recordingSize: string) {
		pending = {
			"output": output,
			"geometry": geometry,
			"size": recordingSize,
			"file": Quickshell.env("HOME") + "/Videos/" + Qt.formatDateTime(new Date(), "MM-dd-yyyy-HH-mm-ss") + ".mp4"
		};
		countdown = 3;
		phase = "countdown";
		countdownTimer.start();
	}

	function record() {
		const p = pending;
		const area = p.geometry !== "" ? ["-g", p.geometry] : ["-o", p.output];
		recorder.command = ["systemd-run", "--user", "--scope", "--unit=islands-recording", "--collect", "--quiet", "--", "islands-capture", "record", p.file, p.size].concat(area);
		since = Date.now();
		size = p.size;
		phase = "recording";
		recorder.running = true;
	}

	function stopRecording() {
		Quickshell.execDetached(["systemctl", "--user", "kill", "--signal=SIGINT", "islands-recording.scope"]);
		stopping.restart();
	}

	// A recorder that hasn't finished its file 5s after SIGINT is stuck (an
	// encoder that hangs reads no signals): killed, so Stop always stops
	Timer {
		id: stopping

		interval: 5000
		onTriggered: {
			if (root.phase === "recording")
				Quickshell.execDetached(["systemctl", "--user", "kill", "--signal=SIGKILL", "islands-recording.scope"]);
		}
	}

	// Super+R and the bar's record button: start (choosing an area), or stop
	function toggleRecording() {
		if (phase === "recording")
			stopRecording();
		else if (phase === "countdown")
			cancel();
		else if (phase === "idle")
			open("record", "area");
	}

	Timer {
		id: countdownTimer

		interval: 1000
		repeat: true
		onTriggered: {
			root.countdown--;
			if (root.countdown <= 0) {
				stop();
				root.record();
			}
		}
	}

	Process {
		id: recorder

		onExited: {
			root.phase = "idle";
			root.run(["finished"]);
		}
	}

	// A recording left running by the shell before a restart: shown, and
	// stoppable, until it ends
	Component.onCompleted: adopt.running = true

	Process {
		id: adopt

		command: ["systemctl", "--user", "show", "islands-recording.scope", "--property=ActiveState,ActiveEnterTimestamp", "--timestamp=unix"]
		stdout: StdioCollector {
			onStreamFinished: {
				const unit = {};
				for (const line of text.trim().split("\n")) {
					const at = line.indexOf("=");
					unit[line.slice(0, at)] = line.slice(at + 1);
				}
				if (unit.ActiveState === "active" && root.phase === "idle") {
					root.since = Number(unit.ActiveEnterTimestamp.slice(1)) * 1000;
					root.size = "";
					root.phase = "recording";
					adopted.start();
				}
			}
		}
	}

	Timer {
		id: adopted

		interval: 1000
		repeat: true
		onTriggered: stillRecording.running = true
	}

	Process {
		id: stillRecording

		command: ["systemctl", "--user", "--quiet", "is-active", "islands-recording.scope"]
		onExited: code => {
			if (code !== 0) {
				adopted.stop();
				root.phase = "idle";
				root.run(["finished"]);
			}
		}
	}

	// For keybinds and the launcher: `qs ipc -c islands call capture …`
	IpcHandler {
		target: "capture"

		readonly property string phase: root.phase

		// kind: screenshot, record, text or colour; target: area or screen
		function open(kind: string, target: string): void {
			root.open(kind, target);
		}

		// Closes the overlay, or ends a countdown
		function cancel(): void {
			root.cancel();
		}

		// window or screen, at once
		function now(what: string): void {
			root.now(what);
		}

		function record(): void {
			root.toggleRecording();
		}

		// Stops a recording, if one's running (or counting down)
		function stop(): string {
			if (root.phase === "recording") {
				root.stopRecording();
				return "stopped";
			}
			if (root.phase === "countdown") {
				root.cancel();
				return "stopped";
			}
			return "none";
		}

		function last(): void {
			root.run(["last"]);
		}
	}
}
