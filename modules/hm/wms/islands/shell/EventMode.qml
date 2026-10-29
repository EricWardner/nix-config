import QtQuick

// A meeting about to start (Events.reminder), over notifications: its
// title, when it starts, and Join, if it has a link, or Dismiss.
IslandMode {
	id: root

	readonly property var event: Events.reminder

	priority: 25
	rim: Theme.accent
	islandWidth: 420
	islandHeight: 64

	Row {
		x: 16
		anchors.verticalCenter: parent.verticalCenter
		width: parent.width - 32
		spacing: 12

		Rectangle {
			anchors.verticalCenter: parent.verticalCenter
			width: 32
			height: 32
			radius: 16
			color: Theme.accent

			BarText {
				anchors.centerIn: parent
				text: Glyphs.calendar
				color: Theme.ink
				font.pixelSize: 15
			}
		}

		Column {
			anchors.verticalCenter: parent.verticalCenter
			width: parent.width - 44 - buttons.width - 12

			BarText {
				width: parent.width
				text: root.event ? Events.title(root.event) : ""
				textFormat: Text.PlainText
				color: Theme.ink
				font.pixelSize: 14
				font.weight: Font.DemiBold
				elide: Text.ElideRight
			}

			BarText {
				text: {
					const event = root.event;
					if (!event)
						return "";
					const minutes = Math.round(Math.abs(event.start - Events.now) / 60000);
					if (event.start > Events.now)
						return minutes <= 1 ? "Starts in a minute" : "Starts in " + minutes + " minutes";
					return minutes < 1 ? "Starting now" : "Started " + minutes + (minutes === 1 ? " minute" : " minutes") + " ago";
				}
				color: Theme.inkDim
				font.pixelSize: 12
			}
		}

		Row {
			id: buttons

			anchors.verticalCenter: parent.verticalCenter
			spacing: 6

			PillButton {
				text: "Dismiss"
				onClicked: Events.dismiss(root.event)
			}

			PillButton {
				visible: !!root.event?.join
				primary: true
				text: "Join"
				onClicked: {
					Events.join(root.event);
					Events.dismiss(root.event);
				}
			}
		}
	}
}
