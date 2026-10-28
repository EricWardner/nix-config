import QtQuick
import Quickshell.Services.Pipewire

// The output volume, from PipeWire. Any change shows the percentage for a
// moment, whatever made it (the keys, scrolling, pavucontrol); a left click
// keeps it shown. Scrolling steps 5% up to 150%, a middle click mutes, a
// right click opens pavucontrol. No scroll-to-mute: crossing the bar with
// the wheel would flip it.
BarIcon {
	id: root

	readonly property PwNode sink: Pipewire.defaultAudioSink
	readonly property real volume: sink?.audio?.volume ?? 0
	readonly property bool muted: sink?.audio?.muted ?? true
	property bool pinned: false

	glyph: muted || volume === 0 ? Glyphs.speakerSlash : volume < 0.34 ? Glyphs.speakerWave1 : volume < 0.67 ? Glyphs.speakerWave2 : Glyphs.speakerWave3
	value: pinned || flash.running ? Math.round(volume * 100) + "%" : ""
	tint: muted ? Theme.dim : Theme.fg

	// Not for the first reading, as the shell starts
	onVolumeChanged: if (settled.ran) flash.restart()
	onMutedChanged: if (settled.ran) flash.restart()
	onClicked: mouse => {
		if (mouse.button === Qt.LeftButton)
			pinned = !pinned;
		else if (mouse.button === Qt.MiddleButton)
			sink.audio.muted = !muted;
		else
			Desktop.launch(["pavucontrol"]);
	}
	onScrolled: wheel => {
		if (!sink?.audio)
			return;
		const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
		sink.audio.volume = Math.max(0, Math.min(1.5, volume + step));
	}

	// The sink's volume and mute are only kept up to date while tracked
	PwObjectTracker {
		objects: [root.sink]
	}

	Timer {
		id: flash

		interval: 1500
	}

	Timer {
		id: settled

		property bool ran: false

		interval: 2000
		running: root.sink !== null
		onTriggered: ran = true
	}
}
