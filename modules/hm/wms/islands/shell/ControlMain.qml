import QtQuick
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// The control centre's main page: tiles for Wi-Fi, Bluetooth, the camera
// and push-to-talk; sliders for the output and the microphone, and for the
// screen; the power profile; and the CPU, memory and temperature (a click
// opens btop), the battery, lock and the power menu. Do Not Disturb is the
// notification centre's.
Column {
	id: root

	signal open(string page)

	readonly property PwNode sink: Pipewire.defaultAudioSink
	readonly property PwNode source: Pipewire.defaultAudioSource
	// The mics are pttd's while push-to-talk is armed
	readonly property bool ptt: Desktop.mic.startsWith("ptt")
	readonly property bool cameraOff: Desktop.webcam === "muted" || Desktop.webcam === "disconnected"

	spacing: 10

	PwObjectTracker {
		objects: [root.sink, root.source]
	}

	Grid {
		width: parent.width
		columns: 2
		spacing: root.spacing

		Tile {
			width: (parent.width - parent.spacing) / 2
			glyph: Net.wired && !Net.current ? Glyphs.ethernet : Net.wifiOn ? Glyphs.wifi : Glyphs.wifiSlash
			title: "Wi-Fi"
			subtitle: Net.current?.name ?? (Net.wired ? "Ethernet" : Net.wifiOn ? "Not connected" : "Off")
			on: Net.wifiOn
			opens: true
			onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
			onOpened: root.open("wifi")
		}

		Tile {
			width: (parent.width - parent.spacing) / 2
			glyph: Net.bluetoothOn ? Glyphs.bluetooth : Glyphs.bluetoothOff
			title: "Bluetooth"
			subtitle: !Net.bluetoothOn ? "Off" : Net.bluetoothConnected.length > 0 ? Net.bluetoothConnected.map(d => d.name).join(", ") : "On"
			on: Net.bluetoothOn
			opens: true
			onToggled: {
				if (Net.adapter)
					Net.adapter.enabled = !Net.adapter.enabled;
			}
			onOpened: root.open("bluetooth")
		}

		Tile {
			width: (parent.width - parent.spacing) / 2
			glyph: root.cameraOff ? Glyphs.videoSlash : Glyphs.video
			title: "Camera"
			subtitle: Desktop.webcam === "in-use" ? "In use" : Desktop.webcam === "disconnected" ? "None connected" : root.cameraOff ? "Off" : "On"
			on: !root.cameraOff
			onToggled: Desktop.launch(["sudo", "/run/current-system/sw/bin/webcam-toggle", "toggle"])
		}

		Tile {
			width: (parent.width - parent.spacing) / 2
			glyph: Glyphs.mic
			title: "Push-to-talk"
			subtitle: Desktop.mic === "ptt-active" ? "Talking" : root.ptt ? "Hold Right Alt" : "Off"
			on: root.ptt
			// Green while Right Alt is held, as the bar's mic gets its dot
			tint: Desktop.mic === "ptt-active" ? Theme.green : Theme.accent
			onToggled: Desktop.launch(["micctl", "ptt"])
		}
	}

	component Card: Rectangle {
		default property alias content: inside.data

		height: inside.implicitHeight + 24
		radius: 16
		color: Theme.alpha(Theme.ink, 0.06)

		Column {
			id: inside

			x: 12
			y: 12
			width: parent.width - 24
			spacing: 12
		}
	}

	Card {
		width: parent.width

		// The output, and which device it is (a click picks another)
		Column {
			width: parent.width
			spacing: 6

			Item {
				width: parent.width
				height: soundLabel.implicitHeight

				BarText {
					id: soundLabel

					text: "Sound"
					color: Theme.inkDim
					font.pixelSize: 12
				}

				BarText {
					anchors.right: parent.right
					width: Math.min(implicitWidth, parent.width - soundLabel.width - 12)
					text: (root.sink?.description || root.sink?.nickname || "No output") + "  ›"
					color: Theme.inkDim
					font.pixelSize: 12
					elide: Text.ElideMiddle

					MouseArea {
						anchors.fill: parent
						onClicked: root.open("sound")
					}
				}
			}

			Slider {
				width: parent.width
				value: root.sink?.audio?.volume ?? 0
				dimmed: root.sink?.audio?.muted ?? false
				onMoved: value => {
					if (root.sink?.audio)
						root.sink.audio.volume = value;
				}
			}
		}

		Column {
			width: parent.width
			spacing: 6

			Item {
				width: parent.width
				height: micLabel.implicitHeight

				BarText {
					id: micLabel

					text: "Microphone"
					color: Theme.inkDim
					font.pixelSize: 12
				}

				BarText {
					anchors.right: parent.right
					text: Desktop.mic === "ptt-active" ? "Talking" : root.ptt ? "Muted until you hold Right Alt" : root.source?.audio?.muted ? "Muted" : ""
					color: Desktop.mic === "ptt-active" ? Theme.inkGreen : Theme.inkDim
					font.pixelSize: 12
				}
			}

			Slider {
				width: parent.width
				value: root.source?.audio?.volume ?? 0
				dimmed: Desktop.mic === "ptt-muted" || Desktop.mic === "muted"
				onMoved: value => {
					if (root.source?.audio)
						root.source.audio.volume = value;
				}
			}
		}
	}

	Card {
		width: parent.width

		Column {
			width: parent.width
			spacing: 6

			BarText {
				text: "Brightness"
				color: Theme.inkDim
				font.pixelSize: 12
			}

			Slider {
				width: parent.width
				value: Metrics.backlight / 100
				onMoved: value => Osd.setBrightness(Math.round(value * 100))
			}
		}
	}

	// The power profile, as a segmented control
	Rectangle {
		width: parent.width
		height: 36
		radius: 12
		color: Theme.alpha(Theme.ink, 0.06)

		Row {
			anchors.fill: parent
			anchors.margins: 3

			Repeater {
				model: [
					{
						"name": "Saver",
						"profile": PowerProfile.PowerSaver
					},
					{
						"name": "Balanced",
						"profile": PowerProfile.Balanced
					},
					{
						"name": "Performance",
						"profile": PowerProfile.Performance
					}
				]

				Rectangle {
					required property var modelData

					readonly property bool chosen: PowerProfiles.profile === modelData.profile

					width: parent.width / 3
					height: parent.height
					radius: 9
					color: chosen ? Theme.ink : "transparent"
					opacity: modelData.profile === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile ? 0.35 : 1

					BarText {
						anchors.centerIn: parent
						text: modelData.name
						color: chosen ? Theme.fg : Theme.ink
						font.pixelSize: 12
						font.weight: chosen ? Font.DemiBold : Font.Medium
					}

					MouseArea {
						anchors.fill: parent
						onClicked: PowerProfiles.profile = modelData.profile
					}
				}
			}
		}
	}

	// The machine's load (a click opens btop) and the battery; lock; the power
	// menu
	Item {
		width: parent.width
		height: Math.max(32, footer.implicitHeight)

		Column {
			id: footer

			anchors.verticalCenter: parent.verticalCenter
			x: 4
			spacing: 4

			BarText {
				text: ["CPU " + Metrics.cpu + "%", "Memory " + Metrics.memory + "%"].concat(Metrics.temperature > 0 ? [Math.round(Metrics.temperature) + "°C"] : []).join(" · ")
				color: loadHover.hovered ? Theme.ink : Theme.inkDim
				font.pixelSize: 12
				font.features: {
					"tnum": 1
				}

				HoverHandler {
					id: loadHover
				}

				TapHandler {
					cursorShape: Qt.PointingHandCursor
					onTapped: Desktop.launch(["system-monitor"])
				}
			}

			BarText {
				visible: text !== ""
				text: {
					const device = UPower.displayDevice;
					if (!device?.isLaptopBattery)
						return "";
					const level = Math.round(device.percentage <= 1 ? device.percentage * 100 : device.percentage);
					return level + "% · " + (UPower.onBattery ? "On battery" : "On power");
				}
				color: Theme.inkDim
				font.pixelSize: 12
			}
		}

		Row {
			anchors.right: parent.right
			anchors.verticalCenter: parent.verticalCenter
			spacing: 4

			Repeater {
				model: [
					{
						"glyph": Glyphs.lock,
						"command": ["loginctl", "lock-session"]
					},
					{
						"glyph": Glyphs.power,
						"command": ["system-menu"]
					}
				]

				Rectangle {
					required property var modelData

					width: 32
					height: 32
					radius: 16
					color: buttonHover.hovered ? Theme.alpha(Theme.ink, 0.12) : "transparent"

					BarText {
						anchors.centerIn: parent
						text: modelData.glyph
						color: Theme.ink
						font.pixelSize: 16
					}

					HoverHandler {
						id: buttonHover
					}

					MouseArea {
						anchors.fill: parent
						onClicked: {
							Desktop.closePanel();
							Desktop.launch(modelData.command);
						}
					}
				}
			}
		}
	}
}
