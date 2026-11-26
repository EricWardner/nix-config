pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The screen's brightness, in % (5-100: the screen never goes dark). The
// shell makes every change: the keys (`qs ipc -c islands call brightness
// up`), the control centre's slider, and hypridle's idle dimming (`dim`,
// `undim`). `level` is the one account of it: what the shell last asked for,
// or what the backlight reads after a change made elsewhere.
Singleton {
	id: root

	property int level: 100
	// The level before an idle dim, while dimmed; -1 otherwise
	property int undimmed: -1

	// By the keys, with the popup
	function step(delta: int) {
		const to = clamp((undimmed >= 0 ? undimmed : level) + delta);
		set(to);
		Osd.show("brightness", to / 100, false);
	}

	// By hand: it ends an idle dim
	function set(percent: int) {
		undimmed = -1;
		ask(percent);
	}

	// A key press that wakes the screen reaches the shell along with
	// hypridle's undim, in either order: a step while dimmed starts from the
	// level before the dim, and an undim after it does nothing
	function dim() {
		if (undimmed >= 0)
			return;
		const from = level;
		ask(Math.min(10, from));
		undimmed = from;
	}

	function undim() {
		if (undimmed < 0)
			return;
		const to = undimmed;
		undimmed = -1;
		ask(to);
	}

	function clamp(percent: int): int {
		return Math.max(5, Math.min(100, percent));
	}

	// One brightnessctl at a time, then the latest level asked for: keys
	// held down and a drag on the slider ask faster than they finish, and
	// several at once can land out of order
	property int wanted: -1

	function ask(percent: int) {
		level = wanted = clamp(percent);
		if (!writer.running)
			write();
	}

	function write() {
		writer.command = ["brightnessctl", "-q", "set", wanted + "%"];
		wanted = -1;
		writer.running = true;
	}

	Process {
		id: writer

		onExited: if (root.wanted >= 0)
			root.write()
	}

	// Kept in the runtime directory while dimmed, so a shell restarted then
	// (by a rebuild, which outlasts the dim) still undims
	onUndimmedChanged: undimmedFile.setText(undimmed < 0 ? "" : String(undimmed))

	FileView {
		id: undimmedFile

		path: Quickshell.env("XDG_RUNTIME_DIR") + "/islands-undimmed"
		blockLoading: true
		printErrors: false
	}

	Component.onCompleted: {
		const saved = parseInt(undimmedFile.text());
		if (saved > 0)
			undimmed = saved;
	}

	// Changes made elsewhere (brightnessctl by hand, the firmware), read
	// when udev reports one; not while the shell's own are on their way,
	// which would read a level it has already moved on from
	function read() {
		if (Host.backlightDir === "" || writer.running || wanted >= 0)
			return;
		current.reload();
		const max = Number(maximum.text().trim());
		if (max > 0)
			level = Math.round(100 * Number(current.text().trim()) / max);
	}

	FileView {
		id: current

		path: Host.backlightDir === "" ? "" : Host.backlightDir + "/brightness"
		blockAllReads: true
	}

	FileView {
		id: maximum

		path: Host.backlightDir === "" ? "" : Host.backlightDir + "/max_brightness"
		blockLoading: true
	}

	// udev's events for the backlight, one line each; restarted if it exits
	Process {
		id: udev

		command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
		running: Host.backlightDir !== ""
		onRunningChanged: if (running)
			root.read()
		onExited: restartUdev.start()
		stdout: SplitParser {
			onRead: line => {
				if (line.includes("(backlight)"))
					root.read();
			}
		}
	}

	Timer {
		id: restartUdev

		interval: 5000
		onTriggered: udev.running = true
	}

	IpcHandler {
		target: "brightness"

		function up(): void {
			root.step(5);
		}

		function down(): void {
			root.step(-5);
		}

		function dim(): void {
			root.dim();
		}

		function undim(): void {
			root.undim();
		}
	}
}
