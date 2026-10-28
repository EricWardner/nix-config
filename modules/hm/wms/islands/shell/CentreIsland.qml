import QtQuick
import Quickshell.Hyprland

// The island in the middle of the bar: the clock at rest (a click opens
// the notification centre), and on the focused monitor, by rising
// priority, notifications, the volume popup, the notification centre, and
// the questions NetworkManager and BlueZ ask (a Wi-Fi password, a passkey)
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

	PromptMode {
		active: Agent.current !== null && root.focused
	}
}
