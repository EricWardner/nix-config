import QtQuick

// Something to start on an empty workspace, on Sky, with the launcher for
// anything else
SkyCard {
	spacing: 12

	BarText {
		text: "This workspace is empty"
		font.pixelSize: 13
		font.weight: Font.DemiBold
	}

	Row {
		spacing: 8

		Repeater {
			model: [[Glyphs.terminal, "Ghostty", ["ghostty"]], [Glyphs.globe, "Chrome", ["google-chrome-stable"]], [Glyphs.folder, "Files", ["thunar"]]]

			Rectangle {
				id: app

				required property var modelData

				width: (300 - 32 - 16) / 3
				height: 64
				radius: 14
				color: hover.hovered ? Theme.alpha(Theme.fg, 0.16) : Theme.alpha(Theme.fg, 0.1)

				Column {
					anchors.centerIn: parent
					spacing: 6

					BarText {
						anchors.horizontalCenter: parent.horizontalCenter
						text: app.modelData[0]
						font.pixelSize: 20
					}

					BarText {
						anchors.horizontalCenter: parent.horizontalCenter
						text: app.modelData[1]
						font.pixelSize: 12
					}
				}

				HoverHandler {
					id: hover
				}

				TapHandler {
					cursorShape: Qt.PointingHandCursor
					onTapped: Desktop.launch(app.modelData[2])
				}
			}
		}
	}

	BarText {
		text: "Super+Space for everything else"
		color: Theme.alpha(Theme.fg, 0.8)
		font.pixelSize: 12
	}
}
