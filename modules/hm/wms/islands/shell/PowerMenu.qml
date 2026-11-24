import QtQuick
import QtQuick.Effects

// The power menu, dropped from the launcher by a right click (or `qs ipc -c
// islands call panel toggle power`). Esc or a click outside closes it.
Item {
	id: root

	// Where Hyprland may blur behind it: a little past the glass, which (by
	// its alpha) trims the blur to its own smooth edge
	readonly property Item blurArea: blurArea

	implicitWidth: 188
	implicitHeight: list.implicitHeight + 16
	onVisibleChanged: {
		if (visible)
			list.forceActiveFocus();
	}
	Keys.onEscapePressed: Panels.close()

	RectangularShadow {
		anchors.fill: glass
		radius: glass.radius
		offset.y: 2
		blur: 6
		color: Qt.rgba(0, 0, 0, 0.25)
	}

	Item {
		id: blurArea

		anchors.fill: parent
		anchors.margins: -2
	}

	Rectangle {
		id: glass

		anchors.fill: parent
		radius: 18
		color: Theme.grownFill
		border.width: 1
		border.color: Theme.grownRim
	}

	PowerList {
		id: list

		x: 8
		y: 8
		width: parent.width - 16
	}
}
