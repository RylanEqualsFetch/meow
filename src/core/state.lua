-- shared runtime state, written by init and by the settings modules

local state = {
	menu_key = Enum.KeyCode.RightShift,
	watermark = true,
	module_list = true,
	notifications = true,
	ui = {},
}

return state
