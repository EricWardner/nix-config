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
	// The notification or control centre (or the power menu, or the held
	// notifications) is open on this monitor
	readonly property bool panelOpen: Panels.name !== "" && Panels.screen === modelData
	// A question (a Wi-Fi password, a pairing step, polkit's password) is in
	// this monitor's island
	readonly property bool asking: Agent.current !== null && Compositor.focusedScreen === modelData
	// The islands, each named once for the two lists of areas below: where
	// Hyprland may blur, and where clicks land
	readonly property list<Item> islands: [power, centre, weather, dnd, meeting, job, held, tray, status]

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
		regions: blurred.instances
	}

	Variants {
		id: blurred

		model: bar.islands

		Region {
			required property Item modelData
			// The area sits inside its island and so doesn't move when the
			// island does: one in a row moves a frame after its neighbour
			// went, by when the areas have been read
			readonly property real islandAt: modelData.x

			item: modelData.visible ? modelData.blurArea : null
			onIslandAtChanged: changed()
		}
	}

	HyprlandFocusGrab {
		windows: [bar]
		active: bar.panelOpen
		onCleared: Panels.close()
	}
	mask: Region {
		item: strip
		regions: clickable.instances
	}

	Variants {
		id: clickable

		model: bar.islands

		Region {
			required property Item modelData

			item: modelData.visible ? modelData : null
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
			onClicked: Panels.close()
		}
	}

	Row {
		id: left

		x: 14
		y: Theme.barTop
		height: Theme.barHeight
		// The launcher as far from the first workspace as the workspaces are
		// from each other (their own 7px of padding makes up the rest)
		spacing: 15

		// The launcher, or the power menu on a right click
		BarIcon {
			glyph: Glyphs.nix
			glyphSize: 18
			onClicked: mouse => {
				if (mouse.button !== Qt.RightButton) {
					if (Panels.shows("power", bar.modelData))
						Panels.close();
					Desktop.launch(["vicinae", "toggle"]);
				} else if (!bar.asking) {
					// Not over a question: the menu would take the keyboard
					// from its field
					Panels.toggle("power", bar.modelData);
				}
			}
		}

		Workspaces {
			id: workspaces

			screen: bar.modelData
			level: Math.max(0, Math.min(2, bar.squeeze - 2))
		}

		// Up to the islands in the middle, cut short with an ellipsis, and
		// gone when only a few letters would fit. Worked out from the
		// workspaces, not its own x: the Row stops placing it while hidden.
		FocusedApp {
			id: focusedApp

			readonly property real start: left.x + workspaces.x + workspaces.width + left.spacing
			readonly property real room: (weather.visible ? weather.x : centre.x) - 12 - start

			screen: bar.modelData
			leftPadding: 7
			width: Math.min(implicitWidth, room)
			// Not back in the room the workspaces give up further on
			visible: room >= 50 && bar.squeeze < 2
			elide: Text.ElideRight
			anchors.verticalCenter: parent.verticalCenter
		}
	}

	// Under the launcher
	PowerMenu {
		id: power

		visible: Panels.shows("power", bar.modelData)
		x: 10
		y: Theme.barTop + Theme.barHeight + 6
	}

	CentreIsland {
		id: centre

		screen: bar.modelData
		anchors.horizontalCenter: parent.horizontalCenter
		y: Theme.barTop + 2
	}

	// How the left of the bar gives way as it runs into the weather, in
	// turn: 1 the weather drops the sun's next change once the app's name
	// would have less than about nine letters, 2 the name goes, 3 the
	// workspaces show one icon per app, 4 their names alone, 5 the weather
	// goes. Judged by what each step would take, not by the widths now, so
	// a step doesn't undo itself.
	readonly property int squeeze: {
		const start = left.x + workspaces.x + left.spacing;
		const edge = centre.x - 8 - 12;
		const name = Math.min(focusedApp.implicitWidth, 90);
		const widths = workspaces.widths;
		if (edge - weather.fullWidth - start - widths[0] >= name)
			return 0;
		if (edge - weather.compactWidth - start - widths[0] >= name)
			return 1;
		if (edge - weather.compactWidth - start - widths[0] >= 0)
			return 2;
		if (edge - weather.compactWidth - start - widths[1] >= 0)
			return 3;
		if (edge - weather.compactWidth - start - widths[2] >= 0)
			return 4;
		return 5;
	}

	// Beside the clock while it's at rest: the weather before it
	WeatherIsland {
		id: weather

		screen: bar.modelData
		compact: bar.squeeze >= 1
		visible: Weather.ready && (open || centre.resting) && bar.squeeze < 5
		x: centre.x - width - 8
		y: centre.y
	}

	// And after it: Keep Awake and Do Not Disturb, then the next meeting,
	// then a terminal's job, each up against the last of them that's showing
	Row {
		id: after

		x: centre.x + centre.width + 8
		y: centre.y
		spacing: 8

		DndIsland {
			id: dnd

			screen: bar.modelData
			visible: (KeepAwake.on || Inbox.dnd) && centre.resting
		}

		EventIsland {
			id: meeting

			screen: bar.modelData
			visible: soon && centre.resting
		}

		JobIsland {
			id: job

			screen: bar.modelData
			visible: Jobs.shown.length > 0 && (open || centre.resting)
			room: (tray.visible ? tray.x : statusRest.x) - 8 - (after.x + x)
		}
	}

	HeldPanel {
		id: held

		visible: Panels.shows("held", bar.modelData)
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
		opacity: Panels.shows("control", bar.modelData) ? 0 : 1

		Behavior on opacity {
			NumberAnimation {
				duration: 150
			}
		}
	}

	// After the tray, so the control centre grows over it
	StatusIsland {
		id: status

		screen: bar.modelData
		anchors.right: parent.right
		anchors.rightMargin: 10
		y: Theme.barTop + 2
	}
}
