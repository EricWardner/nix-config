import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// An orange frame round what's shared on this monitor: the whole screen,
// or the shared window while its workspace shows here, over the window's
// own border. Hyprland can't keep a layer out of a screen share, so the
// people watching see a screen's frame too; a window share is only the
// window.
PanelWindow {
	id: root

	required property ShellScreen modelData
	readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
	readonly property bool wholeScreen: Sharing.kind === "screen" && Sharing.output === modelData.name
	// The shared window's box here, in this monitor's logical pixels
	readonly property var windowBox: {
		const window = Sharing.kind === "window" ? Sharing.window : null;
		const ipc = window?.lastIpcObject;
		if (!ipc?.at || ipc.hidden || window.monitor !== monitor)
			return null;
		const name = window.workspace?.name ?? "";
		const shown = window.workspace === monitor.activeWorkspace || (name.startsWith("special:") && monitor.lastIpcObject?.specialWorkspace?.name === name);
		return shown ? Qt.rect(ipc.at[0] - monitor.x, ipc.at[1] - monitor.y, ipc.size[0], ipc.size[1]) : null;
	}

	screen: modelData
	visible: Sharing.active && (wholeScreen || windowBox !== null)
	anchors.top: true
	anchors.bottom: true
	anchors.left: true
	anchors.right: true
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"
	mask: Region {}
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "islands-share-frame"

	Rectangle {
		visible: root.wholeScreen
		anchors.fill: parent
		color: "transparent"
		border.width: 3
		border.color: Theme.orange
	}

	Rectangle {
		readonly property rect box: root.windowBox ?? Qt.rect(0, 0, 0, 0)
		readonly property int outset: Sharing.windowBorder + 1

		visible: !root.wholeScreen && root.windowBox !== null
		x: Math.max(0, box.x - outset)
		y: Math.max(0, box.y - outset)
		width: Math.min(root.width, box.x + box.width + outset) - x
		height: Math.min(root.height, box.y + box.height + outset) - y
		radius: Sharing.windowRounding + outset
		color: "transparent"
		border.width: outset
		border.color: Theme.orange
	}
}
