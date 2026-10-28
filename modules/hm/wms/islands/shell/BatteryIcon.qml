import QtQuick
import Quickshell.Services.UPower

// The battery, from UPower: its level as an icon, and on power a bolt with
// the percentage (just the bolt once full). A left click shows the
// percentage on battery too. "On power" means the charger is connected, as
// waybar had it: the battery can report discharging at 100% with it in.
BarIcon {
	id: root

	readonly property UPowerDevice device: UPower.displayDevice
	// UPower reports 0-100; Quickshell may scale it to 0-1
	readonly property real level: device.percentage <= 1 ? device.percentage * 100 : device.percentage
	readonly property bool full: device.state === UPowerDeviceState.FullyCharged
	readonly property bool plugged: !UPower.onBattery
	property bool pinned: false

	visible: device.isLaptopBattery
	glyph: plugged ? Glyphs.batteryBolt : level < 13 ? Glyphs.battery0 : level < 38 ? Glyphs.battery25 : level < 63 ? Glyphs.battery50 : level < 88 ? Glyphs.battery75 : Glyphs.battery100
	value: (plugged && !full) || pinned ? Math.round(level) + "%" : ""
	// Green on power; on battery, yellow from 30% and red, blinking, from 15%
	tint: plugged ? Theme.green : level <= 15 ? (blink.on ? Theme.red : Theme.fg) : level <= 30 ? Theme.yellow : Theme.fg

	onClicked: pinned = !pinned

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
