local config = require("nix")
local mod = config.mainMod
local cmd = config.commands
local dsp = hl.dsp

hl.bind(mod .. " + Q", dsp.window.close())
hl.bind(mod .. " + S", dsp.layout("togglesplit"))
hl.bind(mod .. " + P", dsp.window.pseudo())
hl.bind(mod .. " + F", dsp.window.float({ action = "toggle" }))
hl.bind("F11", dsp.window.fullscreen())
hl.bind(mod .. " + CTRL + F", dsp.window.fullscreen_state({ internal = 0, client = 2 }))
hl.bind(mod .. " + ALT + F", dsp.window.fullscreen({ mode = "maximized" }))

local applications = {
	{ "Return", cmd.terminal },
	{ "E", cmd.files },
	{ "SPACE", cmd.launcher },
	{ "Y", cmd.oath },
	{ "V", cmd.clipboard },
	{ "SHIFT + G", cmd.gather },
	{ "F3", cmd.keyboardBrighter },
	{ "F2", cmd.keyboardDimmer },
	{ "R", cmd.record },
}
for _, binding in ipairs(applications) do
	hl.bind(mod .. " + " .. binding[1], dsp.exec_cmd(binding[2]))
end
hl.bind("Print", dsp.exec_cmd(cmd.screenshot))
-- hypridle handles the lock request; spawning a second locker can race it.
hl.bind("ALT + CTRL + SHIFT + L", dsp.exec_cmd(cmd.lock))

for _, direction in ipairs({
	{ vim = "h", arrow = "LEFT", direction = "l", x = -60, y = 0 },
	{ vim = "l", arrow = "RIGHT", direction = "r", x = 60, y = 0 },
	{ vim = "k", arrow = "UP", direction = "u", x = 0, y = -60 },
	{ vim = "j", arrow = "DOWN", direction = "d", x = 0, y = 60 },
}) do
	hl.bind(mod .. " + " .. direction.vim, dsp.focus({ direction = direction.direction }))
	hl.bind(mod .. " + " .. direction.arrow, dsp.focus({ direction = direction.direction }))
	hl.bind(
		mod .. " + SHIFT + " .. direction.vim,
		dsp.window.move({ direction = direction.direction, group_aware = true })
	)
	hl.bind(mod .. " + SHIFT + " .. direction.arrow, dsp.window.swap({ direction = direction.direction }))
	hl.bind(
		mod .. " + CTRL + " .. direction.vim,
		dsp.window.resize({ x = direction.x, y = direction.y, relative = true })
	)
	hl.bind(mod .. " + ALT + " .. direction.arrow, dsp.window.move({ into_group = direction.direction }))
end

for workspace = 1, 10 do
	local key = workspace % 10
	hl.bind(mod .. " + " .. key, dsp.focus({ workspace = workspace }))
	hl.bind(mod .. " + SHIFT + " .. key, dsp.window.move({ workspace = workspace, follow = false }))
end

hl.bind(mod .. " + B", dsp.workspace.toggle_special("browser"))
hl.bind(mod .. " + C", dsp.workspace.toggle_special("chat"))
hl.bind(mod .. " + TAB", dsp.focus({ workspace = "previous" }))
hl.bind(mod .. " + SHIFT + TAB", dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + CTRL + TAB", dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + SHIFT + ALT + LEFT", dsp.workspace.move({ monitor = "l" }))
hl.bind(mod .. " + SHIFT + ALT + RIGHT", dsp.workspace.move({ monitor = "r" }))
hl.bind(mod .. " + mouse_down", dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up", dsp.focus({ workspace = "e-1" }))

hl.bind(mod .. " + minus", dsp.window.resize({ x = -100, y = 0, relative = true }))
hl.bind(mod .. " + equal", dsp.window.resize({ x = 100, y = 0, relative = true }))
hl.bind(mod .. " + SHIFT + minus", dsp.window.resize({ x = 0, y = -100, relative = true }))
hl.bind(mod .. " + SHIFT + equal", dsp.window.resize({ x = 0, y = 100, relative = true }))

hl.bind(mod .. " + G", dsp.group.toggle())
hl.bind(mod .. " + ALT + G", dsp.window.move({ out_of_group = true }))
for _, key in ipairs({ "ALT + J", "ALT + TAB", "CTRL + RIGHT", "ALT + mouse_down" }) do
	hl.bind(mod .. " + " .. key, dsp.group.next())
end
for _, key in ipairs({ "ALT + K", "ALT + SHIFT + TAB", "CTRL + LEFT", "ALT + mouse_up" }) do
	hl.bind(mod .. " + " .. key, dsp.group.prev())
end
for index = 1, 5 do
	hl.bind(mod .. " + ALT + " .. index, dsp.group.active({ index = index }))
end

-- Keep release-triggered cycling and raising in the same callback, in order.
hl.bind("ALT + TAB", function()
	hl.dispatch(dsp.window.cycle_next({ next = true }))
	hl.dispatch(dsp.window.bring_to_top())
end, { release = true })
hl.bind("ALT + SHIFT + TAB", function()
	hl.dispatch(dsp.window.cycle_next({ next = false }))
	hl.dispatch(dsp.window.bring_to_top())
end, { release = true })

for _, binding in ipairs({
	{ "XF86AudioRaiseVolume", cmd.volumeUp },
	{ "XF86AudioLowerVolume", cmd.volumeDown },
	{ "XF86AudioMute", cmd.volumeMute },
	{ "XF86AudioMicMute", cmd.micMute },
	{ "XF86MonBrightnessUp", cmd.brighter },
	{ "XF86MonBrightnessDown", cmd.dimmer },
}) do
	hl.bind(binding[1], dsp.exec_cmd(binding[2]), { repeating = true, locked = true })
end
for _, binding in ipairs({
	{ "XF86AudioNext", cmd.mediaNext },
	{ "XF86AudioPause", cmd.mediaPlayPause },
	{ "XF86AudioPlay", cmd.mediaPlayPause },
	{ "XF86AudioPrev", cmd.mediaPrevious },
}) do
	hl.bind(binding[1], dsp.exec_cmd(binding[2]), { locked = true })
end

hl.bind(mod .. " + mouse:272", dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", dsp.window.resize(), { mouse = true })

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "down", action = "float" })
hl.gesture({ fingers = 4, direction = "up", action = "fullscreen" })
