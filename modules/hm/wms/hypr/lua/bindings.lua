local config = require("nix")
local mod = config.mainMod
local cmd = config.commands
local dsp = hl.dsp

-- Super + a key goes there or opens it. Shift moves the window there (or
-- is the key's close variant: N and Shift+N), Ctrl resizes, Alt is groups.
-- The arrows do what H/J/K/L do. On Tab, Shift goes backwards. Super+/
-- shows them all (islands shell/KeysMode.qml), written out by hand there:
-- change it with them.

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
	{ "G", cmd.gather },
	{ "R", cmd.record },
	{ "A", cmd.controlCentre },
	{ "N", cmd.notificationCentre },
	{ "SHIFT + N", cmd.doNotDisturb },
	{ "Z", cmd.keepAwake },
	{ "M", cmd.micMute },
	{ "SHIFT + M", cmd.pushToTalk },
	{ "slash", cmd.shortcuts },
}
for _, binding in ipairs(applications) do
	hl.bind(mod .. " + " .. binding[1], dsp.exec_cmd(binding[2]))
end
hl.bind("Print", dsp.exec_cmd(cmd.screenshot))
hl.bind("SHIFT + Print", dsp.exec_cmd(cmd.screenshotWindow))
hl.bind("CTRL + Print", dsp.exec_cmd(cmd.screenshotScreen))
hl.bind(mod .. " + Print", dsp.exec_cmd(cmd.screenshotText))
hl.bind(mod .. " + SHIFT + Print", dsp.exec_cmd(cmd.colorPicker))
-- hypridle handles the lock request; spawning a second locker can race it.
hl.bind(mod .. " + Escape", dsp.exec_cmd(cmd.lock))

for _, direction in ipairs({
	{ keys = { "h", "LEFT" }, direction = "l", x = -60, y = 0 },
	{ keys = { "l", "RIGHT" }, direction = "r", x = 60, y = 0 },
	{ keys = { "k", "UP" }, direction = "u", x = 0, y = -60 },
	{ keys = { "j", "DOWN" }, direction = "d", x = 0, y = 60 },
}) do
	for _, key in ipairs(direction.keys) do
		hl.bind(mod .. " + " .. key, dsp.focus({ direction = direction.direction }))
		-- Into a group in that direction, or out of one at its edge
		hl.bind(mod .. " + SHIFT + " .. key, dsp.window.move({ direction = direction.direction, group_aware = true }))
		hl.bind(mod .. " + CTRL + " .. key, dsp.window.resize({ x = direction.x, y = direction.y, relative = true }))
	end
end

for workspace = 1, 10 do
	local key = workspace % 10
	hl.bind(mod .. " + " .. key, dsp.focus({ workspace = workspace }))
	hl.bind(mod .. " + SHIFT + " .. key, dsp.window.move({ workspace = workspace, follow = false }))
end
for _, scratchpad in ipairs({ { "B", "browser" }, { "C", "chat" } }) do
	hl.bind(mod .. " + " .. scratchpad[1], dsp.workspace.toggle_special(scratchpad[2]))
	hl.bind(
		mod .. " + SHIFT + " .. scratchpad[1],
		dsp.window.move({ workspace = "special:" .. scratchpad[2], follow = false })
	)
end

hl.bind(mod .. " + TAB", dsp.focus({ workspace = "previous" }))
hl.bind(mod .. " + CTRL + TAB", dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + CTRL + SHIFT + TAB", dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + mouse_down", dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up", dsp.focus({ workspace = "e-1" }))
hl.bind(mod .. " + SHIFT + ALT + LEFT", dsp.workspace.move({ monitor = "l" }))
hl.bind(mod .. " + SHIFT + ALT + RIGHT", dsp.workspace.move({ monitor = "r" }))

-- Groups: joined and left with Super+Shift+direction (above)
hl.bind(mod .. " + ALT + G", dsp.group.toggle())
for _, key in ipairs({ "l", "RIGHT", "TAB", "mouse_down" }) do
	hl.bind(mod .. " + ALT + " .. key, dsp.group.next())
end
for _, key in ipairs({ "h", "LEFT", "SHIFT + TAB", "mouse_up" }) do
	hl.bind(mod .. " + ALT + " .. key, dsp.group.prev())
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
