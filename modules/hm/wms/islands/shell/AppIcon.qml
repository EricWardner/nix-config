import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

// A window's icon on its workspace (Glyphs.app): a Nerd Font glyph, or, for
// an app that font has no logo of, the outline in logos/NAME.svg, filled in
// the bar's colour at the glyphs' size. Drawn as a shape: as an Image it was
// rasterised, and came out softer than the glyphs beside it.
Item {
	id: root

	// One or the other
	property string glyph
	property string logo

	// The SVG's one path, and its viewBox: x, y, width, height
	readonly property string svg: logo !== "" ? file.text() : ""
	readonly property string outline: svg.match(/\sd="([^"]+)"/)?.[1] ?? ""
	readonly property var box: (svg.match(/viewBox="([^"]+)"/)?.[1] ?? "0 0 1 1").split(" ").map(Number)
	// As tall as Symbols Nerd Font's app icons, and as far under the middle
	// of the line as they sit
	readonly property real size: Theme.fontSize * 0.84
	readonly property real drop: Theme.fontSize * 0.03

	implicitWidth: logo !== "" ? size * box[2] / box[3] : text.implicitWidth
	implicitHeight: text.implicitHeight

	// In the regular weight: the icon font has no bold, and Qt would fake one
	BarText {
		id: text

		text: root.glyph
	}

	FileView {
		id: file

		path: root.logo !== "" ? Quickshell.shellPath(`logos/${root.logo}.svg`) : ""
		blockLoading: true
	}

	Shape {
		visible: root.outline !== ""
		x: -root.box[0] * scale
		y: (root.height - root.size) / 2 + root.drop - root.box[1] * scale
		scale: root.size / root.box[3]
		transformOrigin: Item.TopLeft
		preferredRendererType: Shape.CurveRenderer

		ShapePath {
			strokeColor: "transparent"
			fillColor: Theme.fg
			// SVG's rule; a ShapePath's own default is odd-even
			fillRule: ShapePath.WindingFill

			PathSvg {
				path: root.outline
			}
		}
	}
}
