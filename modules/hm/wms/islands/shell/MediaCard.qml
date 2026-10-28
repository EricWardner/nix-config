import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Widgets

// What's playing (Media), with previous, play/pause and next, on the light
// glass. Nothing shows without a player.
Rectangle {
	id: root

	readonly property MprisPlayer player: Media.player

	visible: player !== null
	implicitHeight: 64
	radius: 16
	color: Theme.alpha(Theme.ink, 0.06)

	ClippingRectangle {
		id: art

		x: 10
		anchors.verticalCenter: parent.verticalCenter
		width: 44
		height: 44
		radius: 9
		color: Theme.accent

		BarText {
			anchors.centerIn: parent
			visible: cover.status !== Image.Ready
			text: Media.noteGlyph
			color: Theme.ink
			font.pixelSize: 20
		}

		Image {
			id: cover

			anchors.fill: parent
			source: root.player?.trackArtUrl ?? ""
			sourceSize: Qt.size(88, 88)
			fillMode: Image.PreserveAspectCrop
			smooth: true
		}
	}

	Column {
		anchors.left: art.right
		anchors.leftMargin: 10
		anchors.right: controls.left
		anchors.rightMargin: 6
		anchors.verticalCenter: parent.verticalCenter

		BarText {
			width: parent.width
			text: root.player?.trackTitle ?? ""
			color: Theme.ink
			font.pixelSize: 13
			font.weight: Font.DemiBold
			elide: Text.ElideRight
		}

		BarText {
			width: parent.width
			visible: text !== ""
			text: root.player?.trackArtist ?? ""
			color: Theme.inkDim
			font.pixelSize: 12
			elide: Text.ElideRight
		}
	}

	Row {
		id: controls

		anchors.right: parent.right
		anchors.rightMargin: 6
		anchors.verticalCenter: parent.verticalCenter

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

			Rectangle {
				required property var modelData

				width: 32
				height: 32
				radius: 16
				opacity: modelData.enabled ? 1 : 0.35
				color: buttonHover.hovered && modelData.enabled ? Theme.inkTrack : "transparent"

				BarText {
					anchors.centerIn: parent
					text: modelData.glyph
					color: Theme.ink
					font.pixelSize: 18
				}

				HoverHandler {
					id: buttonHover
				}

				MouseArea {
					anchors.fill: parent
					enabled: modelData.enabled
					onClicked: modelData.run()
				}
			}
		}
	}
}
