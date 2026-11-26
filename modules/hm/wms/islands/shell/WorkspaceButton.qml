import QtQuick
import Quickshell.Hyprland

// A workspace: its name and an icon per window. The one showing on this
// monitor is underlined, brightly while the monitor has focus; one without
// windows is dimmed. A click switches to it (activate() sends Lua's
// hl.dsp.focus in a Lua-config session), or toggles a special one.
Item {
	id: root

	required property HyprlandWorkspace modelData
	required property HyprlandMonitor monitor

	// A special workspace shows over the monitor's active one
	readonly property bool shown: modelData.id < 0 ? monitor?.lastIpcObject?.specialWorkspace?.name === modelData.name : monitor?.activeWorkspace === modelData

	readonly property string name: modelData.name.replace(/^special:/, "")
	readonly property var windows: modelData.toplevels.values
	readonly property var icons: windows.map(w => Glyphs.app(w.wayland?.appId ?? w.lastIpcObject?.class ?? "")).filter(icon => icon !== null)

	// How much it shows, as the bar has room (Bar): 0 an icon per window,
	// 1 one per app, 2 the name alone
	property int level: 0
	// Its width at each level, for the bar to choose by
	readonly property var widths: {
		let all = 0;
		let apps = 0;
		for (let i = 0; i < iconRepeater.count; i++) {
			const icon = iconRepeater.itemAt(i);
			if (!icon)
				continue;
			all += label.spacing + icon.implicitWidth;
			if (icon.firstOfApp)
				apps += label.spacing + icon.implicitWidth;
		}
		const name = nameText.implicitWidth + 14;
		return [name + all, name + apps, name];
	}

	function key(icon: var): string {
		return (icon.glyph ?? "") + "|" + (icon.logo ?? "");
	}

	implicitWidth: widths[level]
	implicitHeight: Theme.barHeight
	opacity: windows.length === 0 ? 0.5 : 1

	Row {
		id: label

		anchors.centerIn: parent
		anchors.horizontalCenterOffset: 1
		// An en between the name and each icon: the icons have no side
		// bearings
		spacing: Theme.fontSize / 2

		// Bold, as waybar's workspace buttons were
		BarText {
			id: nameText

			text: root.name
			font.weight: Font.Bold
		}

		Repeater {
			id: iconRepeater

			model: root.icons

			AppIcon {
				required property var modelData
				required property int index
				readonly property bool firstOfApp: root.icons.findIndex(icon => root.key(icon) === root.key(modelData)) === index

				visible: root.level === 0 || (root.level === 1 && firstOfApp)
				glyph: modelData.glyph ?? ""
				logo: modelData.logo ?? ""
			}
		}
	}

	Rectangle {
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		height: 3
		color: !root.shown ? "transparent" : root.monitor.focused ? Theme.fg : Theme.alpha(Theme.fg, 0.35)
	}

	MouseArea {
		anchors.fill: parent
		onClicked: root.modelData.id < 0 ? Hyprland.dispatch(`hl.dsp.workspace.toggle_special("${root.name}")`) : root.modelData.activate()
	}
}
