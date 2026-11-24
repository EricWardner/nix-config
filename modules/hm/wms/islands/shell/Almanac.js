// The weather's pure logic, for Weather.qml: the sun's day worked out from a
// place and a time, and what the hours' forecast says about rain. Nothing
// here reads a clock or a file, so tests/almanac.test.mjs can run it under
// Node. Kept to plain functions (no exports, no Qt.*): it's imported as a
// QML JavaScript resource.

// Zeniths, in degrees from overhead: sunrise and sunset (the sun's edge on
// the horizon, with refraction), then the far edges of the civil, nautical
// and astronomical twilights
const zeniths = [108, 102, 96, 90.833];

// The sun's day at `latitude`, `longitude` around `now` (ms). Null where the
// sun doesn't rise and set (a polar summer or winter).
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
// - end: when the last of what's coming is: this evening's last dusk
//   (far enough north, summer nights never get past a twilight), or the
//   sunrise once the dusks are done
// - events: [{time, rising, zenith}], every crossing of two days either
//   side, in order
// - lineFrames, skyFrames: the colours through those days, for between():
//   [time, colour] along a line of the hours, and [time, top, bottom]
//   for a sky that fills something
function sky(latitude, longitude, now) {
  const today = new Date(now);
  // A day's crossings, by its date and not 24 hours off: the days the
  // clocks change are 23 and 25 hours long
  const crossings = (offset) => {
    const date = new Date(
      today.getFullYear(),
      today.getMonth(),
      today.getDate() + offset,
      12,
    );
    const list = [];
    for (const zenith of zeniths) {
      for (const rising of [true, false]) {
        const time = sunCrossing(date, latitude, longitude, rising, zenith);
        if (!isNaN(time))
          list.push({
            time: time,
            rising: rising,
            zenith: zenith,
          });
      }
    }
    return list;
  };
  // Two days either side: a place far from this clock's time zone (a
  // VPN's) has its sunrises on other dates than ours
  const events = [-2, -1, 0, 1, 2]
    .reduce((all, offset) => all.concat(crossings(offset)), [])
    .sort((a, b) => a.time - b.time);
  const isSun = (event) => event.zenith < 91;
  const past = events.filter((event) => event.time <= now).reverse();
  const coming = events.filter((event) => event.time > now);
  const sunrise = past.find((event) => event.rising && isSun(event));
  const sunset = past.find((event) => !event.rising && isSun(event));
  const nextSunrise = coming.find((event) => event.rising && isSun(event));
  if (!sunrise || !sunset || !nextSunrise) return null;
  // What's left of the evening: sunset, and each dusk before the sun's
  // back
  const dusks = coming.filter(
    (event) => !event.rising && event.time < nextSunrise.time,
  );
  const next = dusks[0] ?? nextSunrise;

  // The colours, by how far under the horizon the sun is at each
  // crossing: the line's there, and the sky's top and bottom. The
  // line is clear sky from an hour after sunrise to an hour before
  // sunset; the sky warms for half an hour either side of them, and is
  // the day's blue an hour beyond that.
  const palette = {
    108: ["#10152e", "#04050d", "#0b1030"],
    102: ["#27376f", "#060a1f", "#27376f"],
    96: ["#6c5fa6", "#0c1642", "#5b5aa0"],
    90.833: ["#f3a15f", "#24306b", "#b9604c"],
  };
  const minute = 60000;
  const lineFrames = [];
  const skyFrames = [];
  for (const event of events) {
    const colours = palette[event.zenith];
    lineFrames.push([event.time, colours[0]]);
    skyFrames.push([event.time, colours[1], colours[2]]);
    if (isSun(event)) {
      const way = event.rising ? 1 : -1;
      lineFrames.push([event.time + way * 60 * minute, "#8fc9f2"]);
      skyFrames.push([event.time + way * 30 * minute, "#2f66a8", "#ef9a5f"]);
      skyFrames.push([event.time + way * 90 * minute, "#4a98dc", "#9fd0f2"]);
    }
  }
  return {
    stage: begins(past[0]),
    next: {
      glyph: isSun(next)
        ? next.rising
          ? "sunrise"
          : "sunset"
        : ({
            96: "civilDusk",
            102: "nauticalDusk",
          }[next.zenith] ?? "moon"),
      label: moment(next),
      time: next.time,
    },
    end: (dusks[dusks.length - 1] ?? nextSunrise).time,
    events: events,
    lineFrames: lineFrames.sort((a, b) => a[0] - b[0]),
    skyFrames: skyFrames.sort((a, b) => a[0] - b[0]),
  };
}

// The two frames either side of `time` ({from, to}) and how far it is from
// one to the other (part, 0 to 1); null without frames. Before the first or
// after the last, it's that one.
function between(frames, time) {
  if (frames.length === 0) return null;
  const last = frames[frames.length - 1];
  if (time > last[0]) return { from: last, to: last, part: 0 };
  for (let i = 0; i < frames.length - 1; i++) {
    const a = frames[i];
    const b = frames[i + 1];
    if (time >= a[0] && time <= b[0])
      return {
        from: a,
        to: b,
        part: b[0] === a[0] ? 0 : (time - a[0]) / (b[0] - a[0]),
      };
  }
  return { from: frames[0], to: frames[0], part: 0 };
}

// The stretch that begins as the sun crosses there: coming up, each
// lighter twilight and then the day; going down, each deeper one and
// then the night
function begins(event) {
  const names = [
    "Astronomical twilight",
    "Nautical twilight",
    "Civil twilight",
  ];
  const step = zeniths.indexOf(event.zenith);
  return event.rising ? (names[step] ?? "Day") : (names[step - 1] ?? "Night");
}

// The moment itself: sunrise or sunset, or a twilight's far edge, which
// is its dawn coming up and its dusk going down
function moment(event) {
  if (event.zenith < 91) return event.rising ? "Sunrise" : "Sunset";
  return (
    {
      96: "Civil",
      102: "Nautical",
      108: "Astronomical",
    }[event.zenith] + (event.rising ? " dawn" : " dusk")
  );
}

// When (ms) the sun crosses `zenith` degrees from overhead in the
// morning (rising) or the evening of `date`: 90.833 is sunrise and
// sunset, 96, 102 and 108 the civil, nautical and astronomical
// twilights' far edges. NaN if it doesn't. The Almanac for Computers'
// method, within a minute or two of the published times.
function sunCrossing(date, latitude, longitude, rising, zenith) {
  const rad = Math.PI / 180;
  const start = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
  const day = Math.round(
    (start - Date.UTC(date.getFullYear(), 0, 0)) / 86400000,
  );
  const lngHour = longitude / 15;
  // About when: 6 in the morning or the evening, by the sun, there
  const about = (rising ? 6 : 18) - lngHour;
  const t = day + about / 24;
  const anomaly = 0.9856 * t - 3.289;
  const l =
    (anomaly +
      1.916 * Math.sin(anomaly * rad) +
      0.02 * Math.sin(2 * anomaly * rad) +
      282.634 +
      360) %
    360;
  let ra = (Math.atan(0.91764 * Math.tan(l * rad)) / rad + 360) % 360;
  ra = (ra + Math.floor(l / 90) * 90 - Math.floor(ra / 90) * 90) / 15;
  const sinDec = 0.39782 * Math.sin(l * rad);
  const cosDec = Math.cos(Math.asin(sinDec));
  const cosH =
    (Math.cos(zenith * rad) - sinDec * Math.sin(latitude * rad)) /
    (cosDec * Math.cos(latitude * rad));
  if (cosH > 1 || cosH < -1) return NaN;
  const h = (rising ? 360 - Math.acos(cosH) / rad : Math.acos(cosH) / rad) / 15;
  const utc = (h + ra - 0.06571 * t - 6.622 - lngHour + 48) % 24;
  // The method gives an hour of the day, not which day: it's the one
  // nearest `about`, which a dusk in a short summer night runs past
  // midnight from (and so into the next local day)
  return start + (utc + 24 * Math.round((about - utc) / 24)) * 3600000;
}

// Rain or snow coming in `hours` ({kind, starts, peak}), or falling now
// ({kind, stops}, stops null if it doesn't within them); null if they're
// dry. `current` and each hour are the forecast's: {code, rain, time}.
function outlook(current, hours) {
  const falling = precipitation(current.code);
  if (falling) {
    const dry = hours.find((hour) => !wet(hour));
    return {
      kind: falling,
      stops: dry?.time ?? null,
    };
  }
  const start = hours.findIndex((hour) => wet(hour));
  if (start < 0) return null;
  let peak = hours[start];
  for (let i = start; i < hours.length && wet(hours[i]); i++) {
    if (hours[i].rain > peak.rain) peak = hours[i];
  }
  return {
    kind: wet(hours[start]),
    starts: hours[start].time,
    peak: peak,
  };
}

// "Rain from 6 PM, up to 80% at 7 PM.", with each time put by `hour`
function summary(coming, hour) {
  if (!coming) return "Dry for the next 12 hours.";
  if (!coming.starts)
    return coming.stops
      ? coming.kind + " until " + hour(coming.stops) + "."
      : coming.kind + " for the next 12 hours.";
  let text = coming.kind + " from " + hour(coming.starts);
  if (coming.peak.rain >= 20)
    text +=
      ", up to " +
      coming.peak.rain +
      "%" +
      (coming.peak.time !== coming.starts
        ? " at " + hour(coming.peak.time)
        : "");
  return text + ".";
}

// "Rain", "Snow" or "Storms" for a code that falls; "" for one that doesn't
function precipitation(code) {
  if (code >= 95) return "Storms";
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "Snow";
  return code >= 51 ? "Rain" : "";
}

// An hour likely wet, though its code (the likeliest weather) is dry
function wet(hour) {
  return precipitation(hour.code) || (hour.rain >= 50 ? "Rain" : "");
}

function glyph(code, day) {
  if (code <= 1) return day ? "sun" : "moon";
  if (code === 2) return day ? "partlyDay" : "partlyNight";
  if (code === 3) return "cloud";
  if (code < 51) return "fog";
  if (code < 60) return "drizzle";
  if (code >= 95) return "storm";
  return precipitation(code) === "Snow" ? "snow" : "rain";
}

function label(code, day) {
  return (
    {
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
      99: "Thunderstorms and hail",
    }[code] ?? ""
  );
}
