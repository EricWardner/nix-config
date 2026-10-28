import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The bar along the top of one monitor, transparent but for its islands and
// 4px below the screen's edge, as waybar was. Left: the launcher, this
// monitor's workspaces and the focused app. Middle: the centre island.
// Right: the tray island, then the status icons on the bare bar.
//
// The window reaches well below the bar so islands can grow down into it,
// but windows are only kept clear of the bar itself, and clicks only land
// on the bar and the islands; everywhere else they reach the windows
// underneath.
PanelWindow {
	id: bar

	required property ShellScreen modelData
	readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
	// The notification or control centre (or the held notifications) is open
	// on this monitor
	readonly property bool panelOpen: Desktop.panel !== "" && Desktop.panelOn === monitor
	// A question from NetworkManager or BlueZ is in this monitor's island
	readonly property bool asking: Agent.current !== null && Hyprland.focusedMonitor === monitor

	screen: modelData
	anchors.top: true
	anchors.left: true
	anchors.right: true
	implicitHeight: Theme.windowHeight
	exclusiveZone: Theme.barTop + Theme.barHeight
	color: "transparent"
	// Hyprland blurs behind it where it's at all opaque (hypr/lua/rules.lua)
	WlrLayershell.namespace: "islands-bar"
	// An open panel takes the keyboard (Esc closes it), and a click anywhere
	// but the bar closes it, as a popup's would. A question takes it too, but
	// stays until it's answered.
	WlrLayershell.keyboardFocus: panelOpen || asking ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

	HyprlandFocusGrab {
		windows: [bar]
		active: bar.panelOpen
		onCleared: Desktop.closePanel()
	}
	mask: Region {
		item: strip

		Region {
			item: centre
		}

		Region {
			item: tray
		}

		Region {
			item: held.visible ? held : null
		}
	}

	Item {
		id: strip

		width: parent.width
		height: Theme.barTop + Theme.barHeight
	}

	Row {
		x: 14
		y: Theme.barTop
		height: Theme.barHeight
		spacing: 4

		// The launcher, or the system menu on a right click
		BarIcon {
			glyph: Glyphs.nix
			glyphSize: 20
			onClicked: mouse => Desktop.launch(mouse.button === Qt.RightButton ? ["system-menu"] : ["vicinae", "toggle"])
		}

		Workspaces {
			monitor: bar.monitor
		}

		// The focused window's app, by class
		BarText {
			readonly property var window: Hyprland.activeToplevel
			readonly property string windowClass: window ? (window.wayland?.appId ?? window.lastIpcObject?.class ?? "") : ""
			readonly property string name: ({
					"": "Desktop",
					"com.mitchellh.ghostty": "Ghostty",
					"com.mitchellh.ghostty.btop": "btop"
				})[windowClass] ?? windowClass

			leftPadding: 18
			anchors.verticalCenter: parent.verticalCenter
			text: name.length > 20 ? name.slice(0, 19) + "…" : name
		}
	}

	CentreIsland {
		id: centre

		monitor: bar.monitor
		anchors.horizontalCenter: parent.horizontalCenter
		y: Theme.barTop + 2
	}

	HeldPanel {
		id: held

		visible: Desktop.panel === "held" && Desktop.panelOn === bar.monitor
		x: Math.max(8, Math.min(bar.width - width - 8, centre.x + centre.heldCentre - width / 2))
		y: centre.y + centre.height + 8
	}

	// Set apart from the status icons by twice the gap between them; it grows
	// leftwards and down into the control centre
	TrayIsland {
		id: tray

		monitor: bar.monitor
		window: bar
		anchors.right: status.left
		anchors.rightMargin: 20
		y: Theme.barTop + 2
	}

	Row {
		id: status

		anchors.right: parent.right
		anchors.rightMargin: 14
		y: Theme.barTop
		height: Theme.barHeight
		spacing: 8

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

		VolumeIcon {}

		// These four show just their icon until a left click adds the number
		// (on every bar). A right click on the CPU opens btop.
		BarIcon {
			glyph: Glyphs.cpu
			value: Metrics.showCpu ? Metrics.cpu + "%" : ""
			onClicked: mouse => {
				if (mouse.button === Qt.RightButton)
					Desktop.launch(["system-monitor"]);
				else
					Metrics.showCpu = !Metrics.showCpu;
			}
		}

		BarIcon {
			glyph: Glyphs.memory
			value: Metrics.showMemory ? Metrics.memory + "%" : ""
			onClicked: Metrics.showMemory = !Metrics.showMemory
		}

		// Red, with the number, from 80°C
		BarIcon {
			glyph: Glyphs.thermometer
			value: Metrics.showTemperature || Metrics.critical ? Math.round(Metrics.temperature) + "°C" : ""
			tint: Metrics.critical ? Theme.red : Theme.fg
			onClicked: Metrics.showTemperature = !Metrics.showTemperature
		}

		BarIcon {
			glyph: Metrics.backlight < 50 ? Glyphs.sunMin : Glyphs.sunMax
			value: Metrics.showBacklight ? Metrics.backlight + "%" : ""
			onClicked: Metrics.showBacklight = !Metrics.showBacklight
		}

		BatteryIcon {}
	}
}
