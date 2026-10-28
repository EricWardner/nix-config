pragma Singleton

import Quickshell

// The bar's icons. Status icons are SF Symbols, which ship inside SF Pro as
// private-use characters from U+100000, unnamed in the font; these code
// points were found by rendering them (bar-tools' sf module has the same
// set). SF Symbols has no logos, so the launcher and the workspaces' app
// icons are Nerd Font glyphs, and Gather's is the one-glyph gather-symbol
// font at U+FFF00.
Singleton {
	readonly property string cpu: String.fromCodePoint(0x100AE5)
	readonly property string memory: String.fromCodePoint(0x100AE6)
	readonly property string thermometer: String.fromCodePoint(0x1001EC)
	readonly property string sunMin: String.fromCodePoint(0x1001AB)
	readonly property string sunMax: String.fromCodePoint(0x1001AD)
	readonly property string moonFill: String.fromCodePoint(0x1001BA)
	readonly property string battery0: String.fromCodePoint(0x1006EA)
	readonly property string battery25: String.fromCodePoint(0x1006E9)
	readonly property string battery50: String.fromCodePoint(0x100EB6)
	readonly property string battery75: String.fromCodePoint(0x100EB8)
	readonly property string battery100: String.fromCodePoint(0x1006E8)
	readonly property string batteryBolt: String.fromCodePoint(0x10088B)
	readonly property string video: String.fromCodePoint(0x100349)
	readonly property string videoSlash: String.fromCodePoint(0x10034D)
	readonly property string mic: String.fromCodePoint(0x1002B0)
	readonly property string micSlash: String.fromCodePoint(0x1002B2)
	readonly property string micSlashFill: String.fromCodePoint(0x1002B3)
	readonly property string speakerSlash: String.fromCodePoint(0x1002A2)
	readonly property string speakerWave1: String.fromCodePoint(0x1002A4)
	readonly property string speakerWave2: String.fromCodePoint(0x1002A6)
	readonly property string speakerWave3: String.fromCodePoint(0x1002A8)
	readonly property string recordCircle: String.fromCodePoint(0x10075C)
	readonly property string stopCircle: String.fromCodePoint(0x10072A)
	readonly property string nix: String.fromCodePoint(0xF1105)

	// U+2002 EN SPACE between a workspace's number and its app icons, which
	// have no side bearings
	readonly property string enSpace: " "

	// A window's icon on its workspace, by class (the first match wins);
	// nothing for classes not listed
	readonly property var apps: [
		[/google-chrome/, 0xF268],
		[/firefox/, 0xE745],
		[/kitty|com\.mitchellh\.ghostty/, 0xF018D],
		[/code/, 0xF0A1E],
		[/slack/, 0xF04B1],
		[/spotify/, 0xF04C7],
		// By class only: a title rule also caught any window with the word
		// Gather in its title (a terminal, a doc)
		[/gather|work\.tiberius\.com/, 0xFFF00],
	]

	function app(windowClass: string): string {
		const match = apps.find(([pattern]) => pattern.test(windowClass));
		return match ? String.fromCodePoint(match[1]) : "";
	}
}
