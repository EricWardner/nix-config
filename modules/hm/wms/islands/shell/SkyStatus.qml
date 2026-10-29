import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

// The machine, in a line at the foot of Sky: the battery, CPU, memory and
// how long it's been up
Rectangle {
	id: root

	property bool shown: false
	readonly property UPowerDevice battery: UPower.displayDevice
	property real uptime: 0

	readonly property var parts: {
		const parts = [];
		if (battery?.isLaptopBattery) {
			const level = battery.percentage * 100;
			parts.push("Battery " + Math.round(level) + "% · " + (UPower.onBattery ? "on battery" : "on power"));
		}
		parts.push("CPU " + Metrics.cpu + "%", "Memory " + Metrics.memory + "%");
		const hours = Math.floor(uptime / 3600);
		if (hours >= 48)
			parts.push("Up " + Math.floor(hours / 24) + " days");
		else if (hours >= 1)
			parts.push("Up " + hours + (hours === 1 ? " hour" : " hours"));
		else
			parts.push("Up " + Math.floor(uptime / 60) + " minutes");
		return parts;
	}

	implicitWidth: row.implicitWidth + 32
	implicitHeight: 34
	radius: 17
	color: Theme.alpha(Theme.bg, 0.32)
	border.width: 1
	border.color: Theme.alpha(Theme.fg, 0.18)

	FileView {
		id: uptimeFile

		path: "/proc/uptime"
		onLoaded: root.uptime = parseFloat(text().split(" ")[0])
	}

	Timer {
		interval: 60000
		repeat: true
		running: root.shown
		triggeredOnStart: true
		onTriggered: uptimeFile.reload()
	}

	Row {
		id: row

		anchors.centerIn: parent
		spacing: 18

		Repeater {
			model: root.parts

			Row {
				required property string modelData
				required property int index

				spacing: 18

				BarText {
					visible: parent.index > 0
					text: "·"
					opacity: 0.5
					font.pixelSize: 13
				}

				BarText {
					text: parent.modelData
					font.pixelSize: 13
				}
			}
		}
	}
}
