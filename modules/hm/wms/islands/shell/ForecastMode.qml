import QtQuick

// The weather island grown: now, the next seven hours and the next five
// days. A click on it, Esc or a click outside closes it.
IslandMode {
	id: root

	readonly property var now: Weather.current
	readonly property var today: Weather.days[0] ?? null
	readonly property var hours: now ? [
		{
			label: "Now",
			glyph: Weather.glyph(now.code, now.day),
			temp: now.temp,
			rain: 0
		}
	].concat(Weather.hours.slice(0, 7).map(hour => ({
				label: Weather.hour(hour.time),
				glyph: Weather.glyph(hour.code, hour.day),
				temp: hour.temp,
				rain: hour.rain
			}))) : []
	// The week's range, which each day's bar sits within
	readonly property real lowest: Math.min(...Weather.days.map(day => day.low))
	readonly property real highest: Math.max(...Weather.days.map(day => day.high))

	priority: 40
	cornerRadius: 24
	islandWidth: 392
	islandHeight: column.implicitHeight + 32

	focus: current
	onCurrentChanged: if (current)
		forceActiveFocus()

	Keys.onEscapePressed: Desktop.closePanel()

	MouseArea {
		anchors.fill: parent
		onClicked: Desktop.closePanel()
	}

	Column {
		id: column

		x: 20
		y: 18
		width: parent.width - 40
		spacing: 14

		Row {
			spacing: 14

			WeatherIcon {
				anchors.verticalCenter: parent.verticalCenter
				glyph: root.now ? Weather.glyph(root.now.code, root.now.day) : "cloud"
				size: 44
				strokeWidth: 1.6
				onInk: true
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: root.now ? Weather.deg(root.now.temp) : ""
				color: Theme.ink
				font.family: "SF Pro Display"
				font.pixelSize: 46
				font.weight: Font.Light
				font.features: {
					"tnum": 1
				}
			}

			Column {
				anchors.verticalCenter: parent.verticalCenter
				leftPadding: 2
				spacing: 3

				BarText {
					text: root.now ? Weather.label(root.now.code, root.now.day) : ""
					color: Theme.ink
					font.pixelSize: 15
					font.weight: Font.DemiBold
				}

				BarText {
					text: root.now && root.today ? "Feels " + Weather.deg(root.now.feels) + " · H " + Weather.deg(root.today.high) + " L " + Weather.deg(root.today.low) : ""
					color: Theme.inkDim
					font.pixelSize: 13
				}
			}
		}

		BarText {
			width: parent.width
			text: Weather.summary
			color: Theme.ink
			font.pixelSize: 13
			wrapMode: Text.Wrap
		}

		Row {
			Repeater {
				model: root.hours

				Item {
					id: hour

					required property var modelData
					required property int index

					width: column.width / 8
					height: slot.implicitHeight

					Rectangle {
						anchors.fill: parent
						radius: 12
						color: Theme.alpha(Theme.ink, 0.06)
						visible: hour.index === 0
					}

					Column {
						id: slot

						width: parent.width
						topPadding: 6
						bottomPadding: 6
						spacing: 6

						BarText {
							anchors.horizontalCenter: parent.horizontalCenter
							text: hour.modelData.label
							color: Theme.inkDim
							font.pixelSize: 12
							font.weight: hour.index === 0 ? Font.DemiBold : Font.Normal
						}

						WeatherIcon {
							anchors.horizontalCenter: parent.horizontalCenter
							glyph: hour.modelData.glyph
							size: 20
							onInk: true
						}

						BarText {
							anchors.horizontalCenter: parent.horizontalCenter
							text: Weather.deg(hour.modelData.temp)
							color: Theme.ink
							font.pixelSize: 14
							font.features: {
								"tnum": 1
							}
						}

						BarText {
							anchors.horizontalCenter: parent.horizontalCenter
							height: 13
							text: hour.modelData.rain >= 20 ? hour.modelData.rain + "%" : ""
							color: Theme.inkBlue
							font.pixelSize: 11
							font.weight: Font.DemiBold
						}
					}
				}
			}
		}

		Rectangle {
			width: parent.width
			height: 1
			color: Theme.inkTrack
		}

		Column {
			width: parent.width
			spacing: 2

			Repeater {
				model: Weather.days

				Row {
					id: day

					required property var modelData
					required property int index

					height: 32
					spacing: 8

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						width: 56
						text: day.index === 0 ? "Today" : Qt.formatDate(new Date(day.modelData.time * 1000), "ddd")
						color: Theme.ink
						font.pixelSize: 14
						font.weight: Font.Medium
					}

					WeatherIcon {
						anchors.verticalCenter: parent.verticalCenter
						width: 22
						glyph: Weather.glyph(day.modelData.code, true)
						size: 20
						onInk: true
					}

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						width: 40
						text: day.modelData.rain >= 20 ? day.modelData.rain + "%" : ""
						color: Theme.inkBlue
						font.pixelSize: 11
						font.weight: Font.DemiBold
					}

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						width: 34
						horizontalAlignment: Text.AlignRight
						text: Weather.deg(day.modelData.low)
						color: Theme.inkDim
						font.pixelSize: 14
						font.features: {
							"tnum": 1
						}
					}

					Rectangle {
						anchors.verticalCenter: parent.verticalCenter
						width: column.width - 56 - 22 - 40 - 34 - 34 - 5 * 8
						height: 4
						radius: 2
						color: Theme.inkTrack

						Rectangle {
							readonly property real span: Math.max(1, root.highest - root.lowest)

							x: parent.width * (day.modelData.low - root.lowest) / span
							width: parent.width * (day.modelData.high - day.modelData.low) / span
							height: parent.height
							radius: 2
							color: Theme.alpha(Theme.ink, 0.6)
						}
					}

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						width: 34
						horizontalAlignment: Text.AlignRight
						text: Weather.deg(day.modelData.high)
						color: Theme.ink
						font.pixelSize: 14
						font.features: {
							"tnum": 1
						}
					}
				}
			}
		}

		BarText {
			text: [Weather.place, "updated " + Weather.updated, "Open-Meteo"].filter(part => part).join(" · ")
			color: Theme.inkDim
			font.pixelSize: 11
		}
	}
}
