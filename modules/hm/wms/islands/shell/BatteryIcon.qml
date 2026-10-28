import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The battery, from UPower: its level as an icon, or a bolt on power ("on
// power" meaning the charger is connected: the battery can report
// discharging at 100% with it in). A left click shows or hides the
// percentage, kept across restarts of the shell.
BarIcon {
	id: root

	readonly property UPowerDevice device: UPower.displayDevice
	// UPower reports 0-100; Quickshell may scale it to 0-1
	readonly property real level: device.percentage <= 1 ? device.percentage * 100 : device.percentage
	readonly property bool plugged: !UPower.onBattery
	property bool showPercent: false

	visible: device.isLaptopBattery
	glyph: plugged ? Glyphs.batteryBolt : level < 13 ? Glyphs.battery0 : level < 38 ? Glyphs.battery25 : level < 63 ? Glyphs.battery50 : level < 88 ? Glyphs.battery75 : Glyphs.battery100
	value: showPercent ? Math.round(level) + "%" : ""
	// Green on power; on battery, yellow from 30% and red, blinking, from 15%
	tint: plugged ? Theme.green : level <= 15 ? (blink.on ? Theme.red : Theme.fg) : level <= 30 ? Theme.yellow : Theme.fg

	onClicked: {
		showPercent = !showPercent;
		percent.setText(showPercent ? "on" : "off");
	}

	FileView {
		id: percent

		path: Quickshell.statePath("battery-percent")
		printErrors: false
		onLoaded: root.showPercent = text().trim() === "on"
	}

	Timer {
		id: blink

		property bool on: true

		interval: 500
		repeat: true
		running: !root.plugged && root.level <= 15
		onRunningChanged: on = true
		onTriggered: on = !on
	}
}
