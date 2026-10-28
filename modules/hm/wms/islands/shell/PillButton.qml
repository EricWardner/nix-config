import QtQuick

// A rounded button: the primary one filled in ink, the rest plain until
// hovered; dimmed and inert while not `enabled`
Rectangle {
	id: root

	property string text
	property bool primary: false

	signal clicked

	implicitWidth: label.implicitWidth + 28
	implicitHeight: 30
	radius: height / 2
	opacity: enabled ? 1 : 0.4
	color: primary ? Theme.ink : hover.hovered ? Theme.inkTrack : "transparent"
	border.width: primary ? 0 : 1
	border.color: Theme.alpha(Theme.ink, 0.18)

	BarText {
		id: label

		anchors.centerIn: parent
		text: root.text
		color: root.primary ? Theme.fg : Theme.ink
		font.pixelSize: 13
		font.weight: root.primary ? Font.DemiBold : Font.Medium
	}

	HoverHandler {
		id: hover
	}

	MouseArea {
		anchors.fill: parent
		enabled: root.enabled
		onClicked: root.clicked()
	}
}
