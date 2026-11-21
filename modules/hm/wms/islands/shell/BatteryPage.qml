import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The battery: its level and what it's doing, its charge over the last six
// hours (UPower's own history), the power profile, the machine's load, the
// apps using the most CPU (now, on battery, or today), and the battery's
// health. The history, the apps, the chip's power and the fan are read
// only while the page shows.
Column {
	id: root

	// On the control centre that's open, on this page
	property bool showing: false

	signal back

	readonly property real span: 6 * 3600
	// The battery itself: the display device has no history or health
	readonly property UPowerDevice battery: Array.from(UPower.devices.values).find(d => d.isLaptopBattery && d.nativePath !== "") ?? null
	// [{t, v}], oldest first
	property var history: []
	// [{name, icon, share}], the biggest first, once top has been read
	property var apps: []
	property bool appsRead: false
	// Which apps list shows: "now" (top's, of the whole CPU), or "battery"
	// or "today" (islands-usage's, of the CPU used then)
	property string view: "now"
	// The lists in the order the title steps through them, and which way it
	// last stepped (1 on, -1 back), for its roll
	readonly property var views: ["now", "battery", "today"]
	property int stepped: 1
	// islands-usage's report, null until read: {battery, today}, each
	// {from, to, apps: [{name, icon, share}]} (the battery's stretch also
	// ongoing, levelFrom, levelTo), or null for no time on battery yet
	property var usage: null
	readonly property var period: view === "now" || usage === null ? null : usage[view]
	readonly property var shownApps: view === "now" ? apps : period?.apps ?? []
	// -1 until read, or with no sensor (Host)
	property real power: -1 // W
	property int fan: -1 // rpm

	// "chrome", or ".claude-unwrapp" (a Nix wrapper's name, cut to 15
	// characters) as "claude", by its desktop entry where it has one; some
	// entries are named for neither the command nor the window. Docker's
	// daemons count as one app. islands-usage's names (cgroups': app IDs,
	// services, "docker" for the containers) go through here too.
	function app(command: string): var {
		const name = command.startsWith(".") ? command.slice(1).replace(/-(un)?wra?p?p?e?d?$/, "") : command;
		if (name === "nix-daemon")
			return {
				"name": "Nix builds",
				"icon": Quickshell.iconPath("nix-snowflake", true)
			};
		if (["pipewire", "pipewire-pulse", "wireplumber"].includes(name))
			return {
				"name": "PipeWire",
				"icon": ""
			};
		// Nix's Chromium, as browser automation runs it
		if (name === "org.chromium.Chromium")
			return {
				"name": "Chromium",
				"icon": Quickshell.iconPath("chromium", true)
			};
		if (name === "other")
			return {
				"name": "Other apps",
				"icon": ""
			};
		if (name === "claude")
			return {
				"name": "Claude Code",
				"icon": Qt.resolvedUrl("icons/claude.svg")
			};
		if (name === "Hyprland")
			return {
				"name": "Hyprland",
				"icon": Qt.resolvedUrl("icons/hyprland.svg")
			};
		if (name === "below")
			return {
				"name": "below",
				"icon": Qt.resolvedUrl("icons/below.svg")
			};
		if (["docker", "dockerd", "containerd", "containerd-shim"].includes(name))
			return {
				"name": "Docker",
				"icon": Quickshell.iconPath("docker-desktop", true)
			};
		if (name === "quickshell" || name === "islands")
			return {
				"name": "Islands",
				"icon": Qt.resolvedUrl("icons/quickshell.svg")
			};
		const entry = DesktopEntries.heuristicLookup(({
					"chrome": "google-chrome",
					"com.google.Chrome": "google-chrome",
					"ghostty": "com.mitchellh.ghostty"
				})[name] ?? name);
		return {
			"name": entry?.name ?? name,
			"icon": entry?.icon ? Quickshell.iconPath(entry.icon, true) : ""
		};
	}

	// [[command or name, share %], ...] as the three biggest apps of at
	// least `least` %, [{name, icon, share}], the names that are one app
	// added together
	function topApps(shares: var, least: real): var {
		const byApp = {};
		for (const [name, share] of shares) {
			const a = app(name);
			byApp[a.name] = byApp[a.name] ?? Object.assign(a, {
				"share": 0
			});
			byApp[a.name].share += share;
		}
		return Object.values(byApp).filter(a => a.share >= least).sort((a, b) => b.share - a.share).slice(0, 3);
	}

	// top's second frame (the first counts from each process's start), its
	// %CPU (of one CPU) summed by command, as a share of the whole machine.
	// A top stopped as the page hid or the list turned away still hands
	// over what it had (its first frame, perhaps), which is dropped.
	function readTop(text: string) {
		if (!showing || view !== "now")
			return;
		const lines = text.split("\n");
		let header = 0;
		lines.forEach((l, i) => {
			if (/^\s*PID\s+USER/.test(l))
				header = i;
		});
		const sums = {};
		for (const line of lines.slice(header + 1)) {
			const fields = line.trim().split(/\s+/);
			const cpu = Number(fields[8]);
			const command = fields.slice(11).join(" ");
			if (fields.length >= 12 && cpu > 0 && command !== "top")
				sums[command] = (sums[command] ?? 0) + cpu;
		}
		apps = topApps(Object.entries(sums).map(([command, cpu]) => [command, cpu / Metrics.cores]), 0.1);
		appsRead = true;
	}

	// islands-usage's CPU seconds by app name, as shares of all the CPU used
	// in each window
	function readUsage(json: string) {
		let report;
		try {
			report = JSON.parse(json);
		} catch (e) {
			console.warn("islands: can't read the apps' usage:", e);
			return;
		}
		for (const w of [report.battery, report.today])
			if (w)
				w.apps = topApps(w.apps.map(([name, seconds]) => [name, w.total > 0 ? 100 * seconds / w.total : 0]), 0.5);
		usage = report;
	}

	// "11:39 AM", or "Sun 8:37 PM" before today
	function time(seconds: real): string {
		const date = new Date(seconds * 1000);
		return Qt.formatDateTime(date, date.toDateString() === new Date().toDateString() ? "h:mm AP" : "ddd h:mm AP");
	}

	// A stretch of time, short enough to share a line: "9:12–11:39 AM",
	// "10:52 AM–12:52 PM", "Sun 8:37–11:02 PM", "Sun 8:37 PM–1:02 AM"
	function range(from: real, to: real): string {
		const a = new Date(from * 1000);
		const b = new Date(to * 1000);
		const sameDay = a.toDateString() === b.toDateString();
		const sameHalf = sameDay && (a.getHours() < 12) === (b.getHours() < 12);
		const start = sameHalf ? time(from).replace(Qt.formatDateTime(a, " AP"), "") : time(from);
		return start + "–" + (sameDay ? Qt.formatDateTime(b, "h:mm AP") : time(to));
	}

	function readHistory(json: string) {
		try {
			history = JSON.parse(json).data[0].filter(([t, v, state]) => t > 0 && state !== 0).map(([t, v]) => ({
						"t": t,
						"v": v
					})).sort((a, b) => a.t - b.t);
		} catch (e) {
			console.warn("islands: can't read the battery history:", e);
		}
	}

	// A sensor's number over `scale`, or -1 if it can't be read
	function readSensor(view: FileView, scale: real): real {
		view.reload();
		const text = view.text().trim();
		return text === "" || isNaN(Number(text)) ? -1 : Number(text) / scale;
	}

	// "1.6%", "12%"
	function percent(share: real): string {
		return (share >= 10 ? Math.round(share) : share.toFixed(1)) + "%";
	}

	spacing: 10

	onShowingChanged: if (!showing)
		stopTop()
	onViewChanged: if (view !== "now")
		stopTop()

	// Back to the quick first read when the live list shows again
	function stopTop() {
		top.running = false;
		apps = [];
		appsRead = false;
	}

	// On to the next list (or back, -1), as the title is clicked or scrolled
	function step(by: int) {
		stepped = by;
		view = views[(views.indexOf(view) + by + views.length) % views.length];
	}

	component Stat: Column {
		property string label
		property string value

		spacing: 2

		BarText {
			text: parent.label
			color: Theme.inkDim
			font.pixelSize: 11
		}

		BarText {
			text: parent.value
			color: Theme.ink
			font.pixelSize: 15
			font.weight: Font.DemiBold
			font.features: {
				"tnum": 1
			}
		}
	}

	PageHeader {
		width: parent.width
		title: "Battery"
		onBack: root.back()
	}

	Card {
		width: parent.width

		Column {
			width: parent.width
			spacing: 2

			BarText {
				text: Math.round(Battery.level) + "%"
				color: Theme.ink
				font.pixelSize: 28
				font.weight: Font.DemiBold
				font.features: {
					"tnum": 1
				}
			}

			BarText {
				text: Battery.status
				color: Theme.inkDim
				font.pixelSize: 12
			}
		}

		ChargeChart {
			width: parent.width
			height: 84
			span: root.span
			// The time on battery, while the apps list shows it
			band: root.view === "battery" && root.period ? {
				"from": root.period.from,
				"to": root.period.ongoing ? null : root.period.to
			} : null
			// Up to now: UPower adds a point only as the level changes
			points: root.history.concat([
				{
					"t": Date.now() / 1000,
					"v": Battery.level
				}
			])
		}
	}

	PowerModes {
		width: parent.width
	}

	Card {
		width: parent.width

		// CPU, the chip's power, the temperature and the fan, as many as
		// there are sensors for
		Row {
			id: stats

			readonly property int count: 1 + (root.power >= 0) + (Metrics.temperature > 0) + (root.fan >= 0)

			width: parent.width

			Stat {
				width: stats.width / stats.count
				label: "CPU"
				value: Metrics.cpu + "%"
			}

			Stat {
				width: stats.width / stats.count
				visible: root.power >= 0
				label: "Chip"
				value: Battery.watts(root.power)
			}

			Stat {
				width: stats.width / stats.count
				visible: Metrics.temperature > 0
				label: "Temp"
				value: Math.round(Metrics.temperature) + "°C"
			}

			Stat {
				width: stats.width / stats.count
				visible: root.fan >= 0
				label: "Fan"
				value: root.fan === 0 ? "Off" : root.fan + " rpm"
			}
		}

		Column {
			width: parent.width
			spacing: 6

			// "Busiest right now", the list's title and its switch: a click
			// rolls it on to on battery, then today (a scroll goes either
			// way). On the right, what the shares are of, and for the
			// battery when and how far the level went.
			Item {
				width: parent.width
				height: 28

				// Its hover tint reaches past the text, the text lined up
				// with the stats above
				Rectangle {
					id: title

					x: -8
					width: titleText.implicitWidth + 16
					height: parent.height
					radius: 8
					color: titleHover.hovered ? Theme.alpha(Theme.ink, 0.06) : "transparent"

					Row {
						id: titleText

						x: 8
						anchors.verticalCenter: parent.verticalCenter
						spacing: 4

						BarText {
							anchors.verticalCenter: parent.verticalCenter
							text: "Busiest"
							color: Theme.inkDim
							font.pixelSize: 12
						}

						RollingText {
							anchors.verticalCenter: parent.verticalCenter
							text: ({
									"now": "right now",
									"battery": "on battery",
									"today": "today"
								})[root.view]
							direction: root.stepped
							color: Theme.ink
							pixelSize: 12
							weight: Font.DemiBold
						}

						BarText {
							anchors.verticalCenter: parent.verticalCenter
							text: Glyphs.chevronUpChevronDown
							color: Theme.ink
							font.pixelSize: 10
						}
					}

					HoverHandler {
						id: titleHover

						cursorShape: Qt.PointingHandCursor
					}

					// A wheel's notch, or a swipe's worth, steps once, and
					// the rest of that swipe is let go
					MouseArea {
						property real scrolled: 0
						property real steppedAt: 0

						anchors.fill: parent
						onClicked: root.step(1)
						onWheel: wheel => {
							if (Date.now() - steppedAt < 350)
								return;
							scrolled += wheel.angleDelta.y;
							if (Math.abs(scrolled) >= 120) {
								root.step(scrolled < 0 ? 1 : -1);
								scrolled = 0;
								steppedAt = Date.now();
							}
						}
					}
				}

				BarText {
					id: levels

					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					text: root.view === "battery" && root.period ? "· " + Math.round(root.period.levelFrom) + "% → " + Math.round(root.period.ongoing ? Battery.level : root.period.levelTo) + "%" : ""
					color: Theme.inkDim
					font.pixelSize: 11
					font.features: {
						"tnum": 1
					}
				}

				BarText {
					anchors.right: levels.left
					anchors.rightMargin: levels.text !== "" ? 4 : 0
					anchors.verticalCenter: parent.verticalCenter
					width: Math.min(implicitWidth, levels.x - anchors.rightMargin - (title.x + title.width))
					text: {
						const p = root.period;
						if (root.view === "now")
							return "of the whole CPU";
						if (p === null)
							return "";
						if (root.view === "today")
							return "since midnight";
						return p.ongoing ? "since " + root.time(p.from) : root.range(p.from, p.to);
					}
					color: Theme.inkDim
					font.pixelSize: 11
					font.features: {
						"tnum": 1
					}
					horizontalAlignment: Text.AlignRight
					elide: Text.ElideRight
				}
			}

			// Three rows high however many there are, so the island keeps
			// its size as they come and go
			Item {
				width: parent.width
				height: 3 * 36

				BarText {
					visible: root.shownApps.length === 0
					topPadding: 4
					text: root.view === "now" ? (root.appsRead ? "Nothing much" : "…") : root.usage === null ? "…" : root.period === null ? (root.view === "battery" ? "No time on battery recorded yet" : "Nothing recorded") : "Nothing much"
					color: Theme.inkDim
					font.pixelSize: 12
				}

				Column {
					width: parent.width

					Repeater {
						model: root.shownApps

						// Its icon lined up with the text above
						ListRow {
							required property var modelData

							x: -8
							width: parent.width + 16
							interactive: false
							image: modelData.icon
							glyph: modelData.icon === "" ? Glyphs.terminal : ""
							title: modelData.name
							trailing: root.percent(modelData.share)
						}
					}
				}
			}
		}
	}

	// "Health 98% · 73 cycles"
	BarText {
		x: 4
		visible: text !== ""
		text: [root.battery?.healthSupported ? "Health " + Math.round(root.battery.healthPercentage) + "%" : "", cycles.count > 0 ? cycles.count + " cycles" : ""].filter(s => s !== "").join(" · ")
		color: Theme.inkDim
		font.pixelSize: 12
	}

	FileView {
		id: cycles

		property int count: 0

		path: root.battery ? "/sys/class/power_supply/" + root.battery.nativePath + "/cycle_count" : ""
		printErrors: false
		onLoaded: count = Number(text().trim()) || 0
	}

	// UPower's history of the charge, each minute. The battery's object
	// path is UPower's to name, so it's found by the battery's native path.
	Process {
		id: historyCall

		command: ["sh", "-c", `
			for p in $(busctl --system call org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower EnumerateDevices | grep -o '"[^"]*"' | tr -d '"'); do
				if [ "$(busctl --system get-property org.freedesktop.UPower "$p" org.freedesktop.UPower.Device NativePath)" = "s \\"$1\\"" ]; then
					exec busctl --system --json=short call org.freedesktop.UPower "$p" org.freedesktop.UPower.Device GetHistory suu charge "$2" 200
				fi
			done`, "sh", root.battery?.nativePath ?? "", String(root.span)]
		stdout: StdioCollector {
			onStreamFinished: if (text !== "")
				root.readHistory(text)
		}
	}

	Timer {
		interval: 60000
		repeat: true
		triggeredOnStart: true
		running: root.showing && root.battery !== null
		onTriggered: historyCall.running = true
	}

	// top over two seconds, every three; over half a second the first time,
	// so the apps show soon after the page opens. Its config is pointed at
	// nothing, so a saved toprc can't move the columns read.
	Process {
		id: top

		command: ["top", "-b", "-n", "2", "-d", root.appsRead ? "2" : "0.5", "-w", "512"]
		environment: ({
				"LC_ALL": "C",
				"HOME": "/var/empty",
				"XDG_CONFIG_HOME": "/var/empty"
			})
		stdout: StdioCollector {
			onStreamFinished: root.readTop(text)
		}
	}

	Timer {
		interval: 3000
		repeat: true
		triggeredOnStart: true
		running: root.showing && root.view === "now"
		onTriggered: top.running = true
	}

	// The apps on battery and today, as the list turns to them and each
	// minute while it shows them: islands-usage adds up its five-minute
	// totals of below's recording (and the minutes since), a few
	// hundredths of a second
	Process {
		id: usageCall

		command: ["islands-usage", "report"]
		stdout: StdioCollector {
			onStreamFinished: if (text !== "")
				root.readUsage(text)
		}
	}

	Timer {
		interval: 60000
		repeat: true
		triggeredOnStart: true
		running: root.showing && root.view !== "now"
		onTriggered: usageCall.running = true
	}

	FileView {
		id: powerFile

		path: Host.powerFile
		blockLoading: true
	}

	FileView {
		id: fanFile

		path: Host.fanFile
		blockLoading: true
	}

	Timer {
		interval: 2000
		repeat: true
		triggeredOnStart: true
		running: root.showing && (Host.powerFile !== "" || Host.fanFile !== "")
		onTriggered: {
			if (Host.powerFile !== "")
				root.power = root.readSensor(powerFile, 1e6);
			if (Host.fanFile !== "")
				root.fan = Math.round(root.readSensor(fanFile, 1));
		}
	}
}
