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

	readonly property bool focused: Compositor.focusedScreen === screen
	readonly property real heldCentre: sharing.heldCentre

	ClockMode {
		MouseArea {
			anchors.fill: parent
			cursorShape: Qt.PointingHandCursor
			onClicked: Panels.toggle("centre", root.screen)
		}
	}

	// Not over the control centre, whose sliders show the level already
	OsdMode {
		active: Osd.showing && root.focused && !Panels.shows("control", root.screen)
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
		active: Panels.shows("centre", root.screen)
	}

	KeysMode {
		active: Panels.shows("keys", root.screen)
	}

	PromptMode {
		active: Agent.current !== null && root.focused
	}
}
