-- client settings, these drive the hud and the theme

local manager = meow.load("src/core/manager.lua")
local state = meow.load("src/core/state.lua")
local theme = meow.load("src/ui/theme.lua")
local notify = meow.load("src/ui/notify.lua")

local settings = manager.category("settings")

-- menu, the keybind on this module opens and closes the window

local menu = settings:module{
	name = "menu",
	description = "shows the client window",
	key = Enum.KeyCode.RightShift,
	default = true,
	hidden = true,
}

menu.on_enable = function()
	if state.ui.window then
		state.ui.window:set_visible(true)
	end
end

menu.on_disable = function()
	if state.ui.window then
		state.ui.window:set_visible(false)
	end
end

-- watermark

local watermark = settings:module{
	name = "watermark",
	description = "top left wordmark and stats",
	default = true,
	hidden = true,
}

watermark.on_enable = function()
	state.watermark = true
	if state.ui.watermark then
		state.ui.watermark:set_visible(true)
	end
end

watermark.on_disable = function()
	state.watermark = false
	if state.ui.watermark then
		state.ui.watermark:set_visible(false)
	end
end

-- module list

local module_list = settings:module{
	name = "module list",
	description = "enabled modules in the corner",
	default = true,
	hidden = true,
}

module_list.on_enable = function()
	state.module_list = true
	if state.ui.list then
		state.ui.list:set_visible(true)
	end
end

module_list.on_disable = function()
	state.module_list = false
	if state.ui.list then
		state.ui.list:set_visible(false)
	end
end

-- notifications

local toasts = settings:module{
	name = "notifications",
	description = "toast popups",
	default = true,
	hidden = true,
}

toasts.on_enable = function()
	state.notifications = true
end

toasts.on_disable = function()
	state.notifications = false
end

-- theme

local skin = settings:module{
	name = "theme",
	description = "accent color",
	default = true,
	hidden = true,
}

skin:dropdown{
	name = "font",
	values = theme.family_order,
	default = theme.family,
	callback = function(value)
		theme.set_family(value)
	end,
}

local accent = skin:color{name = "accent", default = Color3.fromRGB(198, 134, 255)}
accent:listen(function(color)
	theme.set_accent(color)
end)

skin:dropdown{
	name = "preset",
	values = {"lilac", "mint", "ice", "ember", "rose"},
	default = "lilac",
	callback = function(value)
		local presets = {
			lilac = Color3.fromRGB(198, 134, 255),
			mint = Color3.fromRGB(126, 217, 141),
			ice = Color3.fromRGB(122, 190, 255),
			ember = Color3.fromRGB(255, 152, 92),
			rose = Color3.fromRGB(255, 122, 162),
		}
		local color = presets[value]
		if color then
			accent:set(color)
		end
	end,
}

-- config

local config_module = settings:module{
	name = "config",
	description = "save and restore settings",
	default = true,
	hidden = true,
}

config_module:button{
	name = "save config",
	action = function()
		local config = meow.load("src/core/config.lua")
		if config.save() then
			notify.push("config saved")
		else
			notify.push("config save failed, no file access")
		end
	end,
}

config_module:button{
	name = "load config",
	action = function()
		local config = meow.load("src/core/config.lua")
		if config.load() then
			notify.push("config loaded")
		else
			notify.push("no saved config")
		end
	end,
}

config_module:button{
	name = "reset modules",
	action = function()
		local config = meow.load("src/core/config.lua")
		config.reset()
		notify.push("modules reset")
	end,
}

config_module:button{
	name = "unload meow",
	action = function()
		task.spawn(function()
			if type(meow.unload) == "function" then
				meow.unload()
			end
		end)
	end,
}

-- keybinds, right click any module row in the window to bind a key

local binds = settings:module{
	name = "keybinds",
	description = "right click a module row to bind a key",
	default = true,
	hidden = true,
}

binds:button{
	name = "clear all keybinds",
	action = function()
		for _, mod in ipairs(manager.module_order) do
			if mod ~= menu then
				mod.key = nil
			end
		end
		manager.changed:fire()
		notify.push("keybinds cleared")
	end,
}

return true
