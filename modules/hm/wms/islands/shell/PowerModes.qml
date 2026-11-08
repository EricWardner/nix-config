import QtQuick
import Quickshell.Services.UPower

// The power profile, as a segmented control
Rectangle {
	height: 36
	radius: 12
	color: Theme.alpha(Theme.ink, 0.06)

	Row {
		anchors.fill: parent
		anchors.margins: 3

		Repeater {
			model: [
				{
					"name": "Saver",
					"profile": PowerProfile.PowerSaver
				},
				{
					"name": "Balanced",
					"profile": PowerProfile.Balanced
				},
				{
					"name": "Performance",
					"profile": PowerProfile.Performance
				}
			]

			Rectangle {
				required property var modelData

				readonly property bool chosen: PowerProfiles.profile === modelData.profile

				width: parent.width / 3
				height: parent.height
				radius: 9
				color: chosen ? Theme.ink : "transparent"
				opacity: modelData.profile === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile ? 0.35 : 1

				BarText {
					anchors.centerIn: parent
					text: modelData.name
					color: chosen ? Theme.fg : Theme.ink
					font.pixelSize: 12
					font.weight: chosen ? Font.DemiBold : Font.Medium
				}

				MouseArea {
					anchors.fill: parent
					onClicked: PowerProfiles.profile = modelData.profile
				}
			}
		}
	}
}
