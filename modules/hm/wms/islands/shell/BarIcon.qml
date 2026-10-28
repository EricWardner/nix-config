import QtQuick

// A status icon on the bare bar: an SF Symbol in a 26px box, so icons of
// different widths still sit at even centre-to-centre spacing, then an
// optional number in the smaller size. A state is shown by colouring the
// icon (and number), never by a box behind it; `live` adds the 6px green
// dot at the top right, which takes no room, so nothing shifts.
Item {
	id: root

	property string glyph
	property int glyphSize: Theme.fontSize
	property string value: ""
	property color tint: Theme.fg
	property bool live: false
	// How far right of the box's edge the dot sits (the camera's must clear
	// its lens)
	property real dotShift: 0
	// For a glyph that changes width (the volume's waves): the widest it gets.
	// The icon keeps that room, every glyph starting where it starts, so
	// nothing beside it moves.
	property string widestGlyph: ""

	signal clicked(var mouse)
	signal scrolled(var wheel)

	implicitWidth: Math.max(26, Math.max(row.implicitWidth, widest.advanceWidth) + 2)
	implicitHeight: Theme.barHeight

	TextMetrics {
		id: widest

		font: glyph.font
		text: root.widestGlyph
	}

	Row {
		id: row

		x: Math.round((root.width - (root.widestGlyph !== "" ? widest.advanceWidth : width)) / 2)
		anchors.verticalCenter: parent.verticalCenter
		spacing: 4

		BarText {
			id: glyph

			text: root.glyph
			color: root.tint
			font.pixelSize: root.glyphSize
			anchors.verticalCenter: parent.verticalCenter
		}

		BarText {
			visible: root.value !== ""
			text: root.value
			color: root.tint
			font.pixelSize: Theme.numberSize
			font.features: { "tnum": 1 }
			anchors.verticalCenter: parent.verticalCenter
		}
	}

	Rectangle {
		visible: root.live
		width: 6
		height: 6
		radius: 3
		color: Theme.green
		anchors.right: parent.right
		anchors.rightMargin: -root.dotShift
		anchors.top: parent.top
		anchors.topMargin: 6
	}

	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
		onClicked: mouse => root.clicked(mouse)
		onWheel: wheel => root.scrolled(wheel)
	}
}
