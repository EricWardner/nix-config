import QtQuick

// The control centre: the status island grown into tiles and sliders (the
// main page), with pages for Wi-Fi, Bluetooth and sound devices that the
// island resizes to. The network, Bluetooth and volume open it on their
// page (or `qs ipc -c islands call panel open control wifi`); Esc goes back
// a page, then closes it, and so does a click outside.
IslandMode {
	id: root

	// Desktop.panelPage alone says which page shows, so the bar's icons
	// (which open their page, or close it if it's showing) see the page
	// moved to in here
	readonly property string page: ["wifi", "bluetooth", "sound"].includes(Desktop.panelPage) ? Desktop.panelPage : "main"
	readonly property Item shown: ({
			"main": main,
			"wifi": wifi,
			"bluetooth": bluetooth,
			"sound": sound
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
			Desktop.closePanel();
		else
			Desktop.panelPage = "";
	}

	ControlMain {
		id: main

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "main"
		onOpen: name => Desktop.panelPage = name
	}

	WifiPage {
		id: wifi

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "wifi"
		onBack: Desktop.panelPage = ""
	}

	BluetoothPage {
		id: bluetooth

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "bluetooth"
		onBack: Desktop.panelPage = ""
	}

	SoundPage {
		id: sound

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "sound"
		onBack: Desktop.panelPage = ""
	}
}
