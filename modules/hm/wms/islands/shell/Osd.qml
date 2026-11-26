pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// The volume and brightness popup's state, which the centre island shows
// for a moment. Any change to the output volume shows it, whatever made it
// (the keys, scrolling on the bar, pavucontrol). The brightness shows it
// only for its keys (Brightness.step), not for idle dimming.
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
}
