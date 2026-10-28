import QtQuick

// The control centre: the tray island grown into tiles and sliders (the
// main page), with pages for Wi-Fi, Bluetooth and sound devices that the
// island resizes to. A click on the network or Bluetooth opens it (or `qs
// ipc -c islands call panel toggle control`); Esc goes back a page, then
// closes it, and so does a click outside.
IslandMode {
	id: root

	property string page: "main"
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
	onCurrentChanged: {
		if (current) {
			page = Desktop.panelPage || "main";
			forceActiveFocus();
		} else {
			page = "main";
		}
	}
	// Asked for a page while already open
	Connections {
		target: Desktop

		function onPanelPageChanged() {
			if (root.current && Desktop.panelPage !== "")
				root.page = Desktop.panelPage;
		}
	}

	Keys.onEscapePressed: {
		if (page === "main")
			Desktop.closePanel();
		else
			page = "main";
	}

	ControlMain {
		id: main

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "main"
		onOpen: name => root.page = name
	}

	WifiPage {
		id: wifi

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "wifi"
		onBack: root.page = "main"
	}

	BluetoothPage {
		id: bluetooth

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "bluetooth"
		onBack: root.page = "main"
	}

	SoundPage {
		id: sound

		x: 14
		y: 14
		width: parent.width - 28
		visible: root.page === "sound"
		onBack: root.page = "main"
	}
}
