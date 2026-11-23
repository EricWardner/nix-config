pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// What only the compositor can say about a screen. The islands know the
// monitor they're on as Quickshell's ShellScreen, which any compositor has;
// this is where one is matched to Hyprland's monitor.
Singleton {
	// The screen the focus is on
	readonly property ShellScreen focusedScreen: {
		const name = Hyprland.focusedMonitor?.name ?? "";
		return Quickshell.screens.find(screen => screen.name === name) ?? null;
	}

	// No windows on the screen's workspace, so Sky shows there
	function workspaceEmpty(screen: ShellScreen): bool {
		const monitor = screen ? Hyprland.monitorFor(screen) : null;
		return monitor !== null && !Hyprland.toplevels.values.some(t => t.workspace === monitor.activeWorkspace);
	}
}
