import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The battery, from UPower: its level as an icon, or a bolt on power ("on
// power" meaning the charger is connected: the battery can report
// discharging at 100% with it in). A left click shows or hides the
// percentage, kept across restarts of the shell. While the battery is low
// (on battery, 30% or less, when the icon turns yellow) the percentage shows
// anyway; a click hides it until the battery is next low.
BarIcon {
	id: root

	readonly property UPowerDevice device: UPower.displayDevice
	readonly property real level: device.percentage * 100
	readonly property bool plugged: !UPower.onBattery
	readonly property bool low: !plugged && level <= 30
	property bool showPercent: false
	property bool hiddenWhileLow: false

	visible: device.isLaptopBattery
	glyph: plugged ? Glyphs.batteryBolt : level < 13 ? Glyphs.battery0 : level < 38 ? Glyphs.battery25 : level < 63 ? Glyphs.battery50 : level < 88 ? Glyphs.battery75 : Glyphs.battery100
	glyphs: [Glyphs.battery0, Glyphs.battery25, Glyphs.battery50, Glyphs.battery75, Glyphs.battery100, Glyphs.batteryBolt]
	value: (low ? !hiddenWhileLow : showPercent) ? Math.round(level) + "%" : ""
	// Green on power; when low, yellow, and red from 15%
	tint: plugged ? Theme.green : level <= 15 ? Theme.red : low ? Theme.yellow : Theme.fg

	onLowChanged: hiddenWhileLow = false
	onClicked: {
		if (low) {
			hiddenWhileLow = !hiddenWhileLow;
		} else {
			showPercent = !showPercent;
			percent.setText(showPercent ? "on" : "off");
		}
	}

	FileView {
		id: percent

		path: Quickshell.statePath("battery-percent")
		printErrors: false
		onLoaded: root.showPercent = text().trim() === "on"
	}
}
