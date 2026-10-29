pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The work calendar's events, from islands-calendar: fetched every five
// minutes into a cache read here, so the bar has the day at once on start,
// and offline. Whatever shows a title keeps it off a shared screen.
Singleton {
	id: root

	// [{title, start, end, allDay, join, location}], times in ms, by start
	property var events: []
	property real now: Date.now()
	readonly property var today: events.filter(e => sameDay(e.start) || (e.allDay && e.start <= now && e.end > now))
	// Today's timed events not over yet, the one on now first
	readonly property var later: today.filter(e => !e.allDay && e.end > now)
	readonly property var next: later[0] ?? null
	// From a minute before an event to two after it starts, unless closed
	readonly property var reminder: later.find(e => e.start - now <= 60 * 1000 && now - e.start <= 2 * 60 * 1000 && !dismissed.includes(key(e))) ?? null
	// Reminders closed, by event
	property var dismissed: []

	function sameDay(ms: real): bool {
		return new Date(ms).toDateString() === new Date(now).toDateString();
	}

	function key(event: var): string {
		return event.start + " " + event.title;
	}

	// A title for where it shows: none on a screen being shared
	function title(event: var): string {
		return Sharing.active ? "Meeting" : event.title;
	}

	// "in 12m", "in 1h 5m", "now"
	function until(event: var): string {
		const minutes = Math.ceil((event.start - now) / 60000);
		if (minutes <= 0)
			return "now";
		if (minutes < 60)
			return "in " + minutes + "m";
		return "in " + Math.floor(minutes / 60) + "h" + (minutes % 60 ? " " + minutes % 60 + "m" : "");
	}

	function join(event: var) {
		if (event?.join)
			Desktop.launch(["xdg-open", event.join]);
	}

	function dismiss(event: var) {
		dismissed = dismissed.concat([key(event)]);
	}

	FileView {
		id: cache

		path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/islands/calendar.json"
		watchChanges: true
		printErrors: false
		onFileChanged: reload()
		onLoaded: {
			try {
				root.events = JSON.parse(text()).events;
			} catch (e) {
				console.warn("islands: can't read calendar.json:", e);
			}
		}
	}

	Process {
		id: fetch

		command: ["islands-calendar"]
		running: true
		stderr: SplitParser {
			onRead: line => console.warn("islands-calendar:", line)
		}
		// A first fetch makes the file, which wasn't there to watch
		onExited: code => {
			if (code === 0)
				cache.reload();
		}
	}

	Timer {
		interval: 5 * 60 * 1000
		repeat: true
		running: true
		onTriggered: fetch.running = true
	}

	Timer {
		interval: 10 * 1000
		repeat: true
		running: true
		onTriggered: root.now = Date.now()
	}
}
