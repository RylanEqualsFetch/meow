-- categories, modules and their options

local util = meow.load("src/core/util.lua")

local manager = {
	categories = {},
	category_order = {},
	modules = {},
	module_order = {},
	toggled = util.signal(),
	changed = util.signal(),
	registered = util.signal(),
	running = false,
}

local option_mt = {}
option_mt.__index = option_mt

function option_mt:set(value, silent)
	if self.kind == "slider" then
		value = util.clamp(tonumber(value) or self.min, self.min, self.max)
		value = util.round(value, self.decimals)
	elseif self.kind == "toggle" then
		value = value and true or false
	elseif self.kind == "dropdown" and not self.multi then
		local found = false
		for _, entry in ipairs(self.values) do
			if entry == value then
				found = true
				break
			end
		end
		if not found then
			return
		end
	end

	if self.value == value and self.kind ~= "dropdown" then
		return
	end

	self.value = value
	for _, fn in ipairs(self.listeners) do
		local ok, err = pcall(fn, value, self)
		if not ok then
			warn("meow: option listener error on " .. self.name .. ": " .. tostring(err))
		end
	end
	if self.callback then
		local ok, err = pcall(self.callback, value, self)
		if not ok then
			warn("meow: option callback error on " .. self.name .. ": " .. tostring(err))
		end
	end
	if not silent then
		manager.changed:fire()
	end
end

-- same contract as util.signal, returns a connection a bin can drop
function option_mt:listen(fn)
	local listeners = self.listeners
	table.insert(listeners, fn)

	local connection = {connected = true}
	function connection:disconnect()
		if not self.connected then
			return
		end
		self.connected = false
		for index, listener in ipairs(listeners) do
			if listener == fn then
				table.remove(listeners, index)
				return
			end
		end
	end

	return connection
end

local module_mt = {}
module_mt.__index = module_mt

local function add_option(self, kind, def)
	assert(type(def) == "table" and type(def.name) == "string", "meow: option needs a name")
	local option = setmetatable({
		kind = kind,
		name = def.name,
		tooltip = def.tooltip,
		module = self,
		listeners = {},
		callback = def.callback,
	}, option_mt)

	if kind == "toggle" then
		option.value = def.default and true or false
	elseif kind == "slider" then
		option.min = def.min or 0
		option.max = def.max or 100
		option.decimals = def.decimals or 0
		option.suffix = def.suffix or ""
		option.value = util.clamp(def.default or option.min, option.min, option.max)
	elseif kind == "dropdown" then
		option.values = def.values or {}
		option.multi = def.multi and true or false
		if option.multi then
			option.value = def.default or {}
		else
			option.value = def.default or option.values[1]
		end
	elseif kind == "color" then
		option.value = def.default or Color3.fromRGB(198, 134, 255)
	elseif kind == "input" then
		option.value = def.default or ""
		option.placeholder = def.placeholder or ""
	elseif kind == "button" then
		option.value = nil
		option.action = def.action
	end

	self.options[def.name] = option
	table.insert(self.option_order, option)
	return option
end

function module_mt:toggle(def)
	return add_option(self, "toggle", def)
end

function module_mt:slider(def)
	return add_option(self, "slider", def)
end

function module_mt:dropdown(def)
	return add_option(self, "dropdown", def)
end

function module_mt:color(def)
	return add_option(self, "color", def)
end

function module_mt:input(def)
	return add_option(self, "input", def)
end

function module_mt:button(def)
	return add_option(self, "button", def)
end

function module_mt:get(name)
	local option = self.options[name]
	if not option then
		return nil
	end
	return option.value
end

function module_mt:set_key(key)
	self.key = key
	manager.changed:fire()
end

function module_mt:set_enabled(enabled, silent)
	enabled = enabled and true or false
	if self.enabled == enabled then
		return
	end
	self.enabled = enabled

	if enabled then
		if self.on_enable then
			local ok, err = pcall(self.on_enable, self)
			if not ok then
				warn("meow: " .. self.name .. " failed to enable: " .. tostring(err))
				self.enabled = false
				self.bin:clean()
				manager.toggled:fire(self, false)
				return
			end
		end
	else
		self.bin:clean()
		if self.on_disable then
			local ok, err = pcall(self.on_disable, self)
			if not ok then
				warn("meow: " .. self.name .. " failed to disable: " .. tostring(err))
			end
		end
	end

	manager.toggled:fire(self, self.enabled)
	if not silent then
		manager.changed:fire()
	end
end

function module_mt:set_state(enabled, silent)
	self:set_enabled(enabled, silent)
end

function module_mt:toggle_state()
	self:set_enabled(not self.enabled)
end

local category_mt = {}
category_mt.__index = category_mt

function category_mt:module(def)
	assert(type(def) == "table" and type(def.name) == "string", "meow: module needs a name")

	local mod = setmetatable({
		name = def.name,
		description = def.description,
		category = self.name,
		enabled = false,
		key = def.key,
		hidden = def.hidden and true or false,
		default_on = def.default and true or false,
		on_enable = def.on_enable,
		on_disable = def.on_disable,
		on_tick = def.on_tick,
		options = {},
		option_order = {},
		bin = util.bin(),
	}, module_mt)

	table.insert(self.modules, mod)
	table.insert(manager.module_order, mod)
	manager.modules[self.name .. "/" .. def.name] = mod
	manager.registered:fire(mod)
	return mod
end

function manager.category(name)
	local existing = manager.categories[name]
	if existing then
		return existing
	end

	local category = setmetatable({
		name = name,
		modules = {},
		index = #manager.category_order + 1,
	}, category_mt)

	manager.categories[name] = category
	table.insert(manager.category_order, category)
	return category
end

function manager.find(name)
	for _, mod in ipairs(manager.module_order) do
		if mod.name == name then
			return mod
		end
	end
	return nil
end

function manager.fire_key(key)
	if typeof(key) ~= "EnumItem" then
		return
	end
	for _, mod in ipairs(manager.module_order) do
		if mod.key == key then
			mod:toggle_state()
		end
	end
end

function manager.disable_all()
	for _, mod in ipairs(manager.module_order) do
		mod:set_enabled(false, true)
	end
end

-- one heartbeat loop drives every enabled module that wants ticks
function manager.start(bin)
	if manager.running then
		return
	end
	manager.running = true

	local run_service = util.services.RunService
	bin:add(run_service.Heartbeat:Connect(function(delta)
		for _, mod in ipairs(manager.module_order) do
			if mod.enabled and mod.on_tick then
				local ok, err = pcall(mod.on_tick, mod, delta)
				if not ok then
					warn("meow: " .. mod.name .. " tick error: " .. tostring(err))
					mod:set_enabled(false)
				end
			end
		end
	end))

	bin:add(function()
		manager.running = false
	end)
end

return manager
