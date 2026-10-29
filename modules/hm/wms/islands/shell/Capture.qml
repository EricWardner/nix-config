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
// in a scope of its own, so restarting the shell doesn't end it. The same
// overlay is the screen-share picker: islands-share-pick asks for a choice
// of window, area or screen, and gets it back through a pipe.
Singleton {
	id: root

	property string kind: "screenshot" // screenshot, record, text, colour, share
	property string target: "area" // area, screen
	// The overlay's
	property string phase: "idle" // idle, freezing, choosing
	// A recording's, apart from the overlay's, so a share or a screenshot
	// can be chosen while one runs
	property string recorder: "off" // off, countdown, on

	readonly property bool choosing: phase === "choosing"
	// The pipe islands-share-pick waits on, while a share is being chosen
	property string reply: ""
	// Overlays whose screens are still being captured
	property int capturing: 0

	// Freezes the screens and brings up the overlays
	function open(newKind: string, newTarget: string) {
		if (phase !== "idle" || (newKind === "record" && recorder !== "off"))
			return;
		kind = newKind;
		target = newTarget;
		capturing = Quickshell.screens.length;
		phase = "freezing";
		freezeTimeout.restart();
		// Where the windows are now, for clicking one
		Hyprland.refreshToplevels();
		Hyprland.refreshMonitors();
	}

	// An overlay's screen is captured
	function frozen() {
		if (phase === "freezing" && --capturing <= 0) {
			freezeTimeout.stop();
			phase = "choosing";
		}
	}

	// A screen share's choice, as islands-share-pick reads it ("" cancels)
	function answer(choice: string) {
		Quickshell.execDetached(["sh", "-c", "[ -p \"$1\" ] && printf '%s\\n' \"$2\" >\"$1\"", "sh", reply, choice]);
		reply = "";
	}

	function share(pipe: string) {
		if (phase !== "idle") {
			reply = pipe;
			answer("");
			return;
		}
		reply = pipe;
		open("share", "area");
	}

	// Closes the overlay, or with none up, ends a countdown
	function cancel() {
		if (phase !== "idle") {
			freezeTimeout.stop();
			if (reply !== "")
				answer("");
			phase = "idle";
		} else if (recorder === "countdown") {
			endCountdown();
		}
	}

	function endCountdown() {
		countdownTimer.stop();
		recorder = "off";
	}

	// Whether taking a choice needs the frozen frame written out
	function needsFrame(window: var): bool {
		return kind === "text" || kind === "colour" || (kind === "screenshot" && !window);
	}

	function frameFile(output: string): string {
		return Quickshell.env("XDG_RUNTIME_DIR") + "/islands-frame-" + Date.now() + "-" + output + ".ppm";
	}

	// The overlay's choice: `rect` in its monitor's logical pixels, the window
	// clicked, if one was, and the frozen frame's file, if it's needed
	function take(monitor: HyprlandMonitor, screen: ShellScreen, rect: rect, window: var, frame: string) {
		const scale = monitor.scale;
		const pixels = [rect.x, rect.y, rect.width, rect.height].map(v => Math.round(v * scale));
		phase = "idle";
		if (kind === "share") {
			if (target === "screen")
				answer("screen:" + screen.name);
			else if (window)
				answer("window:" + window.address + "\t" + window.title);
			else
				answer("region:" + screen.name + "@" + [rect.x, rect.y, rect.width, rect.height].map(Math.round).join(","));
		} else if (kind === "screenshot") {
			// From the window itself, so the parts covered or off screen are in it
			if (window)
				run(["window", window.stableId]);
			else
				run(["area", frame].concat(pixels));
		} else if (kind === "text") {
			run(["text", frame].concat(pixels, [scale]));
		} else if (kind === "colour") {
			run(["colour", frame, Math.floor(rect.x * scale), Math.floor(rect.y * scale)]);
		} else if (kind === "record") {
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

	// A screen that never sends a frame (switched off, say) leaves its
	// overlay see-through and the capture stuck
	Timer {
		id: freezeTimeout

		interval: 1000
		onTriggered: {
			if (root.phase === "freezing") {
				console.warn("capture: a screen sent no frame");
				root.cancel();
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
		recorder = "countdown";
		countdownTimer.start();
	}

	function record() {
		const p = pending;
		const area = p.geometry !== "" ? ["-g", p.geometry] : ["-o", p.output];
		recording.command = ["systemd-run", "--user", "--scope", "--unit=islands-recording", "--collect", "--quiet", "--", "islands-capture", "record", p.file, p.size].concat(area);
		since = Date.now();
		size = p.size;
		recorder = "on";
		recording.running = true;
	}

	// The last one's over: its kill timer mustn't reach the next
	function recordingEnded() {
		stopping.stop();
		recorder = "off";
		run(["finished"]);
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
			if (root.recorder === "on")
				Quickshell.execDetached(["systemctl", "--user", "kill", "--signal=SIGKILL", "islands-recording.scope"]);
		}
	}

	// Super+R and the bar's record button: start (choosing an area), or stop
	function toggleRecording() {
		if (recorder === "on")
			stopRecording();
		else if (recorder === "countdown")
			endCountdown();
		else
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
		id: recording

		onExited: root.recordingEnded()
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
				if (unit.ActiveState === "active" && root.recorder === "off") {
					root.since = Number(unit.ActiveEnterTimestamp.slice(1)) * 1000;
					root.size = "";
					root.recorder = "on";
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
				root.recordingEnded();
			}
		}
	}

	// For keybinds and the launcher: `qs ipc -c islands call capture …`
	IpcHandler {
		target: "capture"

		readonly property string phase: root.phase
		readonly property string recorder: root.recorder

		// kind: screenshot, record, text or colour; target: area or screen
		function open(kind: string, target: string): void {
			root.open(kind, target);
		}

		// For islands-share-pick: the choice is written to `pipe`
		function share(pipe: string): void {
			root.share(pipe);
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
			if (root.recorder === "on") {
				root.stopRecording();
				return "stopped";
			}
			if (root.recorder === "countdown") {
				root.endCountdown();
				return "stopped";
			}
			return "none";
		}

		function last(): void {
			root.run(["last"]);
		}
	}
}
