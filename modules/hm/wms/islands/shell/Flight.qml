import QtQuick

// Something an island shows in two of its modes, flown from its place in
// one to its place in the other as the island morphs between them (the
// weather pill's temperature growing into the forecast's). `from` and `to`
// are the real items, which their modes hide while it flies. Its two looks,
// `fromLook` and `toLook` (declared inside it, drawn like each end), are
// scaled to the size on the way and cross-faded. Declared in the island
// after its modes, so it flies over them.
Item {
	id: root

	required property Item from
	required property Item to
	// 0 at `from`, 1 at `to`, eased with the island's morph
	property real progress: 0
	property Item fromLook
	property Item toLook

	// Where both ends are in the island now. Mapping isn't a binding, so
	// these read the progress and the island's size to be read again on
	// every frame: the island is growing around them.
	readonly property rect start: {
		progress;
		parent?.width;
		parent?.height;
		return place(from);
	}
	readonly property rect end: {
		progress;
		parent?.width;
		parent?.height;
		return place(to);
	}
	// The second look takes over through the middle of the flight
	readonly property real fade: Math.min(Math.max((progress - 0.2) / 0.5, 0), 1)

	function place(item: Item): rect {
		if (!item || !parent)
			return Qt.rect(0, 0, 0, 0);
		const at = item.mapToItem(parent, 0, 0);
		return Qt.rect(at.x, at.y, item.width, item.height);
	}

	function between(a: real, b: real): real {
		return a + (b - a) * progress;
	}

	visible: progress > 0 && progress < 1
	x: between(start.x, end.x)
	y: between(start.y, end.y)
	width: between(start.width, end.width)
	height: between(start.height, end.height)

	Binding {
		target: root.fromLook
		property: "transformOrigin"
		value: Item.TopLeft
	}
	Binding {
		target: root.fromLook
		property: "scale"
		value: root.start.height > 0 ? root.height / root.start.height : 1
	}
	Binding {
		target: root.fromLook
		property: "opacity"
		value: 1 - root.fade
	}
	Binding {
		target: root.toLook
		property: "transformOrigin"
		value: Item.TopLeft
	}
	Binding {
		target: root.toLook
		property: "scale"
		value: root.end.height > 0 ? root.height / root.end.height : 1
	}
	Binding {
		target: root.toLook
		property: "opacity"
		value: root.fade
	}
}
