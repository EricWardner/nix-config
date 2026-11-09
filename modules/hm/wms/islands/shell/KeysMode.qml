import QtQuick

// The keyboard shortcuts: the centre island grown into a sheet of them, in
// the groups hypr/lua/bindings.lua sets them in. Super+/ opens it (or `qs
// ipc -c islands call panel toggle keys`); Esc or a click outside closes
// it. It's written out by hand, so it changes with bindings.lua.
IslandMode {
	id: root

	// Three columns of sections: [title, [[keys], what they do]]
	readonly property var sheet: [
		[
			["Open", [
					[["Super", "Enter"], "Terminal"],
					[["Super", "Space"], "Launcher"],
					[["Super", "E"], "Files"],
					[["Super", "V"], "Clipboard history"],
					[["Super", "Y"], "YubiKey code"],
					[["Super", "G"], "Gather"],
					[["Super", "A"], "Control centre"],
					[["Super", "N"], "Notification centre"],
					[["Super", "/"], "These shortcuts"]
				]],
			["Toggle", [
					[["Super", "Shift", "N"], "Do Not Disturb"],
					[["Super", "Z"], "Keep Awake"],
					[["Super", "M"], "Mute the mic"],
					[["Super", "Shift", "M"], "Push-to-talk"],
					[["Super", "Esc"], "Lock"]
				]]
		],
		[
			["Windows", [
					[["Super", "H J K L"], "Focus"],
					[["Super", "Shift", "H J K L"], "Move, joining groups"],
					[["Super", "Ctrl", "H J K L"], "Resize"],
					[["Super", "Q"], "Close"],
					[["Super", "F"], "Float"],
					[["F11"], "Fullscreen"],
					[["Super", "Alt", "F"], "Maximise"],
					[["Super", "Ctrl", "F"], "Fullscreen in its tile"],
					[["Super", "S"], "Turn the split"],
					[["Super", "P"], "Pseudotile"],
					[["Super", "Drag"], "Move (right drag: resize)"],
					[["Alt", "Tab"], "Cycle windows"]
				]],
			["Groups", [
					[["Super", "Alt", "G"], "Group or ungroup"],
					[["Super", "Alt", "H / L"], "Previous or next tab"],
					[["Super", "Alt", "1–5"], "Tab by number"]
				]]
		],
		[
			["Workspaces", [
					[["Super", "1–0"], "Go to one"],
					[["Super", "Shift", "1–0"], "Send the window"],
					[["Super", "Tab"], "The last one"],
					[["Super", "Ctrl", "Tab"], "Next (Shift: previous)"],
					[["Super", "B / C"], "Browser or chat"],
					[["Super", "Shift", "B / C"], "Send the window there"],
					[["Super", "Shift", "Alt", "← →"], "To the other monitor"]
				]],
			["Capture", [
					[["Print"], "An area"],
					[["Shift", "Print"], "The window"],
					[["Ctrl", "Print"], "The screen"],
					[["Super", "Print"], "Copy text"],
					[["Super", "Shift", "Print"], "Pick a colour"],
					[["Super", "R"], "Record, or stop"]
				]]
		]
	]

	priority: 40
	cornerRadius: 24
	islandWidth: 1020
	islandHeight: content.implicitHeight + 40

	focus: current
	onCurrentChanged: if (current)
		forceActiveFocus()
	Keys.onEscapePressed: Desktop.closePanel()

	Column {
		id: content

		x: 20
		y: 20
		width: parent.width - 40
		spacing: 16

		Column {
			spacing: 2

			BarText {
				text: "Keyboard shortcuts"
				color: Theme.ink
				font.pixelSize: 16
				font.weight: Font.DemiBold
			}

			BarText {
				text: "Shift moves the window · Ctrl resizes · Alt is groups · the arrows work like H J K L"
				color: Theme.inkDim
				font.pixelSize: 12
			}
		}

		Row {
			spacing: 28

			Repeater {
				model: root.sheet

				Column {
					id: column

					required property var modelData

					width: (content.width - 2 * 28) / 3
					spacing: 14

					Repeater {
						model: column.modelData

						Column {
							id: section

							required property var modelData

							width: column.width

							// Its title over a hairline
							Item {
								width: section.width
								height: title.implicitHeight + 9

								BarText {
									id: title

									text: section.modelData[0]
									color: Theme.ink
									font.pixelSize: 13
									font.weight: Font.Bold
								}

								Rectangle {
									anchors.bottom: parent.bottom
									anchors.bottomMargin: 4
									width: parent.width
									height: 1
									color: Theme.alpha(Theme.ink, 0.15)
								}
							}

							Repeater {
								model: section.modelData[1]

								// What it does, and its keys as keycaps
								Item {
									id: shortcut

									required property var modelData

									width: section.width
									height: 24

									BarText {
										anchors.left: parent.left
										anchors.right: keys.left
										anchors.rightMargin: 8
										anchors.verticalCenter: parent.verticalCenter
										text: shortcut.modelData[1]
										color: Theme.ink
										font.pixelSize: 13
										elide: Text.ElideRight
									}

									Row {
										id: keys

										anchors.right: parent.right
										anchors.verticalCenter: parent.verticalCenter
										spacing: 3

										Repeater {
											model: shortcut.modelData[0]

											Rectangle {
												required property string modelData

												width: Math.max(20, cap.implicitWidth + 10)
												height: 20
												radius: 5
												color: Theme.alpha(Theme.ink, 0.08)

												BarText {
													id: cap

													anchors.centerIn: parent
													text: parent.modelData
													color: Theme.ink
													font.pixelSize: 11
													font.weight: Font.DemiBold
												}
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
