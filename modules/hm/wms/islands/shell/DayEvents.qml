import QtQuick
import QtQuick.Effects

// One day's events, in a card under the notification centre's calendar:
// all-day ones, then the rest by time, those over dimmed. A click opens one
// in Google Calendar; its Join pill joins it.
Rectangle {
	id: root

	required property date day
	readonly property var events: Events.onDay(day)
	readonly property int rowHeight: 38
	// Below the scrolled view, or only partly in it
	readonly property int hidden: Math.max(0, Math.ceil((list.contentHeight - list.contentY - list.height - 1) / rowHeight))

	// Something opened in the browser: the panel can close
	signal opened

	implicitHeight: heading.height + column.implicitHeight + 10
	radius: 16
	color: Theme.alpha(Theme.ink, 0.06)

	BarText {
		id: heading

		x: 12
		y: 4
		height: 32
		verticalAlignment: Text.AlignVCenter
		text: root.day.toDateString() === new Date(Events.now).toDateString() ? "Today" : Qt.formatDate(root.day, "dddd d")
		color: Theme.ink
		font.pixelSize: 13
		font.weight: Font.DemiBold
	}

	Item {
		anchors.right: parent.right
		anchors.rightMargin: 12
		anchors.verticalCenter: heading.verticalCenter
		width: more.implicitWidth
		height: heading.height
		visible: root.hidden > 0

		Row {
			id: more

			anchors.verticalCenter: parent.verticalCenter
			spacing: 4

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: root.hidden + " more"
				color: Theme.inkDim
				font.pixelSize: 12
				font.weight: Font.Medium
			}

			// Square, so it turns in place
			BarText {
				anchors.verticalCenter: parent.verticalCenter
				width: implicitHeight
				horizontalAlignment: Text.AlignHCenter
				text: Glyphs.chevronRight
				rotation: 90
				color: Theme.inkDim
				font.pixelSize: 10
			}
		}

		MouseArea {
			anchors.fill: parent
			cursorShape: Qt.PointingHandCursor
			onClicked: toEnd.start()
		}
	}

	NumberAnimation {
		id: toEnd

		target: list
		property: "contentY"
		to: list.contentHeight - list.height
		duration: 250
		easing.type: Easing.OutCubic
	}

	Rectangle {
		id: fade

		width: list.width
		height: list.height
		visible: false
		layer.enabled: true
		layer.smooth: true
		gradient: Gradient {
			GradientStop {
				position: 0
				color: "black"
			}
			GradientStop {
				position: 1 - 28 / Math.max(28, fade.height)
				color: "black"
			}
			GradientStop {
				position: 1
				color: "transparent"
			}
		}
	}

	// Scrolls when the card is given less than its height
	Flickable {
		id: list

		x: 12
		y: heading.y + heading.height
		width: parent.width - 24
		height: parent.height - y - 6
		contentHeight: column.implicitHeight
		clip: true
		interactive: contentHeight > height
		boundsBehavior: Flickable.StopAtBounds
		layer.enabled: root.hidden > 0
		layer.smooth: true
		layer.effect: MultiEffect {
			maskEnabled: true
			maskSource: fade
			maskThresholdMin: 0.5
			maskSpreadAtMin: 1
		}

		Column {
			id: column

			width: parent.width

			Repeater {
				model: root.events

				Item {
					id: row

					required property var modelData
					readonly property bool over: !modelData.allDay && modelData.end <= Events.now
					readonly property bool joinable: !!modelData.join && !over

					width: column.width
					height: root.rowHeight
					opacity: over ? 0.5 : 1

					Rectangle {
						width: parent.width
						height: 1
						color: Theme.alpha(Theme.ink, 0.1)
					}

					MouseArea {
						anchors.fill: parent
						enabled: !!row.modelData.page
						cursorShape: Qt.PointingHandCursor
						onClicked: {
							Events.open(row.modelData);
							root.opened();
						}
					}

					BarText {
						id: when

						width: 64
						anchors.verticalCenter: parent.verticalCenter
						text: row.modelData.allDay ? "All day" : Qt.formatTime(new Date(row.modelData.start), "h:mm AP")
						color: Theme.inkDim
						font.pixelSize: 12
						font.features: {
							"tnum": 1
						}
					}

					BarText {
						anchors.left: when.right
						anchors.leftMargin: 6
						anchors.right: parent.right
						anchors.rightMargin: join.visible ? join.width + 8 : 0
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
						id: join

						visible: row.joinable
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
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

						MouseArea {
							anchors.fill: parent
							cursorShape: Qt.PointingHandCursor
							onClicked: {
								Events.join(row.modelData);
								root.opened();
							}
						}
					}
				}
			}

			Item {
				visible: root.events.length === 0
				width: column.width
				height: root.rowHeight

				Rectangle {
					width: parent.width
					height: 1
					color: Theme.alpha(Theme.ink, 0.1)
				}

				BarText {
					anchors.verticalCenter: parent.verticalCenter
					text: "No events"
					color: Theme.inkDim
					font.pixelSize: 13
				}
			}
		}
	}
}
