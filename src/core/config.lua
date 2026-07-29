-- saves module states, keybinds, option values and window layout to disk
-- the ui half is applied before the window is built, the module half after

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
	local columns = {}
	for name, entry in pairs(state.columns) do
		columns[name] = {
			open = entry.open ~= false,
			collapsed = entry.collapsed == true,
			x = entry.x,
			y = entry.y,
		}
	end

	local data = {
		version = meow.version,
		accent = encode_color(theme.accent),
		font = theme.family,
		nav_x = state.nav_x,
		nav_y = state.nav_y,
		columns = columns,
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

-- theme and layout, safe to run before the window exists
function config.apply_ui(data)
	if type(data) ~= "table" then
		return
	end

	if type(data.font) == "string" then
		theme.set_family(data.font)
	end

	local accent = decode_color(data.accent)
	if accent then
		theme.set_accent(accent)
	end

	if type(data.nav_x) == "number" then
		state.nav_x = data.nav_x
	end
	if type(data.nav_y) == "number" then
		state.nav_y = data.nav_y
	end

	if type(data.columns) == "table" then
		for name, entry in pairs(data.columns) do
			if type(entry) == "table" then
				state.columns[name] = {
					open = entry.open ~= false,
					collapsed = entry.collapsed == true,
					x = tonumber(entry.x),
					y = tonumber(entry.y),
				}
			end
		end
	end
end

-- module states and option values, needs the window so the rows can follow
function config.apply_modules(data)
	if type(data) ~= "table" or type(data.modules) ~= "table" then
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

	manager.changed:fire()
end

function config.read()
	if not can_write or not isfile(path) then
		return nil
	end
	local ok, raw = pcall(readfile, path)
	if not ok or type(raw) ~= "string" or #raw == 0 then
		return nil
	end
	local decoded, data = pcall(function()
		return http_service:JSONDecode(raw)
	end)
	if not decoded or type(data) ~= "table" then
		return nil
	end
	return data
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
	return pcall(writefile, path, encoded)
end

function config.load()
	local data = config.read()
	if not data then
		return false
	end
	config.apply_ui(data)
	config.apply_modules(data)
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
