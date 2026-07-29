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

-- the bedwars anticheat rejects anything past about 23 studs a second, every
-- speed value in this file stays under that ceiling on purpose
local speed_ceiling = 23

local fly = movement:module{name = "fly", description = "free camera relative flight"}
fly:slider{name = "speed", min = 8, max = speed_ceiling, default = 20}
fly:toggle{name = "hover", default = true, tooltip = "hold position when no keys are held"}

fly.on_enable = function(self)
	self.velocity = nil
	self.bin:add(function()
		if self.velocity then
			self.velocity:Destroy()
			self.velocity = nil
		end
	end)
end

fly.on_tick = function(self)
	local root = util.root()
	if not root then
		if self.velocity then
			self.velocity:Destroy()
			self.velocity = nil
		end
		return
	end

	if not self.velocity or self.velocity.Parent ~= root then
		if self.velocity then
			self.velocity:Destroy()
		end
		local body = Instance.new("BodyVelocity")
		body.Name = "meow_fly"
		body.MaxForce = Vector3.new(1, 1, 1) * 9e9
		body.Velocity = Vector3.zero
		body.Parent = root
		self.velocity = body
	end

	local direction = move_input()
	if direction.Magnitude > 0 then
		self.velocity.Velocity = direction * self:get("speed")
	elseif self:get("hover") then
		self.velocity.Velocity = Vector3.zero
	else
		self.velocity.Velocity = Vector3.new(0, -8, 0)
	end
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
