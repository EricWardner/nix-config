pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// What the status icons show that Quickshell has no service for, from
// bar-tools' watchers (one process each, however many bars) and mako-dnd,
// and how the bar starts things.
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
	property bool dnd: false

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

	// Do Not Disturb: mako-dnd writes "on" or "off" here whenever it changes
	// mako's mode, and once as the shell starts
	FileView {
		path: Quickshell.env("XDG_RUNTIME_DIR") + "/islands/dnd"
		watchChanges: true
		printErrors: false
		onFileChanged: reload()
		onLoaded: root.dnd = text().trim() === "on"
	}
	Process {
		command: ["mako-dnd", "sync"]
		running: true
	}

	// Starts a command in its own transient scope, so it outlives the shell
	// (a restart would otherwise take a recording with it)
	function launch(command: list<string>) {
		Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--"].concat(command));
	}
}
