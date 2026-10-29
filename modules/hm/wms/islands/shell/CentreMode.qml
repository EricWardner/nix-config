import QtQuick
import Quickshell

// The notification centre: the clock's island grown into the time and date,
// a calendar with a dot on each day with an event, the picked day's events,
// UTC and what's playing, beside the notification history with Do Not
// Disturb and "Clear all". A click on the clock opens it (or `qs ipc -c
// islands call panel toggle centre`); Esc or a click outside closes it, as
// a popup does.
IslandMode {
	id: root

	priority: 40
	islandWidth: 724
	// Taller for a day with more events than fit
	islandHeight: Math.max(476, (content.item?.sideHeight ?? 0) + 36)

	focus: current
	onCurrentChanged: if (current)
		forceActiveFocus()
	Keys.onEscapePressed: Desktop.closePanel()

	SystemClock {
		id: clock

		precision: SystemClock.Minutes
	}

	// Built while it shows (and as it fades): on every bar it would
	// otherwise keep a calendar and the notification list up to date unseen
	Loader {
		id: content

		anchors.fill: parent
		anchors.margins: 18
		active: root.current || root.visible

		sourceComponent: Row {
			readonly property real sideHeight: side.implicitHeight

			spacing: 18

			Column {
				id: side

				width: 262
				spacing: 12

				Column {
					BarText {
						text: Qt.formatTime(clock.date, "h:mm AP")
						color: Theme.ink
						font.pixelSize: 34
						font.weight: Font.DemiBold
					}

					BarText {
						text: Qt.formatDate(clock.date, "dddd d MMMM")
						color: Theme.inkDim
						font.pixelSize: 14
					}
				}

				Rectangle {
					width: parent.width
					height: calendar.implicitHeight + 20
					radius: 16
					color: Theme.alpha(Theme.ink, 0.06)

					Calendar {
						id: calendar

						x: 12
						y: 10
						width: parent.width - 24
						today: clock.date
					}
				}

				DayEvents {
					width: parent.width
					day: calendar.selected
					onOpened: Desktop.closePanel()
				}

				// The other zone the old bar's clock could show
				Rectangle {
					width: parent.width
					height: 40
					radius: 12
					color: Theme.alpha(Theme.ink, 0.06)

					BarText {
						x: 12
						anchors.verticalCenter: parent.verticalCenter
						text: "UTC"
						color: Theme.inkDim
						font.pixelSize: 12
					}

					BarText {
						anchors.right: parent.right
						anchors.rightMargin: 12
						anchors.verticalCenter: parent.verticalCenter
						text: String(clock.date.getUTCHours()).padStart(2, "0") + ":" + String(clock.date.getUTCMinutes()).padStart(2, "0")
						color: Theme.ink
						font.pixelSize: 14
						font.weight: Font.DemiBold
						font.features: {
							"tnum": 1
						}
					}
				}

				MediaCard {
					width: parent.width
				}
			}

			Column {
				width: parent.width - side.width - parent.spacing
				height: parent.height
				spacing: 8

				Item {
					id: header

					width: parent.width
					height: 30

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						text: "Notifications"
						color: Theme.ink
						font.pixelSize: 15
						font.weight: Font.DemiBold
					}

					Row {
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						spacing: 4

						// Filled in the accent while it's on
						Rectangle {
							width: dndRow.implicitWidth + 22
							height: 28
							radius: 14
							color: Inbox.dnd ? Theme.accent : Theme.alpha(Theme.ink, dndHover.hovered ? 0.12 : 0.06)

							Row {
								id: dndRow

								anchors.centerIn: parent
								spacing: 6

								BarText {
									text: Glyphs.moonFill
									color: Theme.ink
									font.pixelSize: 13
									anchors.verticalCenter: parent.verticalCenter
								}

								BarText {
									text: "Do Not Disturb"
									color: Theme.ink
									font.pixelSize: 13
									font.weight: Font.Medium
									anchors.verticalCenter: parent.verticalCenter
								}
							}

							HoverHandler {
								id: dndHover
							}

							MouseArea {
								anchors.fill: parent
								onClicked: Inbox.dnd = !Inbox.dnd
							}
						}

						Rectangle {
							visible: Inbox.history.length > 0
							width: clearText.implicitWidth + 18
							height: 28
							radius: 14
							color: clearHover.hovered ? Theme.alpha(Theme.ink, 0.08) : "transparent"

							BarText {
								id: clearText

								anchors.centerIn: parent
								text: "Clear all"
								color: Theme.inkDim
								font.pixelSize: 13
								font.weight: Font.Medium
							}

							HoverHandler {
								id: clearHover
							}

							MouseArea {
								anchors.fill: parent
								onClicked: Inbox.clearAll()
							}
						}
					}
				}

				// Newest first
				ListView {
					width: parent.width
					height: parent.height - header.height - parent.spacing
					clip: true
					spacing: 8
					boundsBehavior: Flickable.StopAtBounds
					model: Array.from(Inbox.history).reverse()

					delegate: Rectangle {
						required property var modelData

						width: ListView.view.width
						height: card.implicitHeight
						radius: 16
						color: Theme.alpha(Theme.ink, 0.06)

						NotificationCard {
							id: card

							width: parent.width
							notification: modelData
							time: Inbox.age(modelData, clock.date)
							onActivated: {
								Inbox.activate(modelData);
								Desktop.closePanel();
							}
						}
					}

					BarText {
						anchors.centerIn: parent
						visible: Inbox.history.length === 0
						text: "No notifications"
						color: Theme.inkDim
						font.pixelSize: 13
					}
				}
			}
		}
	}
}
