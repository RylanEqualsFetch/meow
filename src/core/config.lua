-- saves module states, keybinds and option values to disk

local util = meow.load("src/core/util.lua")
local manager = meow.load("src/core/manager.lua")
local state = meow.load("src/core/state.lua")
local theme = meow.load("src/ui/theme.lua")

local http_service = util.services.HttpService

local config = {}

local folder = "meow"
local path = folder .. "/config.json"
local can_write = isfile and readfile and writefile and isfolder and makefolder
local pending = false

local function encode_color(color)
	return {
		kind = "color",
		r = math.floor(color.R * 255 + 0.5),
		g = math.floor(color.G * 255 + 0.5),
		b = math.floor(color.B * 255 + 0.5),
	}
end

local function decode_color(data)
	if type(data) ~= "table" or data.kind ~= "color" then
		return nil
	end
	return Color3.fromRGB(data.r or 255, data.g or 255, data.b or 255)
end

local function encode_option(option)
	if option.kind == "color" then
		return encode_color(option.value)
	end
	if option.kind == "dropdown" and option.multi then
		return {kind = "multi", values = option.value}
	end
	return option.value
end

local function decode_option(option, data)
	if data == nil then
		return
	end
	if option.kind == "color" then
		local color = decode_color(data)
		if color then
			option:set(color, true)
		end
		return
	end
	if option.kind == "dropdown" and option.multi then
		if type(data) == "table" and type(data.values) == "table" then
			option:set(data.values, true)
		end
		return
	end
	option:set(data, true)
end

function config.serialize()
	local data = {
		version = meow.version,
		menu_key = state.menu_key and state.menu_key.Name or nil,
		watermark = state.watermark,
		module_list = state.module_list,
		notifications = state.notifications,
		accent = encode_color(theme.accent),
		modules = {},
	}

	for _, mod in ipairs(manager.module_order) do
		local entry = {
			enabled = mod.enabled,
			key = mod.key and mod.key.Name or nil,
			options = {},
		}
		for _, option in ipairs(mod.option_order) do
			if option.kind ~= "button" then
				entry.options[option.name] = encode_option(option)
			end
		end
		data.modules[mod.category .. "/" .. mod.name] = entry
	end

	return data
end

function config.apply(data)
	if type(data) ~= "table" then
		return
	end

	if type(data.menu_key) == "string" and Enum.KeyCode[data.menu_key] then
		state.menu_key = Enum.KeyCode[data.menu_key]
	end
	if type(data.watermark) == "boolean" then
		state.watermark = data.watermark
	end
	if type(data.module_list) == "boolean" then
		state.module_list = data.module_list
	end
	if type(data.notifications) == "boolean" then
		state.notifications = data.notifications
	end

	local accent = decode_color(data.accent)
	if accent then
		theme.set_accent(accent)
	end

	if type(data.modules) ~= "table" then
		return
	end

	for key, entry in pairs(data.modules) do
		local mod = manager.modules[key]
		if mod and type(entry) == "table" then
			if type(entry.key) == "string" and Enum.KeyCode[entry.key] then
				mod.key = Enum.KeyCode[entry.key]
			end
			if type(entry.options) == "table" then
				for _, option in ipairs(mod.option_order) do
					decode_option(option, entry.options[option.name])
				end
			end
			-- saved state wins over the module default, both ways
			mod:set_enabled(entry.enabled == true, true)
		end
	end
end

function config.save()
	if not can_write then
		return false
	end
	if not isfolder(folder) then
		makefolder(folder)
	end
	local ok, encoded = pcall(function()
		return http_service:JSONEncode(config.serialize())
	end)
	if not ok then
		warn("meow: config encode failed: " .. tostring(encoded))
		return false
	end
	local written = pcall(writefile, path, encoded)
	return written
end

function config.load()
	if not can_write or not isfile(path) then
		return false
	end
	local ok, raw = pcall(readfile, path)
	if not ok or type(raw) ~= "string" or #raw == 0 then
		return false
	end
	local decoded, data = pcall(function()
		return http_service:JSONDecode(raw)
	end)
	if not decoded then
		return false
	end
	config.apply(data)
	return true
end

function config.reset()
	manager.disable_all()
	if can_write and isfile(path) and delfile then
		pcall(delfile, path)
	end
end

-- writes are debounced so dragging a slider does not hammer the disk
function config.watch(bin)
	bin:add(manager.changed:connect(function()
		if pending then
			return
		end
		pending = true
		task.delay(1, function()
			pending = false
			config.save()
		end)
	end))
end

config.path = path

return config
