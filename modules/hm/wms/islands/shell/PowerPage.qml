import QtQuick

// The control centre's power page: the power menu's rows, from its power
// button
Column {
	id: root

	signal back

	spacing: 6
	onVisibleChanged: {
		if (visible)
			list.forceActiveFocus();
	}

	PageHeader {
		width: parent.width
		title: "Power"
		onBack: root.back()
	}

	PowerList {
		id: list

		width: parent.width
	}
}
