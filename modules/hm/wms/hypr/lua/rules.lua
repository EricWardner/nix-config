-- The islands bar (modules/hm/wms/islands): blurred wherever it's at all
-- opaque, so the islands' 10% glass at rest is frosted too; the window's
-- transparent rest stays clear
hl.layer_rule({ match = { namespace = "^islands-bar$" }, blur = true, ignore_alpha = 0.08 })
-- The glass panels of fuzzel (menus) and vicinae (the launcher and its
-- HUD). Global blur xray is off (hyprland.nix), so they frost the windows
-- under them.
hl.layer_rule({
	match = { namespace = "^(launcher|vicinae|vicinae-hud)$" },
	blur = true,
	ignore_alpha = 0.3,
})
-- Sky's cards (wms/islands) frost the wallpaper; its big clock's shadow
-- stays unblurred
hl.layer_rule({ match = { namespace = "^islands-sky$" }, blur = true, ignore_alpha = 0.25 })
-- The capture overlay opens on a picture of the screen as it is, and
-- animates its own dim and toolbar; a fade would hide the toolbar growing
hl.layer_rule({ match = { namespace = "^islands-capture$" }, no_anim = true })

hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})
hl.window_rule({ match = { class = "(Alacritty|kitty)" }, scroll_touchpad = 1.5 })
hl.window_rule({ match = { class = "com.mitchellh.ghostty" }, scroll_touchpad = 0.2 })

hl.window_rule({ match = { title = "^(MainPicker)$" }, float = true })
hl.window_rule({ match = { title = "^(Sign in to Security Device)$" }, float = true })
-- Chrome's screen-share bar is titled "<host> is sharing your screen."; any
-- Gather host matches, as the host has changed before (app.v2.gather.town).
hl.window_rule({ match = { title = "^([^ ]*gather[^ ]* is sharing)(.*)$" }, workspace = "10" })
-- The group effect takes an option string; "set" opens the window in a group.
hl.window_rule({ match = { class = "signal" }, group = "set" })
hl.window_rule({ match = { class = "Slack" }, group = "set" })
-- Chrome names --app windows after the launch URL, and cmd.gather opens
-- work.tiberius.com (a redirect to Gather), so its class has no "gather".
hl.window_rule({
	match = { class = ".*(gather|work\\.tiberius\\.com).*" },
	workspace = "special:chat",
	group = "set",
})
hl.window_rule({
	match = { class = "^(dropdown)$" },
	float = true,
	size = { 800, 400 },
	center = true,
	animation = "slide",
})
-- Apps opened from the bar float in the top-right corner, below it.
-- Check classes with `hyprctl clients` when one tiles: blueman's changed
-- from .blueman-manager-wrapped, and ghostty ignores a --class that isn't a
-- valid app ID (needs a dot), as the bare "btop" once was.
hl.window_rule({
	match = {
		class = "^(org.pulseaudio.pavucontrol|blueman-manager|hu.irl.cameractrls|nm-connection-editor|com.mitchellh.ghostty.btop)$",
	},
	float = true,
	move = { "(monitor_w-window_w-10)", 40 },
})
-- capture-preview (a finished recording or screenshot) and Satty (annotating
-- one) float in the middle at the size they pick, as does the preview's save
-- dialog
hl.window_rule({ match = { class = "^(io.github.capture-preview|com.gabm.satty)$" }, float = true, center = true })
hl.window_rule({ match = { title = "^(Save Screenshot)$" }, float = true, center = true })
-- Thunar floats. Its main windows ("<folder> - Thunar") open at a set size
-- in the middle; its dialogs (copy progress, properties) keep their own size.
hl.window_rule({ match = { class = "^(Thunar)$" }, float = true })
hl.window_rule({
	match = { class = "^(Thunar)$", title = "^(.* - Thunar)$" },
	size = { 1100, 700 },
	center = true,
})
