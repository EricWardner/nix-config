pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// This machine's settings, from the JSON Home Manager writes
// (modules/hm/wms/islands/default.nix), with globs resolved to paths
Singleton {
	id: root

	property var config: ({})

	readonly property string temperatureFile: temperature.path
	readonly property string powerFile: power.path
	readonly property string fanFile: fan.path
	readonly property string backlightDir: backlight.path
	// For the YubiKey touch prompt
	readonly property string attentionSound: config.attentionSound ?? ""

	FileView {
		path: Quickshell.env("HOME") + "/.config/islands/config.json"
		watchChanges: true
		onFileChanged: reload()
		onLoaded: {
			try {
				root.config = JSON.parse(text());
			} catch (e) {
				console.warn("islands: can't read config.json:", e);
			}
		}
	}

	Glob {
		id: temperature

		pattern: root.config.temperatureSensor ?? ""
	}

	Glob {
		id: power

		pattern: root.config.powerSensor ?? ""
	}

	Glob {
		id: fan

		pattern: root.config.fanSensor ?? ""
	}

	// The first backlight, as waybar's module took
	Glob {
		id: backlight

		pattern: "/sys/class/backlight/*"
	}
}
