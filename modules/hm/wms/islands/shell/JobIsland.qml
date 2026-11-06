import QtQuick

// A command a terminal has been running for over 10 seconds, in an island
// after the clock: "test:e2e 3:12", and "+1" for each other job. When it
// ends, how: "test:e2e passed 6m 04s" or "test:e2e failed exit 1", until
// its terminal is looked at. A click goes to that terminal; a right click
// dismisses a result.
Island {
	id: root

	readonly property var job: Jobs.shown[0] ?? null
	readonly property bool running: job?.state === "run"
	readonly property bool passed: job?.state === "end" && job.code === 0

	IslandMode {
		active: true
		resting: true
		islandWidth: row.implicitWidth + 24
		islandHeight: Theme.barHeight - 4
		restRim: !root.job || root.running ? Theme.islandRim : Theme.alpha(root.passed ? Theme.green : Theme.red, 0.7)

		Row {
			id: row

			anchors.centerIn: parent
			spacing: 8

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: root.running ? Glyphs.terminal : root.passed ? Glyphs.checkCircle : Glyphs.xCircle
				color: root.running ? Theme.cyan : root.passed ? Theme.green : Theme.red
				// The result icons are Material ones, drawn smaller
				font.pixelSize: root.running ? 14 : 16
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				// A Claude prompt is just done
				text: !root.job ? "" : root.running ? root.job.name : root.job.name + (!root.job.shell ? " done" : root.passed ? " passed" : " failed")
				textFormat: Text.PlainText
				font.pixelSize: 14
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: !root.job ? "" : root.running ? Jobs.clock(Jobs.now - root.job.started) : root.passed ? Jobs.duration(root.job.ended - root.job.started) : "exit " + root.job.code
				color: Theme.alpha(Theme.fg, 0.72)
				font.pixelSize: 14
				font.features: {
					"tnum": 1
				}
			}

			// How many other jobs there are
			Rectangle {
				visible: Jobs.shown.length > 1
				anchors.verticalCenter: parent.verticalCenter
				width: more.implicitWidth + 12
				height: 18
				radius: 9
				color: Theme.alpha(Theme.fg, 0.16)

				BarText {
					id: more

					anchors.centerIn: parent
					text: "+" + (Jobs.shown.length - 1)
					font.pixelSize: 12
					font.features: {
						"tnum": 1
					}
				}
			}
		}

		// A right click puts a result away without going there; it leaves a
		// running job alone
		MouseArea {
			anchors.fill: parent
			acceptedButtons: Qt.LeftButton | Qt.RightButton
			cursorShape: Qt.PointingHandCursor
			onClicked: mouse => {
				if (!root.job)
					return;
				if (mouse.button === Qt.LeftButton)
					Jobs.open(root.job);
				else if (!root.running)
					Jobs.dismiss(root.job);
			}
		}
	}
}
