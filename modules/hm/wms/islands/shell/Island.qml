import QtQuick
import QtQuick.Effects

// An island on the bar and everything it grows into: the modes declared
// inside it (IslandMode). It shows the active mode with the highest
// priority, grown to that mode's size, in light glass with dark ink unless
// the mode rests in the bar's faint glass. It grows away from the edge it's
// anchored by, and downwards, so nothing beside it moves.
Item {
	id: root

	default property alias modes: stage.data
	// Over the capture overlay's frozen screen, which Hyprland can't blur
	// behind, the island frosts it itself; it must fill the island's parent
	property Item backdrop: null

	readonly property var modeList: Array.from(stage.children).filter(child => child.isMode)
	readonly property IslandMode current: modeList.length === 0 ? null : modeList.reduce((best, mode) => mode.active && mode.priority > best.priority ? mode : best, modeList[0])
	readonly property bool resting: current?.resting ?? true

	function syncCurrent() {
		for (const mode of modeList)
			mode.current = mode === current;
	}

	onCurrentChanged: syncCurrent()
	onModeListChanged: syncCurrent()

	width: current?.islandWidth ?? 0
	height: current?.islandHeight ?? 0

	Behavior on width {
		Morph {}
	}
	Behavior on height {
		Morph {}
	}

	RectangularShadow {
		anchors.fill: glass
		radius: glass.radius
		offset.y: 2
		blur: 6
		color: Qt.rgba(0, 0, 0, 0.25)
		opacity: root.resting ? 0 : 1

		Behavior on opacity {
			NumberAnimation {
				duration: 300
			}
		}
	}

	Loader {
		anchors.fill: parent
		active: root.backdrop !== null

		sourceComponent: Item {
			MultiEffect {
				anchors.fill: parent
				source: ShaderEffectSource {
					sourceItem: root.backdrop
					sourceRect: Qt.rect(root.x, root.y, root.width, root.height)
				}
				autoPaddingEnabled: false
				blurEnabled: true
				blur: 1
				blurMax: 32
				maskEnabled: true
				maskSource: shape
				maskThresholdMin: 0.5
				maskSpreadAtMin: 1
			}

			Rectangle {
				id: shape

				anchors.fill: parent
				radius: glass.radius
				visible: false
				layer.enabled: true
			}
		}
	}

	Rectangle {
		id: glass

		anchors.fill: parent
		radius: root.current && root.current.cornerRadius >= 0 ? root.current.cornerRadius : Math.min(height / 2, 24)
		color: root.resting ? Theme.islandFill : Theme.grownFill
		border.width: 1
		border.color: root.resting ? Theme.islandRim : root.current.rim

		Behavior on radius {
			Morph {}
		}
		Behavior on color {
			ColorAnimation {
				duration: 300
			}
		}
		Behavior on border.color {
			ColorAnimation {
				duration: 300
			}
		}
	}

	Item {
		id: stage

		anchors.fill: parent
		clip: true
	}
}
