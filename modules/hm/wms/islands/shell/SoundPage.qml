import QtQuick
import Quickshell.Services.Pipewire

// How loud the output and the microphone are, and which device each is: a
// click makes one the default
Column {
	id: root

	signal back

	readonly property PwNode sink: Pipewire.defaultAudioSink
	readonly property PwNode source: Pipewire.defaultAudioSource

	readonly property var devices: Array.from(Pipewire.nodes.values).filter(n => n.audio && !n.isStream)
	readonly property var outputs: devices.filter(n => n.isSink)
	readonly property var inputs: devices.filter(n => !n.isSink)

	function nameOf(node: PwNode): string {
		return node.description || node.nickname || node.name;
	}

	spacing: 6

	PwObjectTracker {
		objects: [root.sink, root.source]
	}

	PageHeader {
		width: parent.width
		title: "Sound"
		onBack: root.back()
	}

	BarText {
		x: 4
		topPadding: 4
		text: "Output"
		color: Theme.inkDim
		font.pixelSize: 12
		font.weight: Font.DemiBold
	}

	// The chosen output's volume, as on the main page
	Slider {
		x: 8
		width: parent.width - 16
		value: root.sink?.audio?.volume ?? 0
		dimmed: root.sink?.audio?.muted ?? false
		onMoved: value => {
			if (root.sink?.audio)
				root.sink.audio.volume = value;
		}
	}

	Repeater {
		model: root.outputs

		ListRow {
			required property PwNode modelData

			width: root.width
			glyph: Glyphs.speakerWave2
			title: root.nameOf(modelData)
			chosen: Pipewire.defaultAudioSink === modelData
			trailing: chosen ? "✓" : ""
			onClicked: Pipewire.preferredDefaultAudioSink = modelData
		}
	}

	BarText {
		x: 4
		topPadding: 6
		text: "Input"
		color: Theme.inkDim
		font.pixelSize: 12
		font.weight: Font.DemiBold
	}

	// And the chosen microphone's level
	Slider {
		x: 8
		width: parent.width - 16
		value: root.source?.audio?.volume ?? 0
		dimmed: Desktop.mic === "ptt-muted" || Desktop.mic === "muted"
		onMoved: value => {
			if (root.source?.audio)
				root.source.audio.volume = value;
		}
	}

	Repeater {
		model: root.inputs

		ListRow {
			required property PwNode modelData

			width: root.width
			glyph: Glyphs.mic
			title: root.nameOf(modelData)
			chosen: Pipewire.defaultAudioSource === modelData
			trailing: chosen ? "✓" : ""
			onClicked: Pipewire.preferredDefaultAudioSource = modelData
		}
	}

	ListRow {
		width: parent.width
		glyph: "⚙"
		title: "Sound settings…"
		onClicked: {
			Panels.close();
			Desktop.launch(["pavucontrol"]);
		}
	}
}
