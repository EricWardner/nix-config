hl.layer_rule({ match = { namespace = "waybar" }, blur = true, ignore_alpha = 0.5 })

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
hl.window_rule({
	match = {
		class = "^(org.pulseaudio.pavucontrol|.blueman-manager-wrapped|hu.irl.cameractrls|nm-connection-editor|btop)$",
	},
	float = true,
	move = { "(monitor_w-window_w-10)", 40 },
})
hl.window_rule({ match = { title = "^(GIF Preview)$" }, float = true, center = true })
