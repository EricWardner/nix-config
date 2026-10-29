import QtQuick

// A status icon on the bare bar: an SF Symbol, then an optional number in
// the smaller size. It's as wide as its glyph's ink, so the row's spacing is
// the gap the eye sees between icons of any width. A state is shown by
// colouring the icon (and number), never by a box behind it; `live` adds
// the 6px green dot at the top right, which takes no room, so nothing
// shifts.
Item {
	id: root

	property string glyph
	property int glyphSize: Theme.fontSize
	property string value: ""
	property color tint: Theme.fg
	property bool live: false
	// The gap between the ink and the dot (the camera's must clear its lens)
	property real dotShift: 1
	// Every glyph it can show: it keeps the room of the widest, so nothing
	// beside it moves as it changes
	property var glyphs: [glyph]
	// Each glyph starting where the widest starts, rather than centred (the
	// volume's speaker stays put as its waves come and go)
	property bool fromLeft: false

	readonly property rect ink: metrics.tightBoundingRect(glyph)
	readonly property real room: Math.max(...glyphs.map(g => metrics.tightBoundingRect(g).width))

	signal clicked(var mouse)
	signal scrolled(var wheel)

	implicitWidth: room + (value !== "" ? 4 + number.implicitWidth : 0)
	implicitHeight: Theme.barHeight

	FontMetrics {
		id: metrics

		font: icon.font
	}

	BarText {
		id: icon

		x: Math.round((root.fromLeft ? 0 : (root.room - root.ink.width) / 2) - root.ink.x)
		anchors.verticalCenter: parent.verticalCenter
		text: root.glyph
		color: root.tint
		font.pixelSize: root.glyphSize
	}

	BarText {
		id: number

		x: root.room + 4
		anchors.verticalCenter: parent.verticalCenter
		visible: root.value !== ""
		text: root.value
		color: root.tint
		font.pixelSize: Theme.numberSize
		font.features: {
			"tnum": 1
		}
	}

	Rectangle {
		visible: root.live
		x: root.room + root.dotShift
		y: 6
		width: 6
		height: 6
		radius: 3
		color: Theme.green
	}

	// Out over half the gaps either side: the icons alone are small targets
	MouseArea {
		anchors.fill: parent
		anchors.leftMargin: -6
		anchors.rightMargin: -6
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
		onClicked: mouse => root.clicked(mouse)
		onWheel: wheel => root.scrolled(wheel)
	}
}
