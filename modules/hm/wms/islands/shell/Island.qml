import QtQuick
import QtQuick.Effects
import Quickshell.Hyprland

// The island in the middle of the bar, and everything it grows into. At
// rest it's the clock in faint glass. On the focused monitor it grows into
// the active mode with the highest priority (the volume popup over a
// notification, say): light glass with dark ink, at that mode's size,
// growing around the bar's centre and downwards so nothing beside it moves.
Item {
	id: root

	required property HyprlandMonitor monitor

	readonly property bool focused: Hyprland.focusedMonitor === monitor
	readonly property list<IslandMode> modes: [clock, osd, notification]
	readonly property IslandMode current: modes.reduce((best, mode) => mode.active && mode.priority > best.priority ? mode : best, clock)

	width: current.islandWidth
	height: current.islandHeight

	Behavior on width {
		Morph {}
	}
	Behavior on height {
		Morph {}
	}

	RectangularShadow {
		anchors.fill: glass
		radius: glass.radius
		offset.y: 10
		blur: 30
		color: Qt.rgba(0, 0, 0, 0.3)
		opacity: root.current.resting ? 0 : 1

		Behavior on opacity {
			NumberAnimation {
				duration: 300
			}
		}
	}

	Rectangle {
		id: glass

		anchors.fill: parent
		// A pill while it's a line high; rounded corners once it's taller
		radius: Math.min(height / 2, 24)
		color: root.current.resting ? Theme.islandFill : Theme.grownFill
		border.width: 1
		border.color: root.current.resting ? Theme.islandRim : root.current.rim

		Behavior on color {
			ColorAnimation {
				duration: 300
			}
		}
		Behavior on border.color {
			ColorAnimation {
				duration: 300
			}
		}
	}

	Item {
		anchors.fill: parent
		clip: true

		ClockMode {
			id: clock

			current: root.current === clock
		}

		OsdMode {
			id: osd

			active: Osd.showing && root.focused
			current: root.current === osd
		}

		NotificationMode {
			id: notification

			active: Inbox.popup !== null && root.focused
			current: root.current === notification
		}
	}
}
