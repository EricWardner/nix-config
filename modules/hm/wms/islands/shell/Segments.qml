import QtQuick

// A choice of a few, as a segmented control: `options` are the labels,
// `current` the chosen one's index (-1 for none), `unavailable` the
// indexes shown dimmed that can't be picked, and `picked` says which was
// clicked. PowerModes is one; set height, radius and fontSize for bigger.
Rectangle {
	id: root

	property list<string> options
	property int current: 0
	property var unavailable: []
	property int fontSize: 11

	signal picked(int index)

	height: 28
	radius: 10
	color: Theme.alpha(Theme.ink, 0.06)

	Row {
		anchors.fill: parent
		anchors.margins: 3

		Repeater {
			model: root.options

			Rectangle {
				id: segment

				required property string modelData
				required property int index

				readonly property bool chosen: index === root.current
				readonly property bool available: !root.unavailable.includes(index)
				// One that can be picked, tinted under the pointer
				readonly property bool pickable: !chosen && available

				width: parent.width / root.options.length
				height: parent.height
				radius: root.radius - 3
				color: chosen ? Theme.ink : pickable && hover.hovered ? Theme.alpha(Theme.ink, 0.08) : "transparent"
				opacity: available ? 1 : 0.35

				BarText {
					anchors.centerIn: parent
					text: segment.modelData
					color: segment.chosen ? Theme.fg : Theme.ink
					font.pixelSize: root.fontSize
					font.weight: segment.chosen ? Font.DemiBold : Font.Medium
				}

				HoverHandler {
					id: hover

					cursorShape: segment.pickable ? Qt.PointingHandCursor : Qt.ArrowCursor
				}

				MouseArea {
					anchors.fill: parent
					onClicked: if (segment.pickable)
						root.picked(segment.index)
				}
			}
		}
	}
}
