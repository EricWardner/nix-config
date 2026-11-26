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
			level: bar.levels.workspaces
		}

		// The rest of the room, cut short with an ellipsis. Its start is
		// worked out from the workspaces, not its own x, which the Row
		// leaves alone while it's hidden.
		FocusedApp {
			id: focusedApp

			readonly property real start: left.x + workspaces.x + workspaces.width + left.spacing

			screen: bar.modelData
			leftPadding: 7
			width: Math.min(implicitWidth, bar.leftRoom - start)
			visible: bar.levels.name === 0
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

	// Where the centre island sits at rest, leaving out the popups and
	// panels that float over the bar (IslandMode.floats): the bar is laid
	// out around this, so they pass over it and move nothing
	readonly property real centreLeft: (bar.width - centre.baseWidth) / 2

	// The left of the bar gives way as it fills, in turn: the weather drops
	// the sun's next change once the app's name would have less than about
	// nine letters, the name goes, the workspaces show one icon per app,
	// then their names alone, and last the weather goes. The weather only
	// sits beside the clock, not a share or a recording.
	readonly property bool weatherBeside: Weather.ready && centre.baseResting
	readonly property var levels: Layout.squeeze(centreLeft - 12 - left.x - workspaces.x, {
		"workspaces": workspaces.widths,
		"name": [left.spacing + Math.min(focusedApp.implicitWidth, 90), 0],
		"weather": weatherBeside ? [8 + weather.fullWidth, 8 + weather.compactWidth, 0] : [0]
	}, ["weather", "name", "workspaces", "workspaces", "weather"])
	readonly property bool weatherShown: weatherBeside && levels.weather < 2
	// Where the left of the bar may end, 12px before the weather at rest,
	// and where it does
	readonly property real leftRoom: centreLeft - 12 - (weatherShown ? 8 + weather.restWidth : 0)
	readonly property real leftEnd: focusedApp.visible ? focusedApp.start + focusedApp.width : focusedApp.start - left.spacing
	// And where the islands after the clock may end: before the tray
	readonly property real rightEnd: (tray.visible ? tray.x : statusRest.x) - 8

	// What sits beside the centre island follows its edge, and shows while
	// the island is at rest and it fits between that edge and the fixed
	// parts of the bar: as the island shrinks back from a popup, each rides
	// in on its edge once it's clear of them (the weather 10px clear, as at
	// rest it can be 12 to the pixel)
	readonly property bool weatherFits: centre.resting && Layout.pack(centre.x - 8 - leftEnd - 10, [weather.restWidth], 0)[0]
	readonly property var afterFits: centre.resting ? Layout.pack(rightEnd - (centre.x + centre.width + 8), [(KeepAwake.on || Inbox.dnd) ? dnd.width : null, meeting.soon ? meeting.width : null, Jobs.shown.length > 0 ? job.minWidth : null], after.spacing) : [false, false, false]

	// Beside the clock: the weather before it
	WeatherIsland {
		id: weather

		screen: bar.modelData
		compact: bar.levels.weather >= 1
		visible: bar.weatherShown && (open || bar.weatherFits)
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
			visible: bar.afterFits[0]
		}

		EventIsland {
			id: meeting

			screen: bar.modelData
			visible: bar.afterFits[1]
		}

		JobIsland {
			id: job

			screen: bar.modelData
			visible: open || bar.afterFits[2]
			room: bar.rightEnd - (after.x + x)
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
