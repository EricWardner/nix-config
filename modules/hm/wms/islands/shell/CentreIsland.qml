import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland

// The island in the middle of the bar. At rest it's the clock in faint
// glass. On the focused monitor it grows into the volume or brightness
// popup for a moment when either changes, in light glass with dark ink,
// then shrinks back. It grows around the bar's centre and downwards, so
// nothing beside it moves.
Item {
	id: root

	required property HyprlandMonitor monitor

	readonly property bool osd: Osd.showing && Hyprland.focusedMonitor === monitor
	readonly property bool grown: osd

	width: grown ? 300 : clock.implicitWidth + 28
	height: grown ? 42 : Theme.barHeight - 4

	Behavior on width {
		Morph {}
	}
	Behavior on height {
		Morph {}
	}

	RectangularShadow {
		anchors.fill: glass
		radius: glass.radius
		offset.y: 10
		blur: 30
		color: Qt.rgba(0, 0, 0, 0.3)
		opacity: root.grown ? 1 : 0

		Behavior on opacity {
			NumberAnimation {
				duration: 300
			}
		}
	}

	Rectangle {
		id: glass

		anchors.fill: parent
		radius: height / 2
		color: root.grown ? Theme.grownFill : Theme.islandFill
		border.width: 1
		border.color: root.grown ? Theme.grownRim : Theme.islandRim

		Behavior on color {
			ColorAnimation {
				duration: 300
			}
		}
	}

	SystemClock {
		id: time

		precision: SystemClock.Minutes
	}

	BarText {
		id: clock

		anchors.centerIn: parent
		// waybar's "%a %d %b  %I:%M %p %Z"
		text: Qt.formatDateTime(time.date, "ddd dd MMM  hh:mm AP t")
		opacity: root.grown ? 0 : 1

		Behavior on opacity {
			NumberAnimation {
				duration: 150
			}
		}
	}

	// The popup: an icon, the level as a bar, and the number
	Row {
		anchors.verticalCenter: parent.verticalCenter
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.leftMargin: 16
		anchors.rightMargin: 16
		spacing: 12
		opacity: root.osd ? 1 : 0
		visible: opacity > 0

		Behavior on opacity {
			NumberAnimation {
				duration: 200
			}
		}

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
