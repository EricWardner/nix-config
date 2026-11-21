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

	// {fetched, place, lat, lon, now: {temp, feels, code, day}, hours: [{time, temp,
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

	// The sun's day here, worked out from where the forecast is for (no
	// service has the twilights). Null without a place, or where the sun
	// doesn't go through all of it that day (far north, in summer).
	//
	// - stage: what it is now ("Day", "Civil twilight", "Night", ...)
	// - next: {glyph, label, time} of the change worth knowing next. By day
	//   that's sunset; through the evening each deeper twilight in turn,
	//   then night; from then until morning, sunrise.
	// - steps: [{label, time}], the four of this evening (sunset, the two
	//   deeper twilights, night) or, once it's night, of the morning
	// - stops: [{at, colour}] for a strip of today, midnight to midnight,
	//   with sunrise, sunset and nowAt along it (0 to 1)
	readonly property var sky: {
		const latitude = forecast?.lat;
		const longitude = forecast?.lon;
		if (typeof latitude !== "number" || typeof longitude !== "number")
			return null;
		const day = 86400000;
		const crossings = date => {
			const list = [];
			for (const zenith of [108, 102, 96, 90.833]) {
				for (const rising of [true, false])
					list.push({
						time: sunCrossing(date, latitude, longitude, rising, zenith),
						rising: rising,
						zenith: zenith
					});
			}
			return list;
		};
		const today = crossings(new Date(now));
		const events = today.concat(crossings(new Date(now - day)), crossings(new Date(now + day))).sort((a, b) => a.time - b.time);
		if (events.some(event => isNaN(event.time)))
			return null;
		const past = events.filter(event => event.time <= now);
		const coming = events.filter(event => event.time > now);
		const last = past[past.length - 1];
		const isSun = event => event.zenith < 91;
		const stage = begins(last);
		// The evening runs from sunrise until night has fallen
		const evening = stage === "Day" || (!last.rising && stage !== "Night");
		const next = stage === "Day" ? coming.find(event => !event.rising && isSun(event)) : evening ? coming[0] : coming.find(event => event.rising && isSun(event));
		const turned = past.slice().reverse().find(event => event.rising === evening);
		const midnight = new Date(now).setHours(0, 0, 0, 0);
		const at = (zenith, rising, shift) => {
			const event = today.find(event => event.zenith === zenith && event.rising === rising);
			return Math.min(1, Math.max(0, (event.time + shift - midnight) / day));
		};
		const hour = 3600000;
		return {
			stage: stage,
			next: {
				glyph: isSun(next) ? (next.rising ? "sunrise" : "sunset") : ({
						96: "nautical",
						102: "astronomical"
					})[next.zenith] ?? "moon",
				label: isSun(next) ? (next.rising ? "Sunrise" : "Sunset") : begins(next),
				time: next.time
			},
			steps: events.filter(event => event.rising !== evening && event.time > turned.time).slice(0, 4).map(event => ({
						label: isSun(event) ? (event.rising ? "Sunrise" : "Sunset") : begins(event).split(" ")[0],
						time: event.time
					})),
			stops: [[108, true, 0, "#10152e"], [102, true, 0, "#27376f"], [96, true, 0, "#6c5fa6"], [90.833, true, 0, "#f3a15f"], [90.833, true, hour, "#8fc9f2"], [90.833, false, -hour, "#8fc9f2"], [90.833, false, 0, "#f3a15f"], [96, false, 0, "#6c5fa6"], [102, false, 0, "#27376f"], [108, false, 0, "#10152e"]].map(([zenith, rising, shift, colour]) => ({
						at: at(zenith, rising, shift),
						colour: colour
					})),
			sunrise: at(90.833, true, 0),
			sunset: at(90.833, false, 0),
			nowAt: (now - midnight) / day
		};
	}

	// What begins as the sun crosses there: coming up, each lighter twilight
	// and then the day; going down, each deeper one and then the night
	function begins(event: var): string {
		const names = ["Astronomical twilight", "Nautical twilight", "Civil twilight"];
		const step = [108, 102, 96, 90.833].indexOf(event.zenith);
		return event.rising ? (names[step] ?? "Day") : (names[step - 1] ?? "Night");
	}

	// When (ms) the sun crosses `zenith` degrees from overhead on the local
	// day of `date`, rising or setting: 90.833 is sunrise and sunset, 96, 102
	// and 108 the civil, nautical and astronomical twilights' far edges. NaN
	// if it doesn't that day. The Almanac for Computers' method, within a
	// minute or two of the published times.
	function sunCrossing(date: date, latitude: real, longitude: real, rising: bool, zenith: real): real {
		const rad = Math.PI / 180;
		const midnight = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
		const day = Math.round((midnight - new Date(date.getFullYear(), 0, 0).getTime()) / 86400000);
		const lngHour = longitude / 15;
		const t = day + ((rising ? 6 : 18) - lngHour) / 24;
		const anomaly = 0.9856 * t - 3.289;
		const l = (anomaly + 1.916 * Math.sin(anomaly * rad) + 0.02 * Math.sin(2 * anomaly * rad) + 282.634 + 360) % 360;
		let ra = (Math.atan(0.91764 * Math.tan(l * rad)) / rad + 360) % 360;
		ra = (ra + Math.floor(l / 90) * 90 - Math.floor(ra / 90) * 90) / 15;
		const sinDec = 0.39782 * Math.sin(l * rad);
		const cosDec = Math.cos(Math.asin(sinDec));
		const cosH = (Math.cos(zenith * rad) - sinDec * Math.sin(latitude * rad)) / (cosDec * Math.cos(latitude * rad));
		if (cosH > 1 || cosH < -1)
			return NaN;
		const h = (rising ? 360 - Math.acos(cosH) / rad : Math.acos(cosH) / rad) / 15;
		const utc = (h + ra - 0.06571 * t - 6.622 - lngHour + 48) % 24;
		// That hour of the UTC day, moved onto the local one
		let time = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) + utc * 3600000;
		while (time < midnight)
			time += 86400000;
		while (time >= midnight + 86400000)
			time -= 86400000;
		return time;
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
