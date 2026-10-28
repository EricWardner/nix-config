import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// The tray island at rest: the Do Not Disturb moon while it's on, the
// network and Bluetooth (a click on either opens the control centre), then
// the applets' tray icons. A left click activates an applet, a middle click
// its secondary action, a right click opens its menu.
IslandMode {
	id: root

	// The bar's window, which the menus open from
	required property QsWindow window

	signal controlRequested

	// net-panel's and blueman's icons: the control centre does their job
	readonly property var applets: Array.from(SystemTray.items.values).filter(item => !/^(net-panel|blueman)$/.test(item.id))
	// By id: apps register in whatever order they start, so the icons would
	// otherwise move between sessions
	readonly property var sorted: applets.slice().sort((a, b) => a.id.localeCompare(b.id))

	active: true
	resting: true
	cornerRadius: 8
	islandWidth: row.implicitWidth + 14
	islandHeight: Theme.barHeight - 4

	Row {
		id: row

		anchors.centerIn: parent
		// 16px icons 24px apart: the 40px pitch of the status icons beside
		// the island
		spacing: 24

		BarText {
			visible: Inbox.dnd
			text: Glyphs.moonFill
			anchors.verticalCenter: parent.verticalCenter

			MouseArea {
				anchors.fill: parent
				onClicked: Inbox.dnd = false
			}
		}

		// Ethernet while it's connected, else Wi-Fi: its signal, or slashed
		// when off or not connected; amber behind a login page
		BarText {
			anchors.verticalCenter: parent.verticalCenter
			text: Net.wired ? Glyphs.ethernet : Net.current ? Glyphs.wifi : Glyphs.wifiSlash
			color: Net.limited ? Theme.yellow : Net.wired || Net.current ? Theme.fg : Theme.dim

			MouseArea {
				anchors.fill: parent
				onClicked: root.controlRequested()
			}
		}

		BarText {
			visible: Net.adapter !== null
			anchors.verticalCenter: parent.verticalCenter
			text: !Net.bluetoothOn ? Glyphs.bluetoothOff : Net.bluetoothConnected.length > 0 ? Glyphs.bluetoothConnected : Glyphs.bluetooth
			color: Net.bluetoothOn ? Theme.fg : Theme.dim

			MouseArea {
				anchors.fill: parent
				onClicked: root.controlRequested()
			}
		}

		Repeater {
			model: root.sorted

			IconImage {
				id: icon

				required property SystemTrayItem modelData

				implicitSize: 16
				source: modelData.icon
				anchors.verticalCenter: parent.verticalCenter

				MouseArea {
					anchors.fill: parent
					acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
					onClicked: mouse => {
						const item = icon.modelData;
						if (mouse.button === Qt.MiddleButton) {
							item.secondaryActivate();
						} else if (mouse.button === Qt.RightButton || item.onlyMenu) {
							if (item.hasMenu) {
								const at = icon.mapToItem(null, 0, root.height);
								item.display(root.window, at.x, at.y);
							}
						} else {
							item.activate();
						}
					}
					onWheel: wheel => icon.modelData.scroll(wheel.angleDelta.y / 120, false)
				}
			}
		}
	}
}
