import QtQuick

// One thing the centre island can show. The island shows the active mode
// with the highest priority, grown to the size the mode asks for, and fades
// the others out. A mode's content keeps its own size while the island
// morphs around it, so nothing reflows mid-animation.
Item {
	id: root

	property bool active: false
	property int priority: 0
	// The island's size while this mode shows
	property real islandWidth: 300
	property real islandHeight: 42
	// In the faint glass of the bar at rest, rather than grown light glass
	property bool resting: false
	// The grown glass's rim; a state can colour it (critical: red)
	property color rim: Theme.grownRim
	// Set by the island
	property bool current: false

	width: islandWidth
	height: islandHeight
	anchors.horizontalCenter: parent.horizontalCenter
	opacity: current ? 1 : 0
	visible: opacity > 0

	Behavior on opacity {
		NumberAnimation {
			duration: root.current ? 220 : 120
		}
	}
}
