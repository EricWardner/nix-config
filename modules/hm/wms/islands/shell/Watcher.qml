import QtQuick
import Quickshell.Io

// One of bar-tools' watchers: a long-running process that prints a line of
// JSON ({"class": …}) whenever its state changes, and otherwise sleeps.
// Restarted 5 s after it exits.
Process {
	id: root

	signal update(var state)

	running: true
	stdout: SplitParser {
		onRead: line => {
			try {
				root.update(JSON.parse(line));
			} catch (e) {
				console.warn("islands:", root.command[0], "printed", line);
			}
		}
	}
	onExited: restart.start()

	property Timer restart: Timer {
		interval: 5000
		onTriggered: root.running = true
	}
}
