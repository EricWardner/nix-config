import QtQuick
import Quickshell.Hyprland

// The status island at rest: recording, the camera, the microphone,
// Bluetooth while it's on, the network, the volume, the control centre's
// switches, and the battery. The network, Bluetooth and volume open the
// control centre on their page, the switches on its first.
IslandMode {
	id: root

	required property HyprlandMonitor monitor

	function open(page: string) {
		Desktop.openPanel("control", page, monitor);
	}

	active: true
	resting: true
	cornerRadius: 8
	islandWidth: row.implicitWidth + 16
	islandHeight: Theme.barHeight - 4

	Row {
		id: row

		anchors.centerIn: parent
		// The gap between icons' ink (BarIcon is as wide as its glyph)
		spacing: 18

		// Start a recording (choosing what to record), or stop it; Super+R
		// does the same. A right click opens the last one.
		BarIcon {
			readonly property bool on: Capture.recorder !== "off"

			glyph: on ? Glyphs.stopCircle : Glyphs.recordCircle
			glyphs: [Glyphs.recordCircle, Glyphs.stopCircle]
			tint: on ? Theme.red : Theme.fg
			onClicked: mouse => {
				if (mouse.button === Qt.RightButton)
					Capture.run(["last"]);
				else
					Capture.toggleRecording();
			}
		}

		// A left or middle click turns the cameras off or on; a right click
		// opens (or closes) the camera settings
		BarIcon {
			readonly property bool off: Desktop.webcam === "muted" || Desktop.webcam === "disconnected"

			glyph: off ? Glyphs.videoSlash : Glyphs.video
			glyphs: [Glyphs.video, Glyphs.videoSlash]
			tint: off ? Theme.dim : Theme.fg
			live: Desktop.webcam === "in-use"
			dotShift: 2
			onClicked: mouse => Desktop.launch(mouse.button === Qt.RightButton ? ["camera-settings"] : ["sudo", "/run/current-system/sw/bin/webcam-toggle", "toggle"])
		}

		// A left click arms or disarms push-to-talk (pttd does the muting), a
		// middle click mutes, a right click opens pavucontrol. Armed but
		// silent is red: the hot mic is off.
		BarIcon {
			glyph: ({
					"muted": Glyphs.micSlash,
					"ptt-muted": Glyphs.micSlashFill
				})[Desktop.mic] ?? Glyphs.mic
			glyphs: [Glyphs.mic, Glyphs.micSlash, Glyphs.micSlashFill]
			tint: Desktop.mic === "muted" ? Theme.dim : Desktop.mic === "ptt-muted" ? Theme.red : Theme.fg
			live: Desktop.mic === "ptt-active"
			onClicked: mouse => Desktop.launch(mouse.button === Qt.LeftButton ? ["micctl", "ptt"] : mouse.button === Qt.MiddleButton ? ["micctl", "mute"] : ["pavucontrol"])
		}

		BarIcon {
			visible: Net.adapter !== null && Net.bluetoothOn
			glyph: Net.bluetoothConnected.length > 0 ? Glyphs.bluetoothConnected : Glyphs.bluetooth
			glyphs: [Glyphs.bluetooth, Glyphs.bluetoothConnected]
			onClicked: root.open("bluetooth")
		}

		// Ethernet while it's connected, else Wi-Fi: slashed when off or not
		// connected, amber behind a login page
		BarIcon {
			glyph: Net.wired ? Glyphs.ethernet : Net.current ? Glyphs.wifi : Glyphs.wifiSlash
			glyphs: [Glyphs.ethernet, Glyphs.wifi, Glyphs.wifiSlash]
			tint: Net.limited ? Theme.yellow : Net.wired || Net.current ? Theme.fg : Theme.dim
			onClicked: root.open("wifi")
		}

		VolumeIcon {
			onOpenSound: root.open("sound")
		}

		BarIcon {
			glyph: Glyphs.controlCentre
			onClicked: root.open("")
		}

		BatteryIcon {}
	}
}
