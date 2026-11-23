pragma Singleton

import QtQuick
import Quickshell

// What the status icons show that Quickshell has no service for, from
// bar-tools' watchers (one process each, however many bars), and how the
// bar starts things.
Singleton {
	id: root

	// Each watcher's `class`: the mic is on, muted, ptt-muted (push-to-talk
	// armed) or ptt-active (talking); the webcam disconnected, muted, in-use
	// or available
	property string mic: ""
	property string webcam: ""

	Watcher {
		command: ["mic-watch"]
		onUpdate: state => root.mic = state.class
	}
	Watcher {
		command: ["webcam-watch"]
		onUpdate: state => root.webcam = state.class
	}

	// Starts a command in its own transient scope, so it outlives the shell
	// (a restart would otherwise take a preview window or a settings app
	// with it). Untyped: as a list<string>, a command read from a model (the
	// control centre's buttons) arrives empty, and nothing runs.
	function launch(command) {
		Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--"].concat(Array.from(command)));
	}
}
