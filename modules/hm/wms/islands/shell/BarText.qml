import QtQuick

// Text in the bar's font, size and colour, drawn with the renderer in Theme.
// Plain unless a use asks otherwise: much of it comes from outside (network
// and device names, track titles, notifications), and Text's default would
// read anything that looks like HTML as markup, remote images included.
Text {
	textFormat: Text.PlainText
	color: Theme.fg
	font.family: Theme.sans
	font.pixelSize: Theme.fontSize
	renderType: Theme.textRender
}
