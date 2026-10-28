pragma Singleton

import Quickshell

// The bar's icons. Status icons are SF Symbols, which ship inside SF Pro as
// private-use characters from U+100000, unnamed in the font; these code
// points were found by rendering them (bar-tools' sf module has the same
// set). SF Symbols has no logos, so the launcher and the workspaces' app
// icons are Nerd Font glyphs, and Gather's is the one-glyph gather-symbol
// font at U+FFF00.
Singleton {
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
	readonly property string circle: String.fromCodePoint(0x100000)
	readonly property string recordCircle: String.fromCodePoint(0x10075C)
	readonly property string stopCircle: String.fromCodePoint(0x10072A)
	readonly property string bellSlash: String.fromCodePoint(0x1002DD)
	readonly property string terminal: String.fromCodePoint(0x100A7C)
	readonly property string globe: String.fromCodePoint(0x1001AA)
	readonly property string folder: String.fromCodePoint(0x100215)
	readonly property string rectangleDashed: String.fromCodePoint(0x100941)
	readonly property string display: String.fromCodePoint(0x1008B9)
	readonly property string camera: String.fromCodePoint(0x10031E)
	readonly property string textViewfinder: String.fromCodePoint(0x100E43)
	readonly property string eyedropper: String.fromCodePoint(0x100397)
	readonly property string nix: String.fromCodePoint(0xF1105)
	readonly property string wifi: String.fromCodePoint(0x100647)
	readonly property string wifiSlash: String.fromCodePoint(0x100648)

	// Material Design icons (Nerd Font), where SF Symbols has none (no
	// Bluetooth: it's a trademark) or none whose code point is known yet
	readonly property string bluetooth: String.fromCodePoint(0xF00AF)
	readonly property string bluetoothConnected: String.fromCodePoint(0xF00B1)
	readonly property string bluetoothOff: String.fromCodePoint(0xF00B2)
	readonly property string ethernet: String.fromCodePoint(0xF0200)
	readonly property string lock: String.fromCodePoint(0xF033E)
	readonly property string power: String.fromCodePoint(0xF0425)
	// Wi-Fi signal, weakest to strongest
	readonly property var wifiStrength: [0xF091F, 0xF0922, 0xF0925, 0xF0928].map(c => String.fromCodePoint(c))

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
