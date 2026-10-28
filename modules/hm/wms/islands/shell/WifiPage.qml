import QtQuick
import Quickshell.Networking

// Wi-Fi: on or off, the network in use, and the others in range (known
// ones first, then the strongest). A click joins a network; one that needs
// a password it doesn't have asks for it in its row first, and asks again
// if it was wrong. It scans while it shows.
Column {
	id: root

	signal back

	// The network whose row is asking for a password, and what went wrong
	property var asking: null
	property string error: ""

	readonly property var others: Net.networks.filter(n => !n.connected).sort((a, b) => (b.known - a.known) || (Net.strength(b) - Net.strength(a)))

	function join(network: var) {
		error = "";
		if (Net.takesPassword(network) && !network.known)
			asking = network;
		else
			network.connect();
	}

	spacing: 10
	onVisibleChanged: {
		if (!visible) {
			asking = null;
			error = "";
		}
	}

	Binding {
		when: Net.wifi !== null
		target: Net.wifi
		property: "scannerEnabled"
		value: root.visible && Net.wifiOn
	}

	PageHeader {
		width: parent.width
		title: "Wi-Fi"
		hasSwitch: true
		on: Net.wifiOn
		onBack: root.back()
		onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
	}

	// The network in use
	Rectangle {
		visible: Net.current !== null
		width: parent.width
		height: 52
		radius: 16
		color: Theme.alpha(Theme.ink, 0.06)

		Rectangle {
			id: badge

			x: 10
			anchors.verticalCenter: parent.verticalCenter
			width: 32
			height: 32
			radius: 16
			color: Theme.accent

			BarText {
				anchors.centerIn: parent
				text: Glyphs.wifi
				color: Theme.ink
				font.pixelSize: 15
			}
		}

		Column {
			anchors.left: badge.right
			anchors.leftMargin: 10
			anchors.right: disconnect.left
			anchors.rightMargin: 8
			anchors.verticalCenter: parent.verticalCenter

			BarText {
				width: parent.width
				text: Net.current?.name ?? ""
				color: Theme.ink
				font.pixelSize: 13
				font.weight: Font.DemiBold
				elide: Text.ElideRight
			}

			BarText {
				text: Net.limited ? "Connected · No internet" : "Connected"
				color: Net.limited ? Theme.alpha(Theme.ink, 0.9) : Theme.inkDim
				font.pixelSize: 12
			}
		}

		Rectangle {
			id: disconnect

			anchors.right: parent.right
			anchors.rightMargin: 10
			anchors.verticalCenter: parent.verticalCenter
			width: disconnectText.implicitWidth + 20
			height: 26
			radius: 13
			color: disconnectHover.hovered ? Theme.inkTrack : "transparent"
			border.width: 1
			border.color: Theme.alpha(Theme.ink, 0.18)

			BarText {
				id: disconnectText

				anchors.centerIn: parent
				text: "Disconnect"
				color: Theme.ink
				font.pixelSize: 12
			}

			HoverHandler {
				id: disconnectHover
			}

			MouseArea {
				anchors.fill: parent
				onClicked: Net.current?.disconnect()
			}
		}
	}

	Row {
		visible: Net.wifiOn
		x: 4
		spacing: 8

		BarText {
			text: "Other networks"
			color: Theme.inkDim
			font.pixelSize: 12
			font.weight: Font.DemiBold
		}

		Searching {
			anchors.verticalCenter: parent.verticalCenter
			running: Net.wifi?.scannerEnabled ?? false
		}
	}

	ListView {
		id: list

		visible: Net.wifiOn
		width: parent.width
		height: Math.min(contentHeight, 250)
		clip: true
		spacing: 2
		boundsBehavior: Flickable.StopAtBounds
		model: root.others

		delegate: Column {
			id: entry

			required property var modelData
			readonly property bool askingHere: root.asking === modelData

			width: ListView.view.width
			spacing: 6

			Connections {
				target: entry.modelData

				function onConnectionFailed(reason) {
					if (reason === ConnectionFailReason.NoSecrets && Net.takesPassword(entry.modelData)) {
						root.asking = entry.modelData;
						root.error = entry.modelData.known ? "The saved password didn't work." : "";
					} else {
						root.error = "Couldn't join " + entry.modelData.name + ".";
					}
				}
			}

			ListRow {
				width: parent.width
				glyph: Net.strengthGlyph(entry.modelData)
				title: entry.modelData.name
				subtitle: entry.modelData.stateChanging ? "Connecting…" : entry.modelData.known ? "Saved" : ""
				trailing: Net.secured(entry.modelData) ? Glyphs.lock : ""
				chosen: entry.askingHere
				onClicked: root.join(entry.modelData)
			}

			// Its password, asked for in place
			Rectangle {
				visible: entry.askingHere
				width: parent.width
				height: passwordColumn.implicitHeight + 20
				radius: 12
				color: Theme.alpha(Theme.ink, 0.06)

				function join() {
					if (password.text.length < 8)
						return;
					root.error = "";
					entry.modelData.connectWithPsk(password.text);
					password.text = "";
					root.asking = null;
				}

				onVisibleChanged: if (visible)
					password.focusField()

				Column {
					id: passwordColumn

					x: 10
					y: 10
					width: parent.width - 20
					spacing: 8

					BarText {
						text: root.error || "Password for " + entry.modelData.name
						color: Theme.inkDim
						font.pixelSize: 12
					}

					Field {
						id: password

						width: parent.width
						password: true
						placeholder: "Password"
						onAccepted: parent.parent.join()
						Keys.onEscapePressed: root.asking = null
					}

					Row {
						anchors.right: parent.right
						spacing: 6

						PillButton {
							text: "Cancel"
							onClicked: root.asking = null
						}

						PillButton {
							primary: true
							text: "Join"
							enabled: password.text.length >= 8
							onClicked: passwordColumn.parent.join()
						}
					}
				}
			}
		}
	}

	BarText {
		visible: root.error !== "" && root.asking === null
		x: 4
		text: root.error
		color: Theme.inkDim
		font.pixelSize: 12
	}

	ListRow {
		width: parent.width
		glyph: "⚙"
		title: "Network settings…"
		onClicked: {
			Desktop.closePanel();
			Desktop.launch(["nm-connection-editor"]);
		}
	}
}
