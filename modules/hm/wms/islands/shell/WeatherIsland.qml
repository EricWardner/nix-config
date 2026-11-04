import QtQuick
import Quickshell.Hyprland

// The weather before the clock, and the forecast a click grows it into,
// leftwards and down
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
