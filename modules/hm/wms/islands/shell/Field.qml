import QtQuick

// A text field on the light glass: a password's dots, a name, a PIN.
// `accepted` on Enter.
Rectangle {
	id: root

	property alias text: input.text
	property bool password: false
	property string placeholder
	// Digits only (a passkey)
	property bool numeric: false

	signal accepted

	function focusField() {
		input.forceActiveFocus();
	}

	implicitHeight: 34
	radius: 9
	color: Qt.rgba(1, 1, 1, 0.85)
	border.width: 1
	border.color: input.activeFocus ? Theme.accent : Theme.alpha(Theme.ink, 0.18)

	TextInput {
		id: input

		anchors.fill: parent
		anchors.leftMargin: 10
		anchors.rightMargin: 10
		verticalAlignment: TextInput.AlignVCenter
		echoMode: root.password ? TextInput.Password : TextInput.Normal
		inputMethodHints: root.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
		validator: root.numeric ? digits : null
		color: Theme.ink
		font.family: Theme.sans
		font.pixelSize: 14
		clip: true
		onAccepted: root.accepted()

		RegularExpressionValidator {
			id: digits

			regularExpression: /[0-9]{0,6}/
		}
	}

	BarText {
		anchors.left: parent.left
		anchors.leftMargin: 10
		anchors.verticalCenter: parent.verticalCenter
		visible: input.text === ""
		text: root.placeholder
		color: Theme.alpha(Theme.ink, 0.45)
		font.pixelSize: 14
	}
}
