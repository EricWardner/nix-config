pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The panel an island is grown into, and where: one at a time, on any
// screen. An island grows while its panel shows on its screen; a click on
// the island, a keybind, Esc or a click outside opens and closes it here.
Singleton {
	id: root

	// "centre", the notification centre; "control", the control centre;
	// "keys", the keyboard shortcuts; "weather", the forecast; "jobs", the
	// terminals' jobs; "held", the notifications held during a share;
	// "power", the power menu under the launcher. "" while none is open.
	property string name: ""
	// The screen it's open on
	property ShellScreen screen: null
	// The page showing (the control centre's "wifi", say); "" for its first
	property string page: ""

	// Whether `panel` is open on the screen `on`
	function shows(panel: string, on: ShellScreen): bool {
		return name === panel && screen === on;
	}

	function toggle(panel: string, on: ShellScreen) {
		if (shows(panel, on)) {
			close();
		} else {
			page = "";
			name = panel;
			screen = on;
		}
	}

	// A panel on a page ("" for its first), or closed if it's already open
	// there
	function open(panel: string, onPage: string, on: ShellScreen) {
		if (shows(panel, on) && page === onPage) {
			close();
			return;
		}
		page = onPage;
		name = panel;
		screen = on;
	}

	function close() {
		name = "";
		screen = null;
		page = "";
	}

	// Its monitor unplugged: closed, or popups would stay held back for it
	Connections {
		target: Quickshell

		function onScreensChanged() {
			if (root.screen !== null && !Quickshell.screens.some(s => s === root.screen))
				root.close();
		}
	}

	// For keybinds: `qs ipc -c islands call panel toggle centre` (or
	// control), on the focused screen; `… panel open control wifi` opens it
	// on a page
	IpcHandler {
		target: "panel"

		function toggle(name: string): void {
			root.toggle(name, Compositor.focusedScreen);
		}

		function open(name: string, page: string): void {
			root.open(name, page, Compositor.focusedScreen);
		}
	}
}
