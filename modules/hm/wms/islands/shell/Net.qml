pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking

// Network and Bluetooth state for the status island and the control centre,
// from Quickshell's NetworkManager and BlueZ services
Singleton {
	id: root

	readonly property var devices: Array.from(Networking.devices.values)
	readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi) ?? null
	readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
	readonly property var networks: wifi ? Array.from(wifi.networks.values) : []
	// The Wi-Fi network in use, if any
	readonly property var current: networks.find(n => n.connected) ?? null
	readonly property bool wifiOn: Networking.wifiEnabled
	// Online, but behind a login page or without a way out
	readonly property bool limited: Networking.connectivity === NetworkConnectivity.Portal || Networking.connectivity === NetworkConnectivity.Limited

	readonly property var adapter: Bluetooth.defaultAdapter
	readonly property bool bluetoothOn: adapter?.enabled ?? false
	readonly property var bluetoothDevices: adapter ? Array.from(adapter.devices.values) : []
	readonly property var bluetoothConnected: bluetoothDevices.filter(d => d.connected)

	// 0 to 1
	function strength(network: var): real {
		return network?.signalStrength ?? 0;
	}

	function strengthGlyph(network: var): string {
		return Glyphs.wifiStrength[Math.min(3, Math.floor(strength(network) * 4))];
	}

	function secured(network: var): bool {
		return network?.security !== WifiSecurityType.Open && network?.security !== WifiSecurityType.Owe;
	}

	// Takes a password (WPA/WPA2/WPA3 personal), which the network list can
	// ask for; enterprise networks need nm-connection-editor
	function takesPassword(network: var): bool {
		return [WifiSecurityType.Wpa2Psk, WifiSecurityType.WpaPsk, WifiSecurityType.Sae].includes(network?.security);
	}
}
