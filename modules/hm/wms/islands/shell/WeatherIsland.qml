import QtQuick
import Quickshell

// The weather before the clock, with how long until the sun's next change,
// and the forecast a click grows it into, leftwards and down. The pill's sun and
// temperature fly into the forecast's as it grows, and back as it shrinks.
Island {
	id: root

	required property ShellScreen screen
	readonly property bool open: Panels.shows("weather", screen)
	// How far the sun and temperature are on their way to the forecast
	property real flight: open ? 1 : 0
	// Without the sun's next change, when the bar is short of room (Bar)
	property bool compact: false
	// The pill's width with it, for Bar to judge the room by (added up from
	// its parts: the row's own width depends on compact)
	readonly property real fullWidth: pillIcon.width + row.spacing + pillTemp.width + (Weather.sky !== null ? row.spacing + sun.implicitWidth : 0) + 24

	align: Qt.AlignRight

	Behavior on flight {
		Morph {}
	}

	IslandMode {
		active: true
		resting: true
		islandWidth: row.implicitWidth + 24
		islandHeight: Theme.barHeight - 4

		Row {
			id: row

			anchors.centerIn: parent
			spacing: 7

			WeatherIcon {
				id: pillIcon

				anchors.verticalCenter: parent.verticalCenter
				glyph: Weather.current ? Weather.glyph(Weather.current.code, Weather.current.day) : "cloud"
				opacity: root.flight > 0 ? 0 : 1
			}

			BarText {
				id: pillTemp

				anchors.verticalCenter: parent.verticalCenter
				text: Weather.current ? Weather.deg(Weather.current.temp) : ""
				font.pixelSize: Theme.numberSize
				font.features: {
					"tnum": 1
				}
				opacity: root.flight > 0 ? 0 : 1
			}

			// The sun's next change (Weather.sky), and how long until it:
			// sunset by day, each twilight in turn through the evening,
			// sunrise overnight
			Row {
				id: sun

				anchors.verticalCenter: parent.verticalCenter
				leftPadding: 5
				spacing: 5
				visible: Weather.sky !== null && !root.compact

				WeatherIcon {
					anchors.verticalCenter: parent.verticalCenter
					glyph: Weather.sky?.next.glyph ?? "sunset"
				}

				BarText {
					anchors.verticalCenter: parent.verticalCenter
					text: Weather.skyIn
					font.pixelSize: Theme.numberSize
					font.features: {
						"tnum": 1
					}
				}
			}
		}

		MouseArea {
			anchors.fill: parent
			cursorShape: Qt.PointingHandCursor
			onClicked: Panels.toggle("weather", root.screen)
		}
	}

	ForecastMode {
		id: forecast

		active: root.open
		nowAway: root.flight < 1
	}

	// The two in flight, each drawn as the pill has it and as the forecast
	// does: in the same text, so each matches its end exactly where it
	// lands (curve-rendered text, sharp at any scale, jumped as it was
	// swapped for the real thing)

	Flight {
		from: pillIcon
		to: forecast.nowIcon
		progress: root.flight
		fromLook: smallIcon
		toLook: largeIcon

		WeatherIcon {
			id: smallIcon

			glyph: pillIcon.glyph
		}

		WeatherIcon {
			id: largeIcon

			glyph: forecast.nowIcon.glyph
			size: forecast.nowIcon.size
			strokeWidth: forecast.nowIcon.strokeWidth
			onInk: forecast.nowIcon.onInk
			color: forecast.nowIcon.color
		}
	}

	Flight {
		from: pillTemp
		to: forecast.nowTemp
		progress: root.flight
		fromLook: smallTemp
		toLook: largeTemp

		BarText {
			id: smallTemp

			text: pillTemp.text
			font: pillTemp.font
		}

		BarText {
			id: largeTemp

			text: forecast.nowTemp.text
			color: forecast.nowTemp.color
			font: forecast.nowTemp.font
		}
	}
}
