pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland

// Sharing the screen in a call: on while xdg-desktop-portal-hyprland's
// stream is linked to an app. Chrome drops and restarts its stream as a
// share begins, so a share only ends once the stream's been gone 2s.
Singleton {
	id: root

	// The link exists only while the share runs. Its state isn't usable:
	// Quickshell reports Unlinked for links nothing tracks.
	readonly property bool streaming: Pipewire.linkGroups.values.some(group => (group.source?.name ?? "").includes("xdg-desktop-portal-hyprland"))
	property bool active: false
	property real since: 0
	// Stop sharing was pressed, and the stream hasn't gone yet
	property bool stopping: false
	// What's shared: a screen (`output`, its name, or "" if it isn't known)
	// or a window (`title`)
	property string kind: "screen"
	property string output: ""
	property string title: ""
	// The shared window, found by its title as the share starts
	property HyprlandToplevel window: null
	// Hyprland's window rounding and border, for the frame round a shared
	// window to follow
	property int windowRounding: 12
	property int windowBorder: 2

	// Hyprland's latest screencast start and when the stream last appeared.
	// grim and the capture overlay start screencasts too, so one is only the
	// share's if it comes within a moment of the stream.
	property var started: null
	property real streamedAt: 0

	function identify() {
		if (!started || Math.abs(started.at - streamedAt) > 3000)
			return;
		kind = started.kind;
		output = started.kind === "screen" ? started.target : "";
		title = started.kind === "window" ? started.target : "";
		window = kind === "window" ? sharedWindow(title) : null;
	}

	// The window with that title, or failing that the one whose title differs
	// only in leading symbols: a terminal running Claude Code animates one
	function sharedWindow(shared: string): HyprlandToplevel {
		const windows = Hyprland.toplevels.values;
		const words = t => t.replace(/^\W+/, "").trim();
		return windows.find(t => t.title === shared) ?? windows.find(t => words(t.title) === words(shared)) ?? null;
	}

	// As Chrome's own Stop button would: it takes its "<host> is sharing your
	// screen." bar being closed as one, and Gather sees an ordinary stop
	function stop() {
		for (const toplevel of ToplevelManager.toplevels.values) {
			if (toplevel.title.includes(" is sharing ")) {
				toplevel.close();
				stopping = true;
				stopTimeout.restart();
			}
		}
	}

	onStreamingChanged: {
		if (!streaming) {
			// Chrome only restarts its stream as a share begins, never after
			// it's been stopped
			if (stopping)
				active = false;
			else
				ending.restart();
			return;
		}
		ending.stop();
		streamedAt = Date.now();
		identify();
		if (!active) {
			since = Date.now();
			active = true;
		}
	}

	onActiveChanged: {
		if (active)
			return;
		stopping = false;
		if (Desktop.panel === "held")
			Desktop.closePanel();
	}

	Timer {
		id: ending

		interval: 2000
		onTriggered: root.active = false
	}

	// Where the shared window is now: Hyprland sends no event for a resize
	Timer {
		interval: 250
		repeat: true
		running: root.active && root.window !== null
		onTriggered: {
			Hyprland.refreshToplevels();
			Hyprland.refreshMonitors();
		}
	}

	Process {
		running: true
		command: ["sh", "-c", "hyprctl getoption decoration:rounding -j; hyprctl getoption general:border_size -j"]
		stdout: SplitParser {
			onRead: line => {
				const option = JSON.parse(line);
				if (option.option === "decoration:rounding")
					root.windowRounding = option.int;
				else if (option.option === "general:border_size")
					root.windowBorder = option.int;
			}
		}
	}

	// The app didn't stop: its stream dropping ends the share as usual again
	Timer {
		id: stopTimeout

		interval: 5000
		onTriggered: root.stopping = false
	}

	Connections {
		target: Hyprland

		function onRawEvent(event: HyprlandEvent) {
			if (event.name !== "screencastv2")
				return;
			const [state, owner, ...target] = event.data.split(",");
			if (state !== "1")
				return;
			root.started = {
				"kind": owner === "window" ? "window" : "screen",
				"target": target.join(","),
				"at": Date.now()
			};
			if (root.streaming)
				root.identify();
		}
	}
}
