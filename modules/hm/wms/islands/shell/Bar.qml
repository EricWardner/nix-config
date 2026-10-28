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
// on the bar and the centre island; everywhere else they reach the windows
// underneath.
PanelWindow {
	id: bar

	required property ShellScreen modelData

	screen: modelData
	anchors.top: true
	anchors.left: true
	anchors.right: true
	implicitHeight: Theme.windowHeight
	exclusiveZone: Theme.barTop + Theme.barHeight
	color: "transparent"
	// Hyprland blurs behind it only where it's over 50% opaque
	// (hypr/lua/rules.lua), so the bare bar's text gets no halo
	WlrLayershell.namespace: "islands-bar"
	mask: Region {
		item: strip

		Region {
			item: centre
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
			monitor: Hyprland.monitorFor(bar.modelData)
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

		monitor: Hyprland.monitorFor(bar.modelData)
		anchors.horizontalCenter: parent.horizontalCenter
		y: Theme.barTop + 2
	}

	// A recording's progress, after the clock (which stays centred): the
	// selection, the countdown and the timer in red, then green once saved.
	// A click cancels or stops it, or opens the saved one's preview.
	BarIcon {
		readonly property string state: Desktop.recording.class
		// record-watch writes Pango markup: the icon, then any text
		readonly property var parts: Desktop.recording.text.replace(/<[^>]*>/g, "").split(" ")

		visible: state !== "idle" && state !== ""
		anchors.left: centre.right
		anchors.leftMargin: 12
		y: Theme.barTop
		glyph: parts[0] ?? ""
		value: parts.slice(1).join(" ")
		tint: state === "done" ? Theme.green : state === "countdown" || state === "recording" ? Theme.red : Theme.fg
		onClicked: Desktop.launch(["screen-record", "click"])
	}

	Row {
		anchors.right: parent.right
		anchors.rightMargin: 14
		y: Theme.barTop
		height: Theme.barHeight
		spacing: 8

		TrayIsland {
			window: bar
			anchors.verticalCenter: parent.verticalCenter
		}

		// Sets the island apart: twice the gap between status icons
		Item {
			width: 12
			height: 1
		}

		// Start or stop a recording (Super+R does the same); a right click
		// opens the last one
		BarIcon {
			glyph: Desktop.record === "active" ? Glyphs.stopCircle : Glyphs.recordCircle
			tint: Desktop.record === "active" ? Theme.red : Theme.fg
			onClicked: mouse => Desktop.launch(mouse.button === Qt.RightButton ? ["screen-record", "menu"] : ["screen-record"])
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
