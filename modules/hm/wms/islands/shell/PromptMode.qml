import QtQuick
import Quickshell.Bluetooth

// A question from NetworkManager or BlueZ (Agent), over everything else in
// the centre island until it's answered: a Wi-Fi password (and a login, for
// a work network), or a pairing step (confirm a passkey, type one shown
// here on a keyboard, enter a PIN, allow a device in). Enter answers it, Esc
// cancels it; it keeps the keyboard while it shows.
IslandMode {
	id: root

	readonly property var question: Agent.current
	readonly property string kind: question?.kind ?? ""
	readonly property bool wifi: kind === "wifi"
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
		}
		return "";
	}
	readonly property string detail: kind === "bt-confirm" ? "Check that it shows this number" : ""
	readonly property bool ready: {
		if (wifi)
			return question.login ? identity.text !== "" && secret.text !== "" : secret.text.length >= 8;
		if (typed)
			return secret.text !== "";
		return true;
	}

	function submit() {
		if (!ready)
			return;
		const id = question.id;
		if (wifi)
			Agent.answer(id, {
				"identity": identity.text,
				"secret": secret.text
			});
		else if (typed)
			Agent.answer(id, secret.text);
		else if (kind === "bt-display")
			Agent.answer(id, null);
		else
			Agent.answer(id, true);
	}

	function cancel() {
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

	// A new question: empty fields, and the keyboard where it's typed
	onQuestionChanged: {
		identity.text = question?.identity ?? "";
		secret.text = "";
		if (question?.login)
			identity.focusField();
		else if (wifi || typed)
			secret.focusField();
		else
			forceActiveFocus();
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
					text: root.wifi ? Glyphs.wifi : Glyphs.bluetooth
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
					color: Theme.ink
					font.pixelSize: 14
					font.weight: Font.DemiBold
					wrapMode: Text.Wrap
				}

				BarText {
					visible: text !== ""
					text: root.detail
					color: Theme.inkDim
					font.pixelSize: 12
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

			visible: root.wifi || root.typed
			width: parent.width
			password: root.wifi
			numeric: root.kind === "bt-passkey"
			placeholder: root.wifi ? "Password" : root.kind === "bt-pin" ? "PIN" : "Passkey"
			onAccepted: root.submit()
		}

		Row {
			anchors.right: parent.right
			spacing: 6

			PillButton {
				text: root.kind === "bt-authorize" ? "Deny" : "Cancel"
				onClicked: root.cancel()
			}

			PillButton {
				visible: root.kind !== "bt-display"
				primary: true
				enabled: root.ready
				text: root.wifi ? "Join" : root.kind === "bt-authorize" ? "Allow" : "Pair"
				onClicked: root.submit()
			}
		}
	}
}
