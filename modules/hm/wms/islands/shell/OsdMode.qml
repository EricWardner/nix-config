import QtQuick

// The volume or brightness popup (Osd): an icon, the level as a bar, and
// the number. Over a notification, since it's a direct answer to a key.
IslandMode {
	priority: 30
	islandWidth: 300
	islandHeight: 42

	Row {
		anchors.fill: parent
		anchors.leftMargin: 16
		anchors.rightMargin: 16
		spacing: 12

		BarText {
			id: icon

			width: 22
			horizontalAlignment: Text.AlignHCenter
			anchors.verticalCenter: parent.verticalCenter
			color: Theme.ink
			text: {
				if (Osd.kind === "brightness")
					return Osd.level < 0.5 ? Glyphs.sunMin : Glyphs.sunMax;
				if (Osd.muted || Osd.level === 0)
					return Glyphs.speakerSlash;
				return Osd.level < 0.34 ? Glyphs.speakerWave1 : Osd.level < 0.67 ? Glyphs.speakerWave2 : Glyphs.speakerWave3;
			}
		}

		Rectangle {
			width: parent.width - icon.width - number.width - 2 * parent.spacing
			height: 6
			radius: 3
			anchors.verticalCenter: parent.verticalCenter
			color: Theme.inkTrack

			Rectangle {
				width: parent.width * Math.min(Osd.level, 1)
				height: parent.height
				radius: parent.radius
				color: Osd.muted ? Theme.inkDim : Theme.ink

				Behavior on width {
					NumberAnimation {
						duration: 120
					}
				}
			}
		}

		BarText {
			id: number

			width: 30
			horizontalAlignment: Text.AlignRight
			anchors.verticalCenter: parent.verticalCenter
			color: Theme.ink
			font.pixelSize: Theme.numberSize
			font.weight: Font.DemiBold
			font.features: {
				"tnum": 1
			}
			text: Math.round(Osd.level * 100)
		}
	}
}
