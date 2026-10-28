import QtQuick
import QtQuick.Effects

// The centre island grown into the capture toolbar, over the frozen bar
// where the clock was: what to take (an area, a window, the screen) and
// what to do with it (a screenshot, a recording, its text, a colour), and
// under them, how to choose
Item {
	id: root

	// The frozen screen behind, at the toolbar's parent's origin: frosted
	// here, as Hyprland frosts behind the islands, since the toolbar is over
	// the overlay's own picture of the screen, not over the screen
	property Item backdrop

	signal takeScreen

	// A colour is a pixel, and text is read from an area: neither has a
	// choice of area, window or screen
	readonly property bool targets: Capture.kind !== "colour" && Capture.kind !== "text"
	readonly property string hint: {
		const kind = Capture.kind;
		if (kind === "colour")
			return "Click to pick a colour";
		if (kind === "text")
			return "Drag over the text to copy";
		const doing = kind === "record" ? "record" : "take";
		if (Capture.target === "screen")
			return "Click, or press Enter, to " + doing + " this screen";
		if (Capture.target === "window")
			return "Click a window to " + doing + " it";
		return "Drag to select, or click a window";
	}

	implicitWidth: glass.width
	implicitHeight: glass.height

	RectangularShadow {
		anchors.fill: glass
		radius: glass.radius
		offset.y: 10
		blur: 30
		color: Qt.rgba(0, 0, 0, 0.35)
	}

	MultiEffect {
		anchors.fill: glass
		source: ShaderEffectSource {
			sourceItem: root.backdrop
			sourceRect: Qt.rect(root.x + glass.x, root.y + glass.y, glass.width, glass.height)
			hideSource: false
		}
		autoPaddingEnabled: false
		blurEnabled: true
		blur: 1
		blurMax: 32
		maskEnabled: true
		maskSource: glassShape
		maskThresholdMin: 0.5
		maskSpreadAtMin: 1
	}

	Rectangle {
		id: glassShape

		width: glass.width
		height: glass.height
		radius: glass.radius
		visible: false
		layer.enabled: true
	}

	Rectangle {
		id: glass

		width: column.implicitWidth + 16
		height: column.implicitHeight + 16
		radius: 26
		color: Theme.grownFill
		border.width: 1
		border.color: Theme.grownRim

		Column {
			id: column

			x: 8
			y: 8
			spacing: 6

			Row {
				spacing: 8

				Segmented {
					visible: root.targets
					options: [["area", "Area"], ["window", "Window"], ["screen", "Screen"]]
					chosen: Capture.target
					onPicked: value => Capture.target = value
				}

				Segmented {
					options: [["screenshot", "Screenshot"], ["record", "Record"], ["text", "Text"], ["colour", "Colour"]]
					chosen: Capture.kind
					onPicked: value => {
						Capture.kind = value;
						if (value === "text")
							Capture.target = "area";
					}
				}

				PillButton {
					visible: root.targets && Capture.target === "screen"
					anchors.verticalCenter: parent.verticalCenter
					primary: true
					implicitHeight: 34
					text: Capture.kind === "record" ? "Record" : "Capture"
					onClicked: root.takeScreen()
				}

				PillButton {
					anchors.verticalCenter: parent.verticalCenter
					implicitWidth: 34
					implicitHeight: 34
					text: "×"
					onClicked: Capture.cancel()
				}
			}

			BarText {
				leftPadding: 8
				rightPadding: 8
				text: [root.hint, root.targets ? "Space: area, window, screen" : "", "Esc: cancel"].filter(part => part !== "").join("   ·   ")
				color: Theme.inkDim
				font.pixelSize: 12
			}
		}
	}

	component Segmented: Rectangle {
		id: segmented

		// [value, label] pairs
		property var options: []
		property string chosen

		signal picked(string value)

		width: options.length > 0 ? segments.implicitWidth + 6 : 0
		height: 40
		radius: 20
		color: Theme.alpha(Theme.ink, 0.06)

		Row {
			id: segments

			x: 3
			anchors.verticalCenter: parent.verticalCenter
			spacing: 2

			Repeater {
				model: segmented.options

				Rectangle {
					required property var modelData

					readonly property bool on: segmented.chosen === modelData[0]

					width: label.implicitWidth + 24
					height: 34
					radius: 17
					color: on ? Theme.ink : hover.hovered ? Theme.inkTrack : "transparent"

					BarText {
						id: label

						anchors.centerIn: parent
						text: modelData[1]
						color: parent.on ? Theme.fg : Theme.ink
						font.pixelSize: 13
						font.weight: parent.on ? Font.DemiBold : Font.Medium
					}

					HoverHandler {
						id: hover
					}

					MouseArea {
						anchors.fill: parent
						onClicked: segmented.picked(modelData[0])
					}
				}
			}
		}
	}
}
