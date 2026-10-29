import QtQuick
import Quickshell.Bluetooth

// A question from NetworkManager, BlueZ or gnome-keyring (Agent), over
// everything else in the centre island until it's answered: a Wi-Fi
// password (and a login, for a work network), a pairing step (confirm a
// passkey, type one shown here on a keyboard, enter a PIN, allow a device
// in), or a keyring's password (to unlock it, or a new one) or yes or no.
// Enter answers it, Esc cancels it; it keeps the keyboard while it shows.
IslandMode {
	id: root

	readonly property var question: Agent.current
	readonly property string kind: question?.kind ?? ""
	readonly property bool wifi: kind === "wifi"
	readonly property bool keyring: kind === "keyring"
	readonly property bool keyringPassword: keyring && !question.confirm
	readonly property bool newPassword: keyringPassword && question.new
	readonly property bool typed: kind === "bt-pin" || kind === "bt-passkey"
	readonly property bool shows: kind === "bt-confirm" || kind === "bt-display"
	// The Bluetooth device it's about, to cancel its pairing from here and to
	// see it finish
	readonly property var device: question?.path ? Array.from(Bluetooth.devices.values).find(d => d.dbusPath === question.path) ?? null : null

	readonly property string title: {
		const q = question;
		if (!q)
			return "";
		switch (kind) {
		case "wifi":
			return q.retry ? "The password for " + q.ssid + " didn't work" : q.ssid + " needs a password";
		case "bt-confirm":
			return "Pair with " + q.device + "?";
		case "bt-display":
			return "Type this on " + q.device + ", then Enter";
		case "bt-pin":
			return "PIN for " + q.device;
		case "bt-passkey":
			return "Passkey for " + q.device;
		case "bt-authorize":
			return "Allow " + q.device + " to connect?";
		case "keyring":
			return q.message || q.title;
		}
		return "";
	}
	readonly property string detail: kind === "bt-confirm" ? "Check that it shows this number" : keyring ? question.description : ""
	readonly property bool ready: {
		if (wifi)
			return question.login ? identity.text !== "" && secret.text !== "" : secret.text.length >= 8;
		if (newPassword)
			return secret.text === confirmation.text;
		if (typed || keyringPassword)
			return secret.text !== "";
		return true;
	}

	function submit() {
		if (!question || !ready)
			return;
		const id = question.id;
		if (wifi)
			Agent.answer(id, {
				"identity": identity.text,
				"secret": secret.text
			});
		else if (keyring)
			Agent.answer(id, {
				"secret": secret.text,
				"chosen": choice.on
			});
		else if (typed)
			Agent.answer(id, secret.text);
		else if (kind === "bt-display")
			Agent.answer(id, null);
		else
			Agent.answer(id, true);
	}

	function cancel() {
		if (!question)
			return;
		if (kind === "bt-display")
			device?.cancelPair();
		Agent.answer(question.id, kind === "bt-authorize" ? false : null);
	}

	priority: 60
	rim: Theme.accent
	islandWidth: 420
	islandHeight: content.implicitHeight + 28

	focus: current
	Keys.onEscapePressed: cancel()
	Keys.onReturnPressed: submit()

	// Nothing to take when the last question has gone: the focus belongs to
	// whatever shows instead
	function focusFirst() {
		if (!question)
			return;
		if (question.login)
			identity.focusField();
		else if (wifi || typed || keyringPassword)
			secret.focusField();
		else
			forceActiveFocus();
	}

	// A new question: empty fields, and the keyboard where it's typed, once
	// the fields it asks for are showing (a hidden one can't take it)
	onQuestionChanged: {
		identity.text = question?.identity ?? "";
		secret.text = "";
		confirmation.text = "";
		choice.on = question?.chosen ?? false;
		Qt.callLater(focusFirst);
	}
	onCurrentChanged: if (current)
		questionChanged()

	// The passkey shown to type: done once the device has paired
	Connections {
		target: root.kind === "bt-display" ? root.device : null

		function onPairedChanged() {
			if (root.device.paired)
				Agent.answer(root.question.id, null);
		}
	}

	Column {
		id: content

		x: 16
		y: 14
		width: parent.width - 32
		spacing: 10

		Row {
			width: parent.width
			spacing: 12

			Rectangle {
				width: 32
				height: 32
				radius: 16
				color: Theme.accent

				BarText {
					anchors.centerIn: parent
					text: root.wifi ? Glyphs.wifi : root.keyring ? Glyphs.lock : Glyphs.bluetooth
					color: Theme.ink
					font.pixelSize: 15
				}
			}

			Column {
				width: parent.width - 44
				anchors.verticalCenter: parent.verticalCenter

				BarText {
					width: parent.width
					text: root.title
					// Plain text: networks, devices and keyrings name themselves
					textFormat: Text.PlainText
					color: Theme.ink
					font.pixelSize: 14
					font.weight: Font.DemiBold
					wrapMode: Text.Wrap
				}

				BarText {
					visible: text !== ""
					width: parent.width
					text: root.detail
					textFormat: Text.PlainText
					color: Theme.inkDim
					font.pixelSize: 12
					wrapMode: Text.Wrap
				}

				// The last password didn't work, or the new ones don't match
				BarText {
					visible: text !== ""
					width: parent.width
					text: root.keyring ? root.question.warning : ""
					textFormat: Text.PlainText
					color: Theme.red
					font.pixelSize: 12
					font.weight: Font.DemiBold
					wrapMode: Text.Wrap
				}
			}
		}

		// A passkey to compare or to type: in two groups of three, as phones
		// show them
		BarText {
			visible: root.shows
			x: 44
			text: {
				const passkey = root.question?.passkey ?? "";
				return passkey.length === 6 ? passkey.slice(0, 3) + " " + passkey.slice(3) : passkey;
			}
			color: Theme.ink
			font.pixelSize: 28
			font.weight: Font.DemiBold
			font.letterSpacing: 3
			font.features: {
				"tnum": 1
			}
		}

		Field {
			id: identity

			visible: root.wifi && (root.question?.login ?? false)
			width: parent.width
			placeholder: "Username"
			onAccepted: secret.focusField()
		}

		Field {
			id: secret

			visible: root.wifi || root.typed || root.keyringPassword
			width: parent.width
			password: root.wifi || root.keyring
			numeric: root.kind === "bt-passkey"
			placeholder: root.wifi || root.keyring ? "Password" : root.kind === "bt-pin" ? "PIN" : "Passkey"
			onAccepted: root.newPassword ? confirmation.focusField() : root.submit()
		}

		Field {
			id: confirmation

			visible: root.newPassword
			width: parent.width
			password: true
			placeholder: "Confirm password"
			onAccepted: root.submit()
		}

		// gnome-keyring's offer to remember the password (and so unlock the
		// keyring at login)
		Row {
			visible: root.keyring && root.question.choice !== ""
			width: parent.width
			spacing: 10

			Switch {
				id: choice

				anchors.verticalCenter: parent.verticalCenter
				onToggled: on = !on
			}

			BarText {
				width: parent.width - choice.width - 10
				anchors.verticalCenter: parent.verticalCenter
				text: root.keyring ? root.question.choice : ""
				textFormat: Text.PlainText
				color: Theme.ink
				font.pixelSize: 12
				wrapMode: Text.Wrap
			}
		}

		Row {
			anchors.right: parent.right
			spacing: 6

			PillButton {
				text: root.kind === "bt-authorize" ? "Deny" : root.keyring ? root.question.cancel || "Cancel" : "Cancel"
				onClicked: root.cancel()
			}

			PillButton {
				visible: root.kind !== "bt-display"
				primary: true
				enabled: root.ready
				text: root.wifi ? "Join" : root.keyring ? root.question.continue || "Continue" : root.kind === "bt-authorize" ? "Allow" : "Pair"
				onClicked: root.submit()
			}
		}
	}
}
