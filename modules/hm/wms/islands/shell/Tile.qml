import QtQuick

// A control centre tile: a round icon, filled in the accent while on, that
// toggles; a title over a line of state. When it has a page, the rest of the
// tile opens it (with a chevron); otherwise the whole tile toggles.
Rectangle {
	id: root

	property string glyph
	property string title
	property string subtitle
	property bool on: false
	// The badge's colour while it's on
	property color tint: Theme.accent
	property bool opens: false

	signal toggled
	signal opened

	implicitHeight: 52
	radius: 16
	color: Theme.alpha(Theme.ink, hover.hovered ? 0.1 : 0.06)

	HoverHandler {
		id: hover
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.opens ? root.opened() : root.toggled()
	}

	Rectangle {
		id: badge

		x: 10
		anchors.verticalCenter: parent.verticalCenter
		width: 32
		height: 32
		radius: 16
		color: root.on ? root.tint : Theme.inkTrack

		Behavior on color {
			ColorAnimation {
				duration: 150
			}
		}

		BarText {
			anchors.centerIn: parent
			text: root.glyph
			color: Theme.ink
			font.pixelSize: 15
		}

		MouseArea {
			anchors.fill: parent
			onClicked: root.toggled()
		}
	}

	Column {
		anchors.left: badge.right
		anchors.leftMargin: 10
		anchors.right: chevron.visible ? chevron.left : parent.right
		anchors.rightMargin: 8
		anchors.verticalCenter: parent.verticalCenter

		BarText {
			width: parent.width
			text: root.title
			color: Theme.ink
			font.pixelSize: 13
			font.weight: Font.DemiBold
			elide: Text.ElideRight
		}

		BarText {
			width: parent.width
			visible: text !== ""
			text: root.subtitle
			color: Theme.inkDim
			font.pixelSize: 12
			elide: Text.ElideRight
		}
	}

	BarText {
		id: chevron

		visible: root.opens
		anchors.right: parent.right
		anchors.rightMargin: 10
		anchors.verticalCenter: parent.verticalCenter
		text: "›"
		color: Theme.inkDim
		font.pixelSize: 18
	}
}
