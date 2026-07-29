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
-- vape writes the shared combat constant, but attackEntity only falls back to
-- that when the weapon carries no attackRange of its own, and every sword does,
-- so the item meta has to be patched as well or nothing changes

local base_reach = 14.4

reach = combat:module{name = "reach", description = "extends attack reach"}
reach:slider{name = "range", min = 0, max = 18, default = 14, decimals = 1, suffix = " studs"}

local sword_ranges = {}

local function apply_reach(studs)
	local constants = bedwars.combat_constant()
	if constants then
		constants.RAYCAST_SWORD_CHARACTER_DISTANCE = studs + 2
		constants.REGION_SWORD_CHARACTER_DISTANCE = studs + 2
	end

	local meta = bedwars.item_meta()
	if not meta then
		return constants ~= nil
	end

	for name, entry in pairs(meta) do
		if type(entry) == "table" and type(entry.sword) == "table" then
			if sword_ranges[name] == nil then
				sword_ranges[name] = entry.sword.attackRange or false
			end
			entry.sword.attackRange = studs
		end
	end

	return true
end

local function restore_reach()
	local constants = bedwars.combat_constant()
	if constants then
		constants.RAYCAST_SWORD_CHARACTER_DISTANCE = base_reach
		constants.REGION_SWORD_CHARACTER_DISTANCE = 12.6
	end

	local meta = bedwars.item_meta()
	if meta then
		for name, saved in pairs(sword_ranges) do
			local entry = meta[name]
			if type(entry) == "table" and type(entry.sword) == "table" then
				entry.sword.attackRange = saved or nil
			end
		end
	end
	sword_ranges = {}
end

reach.on_enable = function(self)
	local attached = {}

	-- one, the shared constant, which only matters for weapons with no range
	if bedwars.combat_constant() then
		table.insert(attached, "constant")
	end

	-- two, the raw item meta, this is what attackEntity actually reads
	local meta = bedwars.item_meta()
	if meta then
		table.insert(attached, "item meta")
	end

	apply_reach(self:get("range"))

	-- three, the per swing meta clone, the same hook the games dagger uses
	local hook = bedwars.hook_sword_meta and bedwars.hook_sword_meta(function(clone)
		if type(clone.sword) == "table" then
			clone.sword.attackRange = self:get("range")
		end
	end)

	local events = bedwars.sync_events()
	if events and not hook then
		local ok, handle = pcall(function()
			return events.BeforeSwordSwing:connect(function(_, payload)
				if type(payload) == "table" and type(payload.weaponMetaClone) == "table" then
					local sword = payload.weaponMetaClone.sword
					if type(sword) == "table" then
						sword.attackRange = self:get("range")
					end
				end
			end)
		end)
		if ok then
			hook = handle
			table.insert(attached, "swing hook")
		end
	end

	if hook then
		self.bin:add(function()
			pcall(function()
				if type(hook) == "function" then
					hook()
				elseif type(hook) == "table" then
					if type(hook.disconnect) == "function" then
						hook:disconnect()
					elseif type(hook.Disconnect) == "function" then
						hook:Disconnect()
					end
				end
			end)
		end)
	end

	if #attached == 0 then
		notify.push("reach found nothing to patch, run debug info")
		error("no reach mechanism available")
	end

	notify.push("reach hooked " .. table.concat(attached, ", "), 4)

	self.bin:add(self.options["range"]:listen(function(value)
		apply_reach(value)
	end))

	self.bin:add(restore_reach)
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
aim:slider{name = "speed", min = 1, max = 40, default = 14}
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
	-- vape runs this on heartbeat with a delta scaled lerp toward lookAt, which
	-- lands after the games own camera step without fighting a render binding
	self.bin:add(util.services.RunService.Heartbeat:Connect(function(delta)
		local camera = workspace.CurrentCamera
		local root = util.root()
		if not camera or not root then
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

		local goal = CFrame.lookAt(camera.CFrame.Position, best.Position)
		camera.CFrame = camera.CFrame:Lerp(goal, math.min(self:get("speed") * delta, 1))
	end))
end

-- velocity, scales the knockback the client applies to you

local velocity = combat:module{name = "velocity", description = "reduces knockback taken"}
velocity:slider{name = "horizontal", min = 0, max = 100, default = 0, suffix = " pct"}
velocity:slider{name = "vertical", min = 0, max = 100, default = 0, suffix = " pct"}
velocity:slider{name = "chance", min = 0, max = 100, default = 100, suffix = " pct"}

velocity.on_enable = function(self)
	local knockback = bedwars.knockback_util()
	if not knockback or type(knockback.applyKnockback) ~= "function" then
		notify.push("velocity needs the bedwars knockback util")
		error("knockback util not found")
	end

	local original = knockback.applyKnockback
	local roll = Random.new()

	knockback.applyKnockback = function(part, mass, direction, values, ...)
		if roll:NextNumber(0, 100) <= self:get("chance") then
			values = values or {}
			values.horizontal = (values.horizontal or 1) * (self:get("horizontal") / 100)
			values.vertical = (values.vertical or 1) * (self:get("vertical") / 100)
		end
		return original(part, mass, direction, values, ...)
	end

	self.bin:add(function()
		local current = bedwars.knockback_util()
		if current then
			current.applyKnockback = original
		end
	end)
end

-- projectile aimbot, rewrites the launch values the client computes

local projectile = combat:module{name = "projectile aimbot", description = "aims thrown items and arrows"}
projectile:slider{name = "fov", min = 50, max = 1000, default = 400, suffix = " px"}
projectile:dropdown{name = "target part", values = {"root", "head"}, default = "root"}
projectile:toggle{name = "arrows only", default = false}
projectile:toggle{name = "team check", default = true}

-- iterative ballistic solve, converges on the lead point in a few passes
local function solve_trajectory(origin, speed, gravity, target_pos, target_vel, passes)
	local flight = (target_pos - origin).Magnitude / math.max(speed, 1)

	for _ = 1, passes or 5 do
		local predicted = target_pos + target_vel * flight
		local aim = predicted + Vector3.new(0, 0.5 * gravity * flight * flight, 0)
		flight = (aim - origin).Magnitude / math.max(speed, 1)
	end

	local predicted = target_pos + target_vel * flight
	return predicted + Vector3.new(0, 0.5 * gravity * flight * flight, 0)
end

projectile.on_enable = function(self)
	local controller = bedwars.projectile_controller()
	if not controller or type(controller.calculateImportantLaunchValues) ~= "function" then
		notify.push("projectile aimbot needs the bedwars projectile controller")
		error("projectile controller not found")
	end

	local original = controller.calculateImportantLaunchValues
	local bow = bedwars.bow_constants()

	projectile.calls = 0
	projectile.hits = 0

	controller.calculateImportantLaunchValues = function(this, projectile_meta, world_meta, origin, shoot_position, ...)
		projectile.calls = projectile.calls + 1
		local ok, result = pcall(function()
			local camera = workspace.CurrentCamera
			local root = util.root()
			if not camera or not root then
				return nil
			end

			local name = tostring(projectile_meta and projectile_meta.projectile or "")
			if self:get("arrows only") and not name:find("arrow", 1, true) then
				return nil
			end

			local start = shoot_position
			if not start then
				local got, launch = pcall(function()
					return this:getLaunchPosition(origin)
				end)
				start = got and launch or root.Position
			end
			if not start then
				return nil
			end

			local viewport = camera.ViewportSize
			local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
			local fov = self:get("fov")
			local wanted = self:get("target part") == "head" and "head" or "root"

			local best, best_distance
			for _, character in ipairs(aim_candidates()) do
				local player = players:GetPlayerFromCharacter(character)
				if not (self:get("team check") and player ~= nil and util.same_team(player)) then
					local part = pick_part(character, wanted)
					if part then
						local screen, on_screen = camera:WorldToViewportPoint(part.Position)
						if on_screen then
							local distance = (Vector2.new(screen.X, screen.Y) - center).Magnitude
							if distance <= fov and (not best_distance or distance < best_distance) then
								best = part
								best_distance = distance
							end
						end
					end
				end
			end

			if not best then
				return nil
			end

			local meta = {}
			if type(projectile_meta.getProjectileMeta) == "function" then
				local got, value = pcall(function()
					return projectile_meta:getProjectileMeta()
				end)
				if got and type(value) == "table" then
					meta = value
				end
			end

			local speed = meta.launchVelocity or 100
			local gravity = (meta.gravitationalAcceleration or 196.2)
				* (projectile_meta.gravityMultiplier or 1)
			local lifetime = (world_meta and meta.predictionLifetimeSec) or meta.lifetimeSec or 3

			local offset = start
			if bow and name ~= "owl_projectile" then
				offset = start + Vector3.new(bow.RelX or 0, bow.RelY or 0, bow.RelZ or 0)
			end

			local aim = solve_trajectory(offset, speed, gravity, best.Position, best.AssemblyLinearVelocity, 5)

			return {
				initialVelocity = CFrame.lookAt(offset, aim).LookVector * speed,
				positionFrom = offset,
				deltaT = lifetime,
				gravitationalAcceleration = gravity,
				drawDurationSeconds = 5,
			}
		end)

		if ok and result then
			projectile.hits = projectile.hits + 1
			return result
		end
		return original(this, projectile_meta, world_meta, origin, shoot_position, ...)
	end

	self.bin:add(function()
		local current = bedwars.projectile_controller()
		if current then
			current.calculateImportantLaunchValues = original
		end
	end)
end

-- bed breaker
-- picks the closest reachable face of a tagged bed, swaps to the tool its meta
-- asks for, then drives the games own damage block remote

local breaker = combat:module{name = "bed breaker", description = "breaks beds and blocks nearby"}
breaker:slider{name = "range", min = 6, max = 30, default = 18, suffix = " studs"}
breaker:slider{name = "rate", min = 2, max = 30, default = 12, suffix = " hits"}
breaker:toggle{name = "swap tools", default = true}
breaker:toggle{name = "beds only", default = true}

breaker.on_enable = function(self)
	if not bedwars.block_remotes() then
		notify.push("bed breaker needs the block engine remotes")
		error("block remotes not found")
	end
	self.next_hit = 0
end

breaker.on_tick = function(self)
	local root = util.root()
	if not root then
		return
	end

	local now = os.clock()
	if now < (self.next_hit or 0) then
		return
	end

	local controller = bedwars.block_controller()
	if not controller then
		return
	end

	local range = self:get("range")
	local best, best_distance, best_part

	for _, bed in ipairs(bedwars.beds()) do
		local part = bed:IsA("BasePart") and bed or bed:FindFirstChildWhichIsA("BasePart", true)
		if part then
			-- skip your own bed, the team attribute is on the bed itself
			local team = bed:GetAttribute("Team") or bed:GetAttribute("team")
			local mine = bedwars.team_of()
			if not (team ~= nil and mine ~= nil and tostring(team) == tostring(mine)) then
				local distance = (part.Position - root.Position).Magnitude
				if distance <= range and (not best_distance or distance < best_distance) then
					best, best_distance, best_part = bed, distance, part
				end
			end
		end
	end

	if not best_part then
		self.next_hit = now + 0.2
		return
	end

	if self:get("swap tools") then
		local break_type = bedwars.break_type_of(best.Name) or "wood"
		local tools = bedwars.tools_by_break_type()
		local tool = tools[break_type]
		if tool then
			bedwars.equip(tool)
		end
	end

	local ok, block_position = pcall(function()
		return controller:getBlockPosition(best_part.Position)
	end)
	if not ok or not block_position then
		self.next_hit = now + 0.2
		return
	end

	bedwars.damage_block(block_position, best_part.Position)
	self.next_hit = now + 1 / math.max(self:get("rate"), 1)
end

return true