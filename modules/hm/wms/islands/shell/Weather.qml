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
	// By the minute, on the minute, as the bar's clock is: a time the pill
	// shows has passed by when the clock reads the next minute
	readonly property real now: clock.date.getTime()
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
	// doesn't rise and set (a polar summer or winter).
	//
	// A twilight is a stretch of time: civil while the sun is up to 6° under
	// the horizon, nautical to 12°, astronomical to 18°, and night beyond.
	// The moment one ends is its dusk in the evening (civil dusk is when
	// civil twilight gives way to nautical) and its dawn in the morning,
	// when it begins.
	//
	// - stage: the stretch it is now ("Day", "Civil twilight", "Night", ...)
	// - next: {glyph, label, time} of the moment worth knowing next. By day
	//   that's sunset; through the evening each dusk in turn; once the last
	//   of them has passed, sunrise.
	// - steps: [{label, time}], this evening's moments (sunset and the dusks
	//   it has: far enough north, summer nights never get past a twilight),
	//   or the morning's (the dawns, then sunrise) once those are next
	// - stops: [{at, colour}], in order from 0 to 1, for a strip of today,
	//   midnight to midnight, with nowAt along it
	readonly property var sky: {
		const latitude = forecast?.lat;
		const longitude = forecast?.lon;
		if (typeof latitude !== "number" || typeof longitude !== "number")
			return null;
		const today = new Date(now);
		// A day's crossings, by its date and not 24 hours off: the days the
		// clocks change are 23 and 25 hours long
		const crossings = offset => {
			const date = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset, 12);
			const list = [];
			for (const zenith of [108, 102, 96, 90.833]) {
				for (const rising of [true, false]) {
					const time = sunCrossing(date, latitude, longitude, rising, zenith);
					if (!isNaN(time))
						list.push({
							time: time,
							rising: rising,
							zenith: zenith
						});
				}
			}
			return list;
		};
		// Two days either side: a place far from this clock's time zone (a
		// VPN's) has its sunrises on other dates than ours
		const events = [-2, -1, 0, 1, 2].reduce((all, offset) => all.concat(crossings(offset)), []).sort((a, b) => a.time - b.time);
		const isSun = event => event.zenith < 91;
		const past = events.filter(event => event.time <= now).reverse();
		const coming = events.filter(event => event.time > now);
		const sunrise = past.find(event => event.rising && isSun(event));
		const sunset = past.find(event => !event.rising && isSun(event));
		const nextSunrise = coming.find(event => event.rising && isSun(event));
		if (!sunrise || !sunset || !nextSunrise)
			return null;
		// What's left of the evening: sunset, or a dusk before the sun's back
		const dusk = coming.find(event => !event.rising && event.time < nextSunrise.time);
		const next = dusk ?? nextSunrise;
		const steps = dusk ? events.filter(event => !event.rising && event.time > sunrise.time && event.time < nextSunrise.time) : events.filter(event => event.rising && event.time > sunset.time && event.time <= nextSunrise.time);

		// The strip: each stretch's colour where the day starts and ends in
		// one, each edge's where the sun crosses it, and clear sky from an
		// hour after sunrise to an hour before sunset
		const midnight = new Date(now).setHours(0, 0, 0, 0);
		const length = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1).getTime() - midnight;
		const shade = {
			"Night": "#10152e",
			"Astronomical twilight": "#1c2750",
			"Nautical twilight": "#4a4b8b",
			"Civil twilight": "#b08083",
			"Day": "#8fc9f2"
		};
		const edge = {
			"108": "#10152e",
			"102": "#27376f",
			"96": "#6c5fa6",
			"90.833": "#f3a15f"
		};
		const stageAt = time => begins(events.filter(event => event.time <= time).pop() ?? past[0]);
		const stops = [
			{
				at: 0,
				colour: shade[stageAt(midnight)]
			},
			{
				at: 1,
				colour: shade[stageAt(midnight + length)]
			}
		];
		for (const event of events) {
			const at = (event.time - midnight) / length;
			if (at <= 0 || at >= 1)
				continue;
			stops.push({
				at: at,
				colour: edge[event.zenith]
			});
			const clear = at + (event.rising ? 1 : -1) * 3600000 / length;
			if (isSun(event) && clear > 0 && clear < 1)
				stops.push({
					at: clear,
					colour: shade["Day"]
				});
		}
		return {
			stage: begins(past[0]),
			next: {
				glyph: isSun(next) ? (next.rising ? "sunrise" : "sunset") : ({
						"96": "civilDusk",
						"102": "nauticalDusk"
					})[next.zenith] ?? "moon",
				label: moment(next),
				time: next.time
			},
			steps: steps.map(event => ({
						label: moment(event),
						time: event.time
					})),
			stops: stops.sort((a, b) => a.at - b.at),
			nowAt: (now - midnight) / length
		};
	}

	// The stretch that begins as the sun crosses there: coming up, each
	// lighter twilight and then the day; going down, each deeper one and
	// then the night
	function begins(event: var): string {
		const names = ["Astronomical twilight", "Nautical twilight", "Civil twilight"];
		const step = [108, 102, 96, 90.833].indexOf(event.zenith);
		return event.rising ? (names[step] ?? "Day") : (names[step - 1] ?? "Night");
	}

	// The moment itself: sunrise or sunset, or a twilight's far edge, which
	// is its dawn coming up and its dusk going down
	function moment(event: var): string {
		if (event.zenith < 91)
			return event.rising ? "Sunrise" : "Sunset";
		return ({
				"96": "Civil",
				"102": "Nautical",
				"108": "Astronomical"
			})[event.zenith] + (event.rising ? " dawn" : " dusk");
	}

	// When (ms) the sun crosses `zenith` degrees from overhead in the
	// morning (rising) or the evening of `date`: 90.833 is sunrise and
	// sunset, 96, 102 and 108 the civil, nautical and astronomical
	// twilights' far edges. NaN if it doesn't. The Almanac for Computers'
	// method, within a minute or two of the published times.
	function sunCrossing(date: date, latitude: real, longitude: real, rising: bool, zenith: real): real {
		const rad = Math.PI / 180;
		const start = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
		const day = Math.round((start - Date.UTC(date.getFullYear(), 0, 0)) / 86400000);
		const lngHour = longitude / 15;
		// About when: 6 in the morning or the evening, by the sun, there
		const about = (rising ? 6 : 18) - lngHour;
		const t = day + about / 24;
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
		// The method gives an hour of the day, not which day: it's the one
		// nearest `about`, which a dusk in a short summer night runs past
		// midnight from (and so into the next local day)
		return start + (utc + 24 * Math.round((about - utc) / 24)) * 3600000;
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
			if (!fetch.running && (!root.forecast || Date.now() / 1000 - root.forecast.fetched >= 15 * 60))
				fetch.running = true;
		}
	}
}
