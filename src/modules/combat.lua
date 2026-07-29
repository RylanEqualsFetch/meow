-- combat modules
-- in bedwars these drive the games own sword controller, everywhere else they
-- fall back to the generic behaviour

local util = meow.load("src/core/util.lua")
local manager = meow.load("src/core/manager.lua")
local notify = meow.load("src/ui/notify.lua")
local bedwars = meow.load("src/game/bedwars.lua")

local players = util.services.Players
local user_input = util.services.UserInputService

local combat = manager.category("combat")

-- declared up front because the kill aura tick reads the reach range
local reach

-- kill aura

local aura = combat:module{name = "kill aura", description = "swings at everything in range"}
aura:dropdown{name = "mode", values = {"legit", "rage"}, default = "legit"}
aura:slider{name = "swings", min = 1, max = 20, default = 12, suffix = " cps"}
aura:slider{name = "targets", min = 1, max = 6, default = 3}
aura:toggle{name = "hold weapon only", default = true}

aura.on_enable = function(self)
	if not bedwars.ready() then
		notify.push("kill aura needs the bedwars sword controller")
		error("sword controller not found")
	end
	self.next_swing = 0
end

aura.on_tick = function(self)
	local now = os.clock()
	if now < (self.next_swing or 0) then
		return
	end

	if self:get("hold weapon only") and not bedwars.hand_item() then
		return
	end

	-- reach raises the range the client will accept, so use it when it is on
	local range = reach.range_studs() or bedwars.attack_range()
	local swung = false

	if self:get("mode") == "legit" then
		-- one target, picked by the games own team, sight and match checks
		local target = bedwars.target_in_range(range)
		if target then
			swung = bedwars.attack(target)
		end
	else
		local found = bedwars.entities_in_range(range)
		local limit = math.min(#found, self:get("targets"))
		for index = 1, limit do
			if bedwars.attack(found[index].entity) then
				swung = true
			end
		end
	end

	if swung then
		self.next_swing = now + 1 / math.max(self:get("swings"), 1)
	else
		self.next_swing = now + 0.05
	end
end

-- reach
-- vape writes the shared combat constant the client checks against, which is
-- simpler and more reliable than hooking the swing event

local base_reach = 14.4

reach = combat:module{name = "reach", description = "extends attack reach"}
reach:slider{name = "range", min = 0, max = 18, default = 14, decimals = 1, suffix = " studs"}

local function push_reach(value)
	local constants = bedwars.combat_constant()
	if not constants then
		return false
	end
	constants.RAYCAST_SWORD_CHARACTER_DISTANCE = value
	return true
end

reach.on_enable = function(self)
	if not bedwars.combat_constant() then
		notify.push("reach could not read the combat constants")
		error("combat constant not found")
	end

	push_reach(self:get("range") + 2)

	self.bin:add(self.options["range"]:listen(function(value)
		push_reach(value + 2)
	end))

	self.bin:add(function()
		push_reach(base_reach)
	end)
end

function reach.range_studs()
	if reach.enabled then
		return reach:get("range") + 2
	end
	return nil
end

-- no click delay, drops the swing rate cap the client enforces

local no_click_delay = combat:module{name = "no click delay", description = "removes the cps cap"}

no_click_delay.on_enable = function(self)
	local sword = bedwars.sword()
	if not sword then
		notify.push("no click delay needs the bedwars sword controller")
		error("sword controller not found")
	end

	local original = sword.isClickingTooFast
	sword.isClickingTooFast = function(controller)
		controller.lastAttackTime = 0
		controller.lastSwing = os.clock()
		return false
	end

	self.bin:add(function()
		local current = bedwars.sword()
		if current then
			current.isClickingTooFast = original
		end
	end)
end

-- trigger bot

local trigger = combat:module{name = "trigger bot", description = "swings when a target is under the crosshair"}
trigger:slider{name = "delay", min = 0, max = 400, default = 60, suffix = " ms"}
trigger:slider{name = "range", min = 5, max = 30, default = 16, suffix = " studs"}
trigger:toggle{name = "use reach range", default = true}
trigger:toggle{name = "hold weapon only", default = true}

trigger.on_enable = function(self)
	self.next_swing = 0
	self.native = bedwars.ready()
	if not self.native and type(mouse1click) ~= "function" then
		notify.push("trigger bot needs bedwars or an executor with mouse1click")
		error("no attack path")
	end
end

trigger.on_tick = function(self)
	local now = os.clock()
	if now < (self.next_swing or 0) then
		return
	end

	local camera = workspace.CurrentCamera
	local character = util.character()
	if not camera or not character then
		return
	end

	if self.native and self:get("hold weapon only") and not bedwars.hand_item() then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character, camera}

	local range = self:get("range")
	if self:get("use reach range") then
		range = reach.range_studs() or range
	end

	local hit = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * range, params)
	if not hit or not hit.Instance then
		return
	end

	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	if not model then
		return
	end

	if self.native then
		-- the swing itself goes through the games controller
		local target = bedwars.target_in_range(range)
		if target and bedwars.entity_instance(target) == model then
			if bedwars.attack(target) then
				self.next_swing = now + self:get("delay") / 1000
			end
		end
		return
	end

	local player = players:GetPlayerFromCharacter(model)
	if not player or player == util.local_player() or not util.alive(player) then
		return
	end
	if util.same_team(player) then
		return
	end

	pcall(mouse1click)
	self.next_swing = now + self:get("delay") / 1000
end

-- aim assist

local aim = combat:module{name = "aim assist", description = "smooth camera pull toward a target"}
aim:slider{name = "fov", min = 20, max = 400, default = 110, suffix = " px"}
aim:slider{name = "smoothness", min = 1, max = 25, default = 9}
aim:dropdown{name = "target part", values = {"head", "torso", "root"}, default = "head"}
aim:dropdown{name = "activate", values = {"always", "right mouse", "left mouse"}, default = "always"}
aim:toggle{name = "visible check", default = true}
aim:toggle{name = "team check", default = true}

local part_names = {head = "Head", torso = "UpperTorso", root = "HumanoidRootPart"}

local function pick_part(character, kind)
	local wanted = part_names[kind] or "Head"
	return character:FindFirstChild(wanted)
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
		or character.PrimaryPart
end

local function has_line_of_sight(camera, part, character)
	local origin = camera.CFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {util.character(), camera}

	local hit = workspace:Raycast(origin, part.Position - origin, params)
	if not hit or not hit.Instance then
		return true
	end
	return hit.Instance:IsDescendantOf(character)
end

-- the player list is cheap and covers every case, the entity query is not, so
-- it only runs on a timer as a fallback when the player list came up empty
local candidate_cache = {list = {}, stamp = 0}

local function aim_candidates()
	local me = util.local_player()
	local out = {}

	for _, player in ipairs(players:GetPlayers()) do
		if player ~= me and util.alive(player) then
			local character = util.character(player)
			if character then
				table.insert(out, character)
			end
		end
	end

	if #out > 0 then
		return out
	end

	local now = os.clock()
	if now - candidate_cache.stamp < 0.25 then
		return candidate_cache.list
	end

	local found = {}
	if bedwars.ready() then
		for _, entry in ipairs(bedwars.entities_in_range(300)) do
			table.insert(found, entry.instance)
		end
	end

	candidate_cache.list = found
	candidate_cache.stamp = now
	return found
end

aim.on_enable = function(self)
	-- the game rewrites the camera every frame, so this has to land after it
	util.render_step("meow_aim_assist", function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local activate = self:get("activate")
		if activate == "right mouse"
			and not user_input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
			return
		end
		if activate == "left mouse"
			and not user_input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			return
		end

		local viewport = camera.ViewportSize
		local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
		local fov = self:get("fov")
		local kind = self:get("target part")
		local team_check = self:get("team check")
		local visible_check = self:get("visible check")

		local best, best_distance

		for _, character in ipairs(aim_candidates()) do
			local player = players:GetPlayerFromCharacter(character)
			local skip = team_check and player ~= nil and util.same_team(player)
			local part = not skip and pick_part(character, kind) or nil

			if part then
				local screen, on_screen = camera:WorldToViewportPoint(part.Position)
				if on_screen then
					local distance = (Vector2.new(screen.X, screen.Y) - center).Magnitude
					if distance <= fov and (not best_distance or distance < best_distance) then
						if not visible_check or has_line_of_sight(camera, part, character) then
							best = part
							best_distance = distance
						end
					end
				end
			end
		end

		if not best then
			return
		end

		local goal = CFrame.new(camera.CFrame.Position, best.Position)
		camera.CFrame = camera.CFrame:Lerp(goal, 1 / math.max(self:get("smoothness"), 1))
	end, self.bin)
end

return true
