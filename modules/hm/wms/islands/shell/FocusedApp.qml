import QtQuick
import Quickshell
import Quickshell.Hyprland

// The app of the window focused last on this monitor, by its desktop entry's
// name, bright while the monitor has focus. Never the window's title: a
// shared screen would show what's in it.
BarText {
	id: root

	required property HyprlandMonitor monitor

	// On the monitor's workspace, or its special one while that's open
	readonly property var shown: Hyprland.toplevels.values.filter(t => t.workspace !== null && (t.workspace === monitor?.activeWorkspace || t.workspace.name === monitor?.lastIpcObject?.specialWorkspace?.name))
	// Hyprland keeps the last window active on an empty workspace
	readonly property HyprlandToplevel window: monitor?.focused && shown.includes(Hyprland.activeToplevel) ? Hyprland.activeToplevel : shown.reduce((last, t) => last === null || recency(t) < recency(last) ? t : last, null)
	readonly property string appId: window?.wayland?.appId ?? window?.lastIpcObject?.class ?? ""
	readonly property string name: {
		if (window === null)
			return "Desktop";
		// Looked up again once the desktop entries are read
		DesktopEntries.applications.values;
		return ({
				"chrome-work.tiberius.com__-Default": "Gather",
				"com.mitchellh.ghostty.btop": "btop"
			})[appId] ?? DesktopEntries.heuristicLookup(appId)?.name ?? appId;
	}

	function recency(window: HyprlandToplevel): real {
		return window.lastIpcObject.focusHistoryID ?? Infinity;
	}

	text: name.length > 20 ? name.slice(0, 19) + "…" : name
	opacity: monitor?.focused ? 1 : 0.5

	// The focus history comes with the windows' details, fetched on request
	Connections {
		target: Hyprland

		function onActiveToplevelChanged() {
			Hyprland.refreshToplevels();
		}
	}
}
