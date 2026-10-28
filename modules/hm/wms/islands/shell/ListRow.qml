import QtQuick

// A row in a control centre list: an icon (a glyph, or an image from the
// icon theme), a title with a line of state under it, and something on the
// right (a lock, a check, "Pair"). Hover-highlighted; `clicked` on a click.
Rectangle {
	id: root

	property string glyph
	property string image
	property string title
	property string subtitle
	property string trailing
	property bool chosen: false

	signal clicked

	implicitHeight: subtitle !== "" ? 44 : 36
	radius: 10
	color: chosen ? Theme.alpha(Theme.ink, 0.1) : hover.hovered ? Theme.alpha(Theme.ink, 0.06) : "transparent"

	HoverHandler {
		id: hover
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.clicked()
	}

	Item {
		id: icon

		x: 8
		anchors.verticalCenter: parent.verticalCenter
		width: 22
		height: 22

		BarText {
			anchors.centerIn: parent
			visible: root.image === ""
			text: root.glyph
			color: Theme.ink
			font.pixelSize: 16
		}

		Image {
			anchors.fill: parent
			visible: root.image !== ""
			source: root.image
			sourceSize: Qt.size(44, 44)
			smooth: true
		}
	}

	Column {
		anchors.left: icon.right
		anchors.leftMargin: 10
		anchors.right: trailingText.left
		anchors.rightMargin: 8
		anchors.verticalCenter: parent.verticalCenter

		BarText {
			width: parent.width
			text: root.title
			color: Theme.ink
			font.pixelSize: 13
			font.weight: root.chosen ? Font.DemiBold : Font.Normal
			elide: Text.ElideRight
		}

		BarText {
			width: parent.width
			visible: text !== ""
			text: root.subtitle
			color: Theme.inkDim
			font.pixelSize: 11
			elide: Text.ElideRight
		}
	}

	BarText {
		id: trailingText

		anchors.right: parent.right
		anchors.rightMargin: 10
		anchors.verticalCenter: parent.verticalCenter
		text: root.trailing
		color: Theme.inkDim
		font.pixelSize: 12
	}
}
