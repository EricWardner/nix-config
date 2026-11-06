pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// What the terminals are running, from the files in
// $XDG_RUNTIME_DIR/islands/jobs: a command still going after 10 seconds,
// then how it ended, until its terminal is looked at. Each file holds one
// line of tab-separated fields: run|end, started, ended, exit code, the
// command to match the ignore list against, and its name. The zsh hook
// (islands-jobs.zsh) keeps one per shell, named by its pid, with the
// command as typed for the name; Claude Code's hooks (islands-claude-job)
// one per session, with no command and the name to show as it is.
//
// A job remembers the window that was focused as it started (the terminal
// it was typed in), so a click can go back there: Ghostty runs all its
// windows in one process, so the shell's pid can't name one. Its tabs and
// splits share that window, so a job in another tab counts as looked at.
Singleton {
	id: root

	readonly property string dir: Quickshell.env("XDG_RUNTIME_DIR") + "/islands/jobs"
	// Shown once it has run this long, in seconds
	readonly property int after: 10
	// Results that came in before the bar started were seen then
	readonly property real startedAt: Date.now() / 1000
	property real now: Date.now() / 1000

	// {pid, shell, state ("run" or "end"), started, ended, code, name,
	// ignored}, by file name
	property var jobs: ({})
	// The window each was typed in (its address), by file name; "" if unknown
	property var windows: ({})
	// The results put away (clicked, or their terminal looked at), by file
	// name: "started:ended"
	property var dismissed: ({})

	// Shown, most important first: failures not yet seen, then passes, then
	// running commands, each newest first
	readonly property var shown: {
		const t = now;
		const list = Object.values(jobs).filter(job => {
			if (job.ignored)
				return false;
			if (job.state === "run")
				return t - job.started >= after;
			// Ctrl+C and Ctrl+Z: you stopped it yourself
			return job.ended - job.started >= after && job.code !== 130 && job.code !== 148 && !putAway(job);
		});
		const rank = job => job.state === "run" ? 2 : job.code === 0 ? 1 : 0;
		return list.sort((a, b) => rank(a) !== rank(b) ? rank(a) - rank(b) : a.state === "end" ? b.ended - a.ended : b.started - a.started);
	}

	// Never shown: programs you work in rather than wait for, servers and
	// watchers that run until stopped, and shells within the shell. A REPL
	// only counts without arguments (`python` but not `python build.py`).
	// Matched against the command with its aliases expanded too.
	readonly property var interactive: ["vi", "vim", "nvim", "nano", "hx", "emacs", "micro", "less", "more", "man", "ssh", "mosh", "tmux", "zellij", "screen", "top", "htop", "btop", "watch", "claude", "lazygit", "yazi", "ranger", "nnn", "fzf", "psql", "mysql", "sqlite3", "nix-shell", "systemd-inhibit"]
	readonly property var repls: ["python", "python3", "ipython", "node", "irb", "ghci", "bash", "zsh", "fish", "sh"]
	readonly property var patterns: [/^(npm|pnpm|yarn|bun)( run)? (dev|start|serve|watch|storybook)\b/, /^nix (develop|shell|repl)\b/, /^devenv shell\b/, /^docker[ -]compose\b.* up\b(?!.* -d\b)/, /^kubectl port-forward\b/, /\b(tail|journalctl|logs)\b.* (-f|--follow)\b/, / --watch\b/]
	// Package manager flags whose value is the next word
	readonly property var valueFlags: ["--filter", "-F", "-w", "--workspace", "-C", "--dir", "--prefix", "--cwd"]

	// A result is told apart from the one before it in the same shell by its
	// start and end: two commands can start in the same second
	function putAway(job: var): bool {
		return dismissed[job.pid] === job.started + ":" + job.ended;
	}

	// The command without the assignments and wrappers before it
	function words(command: string): var {
		const list = command.trim().split(/\s+/);
		while (list.length > 1 && (/^\w+=/.test(list[0]) || ["sudo", "time", "noglob", "nocorrect", "command", "exec", "env", "nice"].includes(list[0])))
			list.shift();
		return list;
	}

	function ignored(command: string): bool {
		const list = words(command);
		const program = list[0].replace(/^.*\//, "");
		const bare = list.join(" ");
		return interactive.includes(program) || (list.length === 1 && repls.includes(program)) || patterns.some(pattern => pattern.test(bare));
	}

	function shorten(text: string): string {
		return text.length > 28 ? text.slice(0, 27) + "…" : text;
	}

	// A short name: "pnpm test:e2e" is "test:e2e", "nh home switch ." is
	// "nh home switch", "cargo build --release" is "cargo build"
	function name(command: string): string {
		const list = words(command);
		let kept = [];
		if (["npm", "pnpm", "yarn", "bun"].includes(list[0]) && list.length > 1) {
			// The script, past the flags ("pnpm -r test", "pnpm --filter web build")
			let i = 1;
			while (i < list.length && list[i].startsWith("-"))
				i += valueFlags.includes(list[i]) ? 2 : 1;
			if (["run", "run-script", "exec"].includes(list[i]) && i + 1 < list.length)
				i++;
			kept = [list[i] ?? list[0]];
		} else {
			for (const word of list) {
				// Flags, paths and flake references end it
				if (kept.length > 0 && (word.startsWith("-") || /[\/.#=]/.test(word)))
					break;
				kept.push(kept.length === 0 ? word.replace(/^.*\//, "") : word);
				if (kept.length === 3)
					break;
			}
		}
		return shorten(kept.join(" "));
	}

	// 3:12, or 1:02:03
	function clock(seconds: real): string {
		const s = Math.max(0, Math.floor(seconds));
		const pad = n => String(n).padStart(2, "0");
		return s >= 3600 ? Math.floor(s / 3600) + ":" + pad(Math.floor(s / 60) % 60) + ":" + pad(s % 60) : Math.floor(s / 60) + ":" + pad(s % 60);
	}

	// 42s, 6m 04s, or 1h 02m
	function duration(seconds: real): string {
		const s = Math.max(0, Math.round(seconds));
		const pad = n => String(n).padStart(2, "0");
		if (s < 60)
			return s + "s";
		return s < 3600 ? Math.floor(s / 60) + "m " + pad(s % 60) + "s" : Math.floor(s / 3600) + "h " + pad(Math.floor(s / 60) % 60) + "m";
	}

	function parse(pid: string, text: string): var {
		const fields = text.split("\n")[0].split("\t");
		if (fields.length < 6 || (fields[0] !== "run" && fields[0] !== "end"))
			return null;
		// A shell's command (aliases expanded) and as typed; or no command
		// and a name to show as it is
		const command = fields[4];
		const typed = fields.slice(5).join(" ");
		const shell = command !== "";
		return {
			pid: pid,
			shell: shell,
			state: fields[0],
			started: Number(fields[1]),
			ended: Number(fields[2]),
			code: Number(fields[3]),
			name: shell ? name(typed) : shorten(typed),
			ignored: shell && (ignored(command) || ignored(typed))
		};
	}

	function update(pid: string, text: string) {
		const job = parse(pid, text);
		// Read halfway through a write: the rest is on its way
		if (!job)
			return;
		const old = jobs[pid];
		const active = Hyprland.activeToplevel?.address ?? "";
		now = Date.now() / 1000;
		if (job.state === "run" && old?.started !== job.started) {
			// Typed just now, so it was typed in the focused window; one
			// found running when the bar started could be anywhere
			windows = Object.assign({}, windows, {
				[pid]: now - job.started < 3 ? active : ""
			});
		}
		// Seen already: a result that came in before the bar started, or one
		// that ends in the terminal you're looking at
		if (job.state === "end" && !putAway(job) && (job.ended < startedAt || (old?.state === "run" && active !== "" && windows[pid] === active)))
			dismiss(job);
		jobs = Object.assign({}, jobs, {
			[pid]: job
		});
	}

	// Drops the jobs whose files are gone (their shells have exited), going
	// by the folder's listing once it has settled. Not by the files' views:
	// whenever a file comes or goes, the model drops and recreates them all.
	function prune() {
		const present = {};
		for (let i = 0; i < files.count; i++)
			present[files.get(i, "fileName")] = true;
		const keep = map => {
			const kept = {};
			for (const pid in map) {
				if (present[pid])
					kept[pid] = map[pid];
			}
			return kept;
		};
		if (Object.keys(jobs).some(pid => !present[pid])) {
			jobs = keep(jobs);
			windows = keep(windows);
			dismissed = keep(dismissed);
		}
	}

	function dismiss(job: var) {
		dismissed = Object.assign({}, dismissed, {
			[job.pid]: job.started + ":" + job.ended
		});
	}

	// Go to the job's terminal; a result has then been seen
	function open(job: var) {
		const address = windows[job.pid];
		if (address)
			Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${address}" })`);
		if (job.state === "end")
			dismiss(job);
	}

	// Looking at a terminal sees its results
	Connections {
		target: Hyprland

		function onActiveToplevelChanged() {
			const active = Hyprland.activeToplevel?.address ?? "";
			for (const job of root.shown) {
				if (job.state === "end" && active !== "" && root.windows[job.pid] === active)
					root.dismiss(job);
			}
		}
	}

	// The clocks on running jobs (and the 10 seconds before one shows); idle
	// shells, and jobs never shown, don't tick
	Timer {
		interval: 1000
		repeat: true
		running: Object.values(root.jobs).some(job => job.state === "run" && !job.ignored)
		onTriggered: root.now = Date.now() / 1000
	}

	// The folder has to exist before it's watched: the service makes it
	// (islands/default.nix), as does every shell's hook
	FolderListModel {
		id: files

		folder: "file://" + root.dir
		showDirs: false
		sortField: FolderListModel.Unsorted

		// A file replaced by another in one listing changes rows in place
		onCountChanged: Qt.callLater(root.prune)
		onDataChanged: Qt.callLater(root.prune)
	}

	Instantiator {
		model: files

		delegate: FileView {
			required property string fileName

			path: root.dir + "/" + fileName
			watchChanges: true
			printErrors: false
			onFileChanged: reload()
			onLoaded: root.update(fileName, text())
		}
	}
}
