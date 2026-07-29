-- meow entry point

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local state = meow.load("src/core/state.lua")
local manager = meow.load("src/core/manager.lua")
local config = meow.load("src/core/config.lua")
local notify = meow.load("src/ui/notify.lua")

local user_input = util.services.UserInputService

local bin = util.bin()

-- gui host, hidden containers first so the client survives resets and screenshots
local host
if type(gethui) == "function" then
	host = gethui()
elseif type(get_hidden_gui) == "function" then
	host = get_hidden_gui()
else
	host = game:GetService("CoreGui")
end

local gui = util.new("ScreenGui", {
	Name = "meow",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
})

if syn and type(syn.protect_gui) == "function" then
	pcall(syn.protect_gui, gui)
end

gui.Parent = host
bin:add(gui)
state.ui.gui = gui

-- module definitions, load order sets the category order in the window
local module_files = {
	"src/modules/combat.lua",
	"src/modules/movement.lua",
	"src/modules/render.lua",
	"src/modules/utility.lua",
	"src/modules/settings.lua",
}

for _, path in ipairs(module_files) do
	local ok, err = pcall(meow.load, path)
	if not ok then
		warn("meow: failed to load " .. path .. ": " .. tostring(err))
	end
end

-- ui, built after the modules so the window can render them
local watermark = meow.load("src/ui/watermark.lua")
local modulelist = meow.load("src/ui/modulelist.lua")
local library = meow.load("src/ui/library.lua")

notify.init(gui, bin)

state.ui.watermark = watermark.create(gui, bin)
state.ui.list = modulelist.create(gui, bin)
state.ui.window = library.create(gui, bin)

-- closing the window through the x keeps the menu module in sync
bin:add(state.ui.window.closed:connect(function()
	local menu = manager.modules["settings/menu"]
	if menu then
		menu:set_enabled(false)
	end
end))

-- defaults first, then the saved config wins
for _, mod in ipairs(manager.module_order) do
	if mod.default_on then
		mod:set_enabled(true, true)
	end
end

config.load()
config.watch(bin)

manager.start(bin)

bin:add(user_input.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if user_input:GetFocusedTextBox() then
		return
	end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		manager.fire_key(input.KeyCode)
	end
end))

function meow.unload()
	pcall(function()
		manager.disable_all()
	end)
	pcall(function()
		bin:clean()
	end)
	pcall(theme.reset_bindings)
	state.ui = {}
	local genv = (getgenv and getgenv()) or _G
	if rawget(genv, "meow") == meow then
		genv.meow = nil
	end
end

local menu_key = manager.modules["settings/menu"]
notify.push("meow " .. meow.version .. " loaded, press " ..
	(menu_key and menu_key.key and util.key_name(menu_key.key) or "right shift") .. " for the menu", 5)

return true
