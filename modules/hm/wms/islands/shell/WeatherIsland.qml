import QtQuick
import Quickshell.Hyprland

// The weather before the clock, with the time of the sun's next change, and
// the forecast a click grows it into, leftwards and down
Island {
	id: root

	required property HyprlandMonitor monitor
	readonly property bool open: Desktop.panel === "weather" && Desktop.panelOn === monitor

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
				anchors.verticalCenter: parent.verticalCenter
				glyph: Weather.current ? Weather.glyph(Weather.current.code, Weather.current.day) : "cloud"
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: Weather.current ? Weather.deg(Weather.current.temp) : ""
				font.pixelSize: Theme.numberSize
				font.features: {
					"tnum": 1
				}
			}

			// The sun's next change (Weather.sky): sunset by day, each
			// twilight in turn through the evening, sunrise overnight
			Row {
				anchors.verticalCenter: parent.verticalCenter
				leftPadding: 5
				spacing: 5
				visible: Weather.sky !== null

				WeatherIcon {
					anchors.verticalCenter: parent.verticalCenter
					glyph: Weather.sky?.next.glyph ?? "sunset"
				}

				BarText {
					anchors.verticalCenter: parent.verticalCenter
					text: Weather.sky ? Weather.clock(Weather.sky.next.time).replace(/ [AP]M$/, "") : ""
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
			onClicked: Desktop.togglePanel("weather", root.monitor)
		}
	}

	ForecastMode {
		active: root.open
	}
}
