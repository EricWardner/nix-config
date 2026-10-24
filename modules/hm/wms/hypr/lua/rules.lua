hl.layer_rule({ match = { namespace = "waybar" }, blur = true, ignore_alpha = 0.5 })
-- The glass panels of fuzzel (menus), vicinae (launcher), net-panel (the
-- network panel) and swayosd (volume and brightness popups). Global blur
-- xray is off (hyprland.nix), so they frost the windows under them.
hl.layer_rule({ match = { namespace = "^(launcher|vicinae|net-panel|swayosd)$" }, blur = true, ignore_alpha = 0.3 })
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
hl.window_rule({ match = { title = "^(app.v2.gather.town is sharing)(.*)$" }, workspace = "10" })
-- The group effect takes an option string; "set" opens the window in a group.
hl.window_rule({ match = { class = "signal" }, group = "set" })
hl.window_rule({ match = { class = "Slack" }, group = "set" })
hl.window_rule({ match = { class = ".*gather.*" }, workspace = "special:chat", group = "set" })
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
hl.window_rule({ match = { title = "^(GIF Preview)$" }, float = true, center = true })
