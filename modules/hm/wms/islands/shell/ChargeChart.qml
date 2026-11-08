import QtQuick

// The battery's charge over the last hours: a line over a faint fill, 0 to
// 100%, now at the right edge. Under it, how far back it reaches and "Now",
// or, while hovered, the time and charge under the pointer.
Item {
	id: root

	// [{t: seconds since the epoch, v: %}], oldest first; the last is now
	property var points: []
	property real span: 6 * 3600 // seconds across

	readonly property real now: points.length > 0 ? points[points.length - 1].t : Date.now() / 1000
	readonly property real plotHeight: height - axis.height - 6
	readonly property var shown: points.filter(p => p.t >= now - span)
	// The point nearest the pointer, while hovered
	readonly property var hovered: {
		if (!hover.hovered || shown.length === 0)
			return null;
		const t = now - span + hover.point.position.x / width * span;
		return shown.reduce((best, p) => Math.abs(p.t - t) < Math.abs(best.t - t) ? p : best);
	}

	function xOf(t: real): real {
		return (t - (now - span)) / span * width;
	}

	// 2px in from the top and bottom, so the line isn't clipped at 0 or 100%
	function yOf(v: real): real {
		return 2 + (1 - v / 100) * (plotHeight - 4);
	}

	onShownChanged: canvas.requestPaint()
	onHoveredChanged: canvas.requestPaint()
	onWidthChanged: canvas.requestPaint()
	onPlotHeightChanged: canvas.requestPaint()

	Canvas {
		id: canvas

		width: root.width
		height: root.plotHeight
		antialiasing: true

		onPaint: {
			const ctx = getContext("2d");
			ctx.reset();
			// The 50% guide and the baseline
			ctx.strokeStyle = Theme.inkTrack;
			ctx.lineWidth = 1;
			ctx.setLineDash([2, 3]);
			ctx.beginPath();
			ctx.moveTo(0, Math.round(root.yOf(50)) + 0.5);
			ctx.lineTo(width, Math.round(root.yOf(50)) + 0.5);
			ctx.stroke();
			ctx.setLineDash([]);
			ctx.beginPath();
			ctx.moveTo(0, height - 0.5);
			ctx.lineTo(width, height - 0.5);
			ctx.stroke();

			const pts = root.shown;
			if (pts.length < 2)
				return;
			ctx.beginPath();
			ctx.moveTo(root.xOf(pts[0].t), height);
			for (const p of pts)
				ctx.lineTo(root.xOf(p.t), root.yOf(p.v));
			ctx.lineTo(root.xOf(pts[pts.length - 1].t), height);
			ctx.closePath();
			ctx.fillStyle = Theme.alpha(Theme.ink, 0.08);
			ctx.fill();

			ctx.beginPath();
			pts.forEach((p, i) => i === 0 ? ctx.moveTo(root.xOf(p.t), root.yOf(p.v)) : ctx.lineTo(root.xOf(p.t), root.yOf(p.v)));
			ctx.strokeStyle = Theme.ink;
			ctx.lineWidth = 2;
			ctx.lineJoin = "round";
			ctx.lineCap = "round";
			ctx.stroke();

			// The hovered point: a guide down to the baseline, and an 8px dot
			// ringed in the glass
			const h = root.hovered;
			if (h) {
				const x = Math.round(root.xOf(h.t)) + 0.5;
				ctx.strokeStyle = Theme.alpha(Theme.ink, 0.3);
				ctx.lineWidth = 1;
				ctx.beginPath();
				ctx.moveTo(x, 0);
				ctx.lineTo(x, height);
				ctx.stroke();
				ctx.beginPath();
				ctx.arc(root.xOf(h.t), root.yOf(h.v), 4, 0, 2 * Math.PI);
				ctx.fillStyle = Theme.ink;
				ctx.fill();
				ctx.strokeStyle = Theme.fg;
				ctx.lineWidth = 2;
				ctx.stroke();
			}
		}
	}

	Item {
		id: axis

		y: root.plotHeight + 6
		width: root.width
		height: start.implicitHeight

		BarText {
			id: start

			visible: root.hovered === null
			text: Math.round(root.span / 3600) + "h ago"
			color: Theme.inkDim
			font.pixelSize: 11
		}

		BarText {
			anchors.right: parent.right
			visible: root.hovered === null
			text: "Now"
			color: Theme.inkDim
			font.pixelSize: 11
		}

		// "2:14 PM · 48%", under the point, kept inside the chart
		BarText {
			visible: root.hovered !== null
			x: root.hovered ? Math.max(0, Math.min(root.width - width, root.xOf(root.hovered.t) - width / 2)) : 0
			text: root.hovered ? Qt.formatTime(new Date(root.hovered.t * 1000), "h:mm AP") + " · " + Math.round(root.hovered.v) + "%" : ""
			color: Theme.ink
			font.pixelSize: 11
			font.features: {
				"tnum": 1
			}
		}
	}

	HoverHandler {
		id: hover
	}
}
