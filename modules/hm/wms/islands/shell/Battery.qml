pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

// The laptop battery, from UPower, as the bar, Sky and the control centre
// tell it
Singleton {
	id: root

	readonly property UPowerDevice device: UPower.displayDevice
	readonly property bool present: device?.isLaptopBattery ?? false
	readonly property real level: (device?.percentage ?? 0) * 100
	// The charger connected. The battery can report discharging at 100%
	// with it in, so that alone isn't draining.
	readonly property bool plugged: !UPower.onBattery
	readonly property bool charging: device?.state === UPowerDeviceState.Charging
	readonly property real rate: Math.abs(device?.changeRate ?? 0)
	// Losing charge with the charger in: one too weak for the load, or a
	// hub not passing enough through
	readonly property bool draining: plugged && device?.state === UPowerDeviceState.Discharging && rate >= 1 && level < 99
	// Charging, or kept full: the bar's green bolt
	readonly property bool onPower: plugged && !draining
	// Running down at 30% or less: the bar's icon turns yellow and shows the
	// percentage
	readonly property bool low: !onPower && level <= 30
	// "17 W · Empty in 3h 20m", "Charging at 45 W · Full in 19m", "Draining
	// on power · 9.5 W · Empty in 5h", "On power"; UPower leaves a time out
	// (0) until it has an estimate
	readonly property string status: {
		const parts = [];
		if (charging) {
			parts.push(rate > 0 ? "Charging at " + watts(rate) : "Charging");
			if (device.timeToFull > 0)
				parts.push("Full in " + duration(device.timeToFull));
		} else if (onPower) {
			parts.push("On power");
		} else {
			if (draining)
				parts.push("Draining on power");
			if (rate > 0)
				parts.push(watts(rate));
			if (device.timeToEmpty > 0)
				parts.push("Empty in " + duration(device.timeToEmpty));
		}
		return parts.join(" · ");
	}

	// "3h 20m", "45m"
	function duration(seconds: real): string {
		const minutes = Math.round(seconds / 60);
		const hours = Math.floor(minutes / 60);
		return hours > 0 ? hours + "h " + minutes % 60 + "m" : minutes + "m";
	}

	// "17 W", "4.2 W"
	function watts(rate: real): string {
		return (rate >= 10 ? Math.round(rate) : rate.toFixed(1)) + " W";
	}
}
