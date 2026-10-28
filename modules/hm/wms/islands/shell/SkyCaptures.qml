import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// Today's saved screenshots and recordings, on Sky: the newest three, a
// click opening one's preview, and each draggable as a file (into a chat).
// Listed afresh as Sky appears, and each minute while it shows.
SkyCard {
	id: root

	property bool shown: false
	// [{path, thumb, duration}], newest first; a screenshot is its own thumb
	property var captures: []
	property var listing: []

	spacing: 10
	visible: captures.length > 0

	onShownChanged: {
		if (shown)
			list.running = true;
	}

	Timer {
		interval: 60000
		repeat: true
		running: root.shown
		onTriggered: list.running = true
	}

	Process {
		id: list

		command: ["islands-capture", "today"]
		stdout: SplitParser {
			onRead: line => {
				const [path, thumb, duration] = line.split("\t");
				root.listing.push({
					"path": path,
					"thumb": thumb ?? path,
					"duration": duration ?? ""
				});
			}
		}
		onStarted: root.listing = []
		onExited: root.captures = root.listing
	}

	Row {
		width: parent.width

		BarText {
			width: parent.width - count.width
			text: "Today's captures"
			font.pixelSize: 13
			font.weight: Font.DemiBold
		}

		BarText {
			id: count

			text: root.captures.length
			color: Theme.alpha(Theme.fg, 0.8)
			font.pixelSize: 13
		}
	}

	Row {
		spacing: 8

		Repeater {
			model: root.captures.slice(0, 3)

			ClippingRectangle {
				id: thumb

				required property var modelData

				width: (root.width - 32 - 16) / 3
				height: 62
				radius: 8
				color: Qt.rgba(0.11, 0.11, 0.12, 1)
				border.width: 1
				border.color: Theme.alpha(Theme.fg, 0.2)

				Image {
					anchors.fill: parent
					source: "file://" + thumb.modelData.thumb
					sourceSize: Qt.size(width * 2, height * 2)
					fillMode: Image.PreserveAspectCrop
					asynchronous: true
					cache: false
				}

				Rectangle {
					visible: thumb.modelData.duration !== ""
					anchors.right: parent.right
					anchors.bottom: parent.bottom
					anchors.margins: 4
					width: length.implicitWidth + 8
					height: length.implicitHeight
					radius: 4
					color: Qt.rgba(0, 0, 0, 0.6)

					BarText {
						id: length

						anchors.centerIn: parent
						text: thumb.modelData.duration
						font.pixelSize: 10
						font.weight: Font.DemiBold
					}
				}

				Drag.active: drag.active
				Drag.dragType: Drag.Automatic
				Drag.supportedActions: Qt.CopyAction
				Drag.mimeData: {
					"text/uri-list": "file://" + thumb.modelData.path
				}

				DragHandler {
					id: drag

					target: null
				}

				TapHandler {
					cursorShape: Qt.PointingHandCursor
					onTapped: Desktop.launch(["islands-capture", "open", thumb.modelData.path])
				}
			}
		}
	}

	BarText {
		width: parent.width
		wrapMode: Text.WordWrap
		text: "Drag one into a chat, or click to open its preview"
		color: Theme.alpha(Theme.fg, 0.8)
		font.pixelSize: 12
	}
}
