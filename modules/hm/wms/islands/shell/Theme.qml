pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The stylix theme, from the JSON Home Manager writes
// (modules/hm/wms/islands/default.nix), reloaded whenever that changes.
// Material Darker until it has loaded.
Singleton {
	id: root

	property var colours: ({})
	property var fonts: ({})

	readonly property color fg: colours.base05 ?? "#eeffff"
	readonly property color bg: colours.base00 ?? "#212121"
	readonly property color accent: colours.base0D ?? "#82aaff"
	readonly property color dim: colours.base03 ?? "#4a4a4a"
	readonly property color green: colours.base0B ?? "#c3e88d"
	readonly property color yellow: colours.base0A ?? "#ffcb6b"
	readonly property color red: colours.base08 ?? "#f07178"
	readonly property color orange: colours.base09 ?? "#f78c6c"
	readonly property color purple: colours.base0E ?? "#c792ea"
	readonly property string sans: fonts.sans ?? "sans-serif"

	// The islands at rest: the faint glass of waybar's tray island, a light
	// tint with a brighter rim. QML draws a border beside the fill, not over
	// it as CSS does, so the rim carries both.
	readonly property color islandFill: alpha(fg, 0.1)
	readonly property color islandRim: alpha(fg, 0.22)
	// Grown: light glass (as mako's cards were) with the dark ink on it
	readonly property color grownFill: alpha(fg, 0.65)
	readonly property color grownRim: Qt.rgba(1, 1, 1, 0.55)
	readonly property color ink: bg
	readonly property color inkDim: alpha(bg, 0.75)
	readonly property color inkTrack: alpha(bg, 0.14)
	// The palette's green is too pale to read on the light glass
	readonly property color inkGreen: "#3f8f3a"
	// The bar's window reaches this far down, transparent and letting clicks
	// through below the bar, so islands have room to grow
	readonly property int windowHeight: 560

	// In logical pixels. Numbers beside icons are a size smaller than the
	// bar's text so the icon leads.
	readonly property int barTop: 4
	readonly property int barHeight: 32
	readonly property int fontSize: 16
	readonly property int numberSize: 14

	// FreeType with fontconfig's hinting, as GTK draws: Qt Quick's own
	// distance-field text put colour fringes on every edge of the icons,
	// which read as fat and soft, at both 1.25x and 1.6x. Curve rendering
	// is clean but softer still.
	readonly property int textRender: Text.NativeRendering

	function alpha(colour: color, a: real): color {
		return Qt.rgba(colour.r, colour.g, colour.b, a);
	}

	FileView {
		path: Quickshell.env("HOME") + "/.config/islands/theme.json"
		watchChanges: true
		onFileChanged: reload()
		onLoaded: {
			try {
				const theme = JSON.parse(text());
				root.colours = theme.colours;
				root.fonts = theme.fonts;
			} catch (e) {
				console.warn("islands: can't read theme.json:", e);
			}
		}
	}
}
