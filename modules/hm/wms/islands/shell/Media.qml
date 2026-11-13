pragma Singleton

import Quickshell
import Quickshell.Services.Mpris

// What's playing (Mpris): of the players that name a track and an artist,
// the one that's playing, or else the first. Chrome keeps a player for any
// tab that has had media, titled with the page's title when the page names
// no track, and Gather's stays "Playing" through a whole call without
// making a sound. Without an artist, a player is a page, not a track.
Singleton {
	readonly property var players: Array.from(Mpris.players.values).filter(p => p.trackTitle !== "" && p.trackArtist !== "")
	readonly property MprisPlayer player: players.find(p => p.isPlaying) ?? players[0] ?? null

	// Material Design icons from the Nerd Font fallback: SF Symbols' media
	// controls aren't among the code points found so far
	readonly property string previousGlyph: String.fromCodePoint(0xF04AE)
	readonly property string playGlyph: String.fromCodePoint(0xF040A)
	readonly property string pauseGlyph: String.fromCodePoint(0xF03E4)
	readonly property string nextGlyph: String.fromCodePoint(0xF04AD)
	readonly property string noteGlyph: String.fromCodePoint(0xF0387)
}
