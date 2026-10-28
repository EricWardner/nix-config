//@ pragma UseQApplication
//@ pragma Env TZDIR=/etc/zoneinfo
// UseQApplication: tray items' right-click menus are Qt platform menus.
// TZDIR: Qt looks for the time zone database in /usr/share/zoneinfo, which
// NixOS doesn't have, and warns that it can't find the system's zone.

import QtQuick
import Quickshell

// islands: the desktop shell. One bar per monitor; Quickshell adds and
// removes bars as monitors come and go, so a hotplug restarts nothing. The
// capture overlays are built once per monitor and shown for each capture.
ShellRoot {
	Variants {
		model: Quickshell.screens

		Bar {}
	}

	Variants {
		model: Quickshell.screens

		CaptureOverlay {}
	}
}
