import QtQuick

// Text in the bar's font, size and colour, drawn with the renderer in Theme
Text {
	color: Theme.fg
	font.family: Theme.sans
	font.pixelSize: Theme.fontSize
	renderType: Theme.textRender
}
