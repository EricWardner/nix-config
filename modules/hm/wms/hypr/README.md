# Hyprland Lua configuration

Home Manager now generates `~/.config/hypr/hyprland.lua` using
`wayland.windowManager.hyprland.configType = "lua"`. The flake and installed
compositor were checked against Hyprland **0.56.2**. No input update or
`home.stateVersion` change is needed. The [upstream migration note](https://wiki.hypr.land/Configuring/Start/)
dates the Hyprlang deprecation to 0.55.

| File                              | What to edit here                                                                    |
| --------------------------------- | ------------------------------------------------------------------------------------ |
| `hyprland.nix`                    | Package paths, environment, appearance, input, workspace generation, session startup |
| `lua/bindings.lua`                | Keyboard/mouse bindings and touchpad gestures                                        |
| `lua/animations.lua`              | Animation curves, speeds, and styles                                                 |
| `lua/rules.lua`                   | Window and layer rules                                                               |
| `hosts/<host>/home-overrides.nix` | Monitor modes, positions, scales, default workspaces                                 |

Home Manager installs the Lua modules with `extraLuaFiles` and loads them with
`require`. It also generates a helper module, `nix.lua`, containing `mainMod` and
command strings with Nix store paths. Edit the source files here; files under
`~/.config/hypr` are managed by Home Manager. The [Home Manager module](https://github.com/nix-community/home-manager/blob/f10b3f2ad4aae9259617a1ff518cc921e3394228/modules/services/window-managers/hyprland/default.nix)
documents the Lua generator and `extraLuaFiles`.

Ordinary options live under `settings.config`, which generates `hl.config(...)`.
Stylix merges its colors into this same attribute. The effective border colors,
groupbar colors, opacity, gaps, and rounding are preserved. The green/yellow
gradient remains a fallback: Stylix overrides it, just as it did before.

## Migration details

- Numbered workspaces, directional bindings, group navigation, and media keys use
  Lua loops. Shift+number still moves a window **without following it**.
- Alt+Tab still runs on release, then raises the newly focused window.
- Window rules with identical matches are combined. Group rules use the documented
  `group = "set"` effect instead of the old `group on` spelling.
- Monitor `transform` is now an integer from 0 to 7, independent of `scale`.
  `workspace` now creates a default workspace rule; both hosts declare workspace
  10 on the laptop and workspace 1 on the M32U in their monitor entries.
- The portable display uses the documented `highres` mode. Scale accepts strings
  (including `"auto"`) or positive numbers. Legacy width/height fields still work.
- Cursor software rendering is preserved with the integer value
  `cursor.no_hardware_cursors = 1`.
- Home Manager imports the session environment, restarts `hyprland-session.target`,
  and restarts the portal before launching Slack, Gather, and Chrome. This ordering
  prevents those apps from probing the portal before it is ready. Startup hooks
  run on session start, so saving/reloading the config does not launch more apps.
- The lock key requests `loginctl lock-session`; hypridle starts the locker. This
  avoids racing hypridle with a second direct hyprlock launch.
- Hypridle's DPMS commands and the system menu's logout command use Lua
  dispatchers. Hypridle, Hyprlock, and Hyprpaper retain their own config formats.
- Waybar 0.15's built-in workspace buttons also send legacy dispatchers. The
  Waybar module backports upstream Lua IPC support and detects the running
  compositor's config provider. Its Home Manager package and systemd service
  use the same patched executable. Remove the patch when the pinned Waybar
  includes these fixes; see `../waybar/hyprland-lua-ipc.patch` for upstream commits.
- `nix fmt` now includes StyLua. Lua language server settings reference Hyprland's
  NixOS stubs in this repository and the pinned package stubs in the generated
  Hyprland config directory.

## Check and apply

From the repository root:

```sh
bash scripts/check-hyprland.sh
# Or check one home profile:
bash scripts/check-hyprland.sh ewardner@framework
```

This evaluates the Home Manager files into a temporary directory and runs the
installed Hyprland's `--verify-config` against them. It checks both hosts by
default, includes untracked Lua files, and never activates a home generation or
starts a compositor. It requires `nix`, `jq`, `rg`, and a Lua-capable Hyprland.
`HYPRLAND_BIN=/path/to/Hyprland` selects another verifier.

Before a normal Git-flake rebuild, add the new Lua source files to Git so Nix can
see them:

```sh
git add modules/hm/wms/hypr/lua
nh home switch . -c ewardner@framework
# Use ewardner@tiberius on the Dell.
```

Log out and back in for the first migration. The running compositor was launched
with the old config path; a normal reload does not reliably select the newly
named file. Subsequent config edits can use `hyprctl reload`. Once logged back in:

```sh
hyprctl configerrors
```

Try the terminal, launcher, Alt+Tab, grouped window movement, Shift+number,
touchpad gestures, lock/unlock, and browser screen sharing. Native verification
checks parsing and registration; it cannot establish how these behave with real
windows and hardware. The migration was prepared and verified without activating
it in the running session.

## Optional changes to try next

These are recommendations, not enabled changes. Check availability against the
installed version; the live wiki describes newer Git builds too.

1. **Try hardware cursors again on the AMD Framework and Intel Dell.** You currently
   force software cursors. `cursor.no_hardware_cursors = 2` allows hardware cursors
   except when tearing requires otherwise. Test external-display movement and
   screen sharing, then keep the current `1` if your original cursor issue recurs.
   See [cursor options](https://wiki.hypr.land/Configuring/Basics/Variables/#cursor).
2. **Try the scrolling layout on one workspace.** It could suit an editor,
   terminal, and browser workflow on the M32U without changing your other Dwindle
   workspaces. Add `hl.workspace_rule({ workspace = "2", layout = "scrolling" })`
   to a Lua module. See the [scrolling layout](https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/).
3. **Expose your existing btop scratchpad.** `special:monitor` already launches
   btop when first created, but has no keybinding. Add
   `hl.bind(mod .. " + M", dsp.workspace.toggle_special("monitor"))` in
   `bindings.lua`. This uses an otherwise unused shortcut in your config.
4. **Try spring animations for window movement.** Keep your current fade timings
   and use a spring curve only for `windows`/`windowsIn` for a different feel.
   On your 0.56.2 build the parameter is spelled `dampening`; the current wiki
   uses `damping`. This example passed the installed compositor's verifier:

   ```lua
   hl.curve("easy", { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })
   hl.animation({ leaf = "windows", enabled = true, speed = 4.79, spring = "easy" })
   ```

   See [animation curves](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/)
   when upgrading.

5. **Consolidate shared display profiles.** The M32U and portable-display entries
   are duplicated across both hosts. A shared Nix list with only the laptop scale
   defined per host would reduce future drift. The unused legacy width/height
   monitor fields can also be removed once external overrides are ruled out.

For the newer animated blur effects in the wiki, upgrade and verify support
first. They are a separate visual/performance experiment; this migration keeps
your existing blur configuration.
