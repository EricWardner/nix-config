pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Keep Awake: while it's on, nothing dims, locks or suspends for idleness,
// and the lid and the power key don't suspend (logind would otherwise do
// so even docked). The same block as the `nosleep` alias, held by the
// shell, so the bar shows it and it can't be left running in a forgotten
// terminal. The notification centre turns it on and off.
Singleton {
	id: root

	property bool on: false

	// The block reads the shell's stdin to its end, so it ends with the
	// shell, a crash included, rather than holding off sleep unseen.
	// hypridle honours logind's idle blocks.
	Process {
		running: root.on
		stdinEnabled: true
		command: ["systemd-inhibit", "--what=sleep:idle:handle-lid-switch:handle-power-key", "--who=islands", "--why=Keep Awake", "--mode=block", "cat"]
		// Ended by anything but turning it off: the switch shows it's gone
		onExited: root.on = false
	}

	// With sleep held off, the lid shut in a bag would run the battery flat:
	// at 10% on battery it turns itself off, and says so
	readonly property bool flat: Battery.present && !Battery.onPower && Battery.level <= 10

	function check(): void {
		if (on && flat) {
			on = false;
			Quickshell.execDetached(["notify-send", "--app-name=Keep Awake", "Keep Awake is off", "The battery is at " + Math.round(Battery.level) + "%, so the laptop can sleep again."]);
		}
	}

	onFlatChanged: check()

	// It lasts until it's turned off or the session ends: kept in the
	// runtime directory, so a restart of the shell keeps it
	readonly property string file: Quickshell.env("XDG_RUNTIME_DIR") + "/islands/keep-awake"

	onOnChanged: {
		check();
		Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && echo \"$2\" >\"$1\"", "sh", file, on ? "on" : "off"]);
	}

	FileView {
		path: root.file
		printErrors: false
		onLoaded: root.on = text().trim() === "on"
	}

	// For keybinds: `qs ipc -c islands call keepawake …`
	IpcHandler {
		target: "keepawake"

		function toggle(): string {
			root.on = !root.on;
			return root.on ? "on" : "off";
		}

		function set(on: bool): void {
			root.on = on;
		}
	}
}
