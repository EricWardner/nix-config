import QtQuick
import QtQuick.Shapes

// A glyph from Weather.glyph(), stroked on a 24px grid: the cloud in the
// text's colour and the sun, moon, rain, snow or lightning tinted, deeper on
// the grown light glass (onInk) so it still reads there
Item {
	id: root

	property string glyph: "cloud"
	property real size: 17
	property real strokeWidth: 2
	property bool onInk: false
	property color color: onInk ? Theme.ink : Theme.fg

	readonly property string rainCloud: "M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"
	readonly property var strokes: ({
			"sun": ["", "M16 12a4 4 0 1 1-8 0a4 4 0 1 1 8 0ZM12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41", "sun"],
			"moon": ["", "M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z", "moon"],
			"partlyDay": ["M13 22H7a5 5 0 1 1 4.9-6H13a3 3 0 0 1 0 6Z", "M12 2v2M4.93 4.93l1.41 1.41M20 12h2M19.07 4.93l-1.41 1.41M15.947 12.65a4 4 0 0 0-5.925-4.128", "sun"],
			"partlyNight": ["M13 16a3 3 0 1 1 0 6H7a5 5 0 1 1 4.9-6Z", "M10.1 9A6 6 0 0 1 16 4a4 4 0 0 0 6 6 6 6 0 0 1-3 5.197", "moon"],
			"cloud": ["M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z", "", ""],
			"fog": [rainCloud + "M16 17H7M17 21H9", "", ""],
			"drizzle": [rainCloud, "M8 19v1M8 14v1M16 19v1M16 14v1M12 21v1M12 16v1", "rain"],
			"rain": [rainCloud, "M16 14v6M8 14v6M12 16v6", "rain"],
			"snow": [rainCloud, "M8 15h.01M8 19h.01M12 17h.01M12 21h.01M16 15h.01M16 19h.01", "snow"],
			"storm": ["M6 16.326A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 .5 8.973", "M13 12l-3 5h4l-3 5", "sun"]
		})[glyph] ?? ["M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z", "", ""]
	readonly property color tint: ({
			"sun": onInk ? "#b97c00" : Theme.yellow,
			"moon": onInk ? "#7b4fc2" : Theme.purple,
			"rain": onInk ? Theme.inkBlue : Theme.accent,
			"snow": onInk ? "#1f8fbf" : Theme.cyan
		})[strokes[2]] ?? color

	implicitWidth: size
	implicitHeight: size

	Shape {
		width: 24
		height: 24
		scale: root.size / 24
		transformOrigin: Item.TopLeft
		preferredRendererType: Shape.CurveRenderer

		ShapePath {
			strokeColor: root.color
			strokeWidth: root.strokeWidth
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap
			joinStyle: ShapePath.RoundJoin

			PathSvg {
				path: root.strokes[0]
			}
		}

		ShapePath {
			strokeColor: root.tint
			strokeWidth: root.strokeWidth
			fillColor: "transparent"
			capStyle: ShapePath.RoundCap
			joinStyle: ShapePath.RoundJoin

			PathSvg {
				path: root.strokes[1]
			}
		}
	}
}
