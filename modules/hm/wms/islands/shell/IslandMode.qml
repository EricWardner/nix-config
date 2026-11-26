import QtQuick

// One thing an island can show, declared inside it. The island shows the
// active mode with the highest priority (the first one declared rests
// there when nothing else is active), grown to the size the mode asks for,
// and fades the others out. A mode's content keeps its own size while the
// island morphs around it, so nothing reflows mid-animation. A focus scope,
// so a field it hides hands the keyboard back to it (its Esc), not the
// window.
FocusScope {
	id: root

	readonly property bool isMode: true
	property bool active: false
	property int priority: 0
	// The island's size while this mode shows
	property real islandWidth: 300
	property real islandHeight: 42
	// The island's corners: a pill while it's a line high and 24px rounding
	// once it's taller, unless set
	property real cornerRadius: -1
	// In the faint glass of the bar at rest, rather than grown light glass
	property bool resting: false
	// Passing over the bar (a popup, a panel): what's beside the island
	// keeps its place, as if the island were still the mode under it
	property bool floats: false
	// The grown glass's rim; a state can colour it (critical: red)
	property color rim: Theme.grownRim
	// The rim at rest (a job that failed: red)
	property color restRim: Theme.islandRim
	// A fill of the mode's own over the grown glass (the forecast's
	// sky): a Gradient, or null for the glass alone
	property var fill: null
	// Set by the island
	property bool current: false

	width: islandWidth
	height: islandHeight
	// Kept to the edge the island is pinned by (Island.align), so a mode
	// stays put while the glass morphs around it. By anchors: a centred
	// one snaps to whole pixels as the centre island does, which a
	// computed x didn't, and the notification jittered as it shrank.
	anchors.horizontalCenter: parent?.align === Qt.AlignHCenter ? parent.horizontalCenter : undefined
	anchors.left: parent?.align === Qt.AlignLeft ? parent.left : undefined
	anchors.right: parent?.align === Qt.AlignRight ? parent.right : undefined
	opacity: current ? 1 : 0
	visible: opacity > 0

	// Timed by where the fade is going: timed by `current`, the duration
	// was still the old one when the fade began, so modes faded out over
	// 220ms and in over 120ms, the wrong way round
	Behavior on opacity {
		id: fade

		NumberAnimation {
			duration: fade.targetValue > 0 ? 220 : 120
		}
	}
}
