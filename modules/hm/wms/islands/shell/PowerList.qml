import QtQuick

// Lock, sleep, restart, shut down and log out, as rows: the power menu under
// the launcher (PowerMenu) and the control centre's power page (PowerPage).
// A click does one and closes the panel; so do Up or Down and Enter, while
// it has the keyboard.
Column {
	id: root

	readonly property var actions: [
		{
			"glyph": Glyphs.lock,
			"title": "Lock",
			"command": ["loginctl", "lock-session"]
		},
		{
			"glyph": Glyphs.sleep,
			"title": "Sleep",
			"command": ["systemctl", "suspend-then-hibernate"]
		},
		{
			"glyph": Glyphs.restart,
			"title": "Restart",
			"command": ["systemctl", "reboot"]
		},
		{
			"glyph": Glyphs.power,
			"title": "Shut Down",
			"command": ["systemctl", "poweroff"]
		},
		{
			"glyph": Glyphs.logOut,
			"title": "Log Out",
			"command": ["hyprctl", "dispatch", "hl.dsp.exit()"]
		}
	]
	// The row the arrow keys are on: none until one is pressed
	property int chosen: -1

	function run(action) {
		Panels.close();
		Desktop.launch(action.command);
	}

	// Enter does the chosen row, and is somebody else's key while none is
	function enter(event) {
		if (chosen >= 0)
			run(actions[chosen]);
		else
			event.accepted = false;
	}

	spacing: 2
	onVisibleChanged: chosen = -1

	// Only while it shows: a hidden item keeps the keyboard it was given, and
	// Down and Enter on another page would restart the machine unseen
	Keys.enabled: visible
	Keys.onDownPressed: chosen = (chosen + 1) % actions.length
	Keys.onUpPressed: chosen = chosen <= 0 ? actions.length - 1 : chosen - 1
	Keys.onReturnPressed: event => enter(event)
	Keys.onEnterPressed: event => enter(event)

	Repeater {
		model: root.actions

		ListRow {
			required property var modelData
			required property int index

			width: root.width
			glyph: modelData.glyph
			title: modelData.title
			chosen: index === root.chosen
			// The pointer takes over from the arrow keys, so one row is lit
			onHoveredChanged: if (hovered)
				root.chosen = -1
			onClicked: root.run(modelData)
		}
	}
}
