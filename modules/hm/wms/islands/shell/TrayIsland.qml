import QtQuick
import Quickshell
import Quickshell.Hyprland

// The island at the right of the bar: the tray at rest, and the control
// centre it grows into (leftwards and down) from a click on the network or
// Bluetooth
Island {
	id: root

	required property HyprlandMonitor monitor
	required property QsWindow window

	TrayMode {
		window: root.window
		onControlRequested: Desktop.togglePanel("control", root.monitor)
	}

	ControlMode {
		active: Desktop.panel === "control" && Desktop.panelOn === root.monitor
	}
}
