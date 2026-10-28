import QtQuick
import Quickshell.Hyprland

// This monitor's workspaces in order, then its special ones (chat, browser)
// after a short divider
Row {
	id: root

	required property HyprlandMonitor monitor

	readonly property var mine: Hyprland.workspaces.values.filter(w => w.monitor === root.monitor)
	readonly property var normal: mine.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
	readonly property var special: mine.filter(w => w.id < 0).sort((a, b) => a.name.localeCompare(b.name))

	spacing: 8

	// Which special workspace a monitor shows is only in its IPC object,
	// which Quickshell doesn't refresh when one is toggled
	Connections {
		target: Hyprland

		function onRawEvent(event) {
			if (event.name === "activespecial")
				Hyprland.refreshMonitors();
		}
	}

	Repeater {
		model: root.normal

		WorkspaceButton {
			monitor: root.monitor
		}
	}

	Rectangle {
		visible: root.special.length > 0
		width: 1
		height: 14
		color: Theme.alpha(Theme.fg, 0.5)
		anchors.verticalCenter: parent.verticalCenter
	}

	Repeater {
		model: root.special

		WorkspaceButton {
			monitor: root.monitor
		}
	}
}
