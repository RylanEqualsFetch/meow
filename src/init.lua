-- meow entry point

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local state = meow.load("src/core/state.lua")
local manager = meow.load("src/core/manager.lua")
local config = meow.load("src/core/config.lua")
local notify = meow.load("src/ui/notify.lua")
local splash = meow.load("src/ui/splash.lua")
local fonts = meow.load("src/ui/fonts.lua")

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
state.ui.host = host

local boot = splash.create(gui)
bin:add(function()
	pcall(function()
		boot:finish()
	end)
end)

boot:set(0.08, "starting")
task.wait(0.12)

-- inter is not shipped with roblox, so the faces are downloaded once and wired
-- up through a generated family manifest. everything still runs without it
boot:set(0.16, "loading font")
local family, font_reason = fonts.install(fonts.inter, function(alpha, text)
	boot:set(0.16 + alpha * 0.2, text)
end)

if family then
	theme.families["inter"] = family
	table.insert(theme.family_order, 1, "inter")
	theme.family = "inter"
else
	warn("meow: inter unavailable, " .. tostring(font_reason))
end

boot:set(0.42, "loading modules")
task.wait(0.1)

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

-- theme and layout prefs next so the window is built with them already applied
local saved = config.read()
if saved then
	config.apply_ui(saved)
end

boot:set(0.62, "building interface")
task.wait(0.1)

local watermark = meow.load("src/ui/watermark.lua")
local modulelist = meow.load("src/ui/modulelist.lua")
local library = meow.load("src/ui/library.lua")

notify.init(gui, bin)

state.ui.watermark = watermark.create(gui, bin)
state.ui.list = modulelist.create(gui, bin)
state.ui.window = library.create(gui, bin)

state.ui.watermark:set_visible(false)

-- closing the window through the nav keeps the menu module in sync
bin:add(state.ui.window.closed:connect(function()
	local menu = manager.modules["settings/menu"]
	if menu then
		menu:set_enabled(false)
	end
end))

boot:set(0.84, "restoring config")
task.wait(0.1)

-- defaults first, then the saved config wins.
-- restoring runs off the boot thread on purpose. enabling a saved module calls
-- its on_enable, and some of those yield, the texture pack and animation player
-- both wait on game:GetObjects, so doing this inline left the splash parked on
-- this stage forever whenever one of them was slow or never returned
task.spawn(function()
	for _, mod in ipairs(manager.module_order) do
		if mod.default_on then
			pcall(function()
				mod:set_enabled(true, true)
			end)
		end
	end

	if saved then
		pcall(config.apply_modules, saved)
	end
end)

config.watch(bin)
manager.start(bin)

-- a toast whenever a module flips, hidden ones stay quiet
bin:add(manager.toggled:connect(function(mod, enabled)
	if mod.hidden then
		return
	end
	notify.push(mod.name .. (enabled and " on" or " off"), 2)
end))

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

boot:set(1, "ready")

-- a watchdog as well, nothing after this point may keep the splash on screen
task.delay(4, function()
	pcall(function()
		boot:finish()
	end)
end)

task.wait(0.24)
boot:finish()

if state.watermark and state.ui.watermark then
	state.ui.watermark:intro()
end

local menu = manager.modules["settings/menu"]
notify.push("meow " .. meow.version .. " loaded, press " ..
	(menu and menu.key and util.key_name(menu.key) or "right shift") .. " for the menu", 5)

-- automatic diagnostics
-- the game requires its own modules over the first few seconds, so this runs
-- twice, once early and once late enough that anything slow has landed. the full
-- report goes to the console and only the failures are toasted, so a clean run
-- costs one line and a broken one names the hook that is missing
local bedwars = meow.load("src/game/bedwars.lua")

local function auto_report(label)
	if not state.auto_report then
		return
	end

	local lines = bedwars.report()

	print("[meow] report " .. label .. ", version " .. tostring(meow.version))
	for _, line in ipairs(lines) do
		print("[meow] " .. line)
	end

	local missing = {}
	for _, line in ipairs(lines) do
		local name = line:match("^(.+): missing$")
		if name then
			table.insert(missing, name)
		end
	end

	if #missing == 0 then
		notify.push("all game hooks resolved", 4)
	else
		notify.push("missing: " .. table.concat(missing, ", "), 10)
	end
end

task.delay(3, function()
	pcall(auto_report, "early")
end)

task.delay(15, function()
	pcall(auto_report, "late")
end)

return true
