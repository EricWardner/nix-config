import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

// The applets' island, left of the status island; none, no island
Island {
	id: root

	required property QsWindow window

	visible: SystemTray.items.values.length > 0

	TrayMode {
		window: root.window
	}
}
