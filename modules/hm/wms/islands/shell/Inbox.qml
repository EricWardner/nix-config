pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification server (in place of mako): what pops up in the centre
// island, the history, and Do Not Disturb.
//
// New notifications pop up one at a time on the focused monitor's island,
// each for its own timeout or 5 s; the pointer over one holds it. Critical
// ones and the YubiKey touch prompt stay until they're answered or closed.
// All of them stay in the history, the newest 20, until dismissed.
//
// Do Not Disturb keeps them from popping up, except critical ones and the
// YubiKey prompt: without that one, sudo and signing would look hung. While
// the screen is shared, the rest are held back, and pop up once it ends.
Singleton {
	id: root

	property bool dnd: false
	// The notification popping up, and those waiting their turn
	property Notification popup: null
	property var queue: []
	// Held back while the screen is shared
	property var held: []
	// The popup is under the pointer: hold it there
	property bool hovered: false

	// Oldest first
	readonly property var history: server.trackedNotifications.values
	// When each arrived (ms), by id, for the centre's "2m" and "1h"
	property var received: ({})

	function isYubiKey(n: Notification): bool {
		return n?.appName === "yubikey-touch-detector";
	}

	function breaksThrough(n: Notification): bool {
		return n.urgency === NotificationUrgency.Critical || isYubiKey(n);
	}

	// The app a notification is from. Claude Code notifies through Ghostty
	// under its own title, and Ghostty sends no app name.
	function appName(n: Notification): string {
		if (!n)
			return "";
		if (n.summary === "Claude Code")
			return "Claude Code";
		if (isYubiKey(n))
			return "YubiKey";
		if (n.appName !== "")
			return n.appName;
		return n.desktopEntry === "com.mitchellh.ghostty" ? "Ghostty" : "Notification";
	}

	// A path, an image:// URL, or a name to look up in the icon theme
	function iconSource(source: string): string {
		if (!source)
			return "";
		if (source.startsWith("/"))
			return "file://" + source;
		if (source.includes("://"))
			return source;
		return Quickshell.iconPath(source, true);
	}

	// The app's icon, never the notification's own image
	function appIcon(n: Notification): string {
		if (n?.summary === "Claude Code")
			return Qt.resolvedUrl("icons/claude.svg");
		return iconSource(n?.appIcon ?? "") || iconSource(n?.desktopEntry ?? "");
	}

	// How long the popup shows, in ms; 0 for until it's closed
	readonly property int duration: {
		if (!popup || breaksThrough(popup))
			return 0;
		// The spec's milliseconds, which Quickshell gives in seconds
		return popup.expireTimeout > 0 ? popup.expireTimeout * 1000 : 5000;
	}

	function receive(n: Notification) {
		n.tracked = true;
		received = Object.assign({}, received, {
			[n.id]: Date.now()
		});
		const kept = server.trackedNotifications.values;
		for (let i = 0; i < kept.length - 20; i++)
			kept[i].dismiss();
		n.closed.connect(() => forget(n));
		if (dnd && !breaksThrough(n))
			return;
		// The open notification centre lists it already
		if (Desktop.panel === "centre" && !breaksThrough(n))
			return;
		if (Sharing.active && !breaksThrough(n)) {
			held = held.concat([n]);
			return;
		}
		if (isYubiKey(n) && Host.attentionSound !== "")
			Quickshell.execDetached(["pw-play", Host.attentionSound]);
		queue = queue.concat([n]);
		if (!popup)
			next();
	}

	// Shows the next waiting notification, if any
	function next() {
		const waiting = queue.filter(n => n !== null);
		popup = waiting[0] ?? null;
		queue = waiting.slice(1);
		hovered = false;
	}

	// The popup's time is up: it stays in the history, unless it was only
	// ever meant to pop up
	function timedOut() {
		const n = popup;
		next();
		if (n?.transient)
			n.expire();
	}

	function forget(n: Notification) {
		queue = queue.filter(q => q !== n && q !== null);
		held = held.filter(h => h !== n);
		if (popup === n)
			next();
	}

	function clearAll() {
		for (const n of Array.from(history))
			n.dismiss();
	}

	// "now", "5m", "2h", or the day for older ones
	function age(n: Notification, now: date): string {
		const at = received[n?.id];
		if (!at)
			return "";
		const minutes = Math.floor((now.getTime() - at) / 60000);
		if (minutes < 1)
			return "now";
		if (minutes < 60)
			return minutes + "m";
		if (minutes < 24 * 60)
			return Math.floor(minutes / 60) + "h";
		return Qt.formatDate(new Date(at), "ddd");
	}

	// A click on a notification: its default action, if it has one, which
	// closes it unless it asks to stay; otherwise just out of the way
	function activate(n: Notification) {
		const action = Array.from(n.actions).find(a => a.identifier === "default");
		if (action)
			invoke(n, action);
		else if (popup === n)
			next();
	}

	function invoke(n: Notification, action: NotificationAction) {
		action.invoke();
		if (!n.resident)
			n.dismiss();
		else if (popup === n)
			next();
	}

	// A share starting takes what's showing and waiting off the screen; one
	// ending lets them pop up
	Connections {
		target: Sharing

		function onActiveChanged() {
			if (Sharing.active) {
				const holdable = n => n !== null && !root.breaksThrough(n);
				root.held = root.held.concat([root.popup].concat(root.queue).filter(holdable));
				root.queue = root.queue.filter(n => n !== null && root.breaksThrough(n));
				if (holdable(root.popup))
					root.next();
			} else {
				if (!root.dnd)
					root.queue = root.queue.concat(root.held);
				root.held = [];
				if (!root.popup)
					root.next();
			}
		}
	}

	NotificationServer {
		id: server

		keepOnReload: true
		bodySupported: true
		bodyMarkupSupported: true
		bodyHyperlinksSupported: true
		actionsSupported: true
		imageSupported: true
		persistenceSupported: true
		onNotification: n => root.receive(n)
	}

	// Each popup gets its full time, again after the pointer leaves it
	function schedule() {
		if (popup && duration > 0 && !hovered)
			popupTimer.restart();
		else
			popupTimer.stop();
	}

	onPopupChanged: schedule()
	onHoveredChanged: schedule()
	onDurationChanged: schedule()

	Timer {
		id: popupTimer

		interval: Math.max(root.duration, 1)
		onTriggered: root.timedOut()
	}

	// Do Not Disturb lasts until it's turned off or the session ends: kept in
	// the runtime directory, so a restart of the shell keeps it
	readonly property string dndFile: Quickshell.env("XDG_RUNTIME_DIR") + "/islands/dnd"

	onDndChanged: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && echo \"$2\" >\"$1\"", "sh", dndFile, dnd ? "on" : "off"])

	FileView {
		path: root.dndFile
		printErrors: false
		onLoaded: root.dnd = text().trim() === "on"
	}

	// For keybinds and the launcher: `qs ipc -c islands call notifications …`
	IpcHandler {
		target: "notifications"

		function toggleDnd(): string {
			root.dnd = !root.dnd;
			return root.dnd ? "on" : "off";
		}

		function setDnd(on: bool): void {
			root.dnd = on;
		}

		// Shows the newest notification again
		function restore(): string {
			const newest = root.history[root.history.length - 1];
			if (!newest)
				return "none";
			root.queue = root.queue.filter(n => n !== newest);
			root.popup = newest;
			return "restored";
		}

		function clear(): void {
			root.clearAll();
		}
	}
}
