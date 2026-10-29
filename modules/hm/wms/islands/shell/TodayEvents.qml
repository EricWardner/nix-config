import QtQuick

// The rest of today's calendar, for the notification centre: all-day
// events, then the meetings not over yet. A click joins one with a link.
Column {
	id: root

	readonly property var events: Events.today.filter(e => e.allDay).concat(Events.later).slice(0, 4)

	signal joined

	visible: events.length > 0
	spacing: 4

	BarText {
		height: 30
		verticalAlignment: Text.AlignVCenter
		text: "Today"
		color: Theme.ink
		font.pixelSize: 15
		font.weight: Font.DemiBold
	}

	Repeater {
		model: root.events

		Rectangle {
			id: row

			required property var modelData

			width: root.width
			height: 40
			radius: 12
			color: Theme.alpha(Theme.ink, hover.hovered && modelData.join ? 0.1 : 0.06)

			BarText {
				id: when

				x: 12
				width: 64
				anchors.verticalCenter: parent.verticalCenter
				text: row.modelData.allDay ? "All day" : Qt.formatTime(new Date(row.modelData.start), "h:mm AP")
				color: row.modelData.start <= Events.now && !row.modelData.allDay ? Theme.ink : Theme.inkDim
				font.pixelSize: 12
				font.features: {
					"tnum": 1
				}
			}

			BarText {
				anchors.left: when.right
				anchors.right: parent.right
				anchors.rightMargin: joinText.visible ? joinText.width + 20 : 12
				anchors.verticalCenter: parent.verticalCenter
				text: Events.title(row.modelData)
				textFormat: Text.PlainText
				color: Theme.ink
				font.pixelSize: 13
				font.weight: Font.Medium
				elide: Text.ElideRight
			}

			// As dark as the reminder's Join: the accent is lost on the light glass
			Rectangle {
				id: joinText

				anchors.right: parent.right
				anchors.rightMargin: 8
				anchors.verticalCenter: parent.verticalCenter
				visible: !!row.modelData.join
				width: joinLabel.implicitWidth + 20
				height: 24
				radius: 12
				color: Theme.ink

				BarText {
					id: joinLabel

					anchors.centerIn: parent
					text: "Join"
					color: Theme.fg
					font.pixelSize: 12
					font.weight: Font.DemiBold
				}
			}

			HoverHandler {
				id: hover
			}

			MouseArea {
				anchors.fill: parent
				enabled: !!row.modelData.join
				cursorShape: Qt.PointingHandCursor
				onClicked: {
					Events.join(row.modelData);
					root.joined();
				}
			}
		}
	}
}
