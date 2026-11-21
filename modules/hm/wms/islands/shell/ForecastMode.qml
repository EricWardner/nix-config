import QtQuick

// The weather island grown: now, the next seven hours, the sun's day and the
// next five days, on the sky of the hour (the day's blue, a sunset, each
// twilight, the night) in place of the glass. A click on it, Esc or a click
// outside closes it.
IslandMode {
	id: root

	readonly property var now: Weather.current
	readonly property var today: Weather.days[0] ?? null
	readonly property var hours: now ? [
		{
			label: "Now",
			glyph: Weather.glyph(now.code, now.day),
			temp: now.temp,
			rain: 0
		}
	].concat(Weather.hours.slice(0, 7).map(hour => ({
				label: Weather.hour(hour.time),
				glyph: Weather.glyph(hour.code, hour.day),
				temp: hour.temp,
				rain: hour.rain
			}))) : []
	// The week's range, which each day's bar sits within
	readonly property real lowest: Math.min(...Weather.days.map(day => day.low))
	readonly property real highest: Math.max(...Weather.days.map(day => day.high))

	// The sky now, top and bottom (Weather.sky's); without a place, the
	// glass is left as it is
	readonly property var sky: Weather.sky
	readonly property color skyTop: sky ? Weather.shade(sky.skyFrames, Weather.now, 1) : "transparent"
	readonly property color skyBottom: sky ? Weather.shade(sky.skyFrames, Weather.now, 2) : "transparent"

	// Whether the sky is light `part` of the way down the panel, which
	// only the day's is: what's there is inked dark on it, and white on
	// the rest
	function light(part: real): bool {
		if (!sky)
			return true;
		const here = Weather.mix(skyTop, skyBottom, part);
		return 0.2126 * here.r + 0.7152 * here.g + 0.0722 * here.b > 0.47;
	}

	function ink(part: real): color {
		return light(part) ? Theme.ink : "white";
	}

	function dim(part: real): color {
		return Theme.alpha(ink(part), light(part) ? 0.75 : 0.8);
	}

	function blue(part: real): color {
		return light(part) ? Theme.inkBlue : "#bcd0ff";
	}

	priority: 40
	cornerRadius: 24
	islandWidth: 392
	islandHeight: column.implicitHeight + 32
	fill: sky ? gradient : null

	focus: current
	onCurrentChanged: if (current)
		forceActiveFocus()

	Keys.onEscapePressed: Desktop.closePanel()

	Gradient {
		id: gradient

		GradientStop {
			position: 0
			color: root.skyTop
		}
		GradientStop {
			position: 1
			color: root.skyBottom
		}
	}

	MouseArea {
		anchors.fill: parent
		onClicked: Desktop.closePanel()
	}

	Column {
		id: column

		x: 20
		y: 18
		width: parent.width - 40
		spacing: 14

		Row {
			spacing: 14

			WeatherIcon {
				anchors.verticalCenter: parent.verticalCenter
				glyph: root.now ? Weather.glyph(root.now.code, root.now.day) : "cloud"
				size: 44
				strokeWidth: 1.6
				onInk: root.light(0.08)
				color: root.ink(0.08)
			}

			BarText {
				anchors.verticalCenter: parent.verticalCenter
				text: root.now ? Weather.deg(root.now.temp) : ""
				color: root.ink(0.08)
				font.family: "SF Pro Display"
				font.pixelSize: 46
				font.weight: Font.Light
				font.features: {
					"tnum": 1
				}
			}

			Column {
				anchors.verticalCenter: parent.verticalCenter
				leftPadding: 2
				spacing: 3

				BarText {
					text: root.now ? Weather.label(root.now.code, root.now.day) : ""
					color: root.ink(0.08)
					font.pixelSize: 15
					font.weight: Font.DemiBold
				}

				BarText {
					text: root.now && root.today ? "Feels " + Weather.deg(root.now.feels) + " · H " + Weather.deg(root.today.high) + " L " + Weather.deg(root.today.low) : ""
					color: root.dim(0.08)
					font.pixelSize: 13
				}
			}
		}

		BarText {
			width: parent.width
			text: Weather.summary
			color: root.ink(0.18)
			font.pixelSize: 13
			wrapMode: Text.Wrap
		}

		Row {
			Repeater {
				model: root.hours

				Item {
					id: hour

					required property var modelData
					required property int index

					width: column.width / 8
					height: slot.implicitHeight

					Rectangle {
						anchors.fill: parent
						radius: 12
						color: Theme.alpha(root.ink(0.3), root.light(0.3) ? 0.06 : 0.14)
						visible: hour.index === 0
					}

					Column {
						id: slot

						width: parent.width
						topPadding: 6
						bottomPadding: 6
						spacing: 6

						BarText {
							anchors.horizontalCenter: parent.horizontalCenter
							text: hour.modelData.label
							color: root.dim(0.3)
							font.pixelSize: 12
							font.weight: hour.index === 0 ? Font.DemiBold : Font.Normal
						}

						WeatherIcon {
							anchors.horizontalCenter: parent.horizontalCenter
							glyph: hour.modelData.glyph
							size: 20
							onInk: root.light(0.3)
							color: root.ink(0.3)
						}

						BarText {
							anchors.horizontalCenter: parent.horizontalCenter
							text: Weather.deg(hour.modelData.temp)
							color: root.ink(0.3)
							font.pixelSize: 14
							font.features: {
								"tnum": 1
							}
						}

						BarText {
							anchors.horizontalCenter: parent.horizontalCenter
							height: 13
							text: hour.modelData.rain >= 20 ? hour.modelData.rain + "%" : ""
							color: root.blue(0.3)
							font.pixelSize: 11
							font.weight: Font.DemiBold
						}
					}
				}
			}
		}

		Rectangle {
			width: parent.width
			height: 1
			color: Theme.alpha(root.ink(0.5), root.light(0.5) ? 0.14 : 0.25)
		}

		// The sun's day (Weather.sky): the moment that's next and the stretch
		// it is now, over a line of the hours in the sky's colours. The line
		// runs from now (the sun, a sixth of the way along) to a little past
		// the last of what's coming: the evening's last dusk, or sunrise
		// once the dusks are done. So it looks only as far ahead as there's
		// something to see, the moments come towards the sun as their time
		// does, and the nearer the last one is the further apart they are.
		// What's passed is squeezed up behind the sun, harder the older it
		// is, until it's two hours gone.
		Column {
			id: sun

			readonly property real minute: 60000
			readonly property real ahead: root.sky ? root.sky.end + 15 * minute - Weather.now : 60 * minute
			// Eased: as night falls, and as the sun comes up, the last of
			// what's coming is suddenly half a day off
			property real span: ahead
			readonly property real back: 120 * minute
			readonly property real squeeze: 8 * minute
			readonly property real lead: Math.round(width * 0.16)
			readonly property var shown: root.sky ? root.sky.events.filter(event => event.time > Weather.now - back && event.time < Weather.now + span) : []
			readonly property color inked: root.ink(0.6)

			// How far along the line a time is: evenly ahead of now, and on a
			// log scale behind it
			function along(time: real): real {
				if (time >= Weather.now)
					return lead + (time - Weather.now) / span * (width - lead);
				return lead * (1 - Math.log(1 + Math.min(back, Weather.now - time) / squeeze) / Math.log(1 + back / squeeze));
			}

			width: parent.width
			spacing: 12
			visible: root.sky !== null

			Behavior on span {
				enabled: root.current

				NumberAnimation {
					duration: 700
					easing.type: Easing.OutCubic
				}
			}

			Row {
				spacing: 10

				WeatherIcon {
					anchors.verticalCenter: parent.verticalCenter
					glyph: root.sky?.next.glyph ?? "sunset"
					size: 22
					onInk: root.light(0.52)
					color: root.ink(0.52)
				}

				Column {
					anchors.verticalCenter: parent.verticalCenter
					spacing: 2

					BarText {
						text: root.sky ? root.sky.next.label + " " + Weather.clock(root.sky.next.time) : ""
						color: root.ink(0.52)
						font.pixelSize: 14
						font.weight: Font.DemiBold
						font.features: {
							"tnum": 1
						}
					}

					BarText {
						readonly property int minutes: root.sky ? Math.max(1, Math.round((root.sky.next.time - Weather.now) / sun.minute)) : 0

						text: root.sky ? "Now: " + root.sky.stage.toLowerCase() + " · in " + (minutes >= 60 ? Math.floor(minutes / 60) + " h " + minutes % 60 + " min" : minutes + " min") : ""
						color: root.dim(0.52)
						font.pixelSize: 12
					}
				}
			}

			Item {
				width: parent.width
				height: 54

				// The stretches, each named over its part of the line where
				// that's wide enough for the name
				Repeater {
					model: {
						if (!root.sky)
							return [];
						const edge = Weather.now - sun.back;
						const before = root.sky.events.filter(event => event.time <= edge).pop();
						const bounds = [
							{
								time: edge,
								name: before ? Weather.begins(before) : ""
							}
						].concat(sun.shown.map(event => ({
									time: event.time,
									name: Weather.begins(event)
								})));
						const names = [];
						bounds.forEach((bound, i) => {
							const from = sun.along(bound.time);
							const to = i + 1 < bounds.length ? sun.along(bounds[i + 1].time) : sun.width;
							if (to - from >= 58)
								names.push({
									x: from,
									width: to - from,
									name: bound.name.split(" ")[0].toLowerCase()
								});
						});
						return names;
					}

					BarText {
						required property var modelData

						x: modelData.x
						width: modelData.width
						horizontalAlignment: Text.AlignHCenter
						text: modelData.name
						color: sun.inked
						font.pixelSize: 11
					}
				}

				Canvas {
					id: strip

					// The line's colours, each where it falls: colours change
					// evenly with time, which the squeezed part doesn't, so
					// that part is sampled
					readonly property var marks: {
						if (!root.sky)
							return [];
						const from = Weather.now - sun.back;
						const to = Weather.now + sun.span;
						const times = [1, 0.7, 0.45, 0.28, 0.16, 0.08, 0.03, 0].map(part => Weather.now - sun.back * part).concat(root.sky.lineFrames.map(frame => frame[0]).filter(time => time > from && time < to), [to]);
						return times.sort((a, b) => a - b).map(time => ({
									at: Math.min(1, Math.max(0, sun.along(time) / sun.width)),
									colour: "" + Weather.shade(root.sky.lineFrames, time, 1)
								}));
					}
					readonly property color rim: Theme.alpha(sun.inked, 0.6)

					y: 20
					width: parent.width
					height: 12
					onMarksChanged: requestPaint()
					onRimChanged: requestPaint()
					onPaint: {
						const ctx = getContext("2d");
						ctx.reset();
						if (marks.length < 2)
							return;
						const colours = ctx.createLinearGradient(0, 0, width, 0);
						for (const mark of marks)
							colours.addColorStop(mark.at, mark.colour);
						ctx.fillStyle = colours;
						ctx.beginPath();
						ctx.roundedRect(0, 0, width, height, height / 2, height / 2);
						ctx.fill();
						ctx.strokeStyle = "" + rim;
						ctx.lineWidth = 1;
						ctx.beginPath();
						ctx.roundedRect(0.5, 0.5, width - 1, height - 1, height / 2 - 0.5, height / 2 - 0.5);
						ctx.stroke();
					}
				}

				// The moments: a dot each, which shrinks once it's passed and
				// has faded out by the time it's two hours gone
				Repeater {
					model: sun.shown

					Rectangle {
						required property var modelData
						readonly property bool gone: modelData.time <= Weather.now

						x: sun.along(modelData.time) - width / 2
						y: 26 - height / 2
						width: gone ? 6 : 10
						height: width
						radius: width / 2
						color: "white"
						border.width: gone ? 1 : 2
						border.color: "#10152e"
						opacity: gone ? 0.75 * (1 - Math.min(1, (Weather.now - modelData.time) / sun.back)) : 1
					}
				}

				// Now: the sun, or the moon once it's night
				Rectangle {
					x: sun.lead - width / 2
					y: 26 - height / 2
					width: 22
					height: 22
					radius: 11
					color: root.sky?.stage === "Night" ? "#e9e6ff" : "#ffd27a"
					border.width: 2
					border.color: "#10152e"
				}

				// The times of those to come: the next one's first, then any
				// other that's clear of the ones placed
				Repeater {
					model: {
						if (!root.sky)
							return [];
						const coming = sun.shown.filter(event => event.time > Weather.now);
						const next = coming.find(event => event.time === root.sky.next.time);
						const placed = [];
						const times = [];
						for (const event of (next ? [next] : []).concat(coming.filter(event => event !== next))) {
							const at = sun.along(event.time);
							if (placed.every(other => Math.abs(other - at) >= 36)) {
								placed.push(at);
								times.push({
									x: at,
									text: Weather.clock(event.time).replace(/ [AP]M$/, ""),
									next: event === next
								});
							}
						}
						return times;
					}

					BarText {
						required property var modelData

						x: modelData.x - width / 2
						y: 40
						text: modelData.text
						color: sun.inked
						font.pixelSize: 11
						font.weight: modelData.next ? Font.DemiBold : Font.Normal
						font.features: {
							"tnum": 1
						}
					}
				}
			}
		}

		Rectangle {
			width: parent.width
			height: 1
			color: Theme.alpha(root.ink(0.7), root.light(0.7) ? 0.14 : 0.25)
			visible: sun.visible
		}

		Column {
			width: parent.width
			spacing: 2

			Repeater {
				model: Weather.days

				Row {
					id: day

					required property var modelData
					required property int index

					height: 32
					spacing: 8

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						width: 56
						text: day.index === 0 ? "Today" : Qt.formatDate(new Date(day.modelData.time * 1000), "ddd")
						color: root.ink(0.85)
						font.pixelSize: 14
						font.weight: Font.Medium
					}

					WeatherIcon {
						anchors.verticalCenter: parent.verticalCenter
						width: 22
						glyph: Weather.glyph(day.modelData.code, true)
						size: 20
						onInk: root.light(0.85)
						color: root.ink(0.85)
					}

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						width: 40
						text: day.modelData.rain >= 20 ? day.modelData.rain + "%" : ""
						color: root.blue(0.85)
						font.pixelSize: 11
						font.weight: Font.DemiBold
					}

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						width: 34
						horizontalAlignment: Text.AlignRight
						text: Weather.deg(day.modelData.low)
						color: root.dim(0.85)
						font.pixelSize: 14
						font.features: {
							"tnum": 1
						}
					}

					Rectangle {
						anchors.verticalCenter: parent.verticalCenter
						width: column.width - 56 - 22 - 40 - 34 - 34 - 5 * 8
						height: 4
						radius: 2
						color: Theme.alpha(root.ink(0.85), root.light(0.85) ? 0.14 : 0.25)

						Rectangle {
							readonly property real span: Math.max(1, root.highest - root.lowest)

							x: parent.width * (day.modelData.low - root.lowest) / span
							width: parent.width * (day.modelData.high - day.modelData.low) / span
							height: parent.height
							radius: 2
							color: Theme.alpha(root.ink(0.85), root.light(0.85) ? 0.6 : 0.85)
						}
					}

					BarText {
						anchors.verticalCenter: parent.verticalCenter
						width: 34
						horizontalAlignment: Text.AlignRight
						text: Weather.deg(day.modelData.high)
						color: root.ink(0.85)
						font.pixelSize: 14
						font.features: {
							"tnum": 1
						}
					}
				}
			}
		}

		BarText {
			text: [Weather.place, "updated " + Weather.updated, "Open-Meteo"].filter(part => part).join(" · ")
			color: root.dim(0.97)
			font.pixelSize: 11
		}
	}
}
