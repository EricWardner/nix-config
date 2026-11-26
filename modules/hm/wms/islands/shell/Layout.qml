pragma Singleton

import QtQuick
import Quickshell

// How the bar fits its islands into the room it has. Both work from the
// widths things would take, not the ones they have now, so what they decide
// doesn't undo itself.
Singleton {
	// Each part's level when the parts must fit in `room`: `parts` maps a
	// name to its widths, widest first, and `order` names who gives way
	// next, a level at a time, until they fit. A name already at its last
	// level is passed over.
	function squeeze(room: real, parts: var, order: var): var {
		const levels = {};
		for (const name in parts)
			levels[name] = 0;
		const total = () => Object.keys(parts).reduce((sum, name) => sum + parts[name][levels[name]], 0);
		for (const name of order) {
			if (total() <= room)
				break;
			levels[name] = Math.min(levels[name] + 1, parts[name].length - 1);
		}
		return levels;
	}

	// Which of a row's items fit in `room`, in turn and `spacing` apart:
	// one that doesn't leaves its place to the next. A null width is an
	// item that isn't wanted.
	function pack(room: real, widths: var, spacing: real): var {
		let used = 0;
		return widths.map(width => {
			const fits = width !== null && used + width <= room;
			if (fits)
				used += width + spacing;
			return fits;
		});
	}
}
