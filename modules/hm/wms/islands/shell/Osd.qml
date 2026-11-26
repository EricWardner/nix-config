pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// The volume and brightness popup's state, which the centre island shows
// for a moment. Any change to the output volume shows it, whatever made it
// (the keys, scrolling on the bar, pavucontrol). The brightness keys and
// hypridle's idle dimming come through here instead (`qs ipc -c islands
// call brightness up`, `dim`), and only the keys pop it up.
Singleton {
	id: root

	property string kind: "" // volume or brightness
	property real level: 0 // 0-1, volume up to 1.5
	property bool muted: false
	readonly property bool showing: shown.running && !hushed
	// Its moment passes unseen: it changed while the control centre was
	// open, whose sliders showed it (or the control centre opened over it).
	// Otherwise what was left of the moment flashed up in the island as
	// the control centre closed.
	property bool hushed: false

	function show(newKind: string, newLevel: real, newMuted: bool) {
		kind = newKind;
		level = newLevel;
		muted = newMuted;
		hushed = Panels.name === "control";
		shown.restart();
	}

	Connections {
		target: Panels

		function onNameChanged() {
			if (Panels.name === "control")
				root.hushed = true;
		}
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
	function stepBrightness(delta: int) {
		const to = Math.max(5, Math.min(100, currentBrightness() + delta));
		setBrightness(to);
		show("brightness", to / 100, false);
	}

	// What a step starts from: the level before an idle dim, or the last
	// one asked for, as brightnessctl's change reaches Metrics a moment
	// later, behind a held key's repeats
	function currentBrightness(): int {
		if (undimmed >= 0)
			return undimmed;
		return asked.running ? asked.level : Metrics.backlight;
	}

	// Idle dimming (hypridle calls dim and undim). A key press that wakes
	// the screen reaches the shell along with hypridle's undim, in either
	// order, so a step while dimmed starts from the level before the dim,
	// and an undim after it does nothing. Kept in the runtime directory
	// too, so a shell restarted while dimmed (by a rebuild) still undims.
	property int undimmed: -1

	onUndimmedChanged: undimmedFile.setText(undimmed < 0 ? "" : String(undimmed))

	FileView {
		id: undimmedFile

		path: Quickshell.env("XDG_RUNTIME_DIR") + "/islands-undimmed"
		blockLoading: true
		printErrors: false
	}

	Component.onCompleted: {
		const saved = parseInt(undimmedFile.text());
		if (saved > 0)
			undimmed = saved;
	}

	function dim() {
		if (undimmed >= 0)
			return;
		const from = currentBrightness();
		askBrightness(Math.min(10, from));
		undimmed = from;
	}

	function undim() {
		if (undimmed < 0)
			return;
		const to = undimmed;
		undimmed = -1;
		askBrightness(to);
	}

	Timer {
		id: asked

		property int level: 0

		interval: 1500
	}

	// From the control centre's slider and the keys: a level chosen by
	// hand ends an idle dim
	function setBrightness(percent: int) {
		undimmed = -1;
		askBrightness(percent);
	}

	// Everything goes through here, with no popup: the control centre's
	// slider shows it, and a step shows its own. One brightnessctl at a
	// time, then the latest value: a drag moves faster than they finish,
	// and several at once can land out of order.
	property int wantedBrightness: -1

	function askBrightness(percent: int) {
		wantedBrightness = Math.max(5, Math.min(100, percent));
		asked.level = wantedBrightness;
		asked.restart();
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

		function dim(): void {
			root.dim();
		}

		function undim(): void {
			root.undim();
		}
	}
}
