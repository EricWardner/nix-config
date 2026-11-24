import QtQuick
import Quickshell.Services.Pipewire

// How loud the output and the microphone are, and which device each is: a
// card for each, where a click makes a device the default
Column {
	id: root

	signal back

	readonly property PwNode sink: Pipewire.defaultAudioSink
	readonly property PwNode source: Pipewire.defaultAudioSource
	readonly property var devices: Array.from(Pipewire.nodes.values).filter(n => n.audio && !n.isStream)

	// One direction's card: its level, as on the main page, then its
	// devices with the default ticked
	component Devices: Card {
		id: group

		property string title
		property string glyph
		property PwNode current
		property var devices
		// Drawn faint: the level stands but isn't in effect (muted)
		property bool dimmed

		signal picked(PwNode node)

		Column {
			width: parent.width
			spacing: 4

			BarText {
				x: 2
				text: group.title
				color: Theme.inkDim
				font.pixelSize: 12
				font.weight: Font.DemiBold
			}

			Slider {
				x: 2
				width: parent.width - 4
				value: group.current?.audio?.volume ?? 0
				dimmed: group.dimmed
				onMoved: value => {
					if (group.current?.audio)
						group.current.audio.volume = value;
				}
			}

			// Out to near the card's edge, so their icons sit under the
			// title
			Repeater {
				model: group.devices

				ListRow {
					required property PwNode modelData

					x: -6
					width: parent.width + 12
					glyph: group.glyph
					title: modelData.description || modelData.nickname || modelData.name
					chosen: group.current === modelData
					trailing: chosen ? "✓" : ""
					onClicked: group.picked(modelData)
				}
			}
		}
	}

	spacing: 10

	PwObjectTracker {
		objects: [root.sink, root.source]
	}

	PageHeader {
		width: parent.width
		title: "Sound"
		onBack: root.back()
	}

	Devices {
		width: parent.width
		title: "Output"
		glyph: Glyphs.speakerWave2
		current: root.sink
		devices: root.devices.filter(n => n.isSink)
		dimmed: root.sink?.audio?.muted ?? false
		onPicked: node => Pipewire.preferredDefaultAudioSink = node
	}

	Devices {
		width: parent.width
		title: "Input"
		glyph: Glyphs.mic
		current: root.source
		devices: root.devices.filter(n => !n.isSink)
		dimmed: Desktop.mic === "ptt-muted" || Desktop.mic === "muted"
		onPicked: node => Pipewire.preferredDefaultAudioSource = node
	}

	// Apart from the cards, as it leaves the page, and in line with their rows
	ListRow {
		x: 6
		width: parent.width - 12
		glyph: "⚙"
		title: "Sound settings…"
		onClicked: {
			Panels.close();
			Desktop.launch(["pavucontrol"]);
		}
	}
}
