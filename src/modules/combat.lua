-- combat modules
-- generic for now, bedwars specific remote work lands on top of this same api

local util = meow.load("src/core/util.lua")
local manager = meow.load("src/core/manager.lua")
local notify = meow.load("src/ui/notify.lua")

local players = util.services.Players
local user_input = util.services.UserInputService

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
		-- aim assist, pulls the camera toward the nearest target inside the fov circle

local aim = combat:module{name = "aim assist", description = "smooth camera pull toward a target"}
aim:slider{name = "fov", min = 20, max = 400, default = 110, suffix = " px"}
aim:slider{name = "smoothness", min = 1, max = 25, default = 9}
aim:dropdown{name = "target part", values = {"head", "torso", "root"}, default = "head"}
aim:toggle{name = "hold right mouse", default = true}
aim:toggle{name = "visible check", default = true}
aim:toggle{name = "team check", default = true}

local part_names = {head = "Head", torso = "UpperTorso", root = "HumanoidRootPart"}

local function pick_part(character, kind)
	local wanted = part_names[kind] or "Head"
	return character:FindFirstChild(wanted)
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
end

local function has_line_of_sight(camera, part, character)
	local origin = camera.CFrame.Position
	local direction = part.Position - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {util.character(), camera}

	local hit = workspace:Raycast(origin, direction, params)
	if not hit or not hit.Instance then
		return true
	end
	return hit.Instance:IsDescendantOf(character)
end

aim.on_tick = function(self)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if self:get("hold right mouse")
		and not user_input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		return
	end

	local viewport = camera.ViewportSize
	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local fov = self:get("fov")
	local kind = self:get("target part")
	local team_check = self:get("team check")
	local visible_check = self:get("visible check")
	local me = util.local_player()

	local best, best_distance

	for _, player in ipairs(players:GetPlayers()) do
		if player ~= me and util.alive(player) then
			if not (team_check and util.same_team(player)) then
				local character = util.character(player)
				local part = character and pick_part(character, kind)
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
		end
	end

	if not best then
		return
	end

	local goal = CFrame.new(camera.CFrame.Position, best.Position)
	camera.CFrame = camera.CFrame:Lerp(goal, 1 / math.max(self:get("smoothness"), 1))
end

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

-- aim assist, pulls the camera toward the nearest target inside the fov circle

local aim = combat:module{name = "aim assist", description = "smooth camera pull toward a target"}
aim:slider{name = "fov", min = 20, max = 400, default = 110, suffix = " px"}
aim:slider{name = "smoothness", min = 1, max = 25, default = 9}
aim:dropdown{name = "target part", values = {"head", "torso", "root"}, default = "head"}
aim:toggle{name = "hold right mouse", default = true}
aim:toggle{name = "visible check", default = true}
aim:toggle{name = "team check", default = true}

local part_names = {head = "Head", torso = "UpperTorso", root = "HumanoidRootPart"}

local function pick_part(character, kind)
	local wanted = part_names[kind] or "Head"
	return character:FindFirstChild(wanted)
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart")
end

local function has_line_of_sight(camera, part, character)
	local origin = camera.CFrame.Position
	local direction = part.Position - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {util.character(), camera}

	local hit = workspace:Raycast(origin, direction, params)
	if not hit or not hit.Instance then
		return true
	end
	return hit.Instance:IsDescendantOf(character)
end

aim.on_tick = function(self)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if self:get("hold right mouse")
		and not user_input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		return
	end

	local viewport = camera.ViewportSize
	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local fov = self:get("fov")
	local kind = self:get("target part")
	local team_check = self:get("team check")
	local visible_check = self:get("visible check")
	local me = util.local_player()

	local best, best_distance

	for _, player in ipairs(players:GetPlayers()) do
		if player ~= me and util.alive(player) then
			if not (team_check and util.same_team(player)) then
				local character = util.character(player)
				local part = character and pick_part(character, kind)
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
		end
	end

	if not best then
		return
	end

	local goal = CFrame.new(camera.CFrame.Position, best.Position)
	camera.CFrame = camera.CFrame:Lerp(goal, 1 / math.max(self:get("smoothness"), 1))
end

return true
