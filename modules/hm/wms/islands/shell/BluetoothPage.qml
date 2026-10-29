import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth: on or off, your devices (a click connects or disconnects one,
// and shows its battery where it reports one), and others nearby to pair,
// found while the page shows.
Column {
	id: root

	signal back

	readonly property var mine: Net.bluetoothDevices.filter(d => d.paired || d.bonded).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
	// Only those that give a name: the rest are mostly beacons, which BlueZ
	// names after their address
	readonly property var nearby: Net.bluetoothDevices.filter(d => !d.paired && !d.bonded && d.deviceName !== "")

	function battery(device: var): string {
		if (!device.batteryAvailable)
			return "";
		return Math.round(device.battery <= 1 ? device.battery * 100 : device.battery) + "%";
	}

	function iconFor(device: var): string {
		return device.icon ? Quickshell.iconPath(device.icon, true) : "";
	}

	spacing: 10

	Binding {
		when: Net.adapter !== null
		target: Net.adapter
		property: "discovering"
		value: root.visible && Net.bluetoothOn
	}

	PageHeader {
		width: parent.width
		title: "Bluetooth"
		hasSwitch: Net.adapter !== null
		on: Net.bluetoothOn
		onBack: root.back()
		onToggled: Net.adapter.enabled = !Net.adapter.enabled
	}

	BarText {
		visible: Net.bluetoothOn && root.mine.length > 0
		x: 4
		text: "My devices"
		color: Theme.inkDim
		font.pixelSize: 12
		font.weight: Font.DemiBold
	}

	Repeater {
		model: Net.bluetoothOn ? root.mine : []

		ListRow {
			required property var modelData

			width: root.width
			glyph: Glyphs.bluetooth
			image: root.iconFor(modelData)
			title: modelData.name
			subtitle: modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : modelData.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…" : modelData.connected ? ["Connected", root.battery(modelData)].filter(s => s).join(" · ") : "Not connected"
			chosen: modelData.connected
			onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
		}
	}

	Row {
		visible: Net.bluetoothOn
		x: 4
		spacing: 8

		BarText {
			text: "Nearby"
			color: Theme.inkDim
			font.pixelSize: 12
			font.weight: Font.DemiBold
		}

		Searching {
			anchors.verticalCenter: parent.verticalCenter
			running: Net.adapter?.discovering ?? false
		}
	}

	ListView {
		visible: Net.bluetoothOn
		width: parent.width
		height: Math.min(contentHeight, 180)
		clip: true
		spacing: 2
		boundsBehavior: Flickable.StopAtBounds
		model: root.nearby

		delegate: ListRow {
			required property var modelData

			width: ListView.view.width
			glyph: Glyphs.bluetooth
			image: root.iconFor(modelData)
			title: modelData.name
			subtitle: modelData.pairing ? "Pairing…" : ""
			trailing: modelData.pairing ? "" : "Pair"
			onClicked: {
				if (modelData.pairing)
					modelData.cancelPair();
				else
					modelData.pair();
			}
		}
	}

	ListRow {
		width: parent.width
		glyph: "⚙"
		title: "Bluetooth settings…"
		onClicked: {
			Desktop.closePanel();
			Desktop.launch(["blueman-manager"]);
		}
	}
}
