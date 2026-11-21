# nix-config

My NixOS and Home Manager configuration: one laptop (`framework`, a Framework
13 AMD AI 300), Hyprland, and a desktop shell of its own called islands.

- Hyprland is configured in Lua: see the
  [configuration notes](modules/hm/wms/hypr/README.md).
- The islands shell (bar, notifications, control centre, capture overlay,
  prompts) lives in [modules/hm/wms/islands](modules/hm/wms/islands); the top
  of its `default.nix` says how to run a development copy.

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

The installer was last used in March 2026 and hasn't been tested against the
current tree.

### Build the installer

The host to install is baked into the image, read from the environment
(hence `--impure`). `DRIVE` is the disk to install to, `/dev/nvme0n1` if
unset.

```sh
HOSTNAME=framework nix build --impure .#nixosConfigurations.iso.config.system.build.isoImage
# The image is under result/iso/. Find the USB stick with lsblk first.
sudo dd if=result/iso/nixinstaller.iso of=/dev/sdX bs=4M status=progress conv=fdatasync
```

### Install

Boot the stick, get online, then:

```sh
sudo run-install
```

It generates the hardware configuration, partitions and encrypts the disk
(asking for the passphrase), installs the system and asks for the user's
password. It also leaves a copy of this repository in `~/nix-config/cfg`,
which isn't a git checkout.

### After the first boot

1. Restore the SSH keys. The home configuration has a private input fetched
   over SSH, so it can't be built without them.
2. Clone this repository to `~/nix-config`, replacing the installer's copy.
   The path is assumed by `nh`, the aliases and `nix-keep`.
3. Build the home: `nh home switch ~/nix-config -c ewardner@<hostname>`.
4. Set the hibernation offset for the new swapfile. Read it with
   `sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile`, put it
   in `resume_offset=` in the host's `configuration.nix`, and rebuild.

Not in this repository, to restore by hand:

- `/etc/nix/private-modules.env`, read by the Nix daemon.
- The keyring: Wi-Fi passwords, the `gh` and `fj` logins, and the
  calendar's address (`secret-tool store service islands-calendar`).
- The Claude Code hooks in `~/.claude/settings.json` that call
  `islands-claude-job`, for the bar's job island.
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
