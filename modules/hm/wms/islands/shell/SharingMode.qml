import QtQuick
import Quickshell.Hyprland

// A screen share in the centre island, on every monitor: what's shared and
// for how long, the mic and camera as the call has them, the notifications
// held back (a click lists them), and Stop sharing.
IslandMode {
	id: root

	required property HyprlandMonitor monitor
	property real now: Date.now()
	// Where the held count sits, for the list to open under it
	readonly property real heldCentre: row.x + held.x + held.width / 2

	priority: 15
	islandWidth: row.implicitWidth + 18
	islandHeight: 38
	cornerRadius: 19
	rim: Theme.orange

	Timer {
		interval: 1000
		repeat: true
		running: root.current
		triggeredOnStart: true
		onTriggered: root.now = Date.now()
	}

	Row {
		id: row

		x: 14
		anchors.verticalCenter: parent.verticalCenter
		spacing: 14

		Row {
			anchors.verticalCenter: parent.verticalCenter
			spacing: 8

			Searching {
				anchors.verticalCenter: parent.verticalCenter
				running: Sharing.stopping
				color: Theme.orange
			}

			Rectangle {
				visible: !Sharing.stopping
				anchors.verticalCenter: parent.verticalCenter
				width: 9
				height: 9
				radius: 4.5
				color: Theme.orange

				SequentialAnimation on opacity {
					running: root.current && !Sharing.stopping
					loops: Animation.Infinite

					NumberAnimation {
						to: 0.35
						duration: 800
					}
					NumberAnimation {
						to: 1
						duration: 800
					}
				}
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: {
					if (Sharing.stopping)
						return "Stopping…";
					if (Sharing.kind === "window")
						return "Sharing a window";
					if (Sharing.output === "")
						return "Sharing your screen";
					return Sharing.output === root.monitor?.name ? "Sharing this screen" : "Sharing your other screen";
				}
				color: Theme.ink
				font.pixelSize: 13
				font.weight: Font.DemiBold
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: {
					const seconds = Math.max(0, Math.floor((root.now - Sharing.since) / 1000));
					const pad = n => String(n).padStart(2, "0");
					const hours = Math.floor(seconds / 3600);
					const minutes = Math.floor(seconds / 60) % 60;
					return (hours > 0 ? hours + ":" + pad(minutes) : minutes) + ":" + pad(seconds % 60);
				}
				color: Theme.inkDim
				font.pixelSize: 13
				font.weight: Font.Medium
				font.features: {
					"tnum": 1
				}
			}
		}

		Rectangle {
			anchors.verticalCenter: parent.verticalCenter
			width: 1
			height: 18
			color: Theme.alpha(Theme.ink, 0.15)
		}

		// A click arms or disarms push-to-talk, as the bar's mic does
		Detail {
			readonly property var state: ({
					"ptt-muted": [Glyphs.micSlash, "Hold Right Alt to talk"],
					"ptt-active": [Glyphs.mic, "Talking"],
					"muted": [Glyphs.micSlash, "Muted"],
					"on": [Glyphs.mic, "Mic on"]
				})[Desktop.mic] ?? null

			visible: state !== null
			glyph: state?.[0] ?? ""
			label: state?.[1] ?? ""
			live: Desktop.mic === "ptt-active"
			clickable: true
			onClicked: Desktop.launch(["micctl", "ptt"])
		}

		Detail {
			visible: Desktop.webcam !== "" && Desktop.webcam !== "disconnected"
			glyph: Desktop.webcam === "muted" ? Glyphs.videoSlash : Glyphs.video
			label: Desktop.webcam === "in-use" ? "On" : "Off"
			live: Desktop.webcam === "in-use"
		}

		Detail {
			id: held

			visible: Inbox.held.length > 0
			glyph: Glyphs.bellSlash
			label: Inbox.held.length + " held"
			bold: true
			clickable: true
			onClicked: Desktop.togglePanel("held", root.monitor)
		}

		Rectangle {
			anchors.verticalCenter: parent.verticalCenter
			width: stopText.implicitWidth + 28
			height: 30
			radius: 15
			color: stopHover.hovered && !Sharing.stopping ? Qt.lighter(Theme.orange, 1.08) : Theme.orange
			opacity: Sharing.stopping ? 0.5 : 1

			BarText {
				id: stopText

				anchors.centerIn: parent
				text: "Stop sharing"
				color: Theme.bg
				font.pixelSize: 13
				font.weight: Font.Bold
			}

			HoverHandler {
				id: stopHover
			}

			MouseArea {
				anchors.fill: parent
				enabled: !Sharing.stopping
				cursorShape: Qt.PointingHandCursor
				onClicked: Sharing.stop()
			}
		}
	}

	// An icon and its words; `live` adds the bar's green in-use dot
	component Detail: Item {
		id: detail

		property string glyph
		property string label
		property bool bold: false
		property bool live: false
		property bool clickable: false

		signal clicked

		anchors.verticalCenter: parent.verticalCenter
		implicitWidth: detailRow.implicitWidth
		implicitHeight: detailRow.implicitHeight

		Row {
			id: detailRow

			spacing: 6

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: detail.glyph
				color: Theme.ink
				font.pixelSize: 14

				Rectangle {
					visible: detail.live
					x: parent.width - 3
					y: -1
					width: 6
					height: 6
					radius: 3
					color: Theme.inkGreen
				}
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: detail.label
				color: Theme.ink
				font.pixelSize: 13
				font.weight: detail.bold ? Font.DemiBold : Font.Normal
			}
		}

		MouseArea {
			anchors.fill: parent
			enabled: detail.clickable
			cursorShape: Qt.PointingHandCursor
			onClicked: detail.clicked()
		}
	}
}
