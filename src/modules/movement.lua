-- movement modules

local util = meow.load("src/core/util.lua")
local manager = meow.load("src/core/manager.lua")
local notify = meow.load("src/ui/notify.lua")
local bedwars = meow.load("src/game/bedwars.lua")

local user_input = util.services.UserInputService

local movement = manager.category("movement")

local function typing()
	return user_input:GetFocusedTextBox() ~= nil
end

local function move_input()
	local camera = workspace.CurrentCamera
	if not camera or typing() then
		return Vector3.zero
	end

	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector
	local direction = Vector3.zero

	if user_input:IsKeyDown(Enum.KeyCode.W) then
		direction = direction + look
	end
	if user_input:IsKeyDown(Enum.KeyCode.S) then
		direction = direction - look
	end
	if user_input:IsKeyDown(Enum.KeyCode.D) then
		direction = direction + right
	end
	if user_input:IsKeyDown(Enum.KeyCode.A) then
		direction = direction - right
	end
	if user_input:IsKeyDown(Enum.KeyCode.Space) then
		direction = direction + Vector3.new(0, 1, 0)
	end
	if user_input:IsKeyDown(Enum.KeyCode.LeftControl) then
		direction = direction - Vector3.new(0, 1, 0)
	end

	if direction.Magnitude > 0 then
		return direction.Unit
	end
	return Vector3.zero
end

-- fly
-- ported from cat rather than invented. three things make theirs work where a
-- body velocity does not. the server treats flight as legal while you have an
-- inflated balloon, so it inflates one and blocks the deflate call. the vertical
-- force it writes oscillates sign every 0.2 seconds so the climb averages out.
-- and with no balloon it periodically drops to the floor and back to reset the
-- air time check. 23 studs is cats own ceiling, not a guess

local speed_ceiling = 23

local fly = movement:module{name = "fly", description = "balloon backed flight"}
fly:slider{name = "speed", min = 1, max = speed_ceiling, default = speed_ceiling, suffix = " studs"}
fly:slider{name = "vertical", min = 10, max = 120, default = 55}
fly:toggle{name = "use balloons", default = true}
fly:toggle{name = "pop balloons on stop", default = true}
fly:toggle{name = "wall check", default = true}
fly:toggle{name = "ground reset", default = true}

local function horizontal_speed(root)
	local velocity = root.AssemblyLinearVelocity
	return (velocity * Vector3.new(1, 0, 1)).Magnitude
end

fly.on_enable = function(self)
	local run_service = util.services.RunService
	local balloons = bedwars.balloon_controller()

	local up, down = 0, 0
	local air_since = os.clock()
	local resetting, resume_at, saved_y = false, 0, nil

	-- keep one balloon inflated and stop the game taking it back off us
	if self:get("use balloons") and balloons then
		if bedwars.inflated_balloons() == 0 then
			bedwars.elevated(function()
				balloons:inflateBalloon()
			end)
		end

		local original = balloons.deflateBalloon
		balloons.deflateBalloon = function(...)
			if fly.enabled then
				return nil
			end
			return original(...)
		end

		self.bin:add(function()
			local current = bedwars.balloon_controller()
			if current and current.deflateBalloon ~= original then
				current.deflateBalloon = original
			end

			if self:get("pop balloons on stop") and bedwars.inflated_balloons() > 0 then
				for _ = 1, 3 do
					pcall(function()
						original(current)
					end)
				end
			end
		end)
	end

	self.bin:add(user_input.InputBegan:Connect(function(input)
		if typing() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			up = 1
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			down = -1
		end
	end))

	self.bin:add(user_input.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space then
			up = 0
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			down = 0
		end
	end))

	local params = RaycastParams.new()
	params.RespectCanCollide = true

	self.bin:add(run_service.PreSimulation:Connect(function(delta)
		local root = util.root()
		local humanoid = util.humanoid()
		if not root or not humanoid or humanoid.Health <= 0 then
			return
		end

		if humanoid.FloorMaterial ~= Enum.Material.Air then
			air_since = os.clock()
		end

		local allowed = bedwars.inflated_balloons() > 0

		-- the sign flip is the point, a constant upward force reads as flight
		local flip = (os.clock() % 0.4 < 0.2) and -1 or 1
		local lift = 0.9 + (allowed and 6 or 0) * flip + (up + down) * self:get("vertical") / 55

		local move = humanoid.MoveDirection
		local speed = horizontal_speed(root)
		local step = move * math.max(self:get("speed") - speed, 0) * delta

		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {root.Parent, workspace.CurrentCamera}

		if self:get("wall check") and step.Magnitude > 0 then
			local hit = workspace:Raycast(root.Position, step, params)
			if hit then
				step = (hit.Position + hit.Normal) - root.Position
			end
		end

		-- with no balloon the air time check catches up, so touch down and return
		if not allowed and self:get("ground reset") then
			if not resetting and os.clock() - air_since > 1.7 then
				local ground = workspace:Raycast(root.Position, Vector3.new(0, -1000, 0), params)
				if ground then
					resetting = true
					saved_y = root.Position.Y
					resume_at = os.clock() + 0.07
					root.CFrame = CFrame.lookAlong(
						Vector3.new(root.Position.X, ground.Position.Y + humanoid.HipHeight, root.Position.Z),
						root.CFrame.LookVector
					)
				end
			elseif resetting then
				if os.clock() >= resume_at and saved_y then
					root.CFrame = CFrame.lookAlong(
						Vector3.new(root.Position.X, saved_y, root.Position.Z),
						root.CFrame.LookVector
					)
					resetting = false
					saved_y = nil
					air_since = os.clock()
				else
					lift = 0
				end
			end
		end

		root.CFrame = root.CFrame + step
		root.AssemblyLinearVelocity = (move * speed) + Vector3.new(0, lift, 0)
	end))
end

-- speed

local speed = movement:module{name = "speed", description = "walk faster"}
speed:dropdown{name = "mode", values = {"walkspeed", "cframe"}, default = "walkspeed"}
speed:slider{name = "amount", min = 16, max = speed_ceiling, default = 21, decimals = 1}

speed.on_enable = function(self)
	local humanoid = util.humanoid()
	self.saved_speed = humanoid and humanoid.WalkSpeed or 16
	self.bin:add(function()
		local current = util.humanoid()
		if current then
			current.WalkSpeed = self.saved_speed or 16
		end
	end)
end

speed.on_tick = function(self, delta)
	local humanoid = util.humanoid()
	local root = util.root()
	if not humanoid or not root then
		return
	end

	-- clamped again here so a config file cannot push past the ceiling
	local amount = math.min(self:get("amount"), speed_ceiling)

	if self:get("mode") == "walkspeed" then
		humanoid.WalkSpeed = amount
		return
	end

	humanoid.WalkSpeed = self.saved_speed or 16
	local direction = humanoid.MoveDirection
	if direction.Magnitude > 0 then
		local extra = amount - (self.saved_speed or 16)
		if extra > 0 then
			root.CFrame = root.CFrame + direction * extra * delta
		end
	end
end

-- infinite jump

local infinite_jump = movement:module{name = "infinite jump", description = "jump while airborne"}

infinite_jump.on_enable = function(self)
	self.bin:add(user_input.JumpRequest:Connect(function()
		local humanoid = util.humanoid()
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end))
end

-- noclip

local noclip = movement:module{name = "noclip", description = "walk through geometry"}

noclip.on_enable = function(self)
	self.touched = {}
	self.bin:add(function()
		for part in pairs(self.touched) do
			if part and part.Parent then
				pcall(function()
					part.CanCollide = true
				end)
			end
		end
		self.touched = nil
	end)
end

noclip.on_tick = function(self)
	local character = util.character()
	if not character then
		return
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
			self.touched[part] = true
		end
	end
end

-- high jump

local high_jump = movement:module{name = "high jump", description = "raises jump power"}
high_jump:slider{name = "power", min = 50, max = 68, default = 58}

high_jump.on_enable = function(self)
	local humanoid = util.humanoid()
	self.saved_power = humanoid and humanoid.JumpPower or 50
	self.saved_uses = humanoid and humanoid.UseJumpPower or true
	self.bin:add(function()
		local current = util.humanoid()
		if current then
			pcall(function()
				current.UseJumpPower = self.saved_uses
				current.JumpPower = self.saved_power or 50
			end)
		end
	end)
end

high_jump.on_tick = function(self)
	local humanoid = util.humanoid()
	if not humanoid then
		return
	end
	pcall(function()
		humanoid.UseJumpPower = true
		humanoid.JumpPower = self:get("power")
	end)
end

-- spider, climb walls by pushing into them

local spider = movement:module{name = "spider", description = "climb any wall you walk into"}
spider:slider{name = "speed", min = 5, max = speed_ceiling, default = 14}

spider.on_tick = function(self)
	local root = util.root()
	local humanoid = util.humanoid()
	if not root or not humanoid then
		return
	end

	if humanoid.MoveDirection.Magnitude == 0 then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {root.Parent}

	local hit = workspace:Raycast(root.Position, humanoid.MoveDirection * 3, params)
	if hit then
		root.AssemblyLinearVelocity = Vector3.new(
			root.AssemblyLinearVelocity.X,
			self:get("speed"),
			root.AssemblyLinearVelocity.Z
		)
	end
end

-- fast speed
-- three findings drive this. one, the sprint controller owns WalkSpeed and
-- recomputes it from a modifier list, so writing WalkSpeed directly just gets
-- stamped back, which is why the plain speed module feels like it fights you.
-- two, setSpeed only clamps when maxSpeed is set and it is nil by default.
-- three, the games own speed potion is nothing more than a SpeedBoost attribute
-- that the client turns into a modifier, so that path is the games own code.
-- none of this is kit specific, zephyr was never the requirement

local fast = movement:module{name = "fast speed", description = "drives the games movement multiplier"}
fast:slider{name = "multiplier", min = 1, max = 12, default = 2, decimals = 2}
fast:dropdown{
	name = "method",
	values = {"constant", "additive", "potion attribute"},
	default = "constant",
}
fast:toggle{name = "clear speed cap", default = true}
fast:toggle{name = "zephyr only", default = false}

local zephyr_names = {"wind_walker", "windwalker", "zephyr"}

-- returns matched, and whether the kit could be read at all. an unknown kit is
-- never treated as a mismatch, refusing to enable because a lookup failed is
-- worse than running on the wrong kit
local function on_zephyr()
	for _, name in ipairs(zephyr_names) do
		local matched, known = bedwars.using_kit(name)
		if known and matched then
			return true, true
		end
	end

	local kit = bedwars.local_kit()
	if not kit then
		return false, false
	end
	return false, true
end

local function build_properties(self)
	local value = self:get("multiplier")
	if self:get("method") == "additive" then
		return {moveSpeedMultiplier = value}
	end
	return {constantSpeedMultiplier = value}
end

fast.on_enable = function(self)
	if self:get("zephyr only") then
		local matched, known = on_zephyr()
		if known and not matched then
			notify.push("zephyr only is on and your kit reads as " .. tostring(bedwars.local_kit()))
			error("wrong kit")
		end
		if not known then
			notify.push("could not read your kit, running anyway", 4)
		end
	end

	local sprint = bedwars.sprint_controller()

	-- setSpeed clamps to maxSpeed when it is set, clearing it lifts the ceiling
	if self:get("clear speed cap") and sprint then
		self.saved_max = sprint.maxSpeed
		bedwars.elevated(function()
			sprint.maxSpeed = nil
		end)
		self.bin:add(function()
			local current = bedwars.sprint_controller()
			if current then
				bedwars.elevated(function()
					current.maxSpeed = self.saved_max
				end)
			end
		end)
	end

	-- the potion route sets the attribute the client already listens on, so the
	-- multiplier is applied by the games own handler rather than by a modifier
	-- of ours. locally set attributes do not replicate, this is client side
	if self:get("method") == "potion attribute" then
		local player = util.local_player()
		local read_ok, boost = pcall(function()
			return player:GetAttribute("SpeedBoost")
		end)
		self.saved_boost = read_ok and boost or nil

		local function push()
			bedwars.elevated(function()
				util.local_player():SetAttribute("SpeedBoost", self:get("multiplier"))
			end)
		end

		push()
		self.bin:add(self.options["multiplier"]:listen(push))
		self.bin:add(function()
			pcall(function()
				util.local_player():SetAttribute("SpeedBoost", self.saved_boost)
			end)
		end)

		notify.push("fast speed on through the potion attribute", 4)
		return
	end

	-- the modifier host is built during the controllers own startup, so it can be
	-- unreachable even when knit itself resolved. rather than refusing to enable,
	-- fall through the other routes and say which one took
	local handle = bedwars.add_movement_modifier(build_properties(self))

	if handle then
		self.handle = handle
		self.bin:add(function()
			bedwars.remove_movement_modifier(self.handle)
			self.handle = nil
		end)

		-- the value is only read during reconcile, so a change swaps the modifier
		local function refresh()
			bedwars.remove_movement_modifier(self.handle)
			self.handle = bedwars.add_movement_modifier(build_properties(self))
		end

		self.bin:add(self.options["multiplier"]:listen(refresh))
		self.bin:add(self.options["method"]:listen(refresh))

		notify.push("fast speed on through a modifier", 4)
		return
	end

	-- second route, write the field the controller reads. it is recomputed on the
	-- next reconcile, so the tick puts it back
	if sprint then
		self.saved_multiplier = sprint.moveSpeedMultiplier
		self.direct = true

		self.bin:add(function()
			local current = bedwars.sprint_controller()
			if current then
				bedwars.elevated(function()
					current.moveSpeedMultiplier = self.saved_multiplier or 1
				end)
			end
			self.direct = false
		end)

		notify.push("fast speed on, writing the multiplier directly", 5)
		return
	end

	-- last route, the potion attribute, which needs nothing from knit at all.
	-- every call here is guarded so enabling can never fail outright
	local player = util.local_player()
	local read_ok, boost = pcall(function()
		return player:GetAttribute("SpeedBoost")
	end)
	self.saved_boost = read_ok and boost or nil

	local function push()
		bedwars.elevated(function()
			util.local_player():SetAttribute("SpeedBoost", self:get("multiplier"))
		end)
	end

	push()
	self.bin:add(self.options["multiplier"]:listen(push))
	self.bin:add(function()
		pcall(function()
			util.local_player():SetAttribute("SpeedBoost", self.saved_boost)
		end)
	end)

	notify.push("fast speed on through the potion attribute, no sprint controller", 5)
end

fast.on_tick = function(self)
	if not self.direct then
		return
	end

	local sprint = bedwars.sprint_controller()
	if not sprint then
		return
	end

	local wanted = self:get("multiplier")
	if sprint.moveSpeedMultiplier ~= wanted then
		bedwars.elevated(function()
			sprint.moveSpeedMultiplier = wanted
		end)
	end

	if self:get("clear speed cap") and sprint.maxSpeed ~= nil then
		bedwars.elevated(function()
			sprint.maxSpeed = nil
		end)
	end
end

-- spinbot, spins the character yaw without moving the camera

local spinbot = movement:module{name = "spinbot", description = "spins your character"}
spinbot:slider{name = "speed", min = 30, max = 1500, default = 600, suffix = " deg"}

spinbot.on_enable = function(self)
	self.angle = 0
	local humanoid = util.humanoid()
	self.saved_rotate = humanoid and humanoid.AutoRotate
	self.bin:add(function()
		local current = util.humanoid()
		if current then
			current.AutoRotate = self.saved_rotate ~= false
		end
	end)
end

spinbot.on_tick = function(self, delta)
	local root = util.root()
	local humanoid = util.humanoid()
	if not root or not humanoid then
		return
	end

	humanoid.AutoRotate = false
	self.angle = (self.angle or 0) + self:get("speed") * delta
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(self.angle), 0)
end

-- bhop, jumps the moment you land while still moving

local bhop = movement:module{name = "bhop", description = "jumps every time you land"}

bhop.on_tick = function(self)
	local humanoid = util.humanoid()
	if not humanoid then
		return
	end
	if humanoid.MoveDirection.Magnitude > 0 and humanoid.FloorMaterial ~= Enum.Material.Air then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

-- safe walk, kills horizontal speed when there is no floor ahead

local safe_walk = movement:module{name = "safe walk", description = "stops you walking off an edge"}
safe_walk:slider{name = "look ahead", min = 1, max = 6, default = 2.5, decimals = 1}

safe_walk.on_tick = function(self)
	local root = util.root()
	local humanoid = util.humanoid()
	if not root or not humanoid then
		return
	end

	local direction = humanoid.MoveDirection
	if direction.Magnitude == 0 or humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {root.Parent}

	local origin = root.Position + direction * self:get("look ahead")
	local hit = workspace:Raycast(origin, Vector3.new(0, -7, 0), params)

	if not hit then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
	end
end

-- jump reset, drops fall damage speed on landing

local glide = movement:module{name = "glide", description = "slows your fall"}
glide:slider{name = "fall speed", min = 1, max = 40, default = 12}

glide.on_tick = function(self)
	local root = util.root()
	if not root then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local limit = -self:get("fall speed")
	if velocity.Y < limit then
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, limit, velocity.Z)
	end
end

-- auto sprint

local auto_sprint = movement:module{name = "auto sprint", description = "holds sprint for you"}

auto_sprint.on_enable = function(self)
	if not bedwars.controller("SprintController") then
		notify.push("auto sprint needs the bedwars sprint controller")
		error("sprint controller not found")
	end
end

auto_sprint.on_tick = function(self)
	local sprint = bedwars.controller("SprintController")
	local humanoid = util.humanoid()
	if not sprint or not humanoid then
		return
	end

	if humanoid.MoveDirection.Magnitude == 0 then
		return
	end

	-- the controller owns the state, ask it before starting again
	local ok, sprinting = pcall(function()
		return sprint:isSprinting()
	end)
	if ok and sprinting then
		return
	end

	pcall(function()
		sprint:startSprinting()
	end)
end

-- anti void, yanks you back up when you fall past a height

local anti_void = movement:module{name = "anti void", description = "pulls you back when you fall out"}
anti_void:slider{name = "trigger height", min = -200, max = 40, default = -25, suffix = " y"}

anti_void.on_enable = function(self)
	self.anchor = nil
	self.bin:add(function()
		self.anchor = nil
	end)
end

anti_void.on_tick = function(self)
	local root = util.root()
	if not root then
		return
	end

	if root.Position.Y > self:get("trigger height") then
		-- remember the last safe spot while we are still above the line
		self.anchor = root.Position
		return
	end

	if self.anchor then
		root.CFrame = CFrame.new(self.anchor + Vector3.new(0, 4, 0))
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

return true
