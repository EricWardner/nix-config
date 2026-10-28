pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// CPU, memory, temperature and screen brightness. The CPU and memory are
// read only while Sky shows them; the temperature every 10 s, for the status
// island's warning; the brightness whenever udev reports a change (the
// keys, idle dimming), for the popup, so nothing polls it.
Singleton {
	id: root

	readonly property bool onSky: Quickshell.screens.some(s => Desktop.workspaceEmpty(Hyprland.monitorFor(s)))

	property int cpu: 0 // % busy
	property int memory: 0 // % used
	property real temperature: 0 // °C
	property int backlight: 100 // %

	readonly property bool critical: temperature >= 80

	property var lastCpu: null

	function readCpu() {
		stat.reload();
		// user nice system idle iowait irq softirq steal
		const ticks = stat.text().split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number);
		const idle = ticks[3] + ticks[4];
		const total = ticks.reduce((sum, t) => sum + t, 0);
		if (lastCpu && total > lastCpu.total)
			cpu = Math.round(100 * (1 - (idle - lastCpu.idle) / (total - lastCpu.total)));
		lastCpu = {
			idle,
			total
		};
	}

	function readMemory() {
		meminfo.reload();
		const kib = name => Number(meminfo.text().match(new RegExp("^" + name + ":\\s+(\\d+)", "m"))?.[1] ?? 0);
		const total = kib("MemTotal");
		if (total > 0)
			memory = Math.round(100 * (1 - kib("MemAvailable") / total));
	}

	function readTemperature() {
		if (Host.temperatureFile === "")
			return;
		thermal.reload();
		temperature = Number(thermal.text().trim()) / 1000;
	}

	function readBacklight() {
		if (Host.backlightDir === "")
			return;
		brightness.reload();
		maxBrightness.reload();
		const max = Number(maxBrightness.text().trim());
		if (max > 0)
			backlight = Math.round(100 * Number(brightness.text().trim()) / max);
	}

	FileView {
		id: stat

		path: "/proc/stat"
		blockLoading: true
	}

	FileView {
		id: meminfo

		path: "/proc/meminfo"
		blockLoading: true
	}

	FileView {
		id: thermal

		path: Host.temperatureFile
		blockLoading: true
	}

	FileView {
		id: brightness

		path: Host.backlightDir === "" ? "" : Host.backlightDir + "/brightness"
		blockLoading: true
	}

	FileView {
		id: maxBrightness

		path: Host.backlightDir === "" ? "" : Host.backlightDir + "/max_brightness"
		blockLoading: true
	}

	// Two samples a second apart give the first reading, then every 2 s
	Timer {
		interval: root.lastCpu ? 2000 : 1000
		repeat: true
		triggeredOnStart: true
		running: root.onSky
		onRunningChanged: if (!running)
			root.lastCpu = null
		onTriggered: root.readCpu()
	}

	Timer {
		interval: 5000
		repeat: true
		triggeredOnStart: true
		running: root.onSky
		onTriggered: root.readMemory()
	}

	Timer {
		interval: 10000
		repeat: true
		triggeredOnStart: true
		running: Host.temperatureFile !== ""
		onTriggered: root.readTemperature()
	}

	// udev's events for the backlight, one line each; restarted if it exits
	Process {
		id: udev

		command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
		running: Host.backlightDir !== ""
		onRunningChanged: if (running)
			root.readBacklight()
		onExited: restartUdev.start()
		stdout: SplitParser {
			onRead: line => {
				if (line.includes("(backlight)"))
					root.readBacklight();
			}
		}
	}

	Timer {
		id: restartUdev

		interval: 5000
		onTriggered: udev.running = true
	}
}
