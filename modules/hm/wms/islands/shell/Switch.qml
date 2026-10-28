import QtQuick

// An on/off switch in the accent; `toggled` asks to flip it, and the owner
// sets `on` from whatever it controls
Rectangle {
	id: root

	property bool on: false

	signal toggled

	implicitWidth: 44
	implicitHeight: 26
	radius: height / 2
	color: on ? Theme.accent : Theme.alpha(Theme.ink, 0.18)

	Behavior on color {
		ColorAnimation {
			duration: 150
		}
	}

	Rectangle {
		x: root.on ? root.width - width - 3 : 3
		anchors.verticalCenter: parent.verticalCenter
		width: 20
		height: 20
		radius: 10
		color: "white"

		Behavior on x {
			NumberAnimation {
				duration: 150
			}
		}
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.toggled()
	}
}
