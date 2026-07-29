-- combat modules
-- generic for now, bedwars specific remote work lands on top of this same api

local util = meow.load("src/core/util.lua")
local manager = meow.load("src/core/manager.lua")
local notify = meow.load("src/ui/notify.lua")

local players = util.services.Players

local combat = manager.category("combat")

-- hitbox expander

local hitbox = combat:module{name = "hitbox", description = "grows enemy root parts"}
-- bedwars rejects hits from far outside the real hitbox, small values only
hitbox:slider{name = "size", min = 2, max = 7, default = 3.5, decimals = 1}
hitbox:slider{name = "transparency", min = 0, max = 1, default = 0.75, decimals = 2}
hitbox:toggle{name = "team check", default = true}

hitbox.on_enable = function(self)
	self.saved = {}
	self.bin:add(function()
		for part, data in pairs(self.saved) do
			if part and part.Parent then
				pcall(function()
					part.Size = data.size
					part.Transparency = data.transparency
					part.CanCollide = data.collide
					part.Massless = data.massless
				end)
			end
		end
		self.saved = nil
	end)
end

hitbox.on_tick = function(self)
	local me = util.local_player()
	local size = self:get("size")
	local transparency = self:get("transparency")
	local team_check = self:get("team check")

	for _, player in ipairs(players:GetPlayers()) do
		if player ~= me and util.alive(player) then
			if not (team_check and util.same_team(player)) then
				local root = util.root(player)
				if root then
					if not self.saved[root] then
						self.saved[root] = {
							size = root.Size,
							transparency = root.Transparency,
							collide = root.CanCollide,
							massless = root.Massless,
						}
					end
					root.Size = Vector3.new(size, size, size)
					root.Transparency = transparency
					root.CanCollide = false
					root.Massless = true
				end
			end
		end
	end
end

-- trigger bot, clicks when the crosshair sits on an enemy

local trigger = combat:module{name = "trigger bot", description = "clicks when aiming at an enemy"}
trigger:slider{name = "delay", min = 20, max = 500, default = 90, suffix = " ms"}
trigger:slider{name = "range", min = 5, max = 25, default = 18, suffix = " studs"}
trigger:toggle{name = "team check", default = true}

local function click_mouse()
	local click = mouse1click or (Input and Input.LeftClick)
	if type(click) == "function" then
		click()
		return true
	end
	return false
end

trigger.on_enable = function(self)
	if not (mouse1click or (Input and Input.LeftClick)) then
		notify.push("trigger bot needs an executor with mouse1click")
		error("no mouse click function")
	end
	self.next_click = 0
end

trigger.on_tick = function(self)
	local camera = workspace.CurrentCamera
	local character = util.character()
	if not camera or not character then
		return
	end

	local now = os.clock()
	if now < (self.next_click or 0) then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character, camera}

	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * self:get("range"), params)
	if not hit or not hit.Instance then
		return
	end

	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	if not model then
		return
	end

	local player = players:GetPlayerFromCharacter(model)
	if not player or player == util.local_player() then
		return
	end
	if not util.alive(player) then
		return
	end
	if self:get("team check") and util.same_team(player) then
		return
	end

	if click_mouse() then
		self.next_click = now + self:get("delay") / 1000
	end
end

-- reach, extends tool grip range by scaling the handle hit region

local reach = combat:module{name = "reach", description = "extends the reach of the held tool"}
reach:slider{name = "studs", min = 0.5, max = 5, default = 2.5, decimals = 1}

reach.on_enable = function(self)
	self.parts = {}
	self.bin:add(function()
		for part, size in pairs(self.parts) do
			if part and part.Parent then
				pcall(function()
					part.Size = size
				end)
			end
		end
		self.parts = nil
	end)
end

reach.on_tick = function(self)
	local character = util.character()
	if not character then
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	if not self.parts[handle] then
		self.parts[handle] = handle.Size
	end

	local base = self.parts[handle]
	local extra = self:get("studs")
	handle.Size = Vector3.new(base.X + extra, base.Y + extra, base.Z + extra)
	handle.Massless = true
	handle.CanCollide = false
end

return true
