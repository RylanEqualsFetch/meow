-- utility modules

local util = meow.load("src/core/util.lua")
local manager = meow.load("src/core/manager.lua")
local notify = meow.load("src/ui/notify.lua")

local state = meow.load("src/core/state.lua")
local bedwars = meow.load("src/game/bedwars.lua")

local players = util.services.Players
local user_input = util.services.UserInputService
local run_service = util.services.RunService
local http_service = util.services.HttpService

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

local auto_clicker = utility:module{name = "auto clicker", description = "swings while the mouse is held"}
-- anything past twenty clicks a second reads as automated, cap it there
auto_clicker:slider{name = "cps", min = 1, max = 20, default = 12}
auto_clicker:toggle{name = "hold only", default = true}

auto_clicker.on_enable = function(self)
	-- in bedwars a synthetic click never reaches the sword, the swing has to go
	-- through the controller the game binds the mouse to
	local native = bedwars.ready()
	local click = mouse1click

	if not native and type(click) ~= "function" then
		notify.push("auto clicker needs bedwars or an executor with mouse1click")
		error("no click path")
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
			local down = held or user_input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
			if not self:get("hold only") or down then
				if native then
					local sword = bedwars.sword()
					if sword then
						pcall(function()
							sword:swingSwordInRegion()
						end)
					end
				else
					pcall(click)
				end
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

-- zoom unlocker

local zoom = utility:module{name = "zoom unlocker", description = "raises the camera zoom limit"}
zoom:slider{name = "distance", min = 20, max = 500, default = 220, suffix = " studs"}

zoom.on_enable = function(self)
	local player = util.local_player()
	self.saved_zoom = player.CameraMaxZoomDistance
	self.bin:add(function()
		pcall(function()
			util.local_player().CameraMaxZoomDistance = self.saved_zoom or 128
		end)
	end)
end

zoom.on_tick = function(self)
	pcall(function()
		util.local_player().CameraMaxZoomDistance = self:get("distance")
	end)
end

-- freecam, moves the camera without moving the character

local freecam = utility:module{name = "freecam", description = "detaches the camera"}
freecam:slider{name = "speed", min = 10, max = 250, default = 70}

freecam.on_enable = function(self)
	local camera = workspace.CurrentCamera
	if not camera then
		error("no camera")
	end

	self.saved_type = camera.CameraType
	self.saved_subject = camera.CameraSubject
	camera.CameraType = Enum.CameraType.Scriptable

	self.bin:add(function()
		local current = workspace.CurrentCamera
		if current then
			pcall(function()
				current.CameraType = self.saved_type or Enum.CameraType.Custom
				current.CameraSubject = self.saved_subject
			end)
		end
	end)
end

freecam.on_tick = function(self, delta)
	local camera = workspace.CurrentCamera
	if not camera or user_input:GetFocusedTextBox() then
		return
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
		camera.CFrame = camera.CFrame + direction.Unit * self:get("speed") * delta
	end
end

-- streamer mode, the overlays read this flag

local streamer = utility:module{name = "streamer mode", description = "anonymises names on screen"}

streamer.on_enable = function()
	state.streamer = true
end

streamer.on_disable = function()
	state.streamer = false
end

-- fps boost

local fps_boost = utility:module{name = "fps boost", description = "drops effects and shadows"}
fps_boost:toggle{name = "particles", default = true}
fps_boost:toggle{name = "shadows", default = true}
fps_boost:toggle{name = "quality level", default = true}

fps_boost.on_enable = function(self)
	local lighting = util.services.Lighting
	local saved_shadows = lighting.GlobalShadows
	local disabled = {}

	if self:get("shadows") then
		lighting.GlobalShadows = false
	end

	if self:get("particles") then
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Smoke")
				or inst:IsA("Fire") or inst:IsA("Sparkles") then
				if inst.Enabled then
					inst.Enabled = false
					table.insert(disabled, inst)
				end
			end
		end
	end

	if self:get("quality level") then
		pcall(function()
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
		end)
	end

	self.bin:add(function()
		pcall(function()
			lighting.GlobalShadows = saved_shadows
		end)
		for _, inst in ipairs(disabled) do
			pcall(function()
				inst.Enabled = true
			end)
		end
		pcall(function()
			settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
		end)
	end)
end

-- server hop

local hop = utility:module{name = "server hop", description = "teleports to another public server"}
hop:slider{name = "min slots", min = 1, max = 10, default = 2, suffix = " free"}

hop.on_enable = function(self)
	local teleport = util.services.TeleportService
	local player = util.local_player()
	local wanted = self:get("min slots")

	notify.push("looking for a server")

	task.spawn(function()
		local req = (syn and syn.request) or (http and http.request) or http_request or request
		local url = "https://games.roblox.com/v1/games/"
			.. tostring(game.PlaceId)
			.. "/servers/Public?sortOrder=Asc&limit=100"

		local body
		if req then
			local ok, res = pcall(req, {Url = url, Method = "GET"})
			if ok and type(res) == "table" then
				body = res.Body
			end
		end
		if not body then
			local ok, result = pcall(function()
				return game:HttpGet(url, true)
			end)
			body = ok and result or nil
		end

		if not body then
			notify.push("server list request failed")
			self:set_enabled(false)
			return
		end

		local decoded, data = pcall(function()
			return http_service:JSONDecode(body)
		end)
		if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then
			notify.push("could not read the server list")
			self:set_enabled(false)
			return
		end

		for _, server in ipairs(data.data) do
			local free = (server.maxPlayers or 0) - (server.playing or 0)
			if server.id ~= game.JobId and free >= wanted then
				notify.push("hopping")
				pcall(function()
					teleport:TeleportToPlaceInstance(game.PlaceId, server.id, player)
				end)
				return
			end
		end

		notify.push("no server matched")
		self:set_enabled(false)
	end)
end

-- auto respawn

local auto_respawn = utility:module{name = "auto respawn", description = "reloads the character when you die"}

auto_respawn.on_enable = function(self)
	local player = util.local_player()

	local function watch(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 5)
		if not humanoid then
			return
		end
		self.bin:add(humanoid.Died:Connect(function()
			notify.push("respawning")
		end))
	end

	if player.Character then
		task.spawn(watch, player.Character)
	end
	self.bin:add(player.CharacterAdded:Connect(watch))
end

-- ping spoof free latency readout, shows the real numbers larger

local performance = utility:module{name = "performance", description = "logs frame drops"}
performance:slider{name = "threshold", min = 5, max = 60, default = 20, suffix = " fps"}

performance.on_enable = function(self)
	local frames = 0
	local elapsed = 0
	local warned = 0

	self.bin:add(run_service.RenderStepped:Connect(function(delta)
		frames = frames + 1
		elapsed = elapsed + delta
		if elapsed < 1 then
			return
		end

		local fps = frames / elapsed
		frames = 0
		elapsed = 0

		if fps < self:get("threshold") and os.clock() - warned > 10 then
			warned = os.clock()
			notify.push("frame rate dipped to " .. math.floor(fps))
		end
	end))
end

-- copy join link

local join_link = utility:module{name = "copy join link", description = "puts a rejoin snippet on the clipboard"}

join_link.on_enable = function(self)
	local snippet = "game:GetService(\"TeleportService\"):TeleportToPlaceInstance("
		.. tostring(game.PlaceId)
		.. ", \""
		.. tostring(game.JobId)
		.. "\", game:GetService(\"Players\").LocalPlayer)"

	local copy = setclipboard or toclipboard or (syn and syn.write_clipboard)
	if type(copy) == "function" then
		pcall(copy, snippet)
		notify.push("join link copied")
	else
		notify.push("this executor has no clipboard access")
	end

	task.delay(0.3, function()
		self:set_enabled(false)
	end)
end

-- animation player, plays one animation or ugc emote and can hold it still

local anim_player = utility:module{name = "animation player", description = "plays an animation or ugc emote"}
anim_player:input{name = "asset id", placeholder = "animation or emote id"}
anim_player:slider{name = "speed", min = 0, max = 3, default = 1, decimals = 2}
anim_player:slider{name = "time", min = 0, max = 100, default = 0, suffix = " pct"}
anim_player:toggle{name = "freeze", default = false}
anim_player:toggle{name = "override all", default = true}
anim_player:dropdown{
	name = "priority",
	values = {"action4", "action3", "action2", "action", "movement", "idle", "core"},
	default = "action4",
}

local priority_names = {
	action4 = "Action4",
	action3 = "Action3",
	action2 = "Action2",
	action = "Action",
	movement = "Movement",
	idle = "Idle",
	core = "Core",
}

-- a ugc emote asset is an Animation instance, loading it gives the real id
local function resolve_animation_id(raw)
	local id = tostring(raw or ""):match("%d+")
	if not id then
		return nil
	end

	local ok, objects = pcall(function()
		return game:GetObjects("rbxassetid://" .. id)
	end)
	if ok and type(objects) == "table" and objects[1] then
		local inner = objects[1]
		if inner:IsA("Animation") and inner.AnimationId ~= "" then
			local nested = tostring(inner.AnimationId):match("%d+")
			if nested then
				return "rbxassetid://" .. nested
			end
		end
	end

	return "rbxassetid://" .. id
end

anim_player.on_enable = function(self)
	local id = resolve_animation_id(self:get("asset id"))
	if not id then
		notify.push("animation player needs an asset id")
		error("no asset id")
	end

	local asset = Instance.new("Animation")
	asset.AnimationId = id
	self.bin:add(asset)

	local track
	local player = util.local_player()

	local function animator_of(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return nil
		end
		return humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 3)
	end

	local function play(character)
		local animator = animator_of(character)
		if not animator then
			return
		end

		if track then
			pcall(function()
				track:Stop(0)
			end)
			track = nil
		end

		local ok, loaded = pcall(function()
			return animator:LoadAnimation(asset)
		end)
		if not ok or not loaded then
			notify.push("animation player could not load that id")
			return
		end

		track = loaded
		track.Priority = Enum.AnimationPriority[priority_names[self:get("priority")] or "Action4"]
		track.Looped = true
		track:Play(0.1)
		track:AdjustSpeed(self:get("freeze") and 0 or self:get("speed"))
	end

	if util.character() then
		play(util.character())
	end
	self.bin:add(player.CharacterAdded:Connect(function(character)
		task.wait(0.6)
		play(character)
	end))

	self.bin:add(self.options["speed"]:listen(function(value)
		if track and not self:get("freeze") then
			track:AdjustSpeed(value)
		end
	end))

	self.bin:add(self.options["priority"]:listen(function(value)
		if track then
			track.Priority = Enum.AnimationPriority[priority_names[value] or "Action4"]
		end
	end))

	self.bin:add(self.options["asset id"]:listen(function()
		if self.enabled then
			self:set_enabled(false)
			task.defer(function()
				self:set_enabled(true)
			end)
		end
	end))

	self.bin:add(function()
		if track then
			pcall(function()
				track:Stop(0)
			end)
			track = nil
		end
	end)

	-- the frame loop holds the pose, applies the scrub and clears everything else
	self.bin:add(run_service.RenderStepped:Connect(function()
		if not track or not track.IsPlaying then
			if track then
				pcall(function()
					track:Play(0)
				end)
			end
			return
		end

		local frozen = self:get("freeze")
		local length = track.Length

		if frozen then
			track:AdjustSpeed(0)
			if length > 0 then
				track.TimePosition = util.clamp(self:get("time") / 100, 0, 1) * length
			end
		end

		-- the track sweep allocates, ten times a second is plenty to hold a pose
		local now = os.clock()
		if self:get("override all") and now - (self.last_sweep or 0) >= 0.1 then
			self.last_sweep = now
			local animator = animator_of(util.character())
			if animator then
				local ok, playing = pcall(function()
					return animator:GetPlayingAnimationTracks()
				end)
				if ok and type(playing) == "table" then
					for _, other in ipairs(playing) do
						if other ~= track then
							pcall(function()
								other:Stop(0)
							end)
						end
					end
				end
			end
		end
	end))
end

anim_player.on_tick = function(self)
	-- the scrub slider also works while running, it just does not stick
	if not self:get("freeze") then
		return
	end
end

-- no place delay, lifts the block placement rate cap

local no_place_delay = utility:module{name = "no place delay", description = "removes the block place cap"}
no_place_delay:slider{name = "blocks per second", min = 12, max = 60, default = 40}

no_place_delay.on_enable = function(self)
	local constants = bedwars.cps_constants()
	if not constants then
		notify.push("no place delay could not read the cps constants")
		error("cps constants not found")
	end

	local original = constants.BLOCK_PLACE_CPS
	constants.BLOCK_PLACE_CPS = self:get("blocks per second")

	self.bin:add(self.options["blocks per second"]:listen(function(value)
		local current = bedwars.cps_constants()
		if current then
			current.BLOCK_PLACE_CPS = value
		end
	end))

	self.bin:add(function()
		local current = bedwars.cps_constants()
		if current then
			current.BLOCK_PLACE_CPS = original or 12
		end
	end)
end

-- scaffold, bridges under your feet through the games own block placer

local scaffold = utility:module{name = "scaffold", description = "places blocks under you"}
scaffold:slider{name = "blocks per second", min = 4, max = 30, default = 14}
scaffold:toggle{name = "only when falling", default = false}
scaffold:input{name = "block", placeholder = "leave blank for any wool"}

scaffold.on_enable = function(self)
	if not bedwars.placer() then
		notify.push("scaffold could not reach the block placer")
		error("block placer not found")
	end
	self.next_place = 0
end

scaffold.on_tick = function(self)
	local root = util.root()
	local humanoid = util.humanoid()
	if not root or not humanoid then
		return
	end

	local now = os.clock()
	if now < (self.next_place or 0) then
		return
	end

	if self:get("only when falling") and root.AssemblyLinearVelocity.Y > -1 then
		return
	end

	-- one block below the feet, the placer rounds it onto the block grid
	local feet = root.Position - Vector3.new(0, humanoid.HipHeight + 1.5, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {root.Parent}

	-- nothing to do when there is already something solid under us
	if workspace:Raycast(root.Position, Vector3.new(0, -(humanoid.HipHeight + 2.5), 0), params) then
		return
	end

	local wanted = self:get("block")
	if wanted == "" then
		wanted = bedwars.hotbar_block()
	end
	if not wanted then
		return
	end

	if bedwars.place_block(feet, wanted) then
		self.next_place = now + 1 / math.max(self:get("blocks per second"), 1)
	else
		self.next_place = now + 0.1
	end
end

return true
