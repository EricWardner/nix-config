import QtQuick
import Quickshell.Hyprland

// The status island at rest: Do Not Disturb while it's on, the temperature
// once it's critical, recording, the camera, the microphone, Bluetooth while
// it's on, the network, the volume and the battery. The network, Bluetooth
// and volume open the control centre on their page.
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
		spacing: 10

		BarIcon {
			visible: Inbox.dnd
			glyph: Glyphs.moonFill
			onClicked: Inbox.dnd = false
		}

		// A right click opens btop
		BarIcon {
			visible: Metrics.critical
			glyph: Glyphs.thermometer
			value: Math.round(Metrics.temperature) + "°C"
			tint: Theme.red
			onClicked: mouse => {
				if (mouse.button === Qt.RightButton)
					Desktop.launch(["system-monitor"]);
			}
		}

		// Start a recording (choosing what to record), or stop it; Super+R
		// does the same. A right click opens the last one.
		BarIcon {
			readonly property bool on: Capture.phase === "countdown" || Capture.phase === "recording"

			glyph: on ? Glyphs.stopCircle : Glyphs.recordCircle
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
			tint: off ? Theme.dim : Theme.fg
			live: Desktop.webcam === "in-use"
			// The ~3px gap from the lens that waybar's dot had (measured)
			dotShift: 6.5
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
			tint: Desktop.mic === "muted" ? Theme.dim : Desktop.mic === "ptt-muted" ? Theme.red : Theme.fg
			live: Desktop.mic === "ptt-active"
			onClicked: mouse => Desktop.launch(mouse.button === Qt.LeftButton ? ["micctl", "ptt"] : mouse.button === Qt.MiddleButton ? ["micctl", "mute"] : ["pavucontrol"])
		}

		BarIcon {
			visible: Net.adapter !== null && Net.bluetoothOn
			glyph: Net.bluetoothConnected.length > 0 ? Glyphs.bluetoothConnected : Glyphs.bluetooth
			onClicked: root.open("bluetooth")
		}

		// Ethernet while it's connected, else Wi-Fi: slashed when off or not
		// connected, amber behind a login page
		BarIcon {
			glyph: Net.wired ? Glyphs.ethernet : Net.current ? Glyphs.wifi : Glyphs.wifiSlash
			tint: Net.limited ? Theme.yellow : Net.wired || Net.current ? Theme.fg : Theme.dim
			onClicked: root.open("wifi")
		}

		VolumeIcon {
			onOpenSound: root.open("sound")
		}

		BatteryIcon {}
	}
}
