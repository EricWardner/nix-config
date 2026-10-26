hl.layer_rule({ match = { namespace = "waybar" }, blur = true, ignore_alpha = 0.5 })
-- The glass panels of fuzzel (menus), vicinae (launcher), net-panel (the
-- network panel) and swayosd (volume and brightness popups). Global blur
-- xray is off (hyprland.nix), so they frost the windows under them.
hl.layer_rule({
	match = { namespace = "^(launcher|vicinae|net-panel|swayosd)$" },
	blur = true,
	ignore_alpha = 0.3,
})
-- capture-preview (a finished recording) covers the monitor: 20% dimming,
-- the panel's shadow on that (up to 60% together), and the panel (82%).
-- Only the panel should frost; at 0.3 the shadow frosted too, a blurred
-- band round the panel with a hard outer edge.
hl.layer_rule({ match = { namespace = "^capture-preview$" }, blur = true, ignore_alpha = 0.7 })
-- mako's notification cards: frosted too, sliding in from the right edge
-- they're anchored to.
hl.layer_rule({ match = { namespace = "notifications" }, blur = true, ignore_alpha = 0.3, animation = "slide right" })

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
-- Apps opened from waybar float in the top-right corner, below the bar.
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
-- Satty, annotating a screenshot, floats in the middle at the size it picks,
-- as does the preview's save dialog (it has no parent window to float over)
hl.window_rule({ match = { class = "^(com.gabm.satty)$" }, float = true, center = true })
hl.window_rule({ match = { title = "^(Save Screenshot)$" }, float = true, center = true })
-- Thunar floats. Its main windows ("<folder> - Thunar") open at a set size
-- in the middle; its dialogs (copy progress, properties) keep their own size.
hl.window_rule({ match = { class = "^(Thunar)$" }, float = true })
hl.window_rule({
	match = { class = "^(Thunar)$", title = "^(.* - Thunar)$" },
	size = { 1100, 700 },
	center = true,
})
