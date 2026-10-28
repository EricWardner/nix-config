import QtQuick
import QtQuick.Effects

// The glass behind a Sky card: the wallpaper behind it, blurred well past
// what Hyprland's blur does (one setting for every layer) and a little
// more saturated, under a dark tint. `backdrop` is Sky's copy of the
// wallpaper, laid out as swaybg draws it.
Item {
	id: root

	property Item backdrop
	property real radius

	// Where the card sits over the wallpaper; the reads make it follow the
	// card and the row it's in as they move
	readonly property point origin: {
		parent.x;
		parent.y;
		parent.parent?.x;
		parent.parent?.y;
		return backdrop ? parent.mapToItem(backdrop, 0, 0) : Qt.point(0, 0);
	}

	anchors.fill: parent

	MultiEffect {
		anchors.fill: parent
		source: ShaderEffectSource {
			sourceItem: root.backdrop
			sourceRect: Qt.rect(root.origin.x, root.origin.y, root.width, root.height)
			hideSource: true
		}
		autoPaddingEnabled: false
		blurEnabled: true
		blur: 1
		blurMax: 48
		saturation: 0.3
		maskEnabled: true
		maskSource: shape
		maskThresholdMin: 0.5
		maskSpreadAtMin: 1
	}

	Rectangle {
		id: shape

		anchors.fill: parent
		radius: root.radius
		visible: false
		layer.enabled: true
	}

	Rectangle {
		anchors.fill: parent
		radius: root.radius
		color: Qt.rgba(0.04, 0.08, 0.24, 0.32)
		border.width: 1
		border.color: Theme.alpha(Theme.fg, 0.18)
	}
}
