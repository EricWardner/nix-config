import QtQuick
import Quickshell.Io

// The first existing path a shell glob matches, or "" if none matches
Process {
	id: root

	required property string pattern
	property string path: ""

	command: ["sh", "-c", "for f in $1; do [ -e \"$f\" ] && echo \"$f\"; break; done", "sh", pattern]
	running: pattern !== ""
	stdout: StdioCollector {
		onStreamFinished: root.path = text.trim()
	}
}
