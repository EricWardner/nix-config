pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// The volume and brightness popup's state, which the centre island shows
// for a moment. Any change to the output volume shows it, whatever made it
// (the keys, scrolling on the bar, pavucontrol). The brightness keys come
// through here instead (`qs ipc -c islands call brightness up`), so the
// screen dimming when idle doesn't pop it up.
Singleton {
	id: root

	property string kind: "" // volume or brightness
	property real level: 0 // 0-1, volume up to 1.5
	property bool muted: false
	readonly property bool showing: shown.running

	function show(newKind: string, newLevel: real, newMuted: bool) {
		kind = newKind;
		level = newLevel;
		muted = newMuted;
		shown.restart();
	}

	Timer {
		id: shown

		interval: 1500
	}

	// The volume, from PipeWire
	readonly property PwNode sink: Pipewire.defaultAudioSink
	readonly property real volume: sink?.audio?.volume ?? 0
	readonly property bool sinkMuted: sink?.audio?.muted ?? false

	// Not for the first reading, as the shell starts
	onVolumeChanged: if (settled.ran)
		show("volume", volume, sinkMuted)
	onSinkMutedChanged: if (settled.ran)
		show("volume", volume, sinkMuted)

	PwObjectTracker {
		objects: [root.sink]
	}

	Timer {
		id: settled

		property bool ran: false

		interval: 2000
		running: root.sink !== null
		onTriggered: ran = true
	}

	// The brightness, in 5% steps from 5% (the screen never goes dark).
	// Steps start from the last one while the popup shows: brightnessctl's
	// change reaches Metrics a moment later, behind a held key's repeats.
	function stepBrightness(delta: int) {
		const from = showing && kind === "brightness" ? Math.round(level * 100) : Metrics.backlight;
		const to = Math.max(5, Math.min(100, from + delta));
		Quickshell.execDetached(["brightnessctl", "-q", "set", to + "%"]);
		show("brightness", to / 100, false);
	}

	// From the control centre's slider: no popup, the slider shows it. One
	// brightnessctl at a time, then the latest value: a drag moves faster
	// than they finish, and several at once can land out of order.
	property int wantedBrightness: -1

	function setBrightness(percent: int) {
		wantedBrightness = Math.max(5, Math.min(100, percent));
		if (!brightnessctl.running)
			applyBrightness();
	}

	function applyBrightness() {
		brightnessctl.command = ["brightnessctl", "-q", "set", wantedBrightness + "%"];
		wantedBrightness = -1;
		brightnessctl.running = true;
	}

	Process {
		id: brightnessctl

		onExited: if (root.wantedBrightness >= 0)
			root.applyBrightness()
	}

	IpcHandler {
		target: "brightness"

		function up(): void {
			root.stepBrightness(5);
		}

		function down(): void {
			root.stepBrightness(-5);
		}
	}
}
