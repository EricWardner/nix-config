import QtQuick

// A rounded group on a control centre page, its contents in a column
Rectangle {
	default property alias content: inside.data

	height: inside.implicitHeight + 24
	radius: 16
	color: Theme.alpha(Theme.ink, 0.06)

	Column {
		id: inside

		x: 12
		y: 12
		width: parent.width - 24
		spacing: 12
	}
}
