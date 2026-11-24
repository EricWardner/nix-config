import QtQuick

// The control centre: the status island grown into tiles and sliders (the
// main page), with pages for Wi-Fi, Bluetooth, sound devices, the battery
// and power that the island resizes to. The network, Bluetooth, volume and
// battery open it on their page (or `qs ipc -c islands call panel open
// control wifi`); Esc goes back a page, then closes it, and so does a click
// outside.
IslandMode {
	id: root

	// Panels.page alone says which page shows, so the bar's icons
	// (which open their page, or close it if it's showing) see the page
	// moved to in here
	readonly property string page: ["wifi", "bluetooth", "sound", "battery", "power"].includes(Panels.page) ? Panels.page : "main"
	readonly property Item shown: ({
			"main": main,
			"wifi": wifi,
			"bluetooth": bluetooth,
			"sound": sound,
			"battery": battery,
			"power": power
		})[page]

	priority: 40
	cornerRadius: 24
	islandWidth: 372
	islandHeight: shown.implicitHeight + 28

	focus: current
	onCurrentChanged: if (current)
		forceActiveFocus()

	Keys.onEscapePressed: {
		if (page === "main")
			Panels.close();
		else
			Panels.page = "";
	}

	ControlMain {
		id: main

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "main"
		onOpen: name => Panels.page = name
	}

	WifiPage {
		id: wifi

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "wifi"
		onBack: Panels.page = ""
	}

	BluetoothPage {
		id: bluetooth

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "bluetooth"
		onBack: Panels.page = ""
	}

	SoundPage {
		id: sound

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "sound"
		onBack: Panels.page = ""
	}

	BatteryPage {
		id: battery

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "battery"
		showing: root.active && root.page === "battery"
		onBack: Panels.page = ""
	}

	PowerPage {
		id: power

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "power"
		onBack: Panels.page = ""
	}
}
