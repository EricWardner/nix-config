pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// What the status icons show that Quickshell has no service for, from
// bar-tools' watchers (one process each, however many bars), which panel
// is open where, and how the bar starts things.
Singleton {
	id: root

	// The panel an island is grown into ("centre", the notification centre,
	// or "control", the control centre) and the monitor it's open on: one at
	// a time, anywhere
	property string panel: ""
	property HyprlandMonitor panelOn: null
	// The page a panel opens on, when asked for one (the control centre's
	// "wifi", say); its first page otherwise
	property string panelPage: ""

	function togglePanel(name: string, monitor: HyprlandMonitor) {
		if (panel === name && panelOn === monitor) {
			closePanel();
		} else {
			panel = name;
			panelOn = monitor;
		}
	}

	// No windows on the monitor's workspace, so Sky shows there
	function workspaceEmpty(monitor: HyprlandMonitor): bool {
		return monitor !== null && !Hyprland.toplevels.values.some(t => t.workspace === monitor.activeWorkspace);
	}

	// A panel on a page ("" for its first), or closed if it's already open
	// there
	function openPanel(name: string, page: string, monitor: HyprlandMonitor) {
		if (panel === name && panelOn === monitor && panelPage === page) {
			closePanel();
			return;
		}
		panelPage = page;
		panel = name;
		panelOn = monitor;
	}

	function closePanel() {
		panel = "";
		panelOn = null;
		panelPage = "";
	}

	// For keybinds: `qs ipc -c islands call panel toggle centre` (or
	// control), on the focused monitor; `… panel open control wifi` opens it
	// on a page
	IpcHandler {
		target: "panel"

		function toggle(name: string): void {
			root.togglePanel(name, Hyprland.focusedMonitor);
		}

		function open(name: string, page: string): void {
			root.openPanel(name, page, Hyprland.focusedMonitor);
		}
	}

	// Each watcher's `class`: the mic is on, muted, ptt-muted (push-to-talk
	// armed) or ptt-active (talking); the webcam disconnected, muted, in-use
	// or available
	property string mic: ""
	property string webcam: ""

	Watcher {
		command: ["mic-watch"]
		onUpdate: state => root.mic = state.class
	}
	Watcher {
		command: ["webcam-watch"]
		onUpdate: state => root.webcam = state.class
	}

	// Starts a command in its own transient scope, so it outlives the shell
	// (a restart would otherwise take a recording with it)
	function launch(command: list<string>) {
		Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--"].concat(command));
	}
}
