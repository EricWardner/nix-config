import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// The tray island: the applets' tray icons. A left click activates an
// applet, a middle click its secondary action, a right click opens its menu.
IslandMode {
	id: root

	// The bar's window, which the menus open from
	required property QsWindow window

	// By id: apps register in whatever order they start, so the icons would
	// otherwise move between sessions
	readonly property var sorted: Array.from(SystemTray.items.values).sort((a, b) => a.id.localeCompare(b.id))

	active: true
	resting: true
	cornerRadius: 8
	islandWidth: row.implicitWidth + 14
	islandHeight: Theme.barHeight - 4

	Row {
		id: row

		anchors.centerIn: parent
		// 16px icons 14px apart: the status island's 30px pitch
		spacing: 14

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
