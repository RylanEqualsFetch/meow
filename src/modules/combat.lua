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
aura:slider{name = "range", min = 5, max = 40, default = 18, decimals = 1, suffix = " studs"}
aura:slider{name = "swings", min = 1, max = 20, default = 12, suffix = " cps"}
aura:slider{name = "targets", min = 1, max = 6, default = 3}
aura:slider{name = "angle", min = 30, max = 360, default = 360, suffix = " deg"}
aura:dropdown{name = "method", values = {"silent", "controller", "both"}, default = "silent"}
aura:toggle{name = "wall check", default = false}
aura:toggle{name = "team check", default = true}

aura.on_enable = function(self)
	self.next_swing = 0

	local remote = bedwars.attack_remote() ~= nil
	local controller = bedwars.ready()

	if not remote and not controller then
		notify.push("kill aura found no swing path yet, it will retry")
	elseif not remote then
		notify.push("kill aura is on the controller path, no swing remote found", 4)
	end
end

-- everything alive and hostile inside the range, nearest first
local function aura_targets(self, range)
	local me = util.local_player()
	local my_root = util.root()
	local out = {}
	if not my_root then
		return out
	end

	local facing = my_root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local limit_angle = math.rad(self:get("angle")) / 2

	for _, player in ipairs(players:GetPlayers()) do
		if player ~= me and util.alive(player) then
			if not (self:get("team check") and util.same_team(player)) then
				local character = util.character(player)
				local part = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
				if part then
					local delta = part.Position - my_root.Position
					local distance = delta.Magnitude
					if distance <= range then
						local flat = delta * Vector3.new(1, 0, 1)
						local within = true

						if self:get("angle") < 360 and flat.Magnitude > 0 and facing.Magnitude > 0 then
							local dot = facing.Unit:Dot(flat.Unit)
							within = math.acos(math.clamp(dot, -1, 1)) <= limit_angle
						end

						if within and self:get("wall check") then
							local params = RaycastParams.new()
							params.FilterType = Enum.RaycastFilterType.Exclude
							params.FilterDescendantsInstances = {util.character(), workspace.CurrentCamera}
							local blocked = workspace:Raycast(my_root.Position, delta, params)
							if blocked and blocked.Instance and not blocked.Instance:IsDescendantOf(character) then
								within = false
							end
						end

						if within then
							table.insert(out, {character = character, distance = distance})
						end
					end
				end
			end
		end
	end

	table.sort(out, function(a, b)
		return a.distance < b.distance
	end)

	return out
end

aura.on_tick = function(self)
	local now = os.clock()
	if now < (self.next_swing or 0) then
		return
	end

	-- the weapon rides in the remote payload, but the controller path needs
	-- something in hand, so fall back to whatever is held rather than bailing
	local weapon = bedwars.best_sword() or bedwars.held_tool()

	local range = self:get("range")
	local found = aura_targets(self, range)
	local swung = false

	local method = self:get("method")
	local use_remote = method == "silent" or method == "both"
	local use_controller = method == "controller" or method == "both"

	if use_remote and #found > 0 and weapon then
		local limit = math.min(#found, self:get("targets"))
		for index = 1, limit do
			if bedwars.swing_at(found[index].character, weapon) then
				swung = true
			end
		end
	end

	-- a sent packet is not a landed hit, so the controller path is not gated on
	-- the remote failing, it is its own mode and can run alongside
	if use_controller or (use_remote and not swung) then
		local target = bedwars.target_in_range(range)
		if target and bedwars.attack(target) then
			swung = true
		end
	end

	if swung then
		self.next_swing = now + 1 / math.max(self:get("swings"), 1)
	else
		self.next_swing = now + 0.05
	end
end

-- reach
-- cat and vape both only write CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE,
-- and on this build that constant is dead weight. attackEntity reads the swords
-- own attackRange and only falls back to the constant when the weapon has none,
-- and every sword defines one, 12 on a wood sword up to 24 on the better ones.
-- so the meta is what has to move. it is raised, never lowered, because my last
-- version wrote a flat value and quietly nerfed swords that already reached further

local base_sword_reach = 14.4
local base_place_range = 24
local base_break_range = 18

reach = combat:module{name = "reach", description = "attack, place and break further"}
reach:slider{name = "sword", min = 12, max = 40, default = 26, decimals = 1, suffix = " studs"}
reach:toggle{name = "block reach", default = true}
reach:slider{name = "place", min = 12, max = 60, default = 30, suffix = " studs"}
reach:slider{name = "break", min = 12, max = 60, default = 26, suffix = " studs"}

local saved_ranges = {}

local function apply_sword_reach(value)
	local touched = false

	local constants = bedwars.combat_constant()
	if constants then
		constants.RAYCAST_SWORD_CHARACTER_DISTANCE = value + 2
		constants.REGION_SWORD_CHARACTER_DISTANCE = value + 2
		touched = true
	end

	local meta = bedwars.item_meta()
	if meta then
		for name, entry in pairs(meta) do
			if type(entry) == "table" and type(entry.sword) == "table" then
				local current = entry.sword.attackRange
				if saved_ranges[name] == nil then
					saved_ranges[name] = current or false
				end
				-- never move a sword down, a diamond already reaches 24
				local base = saved_ranges[name] or 0
				entry.sword.attackRange = math.max(value, base)
				touched = true
			end
		end
	end

	return touched
end

local function restore_sword_reach()
	local constants = bedwars.combat_constant()
	if constants then
		constants.RAYCAST_SWORD_CHARACTER_DISTANCE = base_sword_reach
		constants.REGION_SWORD_CHARACTER_DISTANCE = 12.6
	end

	local meta = bedwars.item_meta()
	if meta then
		for name, saved in pairs(saved_ranges) do
			local entry = meta[name]
			if type(entry) == "table" and type(entry.sword) == "table" then
				entry.sword.attackRange = saved or nil
			end
		end
	end
	saved_ranges = {}
end

reach.on_enable = function(self)
	local attached = {}

	if bedwars.item_meta() then
		table.insert(attached, "item meta")
	end
	if bedwars.combat_constant() then
		table.insert(attached, "constant")
	end

	if not apply_sword_reach(self:get("sword")) then
		notify.push("reach could not reach the item meta or the constants")
		error("nothing to patch")
	end

	self.bin:add(restore_sword_reach)
	self.bin:add(self.options["sword"]:listen(apply_sword_reach))

	local selector = bedwars.block_selector()
	if selector and self:get("block reach") then
		local original = selector.getMouseInfo

		selector.getMouseInfo = function(this, mode, args, ...)
			args = args or {}
			if mode == 0 then
				args.range = self:get("place")
			elseif mode == 1 then
				args.range = self:get("break")
			end
			return original(this, mode, args, ...)
		end

		table.insert(attached, "blocks")

		self.bin:add(function()
			local current = bedwars.block_selector()
			if current then
				current.getMouseInfo = original
			end
		end)
	end

	notify.push("reach on through " .. table.concat(attached, ", "), 4)
end

function reach.range_studs()
	if reach.enabled then
		return reach:get("sword")
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