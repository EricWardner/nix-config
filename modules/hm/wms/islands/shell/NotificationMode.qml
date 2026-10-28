import QtQuick
import Quickshell.Services.Notifications

// The notification popping up (Inbox.popup). The pointer over it holds it
// there. Critical ones are rimmed in red, the YubiKey touch prompt in the
// green of the Yubico logo.
IslandMode {
	priority: 20
	islandWidth: 420
	islandHeight: card.implicitHeight
	rim: Inbox.popup?.urgency === NotificationUrgency.Critical ? Theme.red : Inbox.isYubiKey(Inbox.popup) ? "#97c73b" : Theme.grownRim

	NotificationCard {
		id: card

		width: parent.width
		notification: Inbox.popup
		more: Inbox.queue.length
		onActivated: Inbox.activate(notification)
	}

	HoverHandler {
		onHoveredChanged: Inbox.hovered = hovered
	}
}
