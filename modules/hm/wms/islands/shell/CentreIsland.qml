import QtQuick
import Quickshell.Hyprland

// The island in the middle of the bar: the clock at rest (a click opens
// the notification centre), and on the focused monitor the volume popup,
// notifications, and the notification centre, in that order of priority
// below the centre
Island {
	id: root

	required property HyprlandMonitor monitor

	readonly property bool focused: Hyprland.focusedMonitor === monitor

	ClockMode {
		MouseArea {
			anchors.fill: parent
			cursorShape: Qt.PointingHandCursor
			onClicked: Desktop.togglePanel("centre", root.monitor)
		}
	}

	OsdMode {
		active: Osd.showing && root.focused
	}

	NotificationMode {
		active: Inbox.popup !== null && root.focused
	}

	CentreMode {
		active: Desktop.panel === "centre" && Desktop.panelOn === root.monitor
	}
}
