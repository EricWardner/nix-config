import QtQuick

// The job island grown, from its "+N": every job, a row each, failures
// first. A click on a row goes to that job's terminal; a right click puts a
// finished one away. Esc or a click outside closes it, and so does the last
// job going.
IslandMode {
	id: root

	priority: 40
	cornerRadius: 20
	islandWidth: Math.max(260, column.implicitWidth + 24)
	islandHeight: column.implicitHeight + 16

	focus: current
	onCurrentChanged: if (current)
		forceActiveFocus()

	Keys.onEscapePressed: Desktop.closePanel()

	Column {
		id: column

		x: 12
		y: 8
		width: parent.width - 24

		Repeater {
			model: Jobs.shown

			Item {
				id: row

				required property var modelData
				readonly property var job: modelData
				readonly property bool running: job.state === "run"
				readonly property bool passed: job.code === 0

				width: column.width
				implicitWidth: 18 + 10 + name.implicitWidth + 24 + status.implicitWidth + 16
				height: 34

				Rectangle {
					anchors.fill: parent
					radius: 10
					color: Theme.inkTrack
					visible: area.containsMouse
				}

				BarText {
					id: icon

					x: 8
					anchors.verticalCenter: parent.verticalCenter
					width: 18
					horizontalAlignment: Text.AlignHCenter
					text: row.running ? Glyphs.terminal : row.passed ? Glyphs.checkCircle : Glyphs.xCircle
					color: row.running ? Theme.inkBlue : row.passed ? Theme.inkGreen : Theme.inkRed
					font.pixelSize: row.running ? 14 : 16
				}

				BarText {
					id: name

					anchors.left: icon.right
					anchors.leftMargin: 10
					anchors.verticalCenter: parent.verticalCenter
					text: row.job.name
					textFormat: Text.PlainText
					color: Theme.ink
					font.pixelSize: 14
				}

				BarText {
					id: status

					anchors.right: parent.right
					anchors.rightMargin: 8
					anchors.verticalCenter: parent.verticalCenter
					text: {
						const job = row.job;
						if (row.running)
							return Jobs.clock(Jobs.now - job.started);
						const took = Jobs.duration(job.ended - job.started);
						return !job.shell ? "done · " + took : row.passed ? "passed · " + took : "failed · exit " + job.code;
					}
					color: Theme.inkDim
					font.pixelSize: 13
					font.features: {
						"tnum": 1
					}
				}

				MouseArea {
					id: area

					anchors.fill: parent
					hoverEnabled: true
					acceptedButtons: Qt.LeftButton | Qt.RightButton
					cursorShape: Qt.PointingHandCursor
					onClicked: mouse => {
						if (mouse.button === Qt.LeftButton) {
							Desktop.closePanel();
							Jobs.open(row.job);
						} else if (!row.running) {
							Jobs.dismiss(row.job);
						}
					}
				}
			}
		}
	}
}
