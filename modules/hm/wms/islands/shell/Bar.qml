import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The bar along the top of one monitor, transparent but for its islands and
// 4px below the screen's edge, as waybar was. Left: the launcher, this
// monitor's workspaces and the focused app. Middle: the centre island.
// Right: the applets' tray island, then the status island, which grows into
// the control centre.
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
	WlrLayershell.namespace: "islands-bar"
	// An open panel takes the keyboard (Esc closes it), and a click anywhere
	// but the bar closes it, as a popup's would. A question to type into
	// holds the keyboard until it's answered or Esc'd: it can turn up unasked
	// (a keyring's password), and has to take typing without a click first.
	WlrLayershell.keyboardFocus: asking && Agent.typing ? WlrKeyboardFocus.Exclusive : panelOpen || asking ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

	// Hyprland blurs behind the islands' glass here, however clear the glass
	// is: told by opacity alone, it switched the blur on partway through a
	// growing island's fade-in, and the windows behind flashed. Each area
	// reaches a little past its island, and Hyprland's ignore_alpha
	// (rules.lua) trims it to the glass: a region's rounded corners are
	// whole logical pixels, and its steps showed against anything bright
	// beside the islands.
	BackgroundEffect.blurRegion: Region {
		Region {
			item: centre.blurArea
		}

		Region {
			item: weather.visible ? weather.blurArea : null
		}

		Region {
			item: dnd.visible ? dnd.blurArea : null
		}

		Region {
			item: meeting.visible ? meeting.blurArea : null
		}

		Region {
			item: held.visible ? held.blurArea : null
		}

		Region {
			item: tray.visible ? tray.blurArea : null
		}

		Region {
			item: status.blurArea
		}
	}

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
			item: tray.visible ? tray : null
		}

		Region {
			item: status
		}

		Region {
			item: held.visible ? held : null
		}

		Region {
			item: dnd.visible ? dnd : null
		}

		Region {
			item: meeting.visible ? meeting : null
		}

		Region {
			item: weather.visible ? weather : null
		}
	}

	Item {
		id: strip

		width: parent.width
		height: Theme.barTop + Theme.barHeight

		// The focus grab only sees clicks outside the bar, so its empty
		// stretches close a panel here; what's on the bar sits above this
		MouseArea {
			anchors.fill: parent
			enabled: bar.panelOpen
			onClicked: Desktop.closePanel()
		}
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

		FocusedApp {
			monitor: bar.monitor
			leftPadding: 18
			anchors.verticalCenter: parent.verticalCenter
		}
	}

	CentreIsland {
		id: centre

		monitor: bar.monitor
		anchors.horizontalCenter: parent.horizontalCenter
		y: Theme.barTop + 2
	}

	// Beside the clock while it's at rest: the weather before it, Do Not
	// Disturb after it, then the next meeting
	WeatherIsland {
		id: weather

		monitor: bar.monitor
		visible: Weather.ready && (open || centre.resting)
		x: centre.x - width - 8
		y: centre.y
	}

	DndIsland {
		id: dnd

		monitor: bar.monitor
		visible: Inbox.dnd && centre.resting
		x: centre.x + centre.width + 8
		y: centre.y
	}

	EventIsland {
		id: meeting

		monitor: bar.monitor
		visible: soon && centre.resting
		x: (dnd.visible ? dnd.x + dnd.width : centre.x + centre.width) + 8
		y: centre.y
	}

	HeldPanel {
		id: held

		visible: Desktop.panel === "held" && Desktop.panelOn === bar.monitor
		x: Math.max(8, Math.min(bar.width - width - 8, centre.x + centre.heldCentre - width / 2))
		y: centre.y + centre.height + 8
	}

	// Where the status island sits at rest, so the tray beside it stays put
	// as the island grows into the control centre
	Item {
		id: statusRest

		anchors.right: parent.right
		anchors.rightMargin: 10
		width: status.restWidth
	}

	// Gone while the control centre is open: it would show through the glass
	TrayIsland {
		id: tray

		window: bar
		anchors.right: statusRest.left
		anchors.rightMargin: 10
		y: Theme.barTop + 2
		opacity: Desktop.panel === "control" && Desktop.panelOn === bar.monitor ? 0 : 1

		Behavior on opacity {
			NumberAnimation {
				duration: 150
			}
		}
	}

	// After the tray, so the control centre grows over it
	StatusIsland {
		id: status

		monitor: bar.monitor
		anchors.right: parent.right
		anchors.rightMargin: 10
		y: Theme.barTop + 2
	}
}
