-- utility modules

local util = meow.load("src/core/util.lua")
local manager = meow.load("src/core/manager.lua")
local notify = meow.load("src/ui/notify.lua")

local state = meow.load("src/core/state.lua")

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

return true
