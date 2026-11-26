pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU, memory and temperature. The CPU and memory are read only while Sky
// or the control centre shows them, and the temperature while the control
// centre does.
Singleton {
	id: root

	readonly property bool onSky: Quickshell.screens.some(s => Compositor.workspaceEmpty(s))
	readonly property bool onControl: Panels.name === "control"

	property int cpu: 0 // % busy
	property int memory: 0 // % used
	property real temperature: 0 // °C
	property int cores: 1 // the CPUs /proc/stat counts, threads included


	property var lastCpu: null

	function readCpu() {
		stat.reload();
		// user nice system idle iowait irq softirq steal
		const lines = stat.text().split("\n");
		cores = Math.max(1, lines.filter(l => /^cpu\d/.test(l)).length);
		const ticks = lines[0].trim().split(/\s+/).slice(1, 9).map(Number);
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

	// Each read waits for its reload (blockAllReads): text() straight after
	// reload() otherwise gives what the file held before
	FileView {
		id: stat

		path: "/proc/stat"
		blockAllReads: true
	}

	FileView {
		id: meminfo

		path: "/proc/meminfo"
		blockAllReads: true
	}

	FileView {
		id: thermal

		path: Host.temperatureFile
		blockAllReads: true
	}

	// Two samples a second apart give the first reading, then every 2 s
	Timer {
		interval: root.lastCpu ? 2000 : 1000
		repeat: true
		triggeredOnStart: true
		running: root.onSky || root.onControl
		onRunningChanged: if (!running)
			root.lastCpu = null
		onTriggered: root.readCpu()
	}

	Timer {
		interval: 5000
		repeat: true
		triggeredOnStart: true
		running: root.onSky || root.onControl
		onTriggered: root.readMemory()
	}

	Timer {
		interval: 10000
		repeat: true
		triggeredOnStart: true
		running: Host.temperatureFile !== "" && root.onControl
		onTriggered: root.readTemperature()
	}
}
