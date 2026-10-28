import QtQuick

// A screen recording in the centre island, on every monitor: the countdown
// before it starts (a click cancels), then a red dot, how long it's run,
// its size, and a stop button. Below notifications and the volume popup.
IslandMode {
	id: root

	readonly property bool counting: Capture.phase === "countdown"
	property real now: Date.now()

	priority: 10
	islandWidth: counting ? 190 : 252
	islandHeight: 30
	rim: Theme.red

	Timer {
		interval: 1000
		repeat: true
		running: Capture.phase === "recording"
		triggeredOnStart: true
		onTriggered: root.now = Date.now()
	}

	Row {
		anchors.fill: parent
		anchors.leftMargin: 14
		anchors.rightMargin: 4
		spacing: 10

		Rectangle {
			anchors.verticalCenter: parent.verticalCenter
			width: 9
			height: 9
			radius: 5
			color: Theme.red

			SequentialAnimation on opacity {
				running: Capture.phase === "recording"
				loops: Animation.Infinite

				NumberAnimation {
					to: 0.3
					duration: 550
				}
				NumberAnimation {
					to: 1
					duration: 550
				}
			}
		}

		BarText {
			anchors.verticalCenter: parent.verticalCenter
			text: {
				if (root.counting)
					return "Recording in " + Capture.countdown;
				const seconds = Math.max(0, Math.floor((root.now - Capture.since) / 1000));
				return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
			}
			color: Theme.ink
			font.pixelSize: 14
			font.weight: Font.DemiBold
			font.features: {
				"tnum": 1
			}
		}

		BarText {
			visible: !root.counting && Capture.size !== ""
			anchors.verticalCenter: parent.verticalCenter
			text: Capture.size.replace("x", " × ")
			color: Theme.inkDim
			font.pixelSize: 12
		}
	}

	// Stops the recording (or the countdown)
	Rectangle {
		anchors.right: parent.right
		anchors.rightMargin: 4
		anchors.verticalCenter: parent.verticalCenter
		width: 40
		height: 22
		radius: 11
		color: stopHover.hovered ? Theme.alpha(Theme.ink, 0.16) : Theme.alpha(Theme.ink, 0.08)

		Rectangle {
			anchors.centerIn: parent
			width: 9
			height: 9
			radius: 2
			color: Theme.red
		}

		HoverHandler {
			id: stopHover
		}

		MouseArea {
			anchors.fill: parent
			onClicked: root.counting ? Capture.cancel() : Capture.stopRecording()
		}
	}
}
