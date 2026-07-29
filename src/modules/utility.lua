-- utility modules

local util = meow.load("src/core/util.lua")
local manager = meow.load("src/core/manager.lua")
local notify = meow.load("src/ui/notify.lua")

local players = util.services.Players
local user_input = util.services.UserInputService

local utility = manager.category("utility")

-- anti afk

local anti_afk = utility:module{name = "anti afk", description = "blocks the idle kick"}

anti_afk.on_enable = function(self)
	local player = util.local_player()
	local virtual_user = util.services.VirtualUser

	self.bin:add(player.Idled:Connect(function()
		pcall(function()
			virtual_user:CaptureController()
			virtual_user:ClickButton2(Vector2.new())
		end)
	end))
end

-- auto clicker

local auto_clicker = utility:module{name = "auto clicker", description = "clicks while the mouse is held"}
-- anything past twenty clicks a second reads as automated, cap it there
auto_clicker:slider{name = "cps", min = 1, max = 20, default = 12}
auto_clicker:toggle{name = "hold only", default = true}

auto_clicker.on_enable = function(self)
	local click = mouse1click or (Input and Input.LeftClick)
	if type(click) ~= "function" then
		notify.push("auto clicker needs an executor with mouse1click")
		error("no mouse click function")
	end

	local held = false
	self.bin:add(user_input.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			held = true
		end
	end))
	self.bin:add(user_input.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			held = false
		end
	end))

	local running = true
	self.bin:add(function()
		running = false
	end)

	task.spawn(function()
		while running do
			if not self:get("hold only") or held then
				pcall(click)
			end
			task.wait(1 / math.max(self:get("cps"), 1))
		end
	end)
end

-- fps cap

local fps_cap = utility:module{name = "fps cap", description = "raises or lowers the frame limit"}
fps_cap:slider{name = "limit", min = 30, max = 360, default = 240}

fps_cap.on_enable = function(self)
	if type(setfpscap) ~= "function" then
		notify.push("fps cap needs an executor with setfpscap")
		error("no setfpscap function")
	end
	setfpscap(self:get("limit"))
	self.bin:add(self.options["limit"]:listen(function(value)
		setfpscap(value)
	end))
	self.bin:add(function()
		setfpscap(60)
	end)
end

-- player list logging

local join_logger = utility:module{name = "join logger", description = "toast when a player joins or leaves"}

join_logger.on_enable = function(self)
	self.bin:add(players.PlayerAdded:Connect(function(player)
		notify.push(player.Name .. " joined")
	end))
	self.bin:add(players.PlayerRemoving:Connect(function(player)
		notify.push(player.Name .. " left")
	end))
end

-- rejoin

local rejoin = utility:module{name = "rejoin", description = "teleports you back into the same server"}

rejoin.on_enable = function(self)
	local teleport = util.services.TeleportService
	local player = util.local_player()
	notify.push("rejoining")
	task.spawn(function()
		pcall(function()
			teleport:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
		end)
	end)
	task.delay(0.4, function()
		self:set_enabled(false)
	end)
end

return true
