import QtQuick

// The top of a control centre page: back to the tiles, the title, and the
// page's switch if it has one
Item {
	id: root

	property string title
	property bool hasSwitch: false
	property bool on: false

	signal back
	signal toggled

	implicitHeight: 34

	Rectangle {
		id: backButton

		anchors.verticalCenter: parent.verticalCenter
		width: 32
		height: 32
		radius: 16
		color: Theme.alpha(Theme.ink, backHover.hovered ? 0.12 : 0.06)

		BarText {
			anchors.centerIn: parent
			anchors.horizontalCenterOffset: -1
			text: "‹"
			color: Theme.ink
			font.pixelSize: 20
		}

		HoverHandler {
			id: backHover
		}

		MouseArea {
			anchors.fill: parent
			onClicked: root.back()
		}
	}

	BarText {
		anchors.left: backButton.right
		anchors.leftMargin: 10
		anchors.verticalCenter: parent.verticalCenter
		text: root.title
		color: Theme.ink
		font.pixelSize: 16
		font.weight: Font.DemiBold
	}

	Switch {
		visible: root.hasSwitch
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		on: root.on
		onToggled: root.toggled()
	}
}
