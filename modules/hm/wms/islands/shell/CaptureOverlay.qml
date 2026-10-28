import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The capture overlay on one monitor: its screen frozen as it was when
// capture began, dimmed outside the selection. Drag for an area; click a
// window to take it whole (snapped to its edges); with Screen chosen, click
// anywhere. The colour picker shows a magnifier at the pointer. The toolbar,
// on the focused monitor, is the centre island grown. Esc cancels, Enter
// takes the selection (or the screen), Space steps through area, window and
// screen.
PanelWindow {
	id: root

	required property ShellScreen modelData
	readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
	readonly property bool focused: Hyprland.focusedMonitor === monitor
	readonly property string frozen: "file://" + Capture.frozenFile(modelData.name)

	// The selection, in this monitor's logical pixels
	property rect selection: Qt.rect(0, 0, 0, 0)
	readonly property bool selected: selection.width > 0 && selection.height > 0
	property bool dragging: false
	property point pressedAt
	property point pointer: Qt.point(-100, -100)
	// The window under the pointer, outlined while nothing is dragged
	property var hovered: null

	// This monitor's windows on show, topmost first: those on a special
	// workspace over it, then floating ones, then the last focused
	readonly property var windows: {
		const m = monitor;
		if (!m)
			return [];
		const active = m.activeWorkspace?.id;
		const special = m.lastIpcObject?.specialWorkspace?.id ?? 0;
		return Array.from(Hyprland.toplevels.values).map(t => t.lastIpcObject).filter(c => c?.at && !c.hidden && (c.workspace?.id === active || (special !== 0 && c.workspace?.id === special))).sort((a, b) => ((b.workspace?.id === special) - (a.workspace?.id === special)) || (b.floating - a.floating) || (a.focusHistoryID - b.focusHistoryID)).map(c => ({
					"x": c.at[0] - m.x,
					"y": c.at[1] - m.y,
					"width": c.size[0],
					"height": c.size[1],
					"stableId": c.stableId
				}));
	}

	function windowAt(point: point): var {
		return windows.find(w => point.x >= w.x && point.x < w.x + w.width && point.y >= w.y && point.y < w.y + w.height) ?? null;
	}

	function whole(): rect {
		return Qt.rect(0, 0, width, height);
	}

	function take(area: rect, window: var) {
		Capture.take(monitor, modelData, area, window);
	}

	// A click without a drag
	function clicked(point: point) {
		if (Capture.kind === "colour") {
			take(Qt.rect(point.x, point.y, 1, 1), null);
		} else if (Capture.target === "screen") {
			take(whole(), null);
		} else {
			const window = windowAt(point);
			if (window)
				take(Qt.rect(window.x, window.y, window.width, window.height), window);
		}
	}

	screen: modelData
	anchors.top: true
	anchors.bottom: true
	anchors.left: true
	anchors.right: true
	exclusionMode: ExclusionMode.Ignore
	color: "black"
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "islands-capture"
	WlrLayershell.keyboardFocus: focused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

	Image {
		id: frozenImage

		anchors.fill: parent
		source: root.frozen
		cache: false
		smooth: true
	}

	// Dimmed outside what would be taken: the selection, else the window
	// under the pointer, else (choosing the screen) nothing
	Item {
		id: shade

		readonly property rect hole: {
			if (root.selected)
				return root.selection;
			if (Capture.target === "screen" && Capture.kind !== "colour")
				return root.whole();
			if (root.hovered && Capture.kind !== "colour")
				return Qt.rect(root.hovered.x, root.hovered.y, root.hovered.width, root.hovered.height);
			return Qt.rect(0, 0, 0, 0);
		}
		readonly property color dim: Qt.rgba(0.02, 0.03, 0.06, 0.5)

		anchors.fill: parent

		Rectangle {
			width: parent.width
			height: shade.hole.y
			color: shade.dim
		}
		Rectangle {
			y: shade.hole.y + shade.hole.height
			width: parent.width
			height: parent.height - y
			color: shade.dim
		}
		Rectangle {
			y: shade.hole.y
			width: shade.hole.x
			height: shade.hole.height
			color: shade.dim
		}
		Rectangle {
			x: shade.hole.x + shade.hole.width
			y: shade.hole.y
			width: parent.width - x
			height: shade.hole.height
			color: shade.dim
		}

		Rectangle {
			visible: shade.hole.width > 0 && shade.hole.width < root.width
			x: shade.hole.x - 1
			y: shade.hole.y - 1
			width: shade.hole.width + 2
			height: shade.hole.height + 2
			color: "transparent"
			border.width: 1
			border.color: "white"
		}
	}

	// The selection's size, under it
	Rectangle {
		visible: root.selected
		x: Math.min(root.width - width - 8, Math.max(8, root.selection.x + root.selection.width / 2 - width / 2))
		y: Math.min(root.height - height - 8, root.selection.y + root.selection.height + 10)
		width: sizeText.implicitWidth + 24
		height: 26
		radius: 13
		color: Qt.rgba(0.13, 0.13, 0.13, 0.85)

		BarText {
			id: sizeText

			anchors.centerIn: parent
			text: Math.round(root.selection.width) + " × " + Math.round(root.selection.height)
			font.pixelSize: 13
			font.weight: Font.DemiBold
			font.features: {
				"tnum": 1
			}
		}
	}

	// The colour picker's magnifier: the frozen screen, 8x, round the pointer
	Rectangle {
		readonly property int zoom: 8

		visible: Capture.kind === "colour" && root.pointer.x >= 0
		x: Math.min(root.width - width - 8, root.pointer.x + 24)
		y: Math.min(root.height - height - 8, root.pointer.y + 24)
		width: 132
		height: 132
		radius: 66
		clip: true
		color: "black"
		border.width: 2
		border.color: "white"

		Image {
			x: parent.width / 2 - root.pointer.x * parent.zoom
			y: parent.height / 2 - root.pointer.y * parent.zoom
			width: root.width * parent.zoom
			height: root.height * parent.zoom
			source: root.frozen
			cache: false
			smooth: false
		}

		// The pixel that will be picked
		Rectangle {
			anchors.centerIn: parent
			width: parent.zoom + 2
			height: parent.zoom + 2
			color: "transparent"
			border.width: 1
			border.color: "white"
		}
	}

	MouseArea {
		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.CrossCursor
		onPressed: mouse => {
			root.pressedAt = Qt.point(mouse.x, mouse.y);
			root.dragging = false;
		}
		onPositionChanged: mouse => {
			root.pointer = Qt.point(mouse.x, mouse.y);
			if (pressed && Capture.kind !== "colour" && Capture.target !== "screen") {
				const dx = mouse.x - root.pressedAt.x;
				const dy = mouse.y - root.pressedAt.y;
				if (!root.dragging && Math.hypot(dx, dy) > 4)
					root.dragging = true;
				if (root.dragging) {
					const x = Math.max(0, Math.min(mouse.x, root.pressedAt.x));
					const y = Math.max(0, Math.min(mouse.y, root.pressedAt.y));
					root.selection = Qt.rect(x, y, Math.min(root.width, Math.max(mouse.x, root.pressedAt.x)) - x, Math.min(root.height, Math.max(mouse.y, root.pressedAt.y)) - y);
				}
			} else if (!pressed) {
				root.hovered = Capture.target === "screen" ? null : root.windowAt(root.pointer);
			}
		}
		onReleased: mouse => {
			if (root.dragging) {
				root.dragging = false;
				if (root.selection.width >= 4 && root.selection.height >= 4)
					root.take(root.selection, null);
				else
					root.selection = Qt.rect(0, 0, 0, 0);
			} else {
				root.clicked(Qt.point(mouse.x, mouse.y));
			}
		}
	}

	CaptureToolbar {
		visible: root.focused
		backdrop: frozenImage
		anchors.horizontalCenter: parent.horizontalCenter
		y: Theme.barTop + 2
		onTakeScreen: root.take(root.whole(), null)
	}

	Item {
		focus: true
		Keys.onEscapePressed: Capture.cancel()
		Keys.onReturnPressed: {
			if (root.selected)
				root.take(root.selection, null);
			else if (Capture.target === "screen")
				root.take(root.whole(), null);
		}
		Keys.onSpacePressed: {
			if (Capture.kind === "colour" || Capture.kind === "text")
				return;
			const targets = ["area", "window", "screen"];
			Capture.target = targets[(targets.indexOf(Capture.target) + 1) % targets.length];
			root.selection = Qt.rect(0, 0, 0, 0);
		}
	}
}
