import QtQuick

// One of Sky's cards: dark glass over the wallpaper, which Hyprland blurs
// behind it (hypr/lua/rules.lua), with its content in a column
Rectangle {
	default property alias content: column.data
	property alias spacing: column.spacing

	implicitWidth: 300
	implicitHeight: column.implicitHeight + 32
	radius: 22
	color: Qt.rgba(0.04, 0.08, 0.24, 0.32)
	border.width: 1
	border.color: Theme.alpha(Theme.fg, 0.18)

	Column {
		id: column

		x: 16
		y: 16
		width: parent.width - 32
		spacing: 12
	}
}
