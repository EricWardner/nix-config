import QtQuick

// Text that rolls to each new value like an odometer: the old one slides up
// and out as the new one comes up from below (the other way for `direction`
// -1), settling with a small bounce. Its width follows the new text, so
// whatever sits beside it moves along.
Item {
	id: root

	property string text
	property int direction: 1
	property color color: Theme.ink
	property int pixelSize: Theme.fontSize
	property int weight: Font.Normal

	// The text before the last change, for the one sliding out
	property string previous

	component Line: BarText {
		color: root.color
		font.pixelSize: root.pixelSize
		font.weight: root.weight
	}

	clip: true
	implicitWidth: shown.implicitWidth
	implicitHeight: shown.implicitHeight

	Behavior on implicitWidth {
		Morph {}
	}

	Component.onCompleted: previous = text
	onTextChanged: {
		gone.text = previous;
		previous = text;
		roll.restart();
	}

	Line {
		id: gone

		opacity: 0
	}

	Line {
		id: shown

		text: root.text
	}

	ParallelAnimation {
		id: roll

		NumberAnimation {
			target: shown
			property: "y"
			from: root.direction * root.height
			to: 0
			duration: 380
			easing.type: Easing.OutBack
			easing.overshoot: 1.2
		}

		NumberAnimation {
			target: shown
			property: "opacity"
			from: 0
			to: 1
			duration: 200
		}

		NumberAnimation {
			target: gone
			property: "y"
			from: 0
			to: -root.direction * root.height
			duration: 300
			easing.type: Easing.OutCubic
		}

		NumberAnimation {
			target: gone
			property: "opacity"
			from: 1
			to: 0
			duration: 200
		}
	}
}
