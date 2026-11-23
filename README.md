# nix-config

My NixOS and Home Manager configuration: one laptop (`framework`, a Framework
13 AMD AI 300), Hyprland, and a desktop shell of its own called islands.

- Hyprland is configured in Lua: see the
  [configuration notes](modules/hm/wms/hypr/README.md).
- The islands shell (bar, notifications, control centre, capture overlay,
  prompts) lives in [modules/hm/wms/islands](modules/hm/wms/islands): its
  [README](modules/hm/wms/islands/README.md) maps what depends on what, and
  the top of its `default.nix` says how to run a development copy.

## Usage

The system and the home are built separately (Home Manager is standalone),
so most changes need only one of the two.

```sh
nh os switch . -H framework              # system    (alias: rb)
nh home switch . -c ewardner@framework   # home      (alias: rbh)
```

### Update inputs

```sh
nix flake update
```

Then rebuild both. The `upd` alias updates the lock file and switches the
home only; run `rb` after it for the system.

### Format and check

```sh
nix fmt                     # format everything (treefmt)
nix flake check             # the pre-commit hooks: treefmt, flake-checker, convco
scripts/check-hyprland.sh   # render the Hyprland Lua config and verify it
```

With direnv, entering the directory loads the dev shell and installs the
pre-commit hooks.

## Structure

```
flake.nix                  # inputs, the `user` block, hosts, packages
├── hosts/
│   ├── framework/         # the laptop
│   │   ├── configuration.nix
│   │   ├── disks.nix            # disko: LUKS, btrfs subvolumes, swapfile
│   │   ├── hardware-configuration.nix
│   │   └── home-overrides.nix   # monitors, sensors, wallpaper
│   └── iso/               # the installer image and its install script
├── home/home.nix          # Home Manager entry (imports modules/hm)
├── modules/
│   ├── nixos/             # system modules
│   ├── hm/                # home modules: shell, git, editors, wms/ (Hyprland, islands, launchers)
│   └── stylix/            # theme, fonts, wallpapers (shared by both)
├── pkgs/                  # our own packages, added to pkgs by an overlay
└── scripts/
```

Modules sit under one `modules.*` option namespace, most of them on by
default; a host turns things on or off in its `configuration.nix` and
`home-overrides.nix`.

The packages in `pkgs/` are also flake outputs, for use on their own:

```sh
nix build .#bar-tools   # also: islands-agent, capture-preview, gather-symbol
```

## What's using the CPU

The battery page of the islands shell (click the battery in the bar) lists
the three busiest things on the machine. Its title steps through three
lists when clicked or scrolled over: "Busiest right now", "on battery" and
"today".

### The three lists

| List       | Covers                                                                   | The percentage is                    | Comes from                                  |
| ---------- | ------------------------------------------------------------------------ | ------------------------------------ | ------------------------------------------- |
| Right now  | The last two seconds, refreshed every three                              | A share of the whole CPU, every core | `top`, read as the page shows               |
| On battery | The stretch on battery going on, or the last one of five minutes or more | A share of all the CPU used in it    | The recording [below](#the-recording) keeps |
| Today      | Since midnight                                                           | A share of all the CPU used in it    | The same recording                          |

"Right now" leaves out anything under 0.1%, the other two anything under
0.5%.

### What counts as one thing

A row is the thing that was asked for, not each process it started.

- **Apps** (a browser, Slack, the shell itself) are one row each, however
  many processes they have. The system keeps each in a group of its own,
  and the group is what's counted.
- **Work run from a terminal** is credited to the **job**: the command that
  was run, with everything it started. From each process the count goes up
  through its parents:
  - it stops at a **host**, which only runs other things: a shell waiting
    at its prompt, Claude Code, the terminal, tmux, process-compose,
    systemd. A host has only its own CPU, under its own name whatever
    started it.
  - it sees through a **wrapper**, which only passes a command on:
    `timeout`, `env`, `sudo`, `npx`, `npm run`, a shell given one command
    (`sh -c`). `npm ci` is npm's own work, so it is "npm".
  - the highest process left is the job. So the browsers a test run
    starts count as `playwright`, a compiler as the `go` or `make` that
    ran it, and `npm run dev` as `vite`.
- **Scripts** are named for what they run, not the runtime:
  `node …/.bin/vite` is "vite", with Node's icon.
- An app a job started (a test browser opens in a group of its own) is
  the job's, not an app.

Some examples:

| What happened                                                                     | Counted as                                                                                                                                               |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Claude Code runs `npx playwright test`                                            | **Playwright**: the runner, the browsers it starts and their renderers. The `zsh -c` and `npx` in between are wrappers, and Claude Code gets none of it. |
| Claude Code works on a reply: streams it, draws its screen, reads and edits files | **Claude Code**. All of that happens in its own process.                                                                                                 |
| Claude Code starts an MCP server or a language server (`gopls`)                   | A row of its own each. Claude Code is a host, so the count stops below it.                                                                               |
| Claude Code runs `git commit`, and the pre-commit hooks lint and build            | **Git**: the hooks, linters and compilers are all part of that commit.                                                                                   |
| process-compose runs `air`, which rebuilds on every save                          | **air**: the watcher, the `go build` it runs, the compiler and the server it restarts.                                                                   |
| process-compose draws its screen and collects logs                                | **Process Compose**, and only that. Each service it runs is a row of its own.                                                                            |
| A script starts process-compose (`./dev.sh`)                                      | The script's own CPU is "dev". Process Compose and its services are counted as above.                                                                    |
| You type `go test ./...` at a prompt                                              | **go**: the compiler, the linker and the test binaries. The shell is "zsh", with only what its prompt uses.                                              |
| `nix build`, from anywhere                                                        | **Nix** for the command (evaluating), **Nix builds** for the building, which the daemon does as a service.                                               |
| A container, whoever started it                                                   | **Docker**. Containers run under Docker's daemon, not under the job that asked for them.                                                                 |
| Claude Code runs something quick (`ls`, a `grep`)                                 | Its own name if it was caught running, otherwise **Terminal commands** (see [the recording](#the-recording)).                                            |
| A loop that waits: `while pgrep x; do sleep 1; done`                              | Next to nothing. Waiting processes are given none of the CPU that could not be measured.                                                                 |

Names that are one thing are added together and shown under one name with
its icon: Docker's daemons and containers, a Go build's compiler and
linker, Chrome's two ways of starting. `app()` in
[BatteryPage.qml](modules/hm/wms/islands/shell/BatteryPage.qml) has those;
the rules for jobs are the `jobs` block of
[islands-usage](modules/hm/wms/islands/islands-usage).

### The recording

[below](https://github.com/facebookincubator/below) records every group's
and every process's CPU every five seconds and keeps three days of it
(`services.below` in [modules/nixos](modules/nixos/default.nix)). Reading
it back is slow, so a timer adds what's new to per-app totals every five
minutes, in five-minute steps, and the page reads those
(`islands-usage update` and `report`; the totals are in
`~/.cache/islands/usage`).

Two things in it are estimates:

- below can only measure a process it has seen twice. One that came and
  went within a few seconds has no figure of its own, though its group's
  total includes it. What a terminal used beyond the processes measured
  goes to the jobs that had new processes there, by how busy each looked:
  what its measured processes used, plus the new ones that were running
  at that moment. One that was only waiting (a `sleep` in a loop, a
  `tail`) gets none.
- **Terminal commands** is what's left when no job looked busy: work too
  brief to have been seen at all.

It also notes when the charger goes in and out, as the battery itself
can't be trusted to say: that's where "on battery" begins and ends.

### Looking closer

Clicking a row opens a window on it:

- from "right now", `btop` as a tree, showing only that job and what it
  runs;
- from the other two, a report on that row (`islands-usage look`): how
  much it used and when, across the time the list covers, and what ran as
  part of it in its busiest five minutes, as a tree with the CPU measured
  for each branch. For a "Git" row that is the commit, the hooks it ran,
  and the linters and tests under them:

  ```
  In those five minutes (CPU-seconds below measured, processes, …)
       1047    236  git
       1047    224  ├─ prek
        720     31  │  ├─ golangci-lint
        172     47  │  ├─ go
        144     87  │  └─ node:vitest
  Started as
       1047     3×  git commit -q -F -
  ```

  "Terminal commands" has no processes of its own, so its report lists
  the brief ones seen in the terminals then. `b` goes on to below's own
  recording of those minutes, replayed (`p` for processes, `c` for
  groups).

## Adding a host

1. Create `hosts/<hostname>/` with `configuration.nix` (importing
   `../../modules/nixos`), `disks.nix` and `home-overrides.nix`. Copying
   `hosts/framework` is the quickest start. The installer writes
   `hardware-configuration.nix`.
2. In `flake.nix`, add the host and its nixos-hardware modules to `hosts`:

   ```nix
   hosts = {
     framework = { ... };
     <hostname> = {
       hardwareModules = [ nixos-hardware.nixosModules.<model> ];
     };
   };
   ```

3. Add its home configuration next to the existing one:

   ```nix
   "${user.username}@<hostname>" = mkHome "<hostname>";
   ```

## Fresh install

The build, the install and the first boot below were last run in a virtual
machine on 2026-11-21, installing `framework` to a blank disk.

### Build the installer

```sh
nix build .#iso
# Find the USB stick with lsblk first.
sudo dd if="$(ls result/iso/*.iso)" of=/dev/sdX bs=4M status=progress conv=fdatasync
```

The image carries a copy of this repository, so build it from the commit
you want installed.

### Install

Boot the stick and get online (`nmtui` for Wi-Fi), then:

```sh
sudo run-install framework              # the host, as named in flake.nix
sudo run-install framework /dev/sda     # or onto a disk other than /dev/nvme0n1
```

It asks before erasing the disk, then:

1. generates the host's `hardware-configuration.nix` for this machine,
2. partitions and encrypts the disk, asking for the passphrase,
3. installs the system,
4. copies this repository to `~/nix-config`,
5. asks for the user's password.

If the new swapfile's offset isn't the one in the host's
`configuration.nix`, it says so at the end; hibernation needs the two to
match.

### After the first boot

The first boot unlocks the disk and logs straight in to a bare Hyprland
with its stock config: the home isn't built yet. Super+Q opens a terminal
(kitty, which the system installs for this).

1. Get online (`nmtui`) and restore the SSH keys. The home configuration
   has a private input fetched over SSH, so it can't be built without them.
2. Build the home: `nh home switch ~/nix-config -c ewardner@<hostname>`,
   then reboot.
3. Make `~/nix-config` a checkout again; the installer's copy has no git
   history:

   ```sh
   cd ~/nix-config
   git init -b main
   git remote add origin git@github.com:EricWardner/nix-config.git
   git fetch origin
   git reset origin/main
   git branch -u origin/main
   ```

   `git status` then shows what the installer changed: the generated
   `hardware-configuration.nix`, to commit.

Not in this repository, to restore by hand:

- `/etc/nix/private-modules.env`, read by the Nix daemon.
- The keyring: Wi-Fi passwords, the `gh` and `fj` logins, and the
  calendar's address (`secret-tool store service islands-calendar`).
- Everything in the home directory. Nothing here backs it up.

## Using it for someone else

Identity is in the `user` block in `flake.nix`:

```nix
user = {
  username = "jdoe";
  fullName = "Jane Doe";
  work = {
    email = "jdoe@example.com";
    signingKey = "~/.ssh/id_ed25519_sk.pub";
    githubOrg = "example-org";
  };
  personal = {
    email = "jane@example.org";
    signingKey = "~/.ssh/id_ed25519_sk.pub";
    githubUsername = "jdoe";
  };
};
```

That isn't everything. Before it builds for anyone else:

- Remove the private `team-claude-skills` input and
  `modules.ai.team-skills.enable` in `home/home.nix`.
- Replace the work-specific parts: the Gather launcher and its window rules
  (`work.tiberius.com`), the Forgejo client ID in `modules/hm/default.nix`,
  and the YubiKey serial in the `oath` command in `hyprland.nix`.
- Set monitors and sensor paths in the host's `home-overrides.nix`.
