import QtQuick

// One of Sky's cards: frosted glass over the wallpaper, with its content in
// a column
Item {
	id: root

	default property alias content: column.data
	property alias spacing: column.spacing
	property Item backdrop

	implicitWidth: 300
	implicitHeight: column.implicitHeight + 32

	SkyGlass {
		backdrop: root.backdrop
		radius: 22
	}

	Column {
		id: column

		x: 16
		y: 16
		width: parent.width - 32
		spacing: 12
	}
}
