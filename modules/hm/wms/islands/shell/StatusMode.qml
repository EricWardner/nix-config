import QtQuick
import Quickshell.Hyprland

// The status island at rest: Do Not Disturb while it's on, the temperature
// once it's critical, the camera while it's in use, the microphone, Bluetooth
// while it's on, the network, the volume and the battery. The network,
// Bluetooth and volume open the control centre on their page.
IslandMode {
	id: root

	required property HyprlandMonitor monitor

	function open(page: string) {
		Desktop.openPanel("control", page, monitor);
	}

	active: true
	resting: true
	cornerRadius: 8
	islandWidth: row.implicitWidth + 8
	islandHeight: Theme.barHeight - 4

	Row {
		id: row

		anchors.centerIn: parent
		spacing: 4

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

		// A right click opens the camera settings
		BarIcon {
			visible: Desktop.webcam === "in-use"
			glyph: Glyphs.video
			live: true
			// The ~3px gap from the lens that waybar's dot had (measured)
			dotShift: 6.5
			onClicked: mouse => {
				if (mouse.button === Qt.RightButton)
					Desktop.launch(["camera-settings"]);
				else
					root.open("");
			}
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
