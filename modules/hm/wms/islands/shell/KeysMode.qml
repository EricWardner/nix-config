import QtQuick

// The keyboard shortcuts: the centre island grown into a sheet of them, in
// the groups hypr/lua/bindings.lua sets them in. Super+/ opens it (or `qs
// ipc -c islands call panel toggle keys`); Esc or a click outside closes
// it. Typing searches it: what doesn't match fades back, so nothing moves,
// and Esc clears the search first. It's written out by hand, so it changes
// with bindings.lua.
IslandMode {
	id: root

	// Three columns of sections: [title, [[keys], what they do, words it's
	// also found by]]
	readonly property var sheet: [
		[
			["Open", [
					[["Super", "Enter"], "Terminal", "ghostty shell console"],
					[["Super", "Space"], "Launcher", "vicinae apps run"],
					[["Super", "E"], "Files", "thunar folder"],
					[["Super", "V"], "Clipboard history", "paste copy"],
					[["Super", "Y"], "YubiKey code", "oath otp 2fa"],
					[["Super", "G"], "Gather", "meeting call office"],
					[["Super", "A"], "Control centre", "wifi bluetooth sound volume battery settings"],
					[["Super", "N"], "Notification centre", "calendar history"],
					[["Super", "/"], "These shortcuts", "help keys"]
				]],
			["Toggle", [
					[["Super", "Shift", "N"], "Do Not Disturb", "dnd quiet notifications"],
					[["Super", "Z"], "Keep Awake", "caffeine sleep idle"],
					[["Super", "M"], "Mute the mic", "microphone"],
					[["Super", "Shift", "M"], "Push-to-talk", "ptt mic microphone"],
					[["Super", "Esc"], "Lock", "screen"]
				]]
		],
		[
			["Windows", [
					[["Super", "H J K L"], "Focus", "arrows"],
					[["Super", "Shift", "H J K L"], "Move, joining groups", "arrows tabs"],
					[["Super", "Ctrl", "H J K L"], "Resize", "arrows"],
					[["Super", "Q"], "Close", "quit kill"],
					[["Super", "F"], "Float"],
					[["F11"], "Fullscreen"],
					[["Super", "Alt", "F"], "Maximise", "maximize"],
					[["Super", "Ctrl", "F"], "Fullscreen in its tile", "fake"],
					[["Super", "S"], "Turn the split", "layout dwindle"],
					[["Super", "P"], "Pseudotile", "layout"],
					[["Super", "Drag"], "Move (right drag: resize)", "mouse"],
					[["Alt", "Tab"], "Cycle windows", "switch"]
				]],
			["Groups", [
					[["Super", "Alt", "G"], "Group or ungroup", "tabs"],
					[["Super", "Alt", "H / L"], "Previous or next tab", "tabs"],
					[["Super", "Alt", "1–5"], "Tab by number", "tabs"]
				]]
		],
		[
			["Workspaces", [
					[["Super", "1–0"], "Go to one"],
					[["Super", "Shift", "1–0"], "Send the window", "move"],
					[["Super", "Tab"], "The last one", "previous back"],
					[["Super", "Ctrl", "Tab"], "Next (Shift: previous)"],
					[["Super", "B / C"], "Browser or chat", "scratchpad special slack"],
					[["Super", "Shift", "B / C"], "Send the window there", "scratchpad special move"],
					[["Super", "Shift", "Alt", "← →"], "To the other monitor", "display screen"]
				]],
			["Capture", [
					[["Print"], "An area", "screenshot"],
					[["Shift", "Print"], "The window", "screenshot"],
					[["Ctrl", "Print"], "The screen", "screenshot"],
					[["Super", "Print"], "Copy text", "ocr screenshot"],
					[["Super", "Shift", "Print"], "Pick a colour", "color eyedropper"],
					[["Super", "R"], "Record, or stop", "video screencast"]
				]]
		]
	]

	// Every word typed is somewhere in the shortcut, its keys or its section
	function matches(section: string, shortcut: var): bool {
		const text = [section, shortcut[1], shortcut[0].join(" "), shortcut[2] ?? ""].join(" ").toLowerCase();
		return search.text.toLowerCase().split(/\s+/).every(word => text.includes(word));
	}

	readonly property bool searching: search.text.trim() !== ""
	readonly property int found: {
		let n = 0;
		if (searching)
			for (const column of sheet)
				for (const section of column)
					n += section[1].filter(shortcut => matches(section[0], shortcut)).length;
		return n;
	}

	priority: 40
	cornerRadius: 24
	islandWidth: 1020
	islandHeight: content.implicitHeight + 40

	focus: current
	// A fresh search each time it opens
	onCurrentChanged: if (current) {
		search.text = "";
		search.forceActiveFocus();
	}
	Keys.onEscapePressed: Desktop.closePanel()

	Column {
		id: content

		x: 20
		y: 20
		width: parent.width - 40
		spacing: 16

		Item {
			width: parent.width
			height: heading.implicitHeight

			Column {
				id: heading

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

			// The search, quiet until typed into
			Row {
				anchors.right: parent.right
				anchors.verticalCenter: heading.verticalCenter
				spacing: 6

				BarText {
					anchors.verticalCenter: parent.verticalCenter
					text: Glyphs.magnifyingGlass
					color: root.searching ? Theme.ink : Theme.alpha(Theme.ink, 0.4)
					font.pixelSize: 13
				}

				Item {
					anchors.verticalCenter: parent.verticalCenter
					width: 200
					height: 20

					TextInput {
						id: search

						anchors.fill: parent
						verticalAlignment: TextInput.AlignVCenter
						color: Theme.ink
						selectionColor: Theme.alpha(Theme.accent, 0.4)
						font.family: Theme.sans
						font.pixelSize: 13
						clip: true
						// Clears the search, then closes
						Keys.onEscapePressed: {
							if (text !== "")
								text = "";
							else
								Desktop.closePanel();
						}
					}

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						visible: search.text === ""
						text: "Type to search"
						color: Theme.alpha(Theme.ink, 0.4)
						font.pixelSize: 13
					}

					BarText {
						anchors.right: parent.right
						anchors.verticalCenter: parent.verticalCenter
						visible: root.searching && root.found === 0
						text: "No match"
						color: Theme.inkDim
						font.pixelSize: 12
					}
				}
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

							// Its title over a hairline, faded with its shortcuts
							Item {
								width: section.width
								height: title.implicitHeight + 9
								opacity: !root.searching || section.modelData[1].some(shortcut => root.matches(section.modelData[0], shortcut)) ? 1 : 0.25

								Behavior on opacity {
									NumberAnimation {
										duration: 120
									}
								}

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
									opacity: !root.searching || root.matches(section.modelData[0], modelData) ? 1 : 0.25

									Behavior on opacity {
										NumberAnimation {
											duration: 120
										}
									}

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
