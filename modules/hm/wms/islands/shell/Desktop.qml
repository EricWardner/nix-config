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

	// The panel an island is grown into ("centre", the notification centre;
	// "control", the control centre; "keys", the keyboard shortcuts; "held",
	// the notifications held during a share) and the screen it's open on:
	// one at a time, anywhere
	property string panel: ""
	property ShellScreen panelOn: null
	// The page showing (the control centre's "wifi", say); "" for its first
	property string panelPage: ""

	// The islands know the monitor they're on as Quickshell's screen, which
	// any compositor has. What only Hyprland can say about one is asked
	// here: where the focus is, and whether its workspace is empty.
	readonly property ShellScreen focusedScreen: {
		const name = Hyprland.focusedMonitor?.name ?? "";
		return Quickshell.screens.find(screen => screen.name === name) ?? null;
	}

	// Its monitor unplugged: closed, or popups would stay held back for it
	onPanelOnChanged: if (panelOn === null && panel !== "")
		closePanel()

	Connections {
		target: Quickshell

		function onScreensChanged() {
			if (root.panelOn !== null && !Quickshell.screens.some(screen => screen === root.panelOn))
				root.closePanel();
		}
	}

	function togglePanel(name: string, screen: ShellScreen) {
		if (panel === name && panelOn === screen) {
			closePanel();
		} else {
			panelPage = "";
			panel = name;
			panelOn = screen;
		}
	}

	// No windows on the screen's workspace, so Sky shows there
	function workspaceEmpty(screen: ShellScreen): bool {
		const monitor = screen ? Hyprland.monitorFor(screen) : null;
		return monitor !== null && !Hyprland.toplevels.values.some(t => t.workspace === monitor.activeWorkspace);
	}

	// A panel on a page ("" for its first), or closed if it's already open
	// there
	function openPanel(name: string, page: string, screen: ShellScreen) {
		if (panel === name && panelOn === screen && panelPage === page) {
			closePanel();
			return;
		}
		panelPage = page;
		panel = name;
		panelOn = screen;
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
			root.togglePanel(name, root.focusedScreen);
		}

		function open(name: string, page: string): void {
			root.openPanel(name, page, root.focusedScreen);
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
	// (a restart would otherwise take a preview window or a settings app
	// with it). Untyped: as a list<string>, a command read from a model (the
	// control centre's buttons) arrives empty, and nothing runs.
	function launch(command) {
		Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--"].concat(Array.from(command)));
	}
}
