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
	islandWidth: row.implicitWidth + 20
	islandHeight: Theme.barHeight - 4

	Row {
		id: row

		anchors.centerIn: parent
		// 16px icons 20px apart: the status island's 36px pitch
		spacing: 20

		Repeater {
			model: root.sorted

			Item {
				id: icon

				required property SystemTrayItem modelData
				// Tether's, the linked iPhone: a phone in the bar's own glyphs
				// for its logo. Tether says how things are by its icon's name,
				// so the phone is dim while the iPhone is away and has a dot
				// while there are messages unread.
				readonly property bool phone: modelData.id === "tether"
				readonly property string named: String(modelData.icon)

				implicitWidth: 16
				implicitHeight: 16
				anchors.verticalCenter: parent.verticalCenter

				IconImage {
					anchors.fill: parent
					visible: !icon.phone
					implicitSize: 16
					source: icon.phone ? "" : icon.modelData.icon
				}

				BarText {
					anchors.centerIn: parent
					visible: icon.phone
					text: Glyphs.iphone
					opacity: icon.named.includes("tether-offline") ? 0.4 : 1
				}

				Rectangle {
					visible: icon.phone && icon.named.includes("tether-unread")
					x: parent.width - 4
					y: -2
					width: 7
					height: 7
					radius: 3.5
					color: Theme.accent
				}

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
