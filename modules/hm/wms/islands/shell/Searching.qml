import QtQuick

// Three breathing dots: scanning for networks or devices
Row {
	id: root

	property bool running: true

	spacing: 3
	visible: running

	Repeater {
		model: 3

		Rectangle {
			required property int index

			width: 4
			height: 4
			radius: 2
			color: Theme.ink
			anchors.verticalCenter: parent.verticalCenter

			SequentialAnimation on opacity {
				running: root.running
				loops: Animation.Infinite

				PauseAnimation {
					duration: index * 200
				}
				NumberAnimation {
					from: 0.25
					to: 1
					duration: 600
				}
				NumberAnimation {
					from: 1
					to: 0.25
					duration: 600
				}
				PauseAnimation {
					duration: (2 - index) * 200
				}
			}
		}
	}
}
