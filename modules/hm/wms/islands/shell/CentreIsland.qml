import QtQuick
import Quickshell

// The island in the middle of the bar: the clock at rest (a click opens
// the notification centre), a screen recording or share on every monitor
// while one runs, and on the focused monitor, by rising priority,
// notifications, a meeting about to start, the volume popup, the
// notification centre, the keyboard shortcuts, and the questions
// NetworkManager, BlueZ and gnome-keyring ask (a Wi-Fi password, a
// passkey, a keyring's password)
Island {
	id: root

	required property ShellScreen screen

	readonly property bool focused: Desktop.focusedScreen === screen
	readonly property real heldCentre: sharing.heldCentre

	ClockMode {
		MouseArea {
			anchors.fill: parent
			cursorShape: Qt.PointingHandCursor
			onClicked: Desktop.togglePanel("centre", root.screen)
		}
	}

	// Not over the control centre, whose sliders show the level already
	OsdMode {
		active: Osd.showing && root.focused && !(Desktop.panel === "control" && Desktop.panelOn === root.screen)
	}

	RecordMode {
		active: Capture.recorder !== "off"
	}

	SharingMode {
		id: sharing

		screen: root.screen
		active: Sharing.active
	}

	NotificationMode {
		active: Inbox.popup !== null && root.focused
	}

	EventMode {
		active: Events.reminder !== null && root.focused
	}

	CentreMode {
		active: Desktop.panel === "centre" && Desktop.panelOn === root.screen
	}

	KeysMode {
		active: Desktop.panel === "keys" && Desktop.panelOn === root.screen
	}

	PromptMode {
		active: Agent.current !== null && root.focused
	}
}
