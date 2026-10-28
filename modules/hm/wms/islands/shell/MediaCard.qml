import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Widgets

// What's playing (Mpris), with previous, play/pause and next: the player
// that's playing, or else the first with a track. Nothing shows without
// one (Chrome keeps an idle player around for any tab that has had media).
Rectangle {
	id: root

	readonly property var players: Array.from(Mpris.players.values).filter(p => p.trackTitle !== "")
	readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players[0] ?? null

	visible: player !== null
	implicitHeight: 64
	radius: 16
	color: Theme.alpha(Theme.ink, 0.06)

	// Material Design icons from the Nerd Font fallback: SF Symbols' media
	// controls aren't among the code points found so far
	readonly property string previousGlyph: String.fromCodePoint(0xF04AE)
	readonly property string playGlyph: String.fromCodePoint(0xF040A)
	readonly property string pauseGlyph: String.fromCodePoint(0xF03E4)
	readonly property string nextGlyph: String.fromCodePoint(0xF04AD)
	readonly property string noteGlyph: String.fromCodePoint(0xF0387)

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
			text: root.noteGlyph
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
					"glyph": root.previousGlyph,
					"enabled": root.player?.canGoPrevious ?? false,
					"run": () => root.player.previous()
				},
				{
					"glyph": root.player?.isPlaying ? root.pauseGlyph : root.playGlyph,
					"enabled": root.player?.canTogglePlaying ?? false,
					"run": () => root.player.togglePlaying()
				},
				{
					"glyph": root.nextGlyph,
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
