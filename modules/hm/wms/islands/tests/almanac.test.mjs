// Tests for shell/Almanac.js, the weather's pure logic: the sun's day and
// the rain outlook. Run with `node --test modules/hm/wms/islands/tests/*.test.mjs`, or
// `nix flake check` (checks.islands-almanac).
//
// Almanac.js is a QML JavaScript resource, so it has no exports: it's run
// in a context of its own here, and its functions read off that.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const almanac = vm.createContext({});
vm.runInContext(
  readFileSync(new URL("../shell/Almanac.js", import.meta.url), "utf8"),
  almanac,
);
const {
  sunCrossing,
  sky,
  begins,
  moment,
  until,
  between,
  outlook,
  summary,
  precipitation,
  wet,
} = almanac;

const minute = 60000;

// Dates read in `zone`, as the shell reads them in the machine's
function inZone(zone) {
  process.env.TZ = zone;
}

function local(year, month, day, hour = 12, min = 0) {
  return new Date(year, month - 1, day, hour, min).getTime();
}

function clock(time) {
  const date = new Date(time);
  return `${date.getHours()}:${String(date.getMinutes()).padStart(2, "0")}`;
}

// The sun's crossings in order have to walk the twilights one step at a
// time: down through civil, nautical and astronomical as it sets, and back
// up as it rises, turning back wherever a night stops short. A crossing
// put on the wrong day, or one counted twice, breaks the walk.
const zeniths = [90.833, 96, 102, 108];

function assertWalks(events, where) {
  let depth = null;
  let last = -Infinity;
  for (const event of events) {
    const step = zeniths.indexOf(event.zenith);
    const before = event.rising ? step + 1 : step;
    if (depth !== null)
      assert.equal(
        before,
        depth,
        `${where}: ${moment(event)} at ${new Date(event.time).toString()} doesn't follow on`,
      );
    assert.ok(event.time > last, `${where}: crossings out of order`);
    depth = event.rising ? step : step + 1;
    last = event.time;
  }
}

function everyDay(year, month, days, hours, check) {
  for (let day = 1; day <= days; day++)
    for (const hour of hours) check(local(year, month, day, hour));
}

// Sunrise and sunset, against the published times (timeanddate.com)

test("New York's solstice sunrise and sunset, to within 3 minutes", () => {
  inZone("America/New_York");
  const near = (time, hour, min) => {
    const published = new Date(time).setHours(hour, min, 0, 0);
    assert.ok(
      Math.abs(time - published) <= 3 * minute,
      `${clock(time)}, not ${hour}:${String(min).padStart(2, "0")}`,
    );
  };
  const june = new Date(2026, 5, 21, 12);
  near(sunCrossing(june, 40.7128, -74.006, true, 90.833), 5, 25);
  near(sunCrossing(june, 40.7128, -74.006, false, 90.833), 20, 31);
  const december = new Date(2026, 11, 21, 12);
  near(sunCrossing(december, 40.7128, -74.006, true, 90.833), 7, 17);
  near(sunCrossing(december, 40.7128, -74.006, false, 90.833), 16, 32);
});

test("No sunset in a polar summer, no sunrise in a polar winter", () => {
  inZone("Europe/Oslo");
  const june = new Date(2026, 5, 21, 12);
  assert.ok(Number.isNaN(sunCrossing(june, 69.65, 18.96, false, 90.833)));
  const december = new Date(2026, 11, 21, 12);
  assert.ok(Number.isNaN(sunCrossing(december, 69.65, 18.96, true, 90.833)));
  assert.equal(sky(69.65, 18.96, local(2026, 6, 21)), null);
  assert.equal(sky(69.65, 18.96, local(2026, 12, 21)), null);
});

// The walk, through the cases that have broken it

test("A year in New York walks the twilights, both clock changes included", () => {
  inZone("America/New_York");
  for (let month = 1; month <= 12; month++)
    everyDay(2026, month, 28, [0, 3, 12, 21, 23], (now) => {
      const day = sky(40.7128, -74.006, now);
      assert.ok(day, `no sky at ${new Date(now)}`);
      assertWalks(day.events, `New York ${new Date(now).toDateString()}`);
    });
  // The nights the clocks change, by the hour
  for (const [month, day] of [
    [3, 8],
    [11, 1],
  ])
    for (let hour = 0; hour < 24; hour++)
      assertWalks(
        sky(40.7128, -74.006, local(2026, month, day, hour)).events,
        `New York ${month}/${day} ${hour}:00`,
      );
});

test("An astronomical dusk after midnight stays with its evening", () => {
  // Thunder Bay, 48.4° N on Eastern time: in July the sky gets fully dark
  // only after midnight
  inZone("America/Toronto");
  // The 20th's evening: its last dusk is in the small hours of the 21st,
  // not the 20th's
  const crossing = sunCrossing(
    new Date(2026, 6, 20, 12),
    48.38,
    -89.25,
    false,
    108,
  );
  assert.equal(new Date(crossing).getDate(), 21, `${new Date(crossing)}`);
  const evening = local(2026, 7, 20, 21);
  const day = sky(48.38, -89.25, evening);
  const dusk = day.events.find(
    (event) => !event.rising && event.zenith === 108 && event.time > evening,
  );
  assert.ok(dusk, "no astronomical dusk that night");
  assert.equal(
    new Date(dusk.time).getDate(),
    21,
    `astronomical dusk at ${new Date(dusk.time)}`,
  );
  assert.equal(day.end, dusk.time);
  everyDay(2026, 7, 31, [0, 1, 12, 22, 23], (now) =>
    assertWalks(sky(48.38, -89.25, now).events, `Thunder Bay ${new Date(now)}`),
  );
});

test("A summer night that never gets past a twilight still has a day", () => {
  // Edinburgh in June: no astronomical dusk at all
  inZone("Europe/London");
  const late = local(2026, 6, 21, 23);
  const day = sky(55.95, -3.19, late);
  assert.ok(day);
  assert.ok(!day.events.some((event) => event.zenith === 108));
  assert.ok(day.next.time > late);
  everyDay(2026, 6, 30, [0, 2, 12, 23], (now) => {
    const day = sky(55.95, -3.19, now);
    assert.ok(day, `no sky at ${new Date(now)}`);
    assertWalks(day.events, `Edinburgh ${new Date(now)}`);
  });
});

test("A place far from the clock's zone (a VPN's) has its day", () => {
  // Tokyo, read on New York's clock
  inZone("America/New_York");
  everyDay(2026, 3, 31, [0, 6, 12, 18, 23], (now) => {
    const day = sky(35.68, 139.69, now);
    assert.ok(day, `no sky at ${new Date(now)}`);
    assert.ok(day.next.time > now);
    assertWalks(day.events, `Tokyo ${new Date(now)}`);
  });
});

// What the pill and the forecast say

test("The next moment: sunset by day, each dusk, then sunrise", () => {
  inZone("America/New_York");
  const at = (hour, min = 0) =>
    sky(40.7128, -74.006, local(2026, 6, 21, hour, min));
  assert.equal(at(15).next.label, "Sunset");
  assert.equal(at(15).next.glyph, "sunset");
  assert.equal(at(15).stage, "Day");
  assert.equal(at(20, 45).next.label, "Civil dusk");
  assert.equal(at(20, 45).next.glyph, "civilDusk");
  assert.equal(at(20, 45).stage, "Civil twilight");
  assert.equal(at(21, 30).next.label, "Nautical dusk");
  assert.equal(at(21, 30).next.glyph, "nauticalDusk");
  assert.equal(at(22, 15).next.label, "Astronomical dusk");
  assert.equal(at(22, 15).next.glyph, "moon");
  assert.equal(at(23, 30).next.label, "Sunrise");
  assert.equal(at(23, 30).stage, "Night");
  // The line runs to the last of the evening, then to sunrise
  assert.equal(
    at(20, 45).end,
    at(20, 45).events.find(
      (event) =>
        event.zenith === 108 &&
        !event.rising &&
        event.time > local(2026, 6, 21, 20),
    ).time,
  );
  assert.equal(at(23, 30).end, at(23, 30).next.time);
});

test("Until: minutes, then hours and minutes, and nothing once it's passed", () => {
  const time = local(2026, 6, 21, 20, 30);
  assert.equal(until(time, time - 12 * minute), "in 12m");
  assert.equal(until(time, time - 59 * minute), "in 59m");
  assert.equal(until(time, time - 60 * minute), "in 1h");
  assert.equal(until(time, time - 65 * minute), "in 1h 5m");
  assert.equal(until(time, time - 582 * minute), "in 9h 42m");
  assert.equal(until(time, time), "now");
  assert.equal(until(time, time + 5 * minute), "");
});

test("Until adds up with the clock: a sunset at 8:30:23 is 8:30's", () => {
  const sunset = local(2026, 6, 21, 20, 30) + 23000;
  const at = (hour, min) => until(sunset, local(2026, 6, 21, hour, min));
  // 6:58 and 1h 32m make 8:30, the time the sunset is listed at
  assert.equal(at(18, 58), "in 1h 32m");
  assert.equal(at(20, 29), "in 1m");
  assert.equal(at(20, 30), "now");
  assert.equal(at(20, 31), "");
});

test("The stretches and the moments are named", () => {
  assert.equal(moment({ zenith: 90.833, rising: true }), "Sunrise");
  assert.equal(moment({ zenith: 90.833, rising: false }), "Sunset");
  assert.equal(moment({ zenith: 96, rising: false }), "Civil dusk");
  assert.equal(moment({ zenith: 108, rising: true }), "Astronomical dawn");
  assert.equal(begins({ zenith: 90.833, rising: true }), "Day");
  assert.equal(begins({ zenith: 90.833, rising: false }), "Civil twilight");
  assert.equal(begins({ zenith: 96, rising: false }), "Nautical twilight");
  assert.equal(begins({ zenith: 108, rising: false }), "Night");
  assert.equal(begins({ zenith: 108, rising: true }), "Astronomical twilight");
});

// The colour frames

test("Between frames: the two either side, and how far along", () => {
  const frames = [
    [0, "a"],
    [10, "b"],
    [10, "c"],
    [20, "d"],
  ];
  assert.deepEqual(
    { ...between(frames, 5) },
    { from: frames[0], to: frames[1], part: 0.5 },
  );
  // On a frame: the pair that ends there, all the way along
  assert.deepEqual(
    { ...between(frames, 10) },
    { from: frames[0], to: frames[1], part: 1 },
  );
  assert.deepEqual(
    { ...between(frames, 15) },
    { from: frames[2], to: frames[3], part: 0.5 },
  );
  assert.equal(between([], 5), null);
});

test("Past the last frame it's the last colour, before the first the first", () => {
  const frames = [
    [0, "a"],
    [10, "b"],
  ];
  assert.equal(between(frames, 25).from[1], "b");
  assert.equal(between(frames, 25).to[1], "b");
  assert.equal(between(frames, -5).from[1], "a");
});

// Rain

const hourly = (rows) =>
  rows.map(([time, code, rain]) => ({ time, code, rain }));
const hour = (time) => `${time}h`;

test("Dry hours: no outlook", () => {
  const coming = outlook(
    { code: 2 },
    hourly([
      [1, 3, 10],
      [2, 2, 0],
    ]),
  );
  assert.equal(coming, null);
  assert.equal(summary(coming, hour), "Dry for the next 12 hours.");
});

test("Rain coming: when it starts, and its peak", () => {
  const coming = outlook(
    { code: 2 },
    hourly([
      [1, 3, 10],
      [2, 61, 60],
      [3, 63, 80],
      [4, 61, 40],
      [5, 3, 10],
      [6, 63, 95],
    ]),
  );
  assert.equal(coming.kind, "Rain");
  assert.equal(coming.starts, 2);
  // The peak of that spell, not of a later one
  assert.equal(coming.peak.time, 3);
  assert.equal(summary(coming, hour), "Rain from 2h, up to 80% at 3h.");
});

test("A peak at the start isn't timed twice; a low one isn't given", () => {
  assert.equal(
    summary(
      outlook(
        { code: 1 },
        hourly([
          [1, 61, 70],
          [2, 61, 30],
        ]),
      ),
      hour,
    ),
    "Rain from 1h, up to 70%.",
  );
  assert.equal(
    summary(outlook({ code: 1 }, hourly([[1, 51, 10]])), hour),
    "Rain from 1h.",
  );
});

test("Falling now: until when, or for all the hours there are", () => {
  const stops = outlook(
    { code: 73 },
    hourly([
      [1, 73, 90],
      [2, 71, 60],
      [3, 3, 10],
    ]),
  );
  assert.equal(stops.kind, "Snow");
  assert.equal(stops.stops, 3);
  assert.equal(summary(stops, hour), "Snow until 3h.");
  const keeps = outlook({ code: 95 }, hourly([[1, 95, 90]]));
  assert.equal(keeps.stops, null);
  assert.equal(summary(keeps, hour), "Storms for the next 12 hours.");
});

test("What falls: by the code, or a likely chance under a dry code", () => {
  assert.equal(precipitation(0), "");
  assert.equal(precipitation(51), "Rain");
  assert.equal(precipitation(75), "Snow");
  assert.equal(precipitation(86), "Snow");
  assert.equal(precipitation(80), "Rain");
  assert.equal(precipitation(99), "Storms");
  assert.equal(wet({ code: 3, rain: 50 }), "Rain");
  assert.equal(wet({ code: 3, rain: 49 }), "");
});
