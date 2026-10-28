import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// The applets (net-panel, blueman, Slack…) on the light-glass island, led
// by the Do Not Disturb moon while it's on. A left click activates an
// applet, a middle click its secondary action, a right click opens its
// menu; a click on the moon turns Do Not Disturb off.
Rectangle {
	id: root

	// The bar's window, which the menus open from
	required property QsWindow window

	visible: SystemTray.items.values.length > 0 || Desktop.dnd
	implicitWidth: row.implicitWidth + 14
	implicitHeight: Theme.barHeight - 4
	radius: 8
	color: Theme.islandFill
	border.width: 1
	border.color: Theme.islandRim

	Row {
		id: row

		anchors.centerIn: parent
		// 16px icons 24px apart: the 40px pitch of the status icons beside
		// the island
		spacing: 24

		BarText {
			visible: Desktop.dnd
			text: Glyphs.moonFill
			anchors.verticalCenter: parent.verticalCenter

			MouseArea {
				anchors.fill: parent
				onClicked: Desktop.launch(["mako-dnd", "off"])
			}
		}

		Repeater {
			// By id: apps register in whatever order they start, so the
			// icons would otherwise move between sessions
			model: SystemTray.items.values.slice().sort((a, b) => a.id.localeCompare(b.id))

			IconImage {
				id: icon

				required property SystemTrayItem modelData

				implicitSize: 16
				source: modelData.icon

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
