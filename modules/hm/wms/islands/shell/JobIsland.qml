import QtQuick
import Quickshell.Hyprland

// A command a terminal has been running for over 10 seconds, in an island
// after the clock: "test:e2e 3:12", and "+1" for each other job. When it
// ends, how: "test:e2e passed 6m 04s" or "test:e2e failed exit 1", until
// its terminal is looked at. A click goes to that terminal; a right click
// puts the job away, running or not. A click on the "+1" grows it into
// every job (JobsMode).
Island {
	id: root

	required property HyprlandMonitor monitor
	readonly property bool open: Desktop.panel === "jobs" && Desktop.panelOn === monitor
	readonly property var job: Jobs.shown[0] ?? null
	readonly property bool running: job?.state === "run"
	readonly property bool passed: job?.state === "end" && job.code === 0
	// The most it may be wide: the bar's room before the tray. Past it the
	// name is cut short; the time and the "+1" stay.
	property real room: Infinity

	// Nothing left to list
	Connections {
		target: Jobs

		function onShownChanged() {
			if (root.open && Jobs.shown.length === 0)
				Desktop.closePanel();
		}
	}

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
				id: icon

				anchors.verticalCenter: parent.verticalCenter
				text: root.running ? Glyphs.terminal : root.passed ? Glyphs.checkCircle : Glyphs.xCircle
				color: root.running ? Theme.cyan : root.passed ? Theme.green : Theme.red
				// The result icons are Material ones, drawn smaller
				font.pixelSize: root.running ? 14 : 16
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				width: Math.max(0, Math.min(implicitWidth, root.room - 24 - icon.implicitWidth - clock.implicitWidth - (more.visible ? more.width + row.spacing : 0) - 2 * row.spacing))
				// A Claude prompt is just done
				text: !root.job ? "" : root.running ? root.job.name : root.job.name + (!root.job.shell ? " done" : root.passed ? " passed" : " failed")
				textFormat: Text.PlainText
				elide: Text.ElideRight
				font.pixelSize: 14
			}

			BarText {
				id: clock

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
				id: more

				visible: Jobs.shown.length > 1
				anchors.verticalCenter: parent.verticalCenter
				width: count.implicitWidth + 12
				height: 18
				radius: 9
				color: Theme.alpha(Theme.fg, 0.16)

				BarText {
					id: count

					anchors.centerIn: parent
					text: "+" + (Jobs.shown.length - 1)
					font.pixelSize: 12
					font.features: {
						"tnum": 1
					}
				}
			}
		}

		// A right click puts the job away without going there: a result, or
		// a running job (one whose shell was killed never ends). The "+1"
		// (and the pill's end beyond it) opens the list instead.
		MouseArea {
			id: area

			anchors.fill: parent
			acceptedButtons: Qt.LeftButton | Qt.RightButton
			cursorShape: Qt.PointingHandCursor
			onClicked: mouse => {
				if (!root.job)
					return;
				if (more.visible && mouse.button === Qt.LeftButton && mouse.x >= more.mapToItem(area, 0, 0).x - 4)
					Desktop.togglePanel("jobs", root.monitor);
				else if (mouse.button === Qt.LeftButton)
					Jobs.open(root.job);
				else
					Jobs.dismiss(root.job);
			}
		}
	}

	JobsMode {
		active: root.open
	}
}
