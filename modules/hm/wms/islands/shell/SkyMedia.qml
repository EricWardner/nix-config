import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Widgets

// What's playing, on Sky: the cover, the track, how far in, and the
// controls
SkyCard {
	id: root

	readonly property MprisPlayer player: Media.player

	visible: player !== null && !Sharing.active

	// Mpris doesn't announce the position as it moves
	Timer {
		interval: 1000
		repeat: true
		running: root.visible && (root.player?.isPlaying ?? false)
		onTriggered: root.player.positionChanged()
	}

	Row {
		width: parent.width
		spacing: 12

		ClippingRectangle {
			width: 52
			height: 52
			radius: 12
			color: Theme.purple

			BarText {
				anchors.centerIn: parent
				visible: cover.status !== Image.Ready
				text: Media.noteGlyph
				color: Theme.bg
				font.pixelSize: 22
			}

			Image {
				id: cover

				anchors.fill: parent
				source: root.player?.trackArtUrl ?? ""
				sourceSize: Qt.size(104, 104)
				fillMode: Image.PreserveAspectCrop
				smooth: true
			}
		}

		Column {
			anchors.verticalCenter: parent.verticalCenter
			width: parent.width - 64

			BarText {
				width: parent.width
				text: root.player?.trackTitle ?? ""
				font.pixelSize: 15
				font.weight: Font.DemiBold
				elide: Text.ElideRight
			}

			BarText {
				width: parent.width
				visible: text !== ""
				text: root.player?.trackArtist ?? ""
				color: Theme.alpha(Theme.fg, 0.8)
				font.pixelSize: 13
				elide: Text.ElideRight
			}
		}
	}

	Rectangle {
		visible: (root.player?.lengthSupported ?? false) && root.player.length > 0
		width: parent.width
		height: 4
		radius: 2
		color: Theme.alpha(Theme.fg, 0.25)

		Rectangle {
			width: parent.width * Math.min(1, (root.player?.position ?? 0) / Math.max(1, root.player?.length ?? 1))
			height: parent.height
			radius: 2
			color: Theme.fg
		}
	}

	Row {
		anchors.horizontalCenter: parent.horizontalCenter
		spacing: 22

		Repeater {
			model: [
				{
					"glyph": Media.previousGlyph,
					"enabled": root.player?.canGoPrevious ?? false,
					"run": () => root.player.previous()
				},
				{
					"glyph": root.player?.isPlaying ? Media.pauseGlyph : Media.playGlyph,
					"enabled": root.player?.canTogglePlaying ?? false,
					"run": () => root.player.togglePlaying()
				},
				{
					"glyph": Media.nextGlyph,
					"enabled": root.player?.canGoNext ?? false,
					"run": () => root.player.next()
				}
			]

			BarText {
				required property var modelData

				text: modelData.glyph
				opacity: modelData.enabled ? 1 : 0.35
				font.pixelSize: 20

				MouseArea {
					anchors.fill: parent
					anchors.margins: -6
					enabled: parent.modelData.enabled
					cursorShape: Qt.PointingHandCursor
					onClicked: parent.modelData.run()
				}
			}
		}
	}
}
