import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

// The notifications held back while sharing, under the share's island: by
// app, and how many, as this is on the shared screen too. Esc or a click
// outside closes it.
Item {
	id: root

	readonly property int shown: 4
	// [{name, icon, count}], most held first
	readonly property var apps: {
		const byName = {};
		for (const n of Inbox.held) {
			const name = Inbox.appName(n);
			if (!byName[name])
				byName[name] = {
					"name": name,
					"icon": Inbox.appIcon(n),
					"count": 0
				};
			byName[name].count++;
		}
		return Object.values(byName).sort((a, b) => b.count - a.count);
	}

	implicitWidth: 300
	implicitHeight: column.implicitHeight + 24
	focus: visible
	onVisibleChanged: {
		if (visible)
			forceActiveFocus();
	}
	Keys.onEscapePressed: Desktop.closePanel()

	RectangularShadow {
		anchors.fill: glass
		radius: glass.radius
		offset.y: 10
		blur: 30
		color: Qt.rgba(0, 0, 0, 0.3)
	}

	Rectangle {
		id: glass

		anchors.fill: parent
		radius: 18
		color: Theme.grownFill
		border.width: 1
		border.color: Theme.grownRim
	}

	Column {
		id: column

		x: 12
		y: 12
		width: parent.width - 24
		spacing: 8

		BarText {
			width: parent.width
			wrapMode: Text.WordWrap
			text: "Kept off the shared screen. They show when you stop sharing."
			color: Theme.inkDim
			font.pixelSize: 12
		}

		Repeater {
			model: root.apps.slice(0, root.shown)

			Row {
				required property var modelData

				spacing: 10

				ClippingRectangle {
					anchors.verticalCenter: parent.verticalCenter
					width: 24
					height: 24
					radius: 6
					color: Theme.inkTrack

					Image {
						anchors.fill: parent
						visible: source !== ""
						source: modelData.icon
						sourceSize: Qt.size(48, 48)
						fillMode: Image.PreserveAspectFit
						smooth: true
						mipmap: true
					}
				}

				Row {
					anchors.verticalCenter: parent.verticalCenter

					BarText {
						text: modelData.name
						color: Theme.ink
						font.pixelSize: 13
						font.weight: Font.DemiBold
					}

					BarText {
						text: " · " + modelData.count
						color: Theme.ink
						font.pixelSize: 13
					}
				}
			}
		}

		BarText {
			visible: root.apps.length > root.shown
			text: "+ " + (root.apps.length - root.shown) + " more"
			color: Theme.inkDim
			font.pixelSize: 12
		}
	}
}
