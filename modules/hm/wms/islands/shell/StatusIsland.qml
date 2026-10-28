import QtQuick
import Quickshell.Hyprland

// The island at the right of the bar: the system's state at rest, and the
// control centre it grows into, leftwards and down
Island {
	id: root

	required property HyprlandMonitor monitor
	// Its width at rest, for what sits beside it to stay put as it grows
	readonly property real restWidth: status.islandWidth

	StatusMode {
		id: status

		monitor: root.monitor
	}

	ControlMode {
		active: Desktop.panel === "control" && Desktop.panelOn === root.monitor
	}
}
