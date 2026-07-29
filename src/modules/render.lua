-- visual modules

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local manager = meow.load("src/core/manager.lua")
local state = meow.load("src/core/state.lua")

local new = util.new
local players = util.services.Players
local run_service = util.services.RunService
local lighting = util.services.Lighting

local render = manager.category("render")

-- esp

local esp = render:module{name = "esp", description = "boxes, names and health on players"}
esp:toggle{name = "boxes", default = true}
esp:toggle{name = "names", default = true}
esp:toggle{name = "health", default = true}
esp:toggle{name = "distance", default = false}
esp:toggle{name = "tracers", default = false}
esp:toggle{name = "chams", default = false}
esp:toggle{name = "team check", default = true}
esp:slider{name = "max distance", min = 50, max = 2500, default = 900, suffix = " studs"}
esp:color{name = "color", default = Color3.fromRGB(198, 134, 255)}

local function make_entry(container, player)
	local entry = {}

	entry.box = new("Frame", {
		Parent = container,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		util.stroke(Color3.new(1, 1, 1), 1, 0),
	})

	entry.box_stroke = entry.box:FindFirstChildOfClass("UIStroke")

	entry.name = new("TextLabel", {
		Parent = container,
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 14),
		Text = player.Name,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
		Visible = false,
	})
	theme.apply_font(entry.name, "semibold")

	entry.distance = new("TextLabel", {
		Parent = container,
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 13),
		Text = "",
		TextSize = 12,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		Visible = false,
	})
	theme.apply_font(entry.distance, "medium")

	entry.health = new("Frame", {
		Parent = container,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(12, 12, 14),
		BorderSizePixel = 0,
		Visible = false,
	})

	entry.health_fill = new("Frame", {
		Parent = entry.health,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(126, 217, 141),
		BorderSizePixel = 0,
	})

	entry.tracer = new("Frame", {
		Parent = container,
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 1),
		Visible = false,
	})

	return entry
end

local function hide_entry(entry)
	entry.box.Visible = false
	entry.name.Visible = false
	entry.distance.Visible = false
	entry.health.Visible = false
	entry.tracer.Visible = false
end

esp.on_enable = function(self)
	local gui = state.ui.gui
	if not gui then
		error("meow: esp needs the client gui")
	end

	local container = new("Frame", {
		Name = "esp",
		Parent = gui,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	})
	self.bin:add(container)

	local entries = {}
	local highlights = {}

	local function drop(player)
		local entry = entries[player]
		if entry then
			for _, inst in pairs(entry) do
				if typeof(inst) == "Instance" then
					inst:Destroy()
				end
			end
			entries[player] = nil
		end
		local highlight = highlights[player]
		if highlight then
			highlight:Destroy()
			highlights[player] = nil
		end
	end

	self.bin:add(function()
		for player in pairs(entries) do
			drop(player)
		end
	end)

	self.bin:add(players.PlayerRemoving:Connect(drop))

	self.bin:add(run_service.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local viewport = camera.ViewportSize
		local me = util.local_player()
		local my_root = util.root()
		local color = self:get("color")
		local max_distance = self:get("max distance")
		local team_check = self:get("team check")

		for _, player in ipairs(players:GetPlayers()) do
			if player ~= me then
				local entry = entries[player]
				if not entry then
					entry = make_entry(container, player)
					entries[player] = entry
				end

				local root = util.root(player)
				local humanoid = util.humanoid(player)
				local visible = root ~= nil and humanoid ~= nil and humanoid.Health > 0

				if visible and team_check and util.same_team(player) then
					visible = false
				end

				local distance = 0
				if visible and my_root then
					distance = (root.Position - my_root.Position).Magnitude
					if distance > max_distance then
						visible = false
					end
				end

				local screen, on_screen
				if visible then
					screen, on_screen = camera:WorldToViewportPoint(root.Position)
					visible = on_screen
				end

				if not visible then
					hide_entry(entry)
					local highlight = highlights[player]
					if highlight then
						highlight:Destroy()
						highlights[player] = nil
					end
				else
					local depth = math.max(screen.Z, 0.1)
					local scale = 1 / (depth * math.tan(math.rad(camera.FieldOfView * 0.5)) * 2) * 1000
					local width = math.max(math.floor(3.1 * scale), 6)
					local height = math.max(math.floor(4.7 * scale), 10)
					local center = Vector2.new(screen.X, screen.Y)

					local show_box = self:get("boxes")
					entry.box.Visible = show_box
					if show_box then
						entry.box.Position = UDim2.fromOffset(center.X, center.Y)
						entry.box.Size = UDim2.fromOffset(width, height)
						entry.box_stroke.Color = color
					end

					local show_name = self:get("names")
					entry.name.Visible = show_name
					if show_name then
						entry.name.Position = UDim2.fromOffset(center.X, center.Y - height / 2 - 2)
						entry.name.TextColor3 = color
					end

					local show_distance = self:get("distance")
					entry.distance.Visible = show_distance
					if show_distance then
						entry.distance.Position = UDim2.fromOffset(center.X, center.Y + height / 2 + 2)
						entry.distance.Text = math.floor(distance) .. "m"
					end

					local show_health = self:get("health")
					entry.health.Visible = show_health
					if show_health then
						local ratio = util.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
						entry.health.Position = UDim2.fromOffset(center.X - width / 2 - 5, center.Y)
						entry.health.Size = UDim2.fromOffset(3, height)
						entry.health_fill.Size = UDim2.fromScale(1, ratio)
						entry.health_fill.BackgroundColor3 = Color3.fromRGB(228, 106, 118):Lerp(
							Color3.fromRGB(126, 217, 141),
							ratio
						)
					end

					local show_tracer = self:get("tracers")
					entry.tracer.Visible = show_tracer
					if show_tracer then
						local origin = Vector2.new(viewport.X / 2, viewport.Y)
						local delta = center - origin
						entry.tracer.Position = UDim2.fromOffset(origin.X, origin.Y)
						entry.tracer.Size = UDim2.fromOffset(delta.Magnitude, 1)
						entry.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
						entry.tracer.BackgroundColor3 = color
					end

					if self:get("chams") then
						local highlight = highlights[player]
						if not highlight or not highlight.Parent then
							highlight = Instance.new("Highlight")
							highlight.Name = "meow_cham"
							highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
							highlight.FillTransparency = 0.55
							highlight.OutlineTransparency = 0
							highlight.Adornee = root.Parent
							highlight.Parent = container
							highlights[player] = highlight
						end
						highlight.FillColor = color
						highlight.OutlineColor = color
						highlight.Adornee = root.Parent
					else
						local highlight = highlights[player]
						if highlight then
							highlight:Destroy()
							highlights[player] = nil
						end
					end
				end
			end
		end
	end))
end

-- fullbright

local fullbright = render:module{name = "fullbright", description = "removes darkness and fog"}
fullbright:slider{name = "brightness", min = 1, max = 5, default = 3, decimals = 1}

fullbright.on_enable = function(self)
	self.saved = {
		Brightness = lighting.Brightness,
		ClockTime = lighting.ClockTime,
		FogEnd = lighting.FogEnd,
		FogStart = lighting.FogStart,
		GlobalShadows = lighting.GlobalShadows,
		Ambient = lighting.Ambient,
		OutdoorAmbient = lighting.OutdoorAmbient,
	}

	local function apply()
		lighting.Brightness = self:get("brightness")
		lighting.ClockTime = 12
		lighting.FogEnd = 100000
		lighting.FogStart = 100000
		lighting.GlobalShadows = false
		lighting.Ambient = Color3.fromRGB(178, 178, 178)
		lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
	end

	apply()
	self.bin:add(run_service.Heartbeat:Connect(apply))
end

fullbright.on_disable = function(self)
	if not self.saved then
		return
	end
	for key, value in pairs(self.saved) do
		pcall(function()
			lighting[key] = value
		end)
	end
	self.saved = nil
end

-- no fog only, lighter than fullbright when a map looks fine otherwise

local nofog = render:module{name = "no fog", description = "clears atmosphere and fog"}

nofog.on_enable = function(self)
	local hidden = {}
	for _, inst in ipairs(lighting:GetChildren()) do
		if inst:IsA("Atmosphere") then
			inst.Parent = nil
			table.insert(hidden, inst)
		end
	end

	local saved_end = lighting.FogEnd
	lighting.FogEnd = 100000

	self.bin:add(function()
		lighting.FogEnd = saved_end
		for _, inst in ipairs(hidden) do
			inst.Parent = lighting
		end
	end)
end

return true
