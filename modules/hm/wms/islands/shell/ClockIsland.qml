import QtQuick
import Quickshell

// The clock on its island in the middle of the bar, in the faint glass the
// tray island has. This is the island that will grow into notifications,
// the volume popup and the notification centre.
Rectangle {
	id: root

	implicitWidth: label.implicitWidth + 28
	implicitHeight: Theme.barHeight - 4
	radius: height / 2
	color: Theme.islandFill
	border.width: 1
	border.color: Theme.islandRim

	SystemClock {
		id: clock

		precision: SystemClock.Minutes
	}

	BarText {
		id: label

		anchors.centerIn: parent
		// waybar's "%a %d %b  %I:%M %p %Z"
		text: Qt.formatDateTime(clock.date, "ddd dd MMM  hh:mm AP t")
	}
}
