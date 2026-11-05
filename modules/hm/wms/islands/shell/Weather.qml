pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The forecast where this machine's IP address places it, from
// islands-weather: located once the shell starts, then fetched every 15
// minutes into a cache read here, so it shows at once on a restart. Nothing
// shows once it's three hours old.
Singleton {
	id: root

	// {fetched, place, now: {temp, feels, code, day}, hours: [{time, temp,
	// code, day, rain}], days: [{time, code, high, low, rain}]}: times in
	// seconds, codes WMO's, rain the chance in percent
	property var forecast: null
	property real now: Date.now()
	readonly property bool ready: forecast !== null && now / 1000 - forecast.fetched < 3 * 3600
	readonly property var current: ready ? forecast.now : null
	readonly property var hours: ready ? forecast.hours.filter(hour => hour.time * 1000 > now) : []
	readonly property var days: ready ? forecast.days : []
	readonly property string place: ready ? forecast.place ?? "" : ""
	readonly property string updated: ready ? Qt.formatTime(new Date(forecast.fetched * 1000), "h:mm AP") : ""

	// Rain or snow coming in the next hours ({kind, starts, peak}), or
	// falling now ({kind, stops}, stops null if it doesn't within them);
	// null if they're dry
	readonly property var outlook: {
		if (!current)
			return null;
		const falling = precipitation(current.code);
		if (falling) {
			const dry = hours.find(hour => !wet(hour));
			return {
				kind: falling,
				stops: dry?.time ?? null
			};
		}
		const start = hours.findIndex(hour => wet(hour));
		if (start < 0)
			return null;
		let peak = hours[start];
		for (let i = start; i < hours.length && wet(hours[i]); i++) {
			if (hours[i].rain > peak.rain)
				peak = hours[i];
		}
		return {
			kind: wet(hours[start]),
			starts: hours[start].time,
			peak: peak
		};
	}
	// "Rain from 6 PM, up to 80% at 7 PM."
	readonly property string summary: {
		const coming = outlook;
		if (!coming)
			return "Dry for the next 12 hours.";
		if (!coming.starts)
			return coming.stops ? coming.kind + " until " + hour(coming.stops) + "." : coming.kind + " for the next 12 hours.";
		let text = coming.kind + " from " + hour(coming.starts);
		if (coming.peak.rain >= 20)
			text += ", up to " + coming.peak.rain + "%" + (coming.peak.time !== coming.starts ? " at " + hour(coming.peak.time) : "");
		return text + ".";
	}
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

	function deg(temperature: real): string {
		return Math.round(temperature) + "°";
	}

	function hour(seconds: real): string {
		return Qt.formatTime(new Date(seconds * 1000), "h AP");
	}

	// "Rain", "Snow" or "Storms" for a code that falls; "" for one that doesn't
	function precipitation(code: int): string {
		if (code >= 95)
			return "Storms";
		if ((code >= 71 && code <= 77) || code === 85 || code === 86)
			return "Snow";
		return code >= 51 ? "Rain" : "";
	}

	// An hour likely wet, though its code (the likeliest weather) is dry
	function wet(hour: var): string {
		return precipitation(hour.code) || (hour.rain >= 50 ? "Rain" : "");
	}

	function glyph(code: int, day: bool): string {
		if (code <= 1)
			return day ? "sun" : "moon";
		if (code === 2)
			return day ? "partlyDay" : "partlyNight";
		if (code === 3)
			return "cloud";
		if (code < 51)
			return "fog";
		if (code < 60)
			return "drizzle";
		if (code >= 95)
			return "storm";
		return precipitation(code) === "Snow" ? "snow" : "rain";
	}

	function label(code: int, day: bool): string {
		return ({
				0: day ? "Sunny" : "Clear",
				1: day ? "Mostly sunny" : "Mostly clear",
				2: "Partly cloudy",
				3: "Cloudy",
				45: "Fog",
				48: "Fog",
				51: "Drizzle",
				53: "Drizzle",
				55: "Drizzle",
				56: "Freezing drizzle",
				57: "Freezing drizzle",
				61: "Light rain",
				63: "Rain",
				65: "Heavy rain",
				66: "Freezing rain",
				67: "Freezing rain",
				71: "Light snow",
				73: "Snow",
				75: "Heavy snow",
				77: "Snow",
				80: "Showers",
				81: "Showers",
				82: "Heavy showers",
				85: "Snow showers",
				86: "Snow showers",
				95: "Thunderstorms",
				96: "Thunderstorms and hail",
				99: "Thunderstorms and hail"
			})[code] ?? "";
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

	Process {
		id: fetch

		property bool located: false

		command: ["islands-weather"].concat(located ? [] : ["--locate"])
		running: true
		stderr: SplitParser {
			onRead: line => console.warn("islands-weather:", line)
		}
		onExited: code => {
			if (code !== 0)
				return;
			located = true;
			cache.reload();
		}
	}

	// Fetched again once it's 15 minutes old, by the clock: a Timer doesn't
	// count time asleep, so one 15 minutes long left the forecast hidden for
	// most of that after waking. Also tries a failed fetch again, as one on
	// waking fails until the network is back.
	Timer {
		interval: 60 * 1000
		repeat: true
		running: true
		onTriggered: {
			root.now = Date.now();
			if (!fetch.running && (!root.forecast || root.now / 1000 - root.forecast.fetched >= 15 * 60))
				fetch.running = true;
		}
	}
}
