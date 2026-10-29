import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

// One notification in the light glass's dark ink: its icon, the app's name
// small and dimmed over a bold title (as on iOS), the body, and any
// actions. A click runs its default action, a right click dismisses it;
// hovering shows a close button.
Item {
	id: root

	required property Notification notification
	// Others waiting behind this one, for a "2 more" beside its app's name
	property int more: 0
	// How long ago it arrived, in the centre's history
	property string time: ""

	readonly property Notification n: notification
	// Claude Code notifies through Ghostty under its own title: shown as its
	// own app, with its message as the title
	readonly property bool claude: n?.summary === "Claude Code"
	readonly property bool yubikey: Inbox.isYubiKey(n)
	readonly property bool low: n?.urgency === NotificationUrgency.Low
	readonly property string label: Inbox.appName(n)
	readonly property string title: claude ? n?.body ?? "" : n?.summary ?? ""
	readonly property string body: claude || yubikey ? "" : n?.body ?? ""
	readonly property var actions: n ? Array.from(n.actions).filter(a => a.identifier !== "default") : []
	// Its image, else its app's icon (Ghostty sends its icon's name as the
	// image)
	readonly property string icon: claude ? Inbox.appIcon(n) : Inbox.iconSource(n?.image ?? "") || Inbox.appIcon(n)
	// The colour picker's notification carries the colour as its image: a
	// bigger swatch than an app icon
	readonly property int iconSize: n?.appName === "Screenshot" && n.image !== "" ? 56 : yubikey ? 48 : 40

	signal activated

	implicitWidth: 420
	implicitHeight: Math.max(content.implicitHeight, iconSlot.height) + 28

	HoverHandler {
		id: hover
	}

	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.LeftButton | Qt.RightButton
		onClicked: mouse => {
			if (mouse.button === Qt.RightButton)
				root.n.dismiss();
			else
				root.activated();
		}
	}

	ClippingRectangle {
		id: iconSlot

		visible: root.icon !== ""
		x: 16
		y: 14
		width: root.iconSize
		height: root.iconSize
		radius: 10
		color: "transparent"

		Image {
			anchors.fill: parent
			source: root.icon
			sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
			fillMode: Image.PreserveAspectFit
			smooth: true
			mipmap: true
		}
	}

	Column {
		id: content

		x: iconSlot.visible ? iconSlot.x + iconSlot.width + 12 : 16
		y: 14
		width: root.width - x - 16
		spacing: 2

		Item {
			width: parent.width
			height: labelText.implicitHeight

			BarText {
				id: labelText

				width: parent.width - timeText.implicitWidth - 30
				text: root.more > 0 ? root.label + " · " + root.more + " more" : root.label
				color: Theme.inkDim
				font.pixelSize: 12
				elide: Text.ElideRight
			}

			// Under the close button while the pointer's over the card
			BarText {
				id: timeText

				anchors.right: parent.right
				visible: !hover.hovered
				text: root.time
				color: Theme.inkDim
				font.pixelSize: 12
			}
		}

		BarText {
			visible: text !== ""
			width: parent.width
			text: root.title
			color: root.low ? Theme.inkDim : Theme.ink
			font.pixelSize: 14
			font.weight: Font.DemiBold
			wrapMode: Text.Wrap
			maximumLineCount: 2
			elide: Text.ElideRight
		}

		BarText {
			visible: text !== ""
			width: parent.width
			text: root.body
			textFormat: Text.StyledText
			color: Theme.inkDim
			font.pixelSize: 13
			wrapMode: Text.Wrap
			maximumLineCount: 3
			elide: Text.ElideRight
			linkColor: Theme.ink
			onLinkActivated: link => Qt.openUrlExternally(link)
		}

		Row {
			visible: root.actions.length > 0
			topPadding: 8
			spacing: 6

			Repeater {
				model: root.actions

				Rectangle {
					required property NotificationAction modelData

					width: actionLabel.implicitWidth + 20
					height: 26
					radius: 13
					color: actionHover.hovered ? Theme.inkTrack : "transparent"
					border.width: 1
					border.color: Theme.alpha(Theme.ink, 0.18)

					BarText {
						id: actionLabel

						anchors.centerIn: parent
						text: modelData.text
						color: Theme.ink
						font.pixelSize: 12
						font.weight: Font.Medium
					}

					HoverHandler {
						id: actionHover
					}

					MouseArea {
						anchors.fill: parent
						onClicked: Inbox.invoke(root.n, modelData)
					}
				}
			}
		}
	}

	// Dismisses it
	Rectangle {
		visible: hover.hovered
		anchors.top: parent.top
		anchors.right: parent.right
		anchors.margins: 10
		width: 22
		height: 22
		radius: 11
		color: closeHover.hovered ? Theme.alpha(Theme.ink, 0.16) : Theme.inkTrack

		BarText {
			anchors.centerIn: parent
			text: "×"
			color: Theme.ink
			font.pixelSize: 15
		}

		HoverHandler {
			id: closeHover
		}

		MouseArea {
			anchors.fill: parent
			onClicked: root.n.dismiss()
		}
	}
}
