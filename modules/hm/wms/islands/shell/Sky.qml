import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Sky: a workspace with no windows is a dashboard, over the wallpaper and
// under any window that opens. The time, what's playing, today's captures,
// something to start, and the machine's state; only the cards and the
// status line take clicks.
PanelWindow {
	id: root

	required property ShellScreen modelData
	readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
	// The cards share the tallest one's height, as a row
	readonly property real cardHeight: Math.max(...[media, captures, apps].filter(card => card.visible).map(card => card.implicitHeight))

	screen: modelData
	visible: Desktop.workspaceEmpty(monitor)
	anchors.top: true
	anchors.bottom: true
	anchors.left: true
	anchors.right: true
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"
	WlrLayershell.layer: WlrLayer.Bottom
	WlrLayershell.namespace: "islands-sky"
	mask: Region {
		item: cards

		Region {
			item: status
		}
	}

	SystemClock {
		id: clock

		precision: SystemClock.Minutes
	}

	// The wallpaper as swaybg draws it ("fill"), never on screen itself:
	// only blurred into the glass of the cards. Half size, as it's blurred.
	Image {
		id: wallpaper

		anchors.fill: parent
		source: Host.wallpaper !== "" ? "file://" + Host.wallpaper : ""
		sourceSize: Qt.size(root.width / 2, root.height / 2)
		fillMode: Image.PreserveAspectCrop
		asynchronous: true
	}

	Column {
		anchors.horizontalCenter: parent.horizontalCenter
		y: Math.round(root.height * 0.12)
		spacing: 10
		layer.enabled: true
		layer.effect: MultiEffect {
			shadowEnabled: true
			shadowBlur: 1
			shadowVerticalOffset: 2
			shadowColor: Qt.rgba(0, 0.08, 0.31, 0.35)
		}

		BarText {
			anchors.horizontalCenter: parent.horizontalCenter
			text: Qt.formatTime(clock.date, "h:mm")
			font.family: "SF Pro Display"
			font.pixelSize: 196
			font.weight: Font.ExtraLight
			font.letterSpacing: -6
		}

		BarText {
			anchors.horizontalCenter: parent.horizontalCenter
			text: Qt.formatDate(clock.date, "dddd d MMMM")
			opacity: 0.92
			font.pixelSize: 22
		}
	}

	Row {
		id: cards

		anchors.horizontalCenter: parent.horizontalCenter
		y: Math.round(root.height * 0.5)
		spacing: 16

		SkyMedia {
			id: media

			backdrop: wallpaper
			height: root.cardHeight
		}

		SkyCaptures {
			id: captures

			backdrop: wallpaper
			shown: root.visible
			height: root.cardHeight
		}

		SkyApps {
			id: apps

			backdrop: wallpaper
			height: root.cardHeight
		}
	}

	SkyStatus {
		id: status

		backdrop: wallpaper
		shown: root.visible
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.bottom: parent.bottom
		anchors.bottomMargin: 34
	}
}
