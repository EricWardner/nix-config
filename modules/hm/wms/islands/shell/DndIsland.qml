import QtQuick
import Quickshell.Hyprland

// Keep Awake and Do Not Disturb while either is on, in an island of its own
// beside the clock: a cup for Keep Awake; a slashed bell, and how many
// notifications it has kept quiet, for Do Not Disturb. A click opens the
// notification centre, which lists them and turns both off.
Island {
	id: root

	required property HyprlandMonitor monitor

	IslandMode {
		active: true
		resting: true
		islandWidth: row.implicitWidth + 24
		islandHeight: Theme.barHeight - 4

		Row {
			id: row

			anchors.centerIn: parent
			spacing: 8

			BarText {
				visible: KeepAwake.on
				anchors.verticalCenter: parent.verticalCenter
				text: Glyphs.coffee
				font.pixelSize: 14
			}

			BarText {
				visible: Inbox.dnd
				anchors.verticalCenter: parent.verticalCenter
				text: Glyphs.bellSlash
				font.pixelSize: 14
			}

			BarText {
				visible: Inbox.dnd && Inbox.quiet.length > 0
				anchors.verticalCenter: parent.verticalCenter
				text: Inbox.quiet.length
				font.pixelSize: 14
				font.features: {
					"tnum": 1
				}
			}
		}

		MouseArea {
			anchors.fill: parent
			cursorShape: Qt.PointingHandCursor
			onClicked: Desktop.togglePanel("centre", root.monitor)
		}
	}
}
