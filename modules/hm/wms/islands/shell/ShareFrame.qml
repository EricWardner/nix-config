import QtQuick
import Quickshell
import Quickshell.Wayland

// An orange frame round a screen while it's shared. Hyprland can't keep a
// layer out of a share, so the people watching see it too.
PanelWindow {
	id: root

	required property ShellScreen modelData

	screen: modelData
	visible: Sharing.active && Sharing.kind === "screen" && Sharing.output === modelData.name
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
		anchors.fill: parent
		color: "transparent"
		border.width: 3
		border.color: Theme.orange
	}
}
