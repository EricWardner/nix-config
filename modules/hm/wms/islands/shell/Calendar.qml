import QtQuick

// A month, with today ringed in the accent; the arrows step through months.
// Weeks start on the locale's first day.
Item {
	id: root

	required property date today
	// Months away from today's
	property int offset: 0

	readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)
	// Qt counts Monday 1 to Sunday 7; JavaScript, Sunday 0 to Saturday 6
	readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
	readonly property var days: {
		const lead = (month.getDay() - firstDay + 7) % 7;
		const count = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
		const isThisMonth = month.getFullYear() === today.getFullYear() && month.getMonth() === today.getMonth();
		const cells = [];
		for (let i = 0; i < lead; i++)
			cells.push({
				"day": 0,
				"today": false
			});
		for (let d = 1; d <= count; d++)
			cells.push({
				"day": d,
				"today": isThisMonth && d === today.getDate()
			});
		return cells;
	}

	implicitHeight: column.implicitHeight

	Column {
		id: column

		width: parent.width
		spacing: 6

		Item {
			width: parent.width
			height: 26

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: Qt.formatDate(root.month, "MMMM yyyy")
				color: Theme.ink
				font.pixelSize: 13
				font.weight: Font.DemiBold
			}

			Row {
				anchors.right: parent.right
				height: parent.height

				Repeater {
					model: [
						{
							"glyph": "‹",
							"step": -1
						},
						{
							"glyph": "›",
							"step": 1
						}
					]

					Rectangle {
						required property var modelData

						width: 26
						height: 26
						radius: 13
						color: arrowHover.hovered ? Theme.inkTrack : "transparent"

						BarText {
							anchors.centerIn: parent
							text: modelData.glyph
							color: Theme.ink
							font.pixelSize: 18
						}

						HoverHandler {
							id: arrowHover
						}

						MouseArea {
							anchors.fill: parent
							onClicked: root.offset += modelData.step
						}
					}
				}
			}
		}

		Grid {
			id: grid

			columns: 7
			width: parent.width

			Repeater {
				model: 7

				BarText {
					required property int index

					width: grid.width / 7
					height: 22
					horizontalAlignment: Text.AlignHCenter
					verticalAlignment: Text.AlignVCenter
					text: Qt.locale().dayName((root.firstDay + index) % 7, Locale.NarrowFormat)
					color: Theme.inkDim
					font.pixelSize: 11
				}
			}

			Repeater {
				model: root.days

				Item {
					required property var modelData

					width: grid.width / 7
					height: 28

					Rectangle {
						visible: modelData.today
						anchors.centerIn: parent
						width: 26
						height: 26
						radius: 13
						color: Theme.accent
					}

					BarText {
						anchors.centerIn: parent
						text: modelData.day > 0 ? modelData.day : ""
						color: Theme.ink
						font.pixelSize: 13
						font.weight: modelData.today ? Font.Bold : Font.Normal
					}
				}
			}
		}
	}
}
