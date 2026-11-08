import QtQuick

// A labelled switch in a pill, filled in the accent while it's on: the
// notification centre's Keep Awake and Do Not Disturb
Rectangle {
	id: root

	property string glyph
	property string text
	property bool on: false

	signal toggled

	implicitWidth: row.implicitWidth + 22
	implicitHeight: 28
	radius: height / 2
	color: on ? Theme.accent : Theme.alpha(Theme.ink, hover.hovered ? 0.12 : 0.06)

	Row {
		id: row

		anchors.centerIn: parent
		spacing: 6

		BarText {
			text: root.glyph
			color: Theme.ink
			font.pixelSize: 13
			anchors.verticalCenter: parent.verticalCenter
		}

		BarText {
			text: root.text
			color: Theme.ink
			font.pixelSize: 13
			font.weight: Font.Medium
			anchors.verticalCenter: parent.verticalCenter
		}
	}

	HoverHandler {
		id: hover
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.toggled()
	}
}
