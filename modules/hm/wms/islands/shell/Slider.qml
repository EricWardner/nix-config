import QtQuick

// A level from 0 to 1 to drag, click or scroll: `moved` says where to, and
// the owner sets `value` from whatever it controls
Item {
	id: root

	property real value: 0
	// Drawn faint: the level stands but isn't in effect (a muted mic)
	property bool dimmed: false

	signal moved(real value)

	readonly property real shown: Math.max(0, Math.min(1, value))

	implicitHeight: 20

	Rectangle {
		anchors.verticalCenter: parent.verticalCenter
		width: parent.width
		height: 6
		radius: 3
		color: Theme.inkTrack

		Rectangle {
			width: parent.width * root.shown
			height: parent.height
			radius: parent.radius
			color: root.dimmed ? Theme.alpha(Theme.ink, 0.3) : Theme.ink
		}
	}

	Rectangle {
		x: root.shown * (root.width - width)
		anchors.verticalCenter: parent.verticalCenter
		width: 16
		height: 16
		radius: 8
		color: "white"
		border.width: 1
		border.color: Theme.alpha(Theme.ink, 0.15)
	}

	MouseArea {
		anchors.fill: parent

		function report(x: real) {
			root.moved(Math.max(0, Math.min(1, x / width)));
		}

		onPressed: mouse => report(mouse.x)
		onPositionChanged: mouse => {
			if (pressed)
				report(mouse.x);
		}
		// 5% for a notch of the wheel, up for more; a touchpad's finer
		// steps move it in proportion
		onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.shown + wheel.angleDelta.y / 120 * 0.05)))
	}
}
