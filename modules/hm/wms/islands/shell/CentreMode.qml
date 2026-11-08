import QtQuick
import Quickshell

// The notification centre: the clock's island grown into the time, date and
// UTC, a calendar with a dot on each day with an event and the picked day's
// events, beside what's playing and the notification history with Keep
// Awake, Do Not Disturb and "Clear all". A click on the clock opens it (or
// `qs ipc -c islands call panel toggle centre`); Esc or a click outside
// closes it, as a popup does.
IslandMode {
	id: root

	// The bar window below the island, less its shadow: past it the island
	// is cut off
	readonly property real room: Theme.windowHeight - Theme.barTop - 2 - 10

	priority: 40
	islandWidth: 756
	// Taller for a day with more events than fit, up to the room; past it
	// they scroll
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
					id: time

					BarText {
						text: Qt.formatTime(clock.date, "h:mm AP")
						color: Theme.ink
						font.pixelSize: 34
						font.weight: Font.DemiBold
					}

					// With the other zone the old bar's clock could show
					BarText {
						text: Qt.formatDate(clock.date, "dddd d MMMM") + " · " + String(clock.date.getUTCHours()).padStart(2, "0") + ":" + String(clock.date.getUTCMinutes()).padStart(2, "0") + " UTC"
						color: Theme.inkDim
						font.pixelSize: 14
						font.features: {
							"tnum": 1
						}
					}
				}

				Rectangle {
					id: month

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
					height: Math.min(implicitHeight, root.room - 36 - time.height - month.height - 2 * side.spacing)
					day: calendar.selected
					onOpened: Desktop.closePanel()
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

						TogglePill {
							glyph: Glyphs.cupFill
							text: "Keep Awake"
							on: KeepAwake.on
							onToggled: KeepAwake.on = !KeepAwake.on
						}

						TogglePill {
							glyph: Glyphs.moonFill
							text: "Do Not Disturb"
							on: Inbox.dnd
							onToggled: Inbox.dnd = !Inbox.dnd
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

				MediaCard {
					id: media

					width: parent.width
				}

				// Newest first
				ListView {
					width: parent.width
					height: parent.height - header.height - parent.spacing - (media.visible ? media.height + parent.spacing : 0)
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
