import QtQuick
import Quickshell.Services.UPower

// The power profile, as a segmented control
Segments {
	readonly property var profiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]

	height: 36
	radius: 12
	fontSize: 12
	options: ["Saver", "Balanced", "Performance"]
	current: profiles.indexOf(PowerProfiles.profile)
	unavailable: PowerProfiles.hasPerformanceProfile ? [] : [2]
	onPicked: index => PowerProfiles.profile = profiles[index]
}
