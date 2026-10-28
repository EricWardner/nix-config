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
	// or available; the record button idle or active
	property string mic: ""
	property string webcam: ""
	property string record: ""
	// A recording's progress, for beside the clock: record-watch's `class`
	// (idle, selecting, countdown, recording, done) and its text
	property var recording: ({
			"class": "idle",
			"text": ""
		})

	Watcher {
		command: ["mic-watch"]
		onUpdate: state => root.mic = state.class
	}
	Watcher {
		command: ["webcam-watch"]
		onUpdate: state => root.webcam = state.class
	}
	Watcher {
		command: ["record-watch", "button"]
		onUpdate: state => root.record = state.class
	}
	Watcher {
		command: ["record-watch", "status"]
		onUpdate: state => root.recording = state
	}

	// Starts a command in its own transient scope, so it outlives the shell
	// (a restart would otherwise take a recording with it)
	function launch(command: list<string>) {
		Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--"].concat(command));
	}
}
