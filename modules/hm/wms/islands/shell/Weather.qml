pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Almanac.js" as Almanac

// The forecast where this machine's IP address places it, from
// islands-weather: located as the shell starts and when the network changes,
// then fetched every 15 minutes into a cache read here, so it shows at once
// on a restart. Nothing shows once it's three hours old. The working out
// (the sun's day, the rain outlook) is in Almanac.js, which has tests.
Singleton {
	id: root

	// {fetched, place, lat, lon, now: {temp, feels, code, day}, hours: [{time, temp,
	// code, day, rain}], days: [{time, code, high, low, rain}]}: times in
	// seconds, codes WMO's, rain the chance in percent
	property var forecast: null
	// By the minute, on the minute, as the bar's clock is: a time the pill
	// shows has passed by when the clock reads the next minute
	readonly property real now: clock.date.getTime()
	readonly property bool ready: forecast !== null && now / 1000 - forecast.fetched < 3 * 3600
	readonly property var current: ready ? forecast.now : null
	readonly property var hours: ready ? forecast.hours.filter(hour => hour.time * 1000 > now) : []
	readonly property var days: ready ? forecast.days : []
	readonly property string place: ready ? forecast.place ?? "" : ""
	readonly property string updated: ready ? Qt.formatTime(new Date(forecast.fetched * 1000), "h:mm AP") : ""

	// Rain or snow coming in the next hours, or falling now (Almanac.outlook)
	readonly property var outlook: current ? Almanac.outlook(current, hours) : null
	// "Rain from 6 PM, up to 80% at 7 PM."
	readonly property string summary: Almanac.summary(outlook, seconds => hour(seconds))
	// "58°, partly cloudy · rain from 6 PM"
	readonly property string line: {
		if (!current)
			return "";
		let text = deg(current.temp) + ", " + label(current.code, current.day).toLowerCase();
		const coming = outlook;
		if (coming?.starts)
			text += " · " + coming.kind.toLowerCase() + " from " + hour(coming.starts);
		else if (coming?.stops)
			text += " · " + coming.kind.toLowerCase() + " until " + hour(coming.stops);
		return text;
	}

	// The sun's day where the forecast is for, worked out here as no service
	// has the twilights (Almanac.sky: {stage, next, end, events, lineFrames,
	// skyFrames}). Null without a place, or where the sun doesn't rise and set.
	readonly property var sky: typeof forecast?.lat === "number" && typeof forecast?.lon === "number" ? Almanac.sky(forecast.lat, forecast.lon, now) : null

	// The colour at `time` between the two frames either side of it, from
	// their column `index` (sky's lineFrames and skyFrames)
	function shade(frames: var, time: real, index: int): color {
		const at = Almanac.between(frames, time);
		return at ? mix(at.from[index], at.to[index], at.part) : "black";
	}

	function mix(from: color, to: color, part: real): color {
		return Qt.rgba(from.r + (to.r - from.r) * part, from.g + (to.g - from.g) * part, from.b + (to.b - from.b) * part, 1);
	}

	// The stretch that begins as the sun crosses there ("Day", "Night", ...)
	function begins(event: var): string {
		return Almanac.begins(event);
	}

	function clock(time: real): string {
		return Qt.formatTime(new Date(time), "h:mm AP");
	}

	function deg(temperature: real): string {
		return Math.round(temperature) + "°";
	}

	function hour(seconds: real): string {
		return Qt.formatTime(new Date(seconds * 1000), "h AP");
	}

	function glyph(code: int, day: bool): string {
		return Almanac.glyph(code, day);
	}

	function label(code: int, day: bool): string {
		return Almanac.label(code, day);
	}

	SystemClock {
		id: clock

		precision: SystemClock.Minutes
	}

	FileView {
		id: cache

		path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/islands/weather.json"
		printErrors: false
		onLoaded: {
			try {
				root.forecast = JSON.parse(text());
			} catch (e) {
				console.warn("islands: can't read weather.json:", e);
			}
		}
	}

	// The network it's on, to look for the machine again when that becomes
	// a different one, which may be a different place: not the first one
	// seen (the shell's start finds it anyway), nor the same one back
	// after a drop. A while after, for the connection (and a VPN on it) to
	// settle.
	readonly property string network: (Net.current?.name ?? "") + (Net.wired ? " wired" : "")
	property string lastNetwork: ""
	onNetworkChanged: {
		if (network === "")
			return;
		if (lastNetwork !== "" && network !== lastNetwork)
			moved.restart();
		lastNetwork = network;
	}

	Timer {
		id: moved

		interval: 20 * 1000
		onTriggered: fetch.relocate()
	}

	Process {
		id: fetch

		// Found on this shell's first fetch, then again when relocate()
		// asks: finding it is a request to a service that sees where from
		property bool located: false
		property bool again: false

		function relocate() {
			located = false;
			if (running)
				again = true;
			else
				running = true;
		}

		command: ["islands-weather"].concat(located ? [] : ["--locate"])
		running: true
		stderr: SplitParser {
			onRead: line => console.warn("islands-weather:", line)
		}
		onExited: code => {
			if (code === 0)
				cache.reload();
			// A relocate() came while this ran, which didn't look: the run
			// that does starts now, and only its success counts as found
			if (again) {
				again = false;
				running = true;
				return;
			}
			if (code === 0)
				located = true;
		}
	}

	// Fetched again once it's 15 minutes old, by the clock: a Timer doesn't
	// count time asleep, so one 15 minutes long left the forecast hidden for
	// most of that after waking. Also tries a failed fetch again, as one on
	// waking fails until the network is back. After an hour or more (asleep
	// in a bag, say) it may be somewhere else on a network of the same
	// name, a phone's, so that fetch looks for it again.
	Timer {
		interval: 60 * 1000
		repeat: true
		running: true
		onTriggered: {
			const age = root.forecast ? Date.now() / 1000 - root.forecast.fetched : Infinity;
			if (fetch.running || age < 15 * 60)
				return;
			if (age >= 3600)
				fetch.located = false;
			fetch.running = true;
		}
	}
}
