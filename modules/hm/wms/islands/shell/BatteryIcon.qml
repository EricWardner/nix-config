import QtQuick
import Quickshell
import Quickshell.Io

// The battery: its level as an icon, or a bolt while it's charging or kept
// full (draining with the charger in shows the level, in yellow). A left
// click opens the control centre's battery page. A right click shows or
// hides the percentage, kept across restarts of the shell. While the
// battery is low (Battery.low) the percentage shows anyway; a right click
// hides it until the battery is next low.
BarIcon {
	id: root

	readonly property real level: Battery.level
	property bool showPercent: false
	property bool hiddenWhileLow: false

	signal openBattery

	visible: Battery.present
	glyph: Battery.onPower ? Glyphs.batteryBolt : level < 13 ? Glyphs.battery0 : level < 38 ? Glyphs.battery25 : level < 63 ? Glyphs.battery50 : level < 88 ? Glyphs.battery75 : Glyphs.battery100
	glyphs: [Glyphs.battery0, Glyphs.battery25, Glyphs.battery50, Glyphs.battery75, Glyphs.battery100, Glyphs.batteryBolt]
	value: (Battery.low ? !hiddenWhileLow : showPercent) ? Math.round(level) + "%" : ""
	// Green on power; yellow when low or draining on power, and red from 15%
	tint: Battery.onPower ? Theme.green : level <= 15 ? Theme.red : Battery.low || Battery.draining ? Theme.yellow : Theme.fg

	Connections {
		target: Battery

		function onLowChanged() {
			root.hiddenWhileLow = false;
		}
	}

	function togglePercent() {
		if (Battery.low) {
			hiddenWhileLow = !hiddenWhileLow;
		} else {
			showPercent = !showPercent;
			percent.setText(showPercent ? "on" : "off");
		}
	}

	onClicked: mouse => {
		if (mouse.button === Qt.LeftButton)
			openBattery();
		else if (mouse.button === Qt.RightButton)
			togglePercent();
	}

	FileView {
		id: percent

		path: Quickshell.statePath("battery-percent")
		printErrors: false
		onLoaded: root.showPercent = text().trim() === "on"
	}
}
