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
// YubiKey prompt: without that one, sudo and signing would look hung.
Singleton {
	id: root

	property bool dnd: false
	// The notification popping up, and those waiting their turn
	property Notification popup: null
	property var queue: []
	// The popup is under the pointer: hold it there
	property bool hovered: false

	// Oldest first
	readonly property var history: server.trackedNotifications.values

	function isYubiKey(n: Notification): bool {
		return n?.appName === "yubikey-touch-detector";
	}

	function breaksThrough(n: Notification): bool {
		return n.urgency === NotificationUrgency.Critical || isYubiKey(n);
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
		const kept = server.trackedNotifications.values;
		for (let i = 0; i < kept.length - 20; i++)
			kept[i].dismiss();
		n.closed.connect(() => forget(n));
		if (dnd && !breaksThrough(n))
			return;
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
		if (popup === n)
			next();
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
			for (const n of root.history.slice())
				n.dismiss();
		}
	}
}
