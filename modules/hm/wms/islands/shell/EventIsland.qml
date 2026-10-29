import QtQuick
import Quickshell.Hyprland

// The next meeting, in an island of its own beside the clock, from half an
// hour before it starts until it ends: "Team sync · in 12m". A click joins
// it, if it has a link, or opens the notification centre and today's list.
Island {
	id: root

	required property HyprlandMonitor monitor
	readonly property var event: Events.next
	readonly property bool soon: event !== null && event.start - Events.now <= 30 * 60 * 1000

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
				anchors.verticalCenter: parent.verticalCenter
				text: Glyphs.calendar
				font.pixelSize: 14
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: {
					const event = root.event;
					if (!event)
						return "";
					const title = Events.title(event);
					return (title.length > 28 ? title.slice(0, 27) + "…" : title) + " · " + Events.until(event);
				}
				textFormat: Text.PlainText
				font.pixelSize: 14
			}
		}

		MouseArea {
			anchors.fill: parent
			cursorShape: Qt.PointingHandCursor
			onClicked: {
				if (root.event?.join)
					Events.join(root.event);
				else
					Desktop.togglePanel("centre", root.monitor);
			}
		}
	}
}
