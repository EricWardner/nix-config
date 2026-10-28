import QtQuick
import Quickshell.Services.Pipewire

// Which device plays sound and which records it: a click makes one the
// default
Column {
	id: root

	signal back

	readonly property var devices: Array.from(Pipewire.nodes.values).filter(n => n.audio && !n.isStream)
	readonly property var outputs: devices.filter(n => n.isSink)
	readonly property var inputs: devices.filter(n => !n.isSink)

	function nameOf(node: PwNode): string {
		return node.description || node.nickname || node.name;
	}

	spacing: 6

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
			Desktop.closePanel();
			Desktop.launch(["pavucontrol"]);
		}
	}
}
