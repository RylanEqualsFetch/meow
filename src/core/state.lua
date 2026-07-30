-- shared runtime state, written by init, the ui and the settings modules

local state = {
	watermark = true,
	module_list = true,
	notifications = true,
	auto_report = true,
	nav_x = nil,
	nav_y = nil,
	columns = {},
	ui = {},
}

return state
