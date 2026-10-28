import QtQuick
import Quickshell

// The island at rest: the clock
IslandMode {
	active: true
	resting: true
	islandWidth: clock.implicitWidth + 28
	islandHeight: Theme.barHeight - 4

	SystemClock {
		id: time

		precision: SystemClock.Minutes
	}

	BarText {
		id: clock

		anchors.centerIn: parent
		// waybar's "%a %d %b  %I:%M %p %Z"
		text: Qt.formatDateTime(time.date, "ddd dd MMM  hh:mm AP t")
	}
}
