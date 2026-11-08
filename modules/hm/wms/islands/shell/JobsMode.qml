import QtQuick

// The job island grown, from its "+N": every job, a row each, failures
// first. A click on a row goes to that job's terminal; a right click puts a
// finished one away. Esc or a click outside closes it, and so does the last
// job going.
IslandMode {
	id: root

	// The widest row as its text would lay out: measured from the jobs, as
	// the rows themselves are the island's width, not their own
	readonly property real widest: Math.max(0, ...Jobs.shown.map(job => 8 + 18 + 10 + Math.ceil(nameMetrics.advanceWidth(job.name)) + 24 + Math.ceil(statusMetrics.advanceWidth(status(job))) + 8))

	// "1:05" while it runs; "done · 5m 00s", "passed · 12s", "failed · exit 1"
	function status(job: var): string {
		if (job.state === "run")
			return Jobs.clock(Jobs.now - job.started);
		const took = Jobs.duration(job.ended - job.started);
		return !job.shell ? "done · " + took : job.code === 0 ? "passed · " + took : "failed · exit " + job.code;
	}


	priority: 40
	cornerRadius: 20
	// Wide enough for the widest row, up to a point: past it, names are cut
	// short
	islandWidth: Math.max(260, Math.min(480, widest + 24))
	islandHeight: column.implicitHeight + 16

	focus: current
	onCurrentChanged: if (current)
		forceActiveFocus()

	Keys.onEscapePressed: Desktop.closePanel()

	FontMetrics {
		id: nameMetrics

		font.family: Theme.sans
		font.pixelSize: 14
	}

	FontMetrics {
		id: statusMetrics

		font.family: Theme.sans
		font.pixelSize: 13
		font.features: {
			"tnum": 1
		}
	}

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
					anchors.left: icon.right
					anchors.leftMargin: 10
					anchors.right: status.left
					anchors.rightMargin: 24
					anchors.verticalCenter: parent.verticalCenter
					text: row.job.name
					textFormat: Text.PlainText
					elide: Text.ElideRight
					color: Theme.ink
					font: nameMetrics.font
				}

				BarText {
					id: status

					anchors.right: parent.right
					anchors.rightMargin: 8
					anchors.verticalCenter: parent.verticalCenter
					text: root.status(row.job)
					color: Theme.inkDim
					font: statusMetrics.font
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
