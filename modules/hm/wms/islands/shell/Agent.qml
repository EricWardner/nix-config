pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit

// The questions NetworkManager, BlueZ and gnome-keyring ask (a Wi-Fi
// password, a pairing passkey, a keyring's password), from islands-agent
// (pkgs/islands-agent), and polkit's, for an app that needs root (mounting
// an internal disk), for the centre island to ask in turn. The agent runs
// as this shell's child, so it stops with it, and it's restarted if it
// exits. A copy of the shell run by hand for development can leave both
// out (ISLANDS_NO_AGENT=1), so it doesn't take BlueZ's default agent or
// polkit's from the running one.
Singleton {
	id: root

	// Oldest first: each {id, kind, …} as the agent sent it, and polkit's
	// request as {id: -1, kind: "polkit"}, its state in `flow`
	property var questions: []
	readonly property var current: questions[0] ?? null
	// It has a field to type into
	readonly property bool typing: current !== null && (["wifi", "bt-pin", "bt-passkey", "polkit"].includes(current.kind) || current.kind === "keyring" && !current.confirm)
	// The questions PromptMode knows how to ask
	readonly property var kinds: ["wifi", "bt-confirm", "bt-display", "bt-pin", "bt-passkey", "bt-authorize", "keyring"]
	// Polkit's request, one at a time (it queues the rest)
	readonly property AuthFlow flow: polkit.item?.flow ?? null

	onFlowChanged: {
		questions = questions.filter(q => q.kind !== "polkit");
		if (flow)
			questions = questions.concat([
				{
					"id": -1,
					"kind": "polkit"
				}
			]);
	}

	// `value` is null to cancel. A polkit request goes once polkit's done
	// with it: a wrong password asks again.
	function answer(id: int, value: var) {
		if (id === -1) {
			if (value === null)
				flow?.cancelAuthenticationRequest();
			else
				flow?.submit(value);
			return;
		}
		agent.write(JSON.stringify({
			"id": id,
			"value": value
		}) + "\n");
		questions = questions.filter(q => q.id !== id);
	}

	Process {
		id: agent

		// ISLANDS_AGENT: the service names its own build of the agent; by
		// hand, a stand-in to try the prompts without a real request
		command: [Quickshell.env("ISLANDS_AGENT") || "islands-agent"]
		running: !Quickshell.env("ISLANDS_NO_AGENT")
		stdinEnabled: true
		stdout: SplitParser {
			onRead: line => {
				let question;
				try {
					question = JSON.parse(line);
				} catch (e) {
					return;
				}
				if (question.kind === "cancel")
					root.questions = root.questions.filter(q => q.id !== question.id);
				else if (root.kinds.includes(question.kind))
					root.questions = root.questions.concat([question]);
			}
		}
		// What it has to say for itself (registrations, errors), for the log
		stderr: SplitParser {
			onRead: line => console.warn("islands-agent:", line)
		}
		onExited: {
			root.questions = root.questions.filter(q => q.kind === "polkit");
			restart.start();
		}
	}

	LazyLoader {
		id: polkit

		active: !Quickshell.env("ISLANDS_NO_AGENT")

		PolkitAgent {}
	}

	// For a keybind: `qs ipc -c islands call prompt cancel` turns down the
	// question showing
	IpcHandler {
		target: "prompt"

		function cancel(): void {
			const question = root.current;
			if (question)
				root.answer(question.id, question.kind === "bt-authorize" ? false : null);
		}
	}

	Timer {
		id: restart

		interval: 3000
		onTriggered: agent.running = true
	}
}
