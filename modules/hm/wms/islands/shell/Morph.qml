import QtQuick

// How an island grows and shrinks: quick off the mark and settling gently,
// the curve from the design prototype
NumberAnimation {
	duration: 440
	easing.type: Easing.BezierSpline
	easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1]
}
