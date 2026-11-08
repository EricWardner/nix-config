import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The battery: its level and what it's doing, its charge over the last six
// hours (UPower's own history), the power profile, the machine's load, the
// apps using the most CPU, and the battery's health. The history, the
// apps, the chip's power and the fan are read only while the page shows.
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
	// -1 until read, or with no sensor (Host)
	property real power: -1 // W
	property int fan: -1 // rpm

	// "chrome", or ".claude-unwrapp" (a Nix wrapper's name, cut to 15
	// characters) as "claude", by its desktop entry where it has one; some
	// entries are named for neither the command nor the window
	function app(command: string): var {
		const name = command.startsWith(".") ? command.slice(1).replace(/-(un)?wra?p?p?e?d?$/, "") : command;
		if (name === "claude")
			return {
				"name": "Claude Code",
				"icon": Qt.resolvedUrl("icons/claude.svg")
			};
		if (name === "quickshell")
			return {
				"name": "Islands",
				"icon": ""
			};
		const entry = DesktopEntries.heuristicLookup(({
					"chrome": "google-chrome",
					"ghostty": "com.mitchellh.ghostty"
				})[name] ?? name);
		return {
			"name": entry?.name ?? name,
			"icon": entry?.icon ? Quickshell.iconPath(entry.icon, true) : ""
		};
	}

	// top's second frame (the first counts from each process's start), its
	// %CPU (of one CPU) summed by command, as a share of the whole machine
	function readTop(text: string) {
		if (!showing)
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
		const byApp = {};
		for (const [command, cpu] of Object.entries(sums)) {
			const a = app(command);
			byApp[a.name] = byApp[a.name] ?? Object.assign(a, {
				"share": 0
			});
			byApp[a.name].share += cpu / Metrics.cores;
		}
		apps = Object.values(byApp).filter(a => a.share >= 0.1).sort((a, b) => b.share - a.share).slice(0, 3);
		appsRead = true;
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

	onShowingChanged: if (!showing) {
		top.running = false;
		apps = [];
		appsRead = false;
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
			spacing: 2

			BarText {
				text: "Using the most CPU"
				color: Theme.inkDim
				font.pixelSize: 11
			}

			// Three rows high however many there are, so the island keeps
			// its size as they come and go
			Item {
				width: parent.width
				height: 3 * 36

				BarText {
					visible: root.apps.length === 0
					topPadding: 4
					text: root.appsRead ? "Nothing much" : "…"
					color: Theme.inkDim
					font.pixelSize: 12
				}

				Column {
					width: parent.width

					Repeater {
						model: root.apps

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

	// top over two seconds, every three. Its config is pointed at nothing,
	// so a saved toprc can't move the columns read.
	Process {
		id: top

		command: ["top", "-b", "-n", "2", "-d", "2", "-w", "512"]
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
		running: root.showing
		onTriggered: top.running = true
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
