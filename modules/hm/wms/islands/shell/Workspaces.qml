import QtQuick
import Quickshell
import Quickshell.Hyprland

// This monitor's workspaces in order, then its special ones (chat, browser)
// after a short divider
Row {
	id: root

	required property ShellScreen screen
	readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)

	readonly property var mine: Hyprland.workspaces.values.filter(w => w.monitor === root.monitor)
	readonly property var normal: mine.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
	readonly property var special: mine.filter(w => w.id < 0).sort((a, b) => a.name.localeCompare(b.name))

	// How much each workspace shows (WorkspaceButton), as the bar has room
	property int level: 0
	// The row's width at each level, for the bar to choose by
	readonly property var widths: [0, 1, 2].map(level => {
		let width = 0;
		let shown = 0;
		for (const repeater of [normalRepeater, specialRepeater]) {
			for (let i = 0; i < repeater.count; i++) {
				const button = repeater.itemAt(i);
				if (button) {
					width += button.widths[level];
					shown++;
				}
			}
		}
		if (special.length > 0) {
			width += divider.width;
			shown++;
		}
		return width + spacing * Math.max(0, shown - 1);
	})

	spacing: 8

	// Which special workspace a monitor shows is only in its IPC object,
	// which Quickshell doesn't refresh when one is toggled. Opening one on
	// another monitor moves it there without a moveworkspacev2, so its
	// monitor (which bar lists it) needs the workspaces refreshed too.
	Connections {
		target: Hyprland

		function onRawEvent(event) {
			if (event.name === "activespecial") {
				Hyprland.refreshMonitors();
				Hyprland.refreshWorkspaces();
			}
		}
	}

	Repeater {
		id: normalRepeater

		model: root.normal

		WorkspaceButton {
			monitor: root.monitor
			level: root.level
		}
	}

	Rectangle {
		id: divider

		visible: root.special.length > 0
		width: 1
		height: 14
		color: Theme.alpha(Theme.fg, 0.5)
		anchors.verticalCenter: parent.verticalCenter
	}

	Repeater {
		id: specialRepeater

		model: root.special

		WorkspaceButton {
			monitor: root.monitor
			level: root.level
		}
	}
}
