-- visual modules

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local manager = meow.load("src/core/manager.lua")
local state = meow.load("src/core/state.lua")
local bedwars = meow.load("src/game/bedwars.lua")

local new = util.new
local players = util.services.Players
local run_service = util.services.RunService
local lighting = util.services.Lighting

local render = manager.category("render")

-- esp

local esp = render:module{name = "esp", description = "boxes, names and health on players"}
esp:dropdown{name = "box style", values = {"box", "corners", "3d box", "3d corners", "off"}, default = "corners"}
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

	-- four L shaped corners, each is two thin frames sharing an anchor
	entry.corners = {}
	for index = 1, 8 do
		entry.corners[index] = new("Frame", {
			Parent = container,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,
		})
	end

	-- twelve edges of a cube, drawn as rotated lines between projected corners
	entry.edges = {}
	for index = 1, 12 do
		entry.edges[index] = new("Frame", {
			Parent = container,
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,
		})
	end

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
	for _, corner in ipairs(entry.corners) do
		corner.Visible = false
	end
	for _, edge in ipairs(entry.edges) do
		edge.Visible = false
	end
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

					local style = self:get("box style")
					local flat = style == "box"
					local corners_only = style == "corners"
					local cube = style == "3d box"
					local cube_corners = style == "3d corners"

					entry.box.Visible = flat
					if flat then
						entry.box.Position = UDim2.fromOffset(center.X, center.Y)
						entry.box.Size = UDim2.fromOffset(width, height)
						entry.box_stroke.Color = color
					end

					-- corners are drawn as eight short bars pinned to the box edges
					local corner_length = math.max(math.floor(math.min(width, height) * 0.28), 3)
					local left = center.X - width / 2
					local top = center.Y - height / 2
					local corner_specs = {
						{left, top, corner_length, 1},
						{left, top, 1, corner_length},
						{left + width - corner_length, top, corner_length, 1},
						{left + width - 1, top, 1, corner_length},
						{left, top + height - 1, corner_length, 1},
						{left, top + height - corner_length, 1, corner_length},
						{left + width - corner_length, top + height - 1, corner_length, 1},
						{left + width - 1, top + height - corner_length, 1, corner_length},
					}

					for index, spec in ipairs(corner_specs) do
						local piece = entry.corners[index]
						piece.Visible = corners_only
						if corners_only then
							piece.Position = UDim2.fromOffset(spec[1], spec[2])
							piece.Size = UDim2.fromOffset(spec[3], spec[4])
							piece.BackgroundColor3 = color
						end
					end

					local show_cube = cube or cube_corners
					if show_cube then
						local pivot = root.CFrame
						local half = Vector3.new(2.2, 3.2, 1.6)
						local points = {}
						local on_all = true

						for index = 1, 8 do
							local sign_x = (index % 2 == 0) and 1 or -1
							local sign_y = (math.floor((index - 1) / 2) % 2 == 0) and -1 or 1
							local sign_z = (index <= 4) and -1 or 1
							local world = pivot * CFrame.new(half.X * sign_x, half.Y * sign_y, half.Z * sign_z)
							local projected, visible_point = camera:WorldToViewportPoint(world.Position)
							points[index] = Vector2.new(projected.X, projected.Y)
							if not visible_point then
								on_all = false
							end
						end

						local pairs_list = {
							{1, 2}, {3, 4}, {1, 3}, {2, 4},
							{5, 6}, {7, 8}, {5, 7}, {6, 8},
							{1, 5}, {2, 6}, {3, 7}, {4, 8},
						}

						for index, pair in ipairs(pairs_list) do
							local edge = entry.edges[index]
							edge.Visible = on_all
							if on_all then
								local from = points[pair[1]]
								local to = points[pair[2]]
								local delta = to - from
								local span = delta.Magnitude
								local draw = cube_corners and math.min(span * 0.3, 18) or span
								edge.Position = UDim2.fromOffset(from.X, from.Y)
								edge.Size = UDim2.fromOffset(draw, 1)
								edge.Rotation = math.deg(math.atan2(delta.Y, delta.X))
								edge.BackgroundColor3 = color
							end
						end
					else
						for _, edge in ipairs(entry.edges) do
							edge.Visible = false
						end
					end

					local show_name = self:get("names")
					entry.name.Visible = show_name
					if show_name then
						entry.name.Position = UDim2.fromOffset(center.X, center.Y - height / 2 - 2)
						entry.name.TextColor3 = color
						-- streamer mode keeps real names off the screen
						entry.name.Text = state.streamer and "player" or player.Name
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

-- bed esp, beds carry a collection service tag in bedwars so they are exact

local bed_esp = render:module{name = "bed esp", description = "beds through walls"}
bed_esp:toggle{name = "highlight", default = true}
bed_esp:toggle{name = "label", default = true}
bed_esp:toggle{name = "hide own bed", default = true}
bed_esp:slider{name = "max distance", min = 100, max = 3000, default = 1200, suffix = " studs"}
bed_esp:color{name = "color", default = Color3.fromRGB(255, 122, 162)}

local function through_wall_highlight(adornee, parent, color)
	local highlight = Instance.new("Highlight")
	highlight.Name = "meow_esp"
	-- always on top is what makes it read through geometry
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.Adornee = adornee
	highlight.Parent = parent
	return highlight
end

local function through_wall_label(adornee, parent, text, color, distance_limit)
	local billboard = new("BillboardGui", {
		Name = "meow_esp_tag",
		Parent = parent,
		Adornee = adornee,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(180, 20),
		StudsOffset = Vector3.new(0, 2.4, 0),
		MaxDistance = distance_limit,
	})

	local label = new("TextLabel", {
		Parent = billboard,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextSize = theme.size.small,
		TextColor3 = color,
		TextStrokeTransparency = 0.4,
	})
	theme.apply_font(label, "semibold")

	return billboard, label
end

bed_esp.on_enable = function(self)
	local host = state.ui.host or state.ui.gui
	if not host then
		error("meow: bed esp needs the gui host")
	end

	local tracked = {}

	self.bin:add(function()
		for _, entry in pairs(tracked) do
			if entry.highlight then
				entry.highlight:Destroy()
			end
			if entry.billboard then
				entry.billboard:Destroy()
			end
		end
	end)

	local function drop(bed)
		local entry = tracked[bed]
		if not entry then
			return
		end
		if entry.highlight then
			entry.highlight:Destroy()
		end
		if entry.billboard then
			entry.billboard:Destroy()
		end
		tracked[bed] = nil
	end

	self.bin:add(run_service.Heartbeat:Connect(function()
		local color = self:get("color")
		local limit = self:get("max distance")
		local root = util.root()
		local my_team = bedwars.team_of()
		local seen = {}

		for _, bed in ipairs(bedwars.beds()) do
			local part = bed:IsA("BasePart") and bed or bed:FindFirstChildWhichIsA("BasePart", true)
			local adornee = bed:IsA("Model") and bed or part

			local skip = false
			if self:get("hide own bed") and my_team then
				local team = bed:GetAttribute("Team") or bed:GetAttribute("team")
				if team ~= nil and tostring(team) == tostring(my_team) then
					skip = true
				end
			end

			if part and adornee and not skip then
				local distance = root and (part.Position - root.Position).Magnitude or 0
				if distance <= limit then
					seen[bed] = true
					local entry = tracked[bed]
					if not entry then
						entry = {}
						tracked[bed] = entry
					end

					if self:get("highlight") then
						if not entry.highlight or not entry.highlight.Parent then
							entry.highlight = through_wall_highlight(adornee, host, color)
						end
						entry.highlight.FillColor = color
						entry.highlight.OutlineColor = color
					elseif entry.highlight then
						entry.highlight:Destroy()
						entry.highlight = nil
					end

					if self:get("label") then
						if not entry.billboard or not entry.billboard.Parent then
							entry.billboard, entry.label = through_wall_label(part, host, "bed", color, limit)
						end
						entry.billboard.MaxDistance = limit
						if entry.label then
							entry.label.TextColor3 = color
							entry.label.Text = root and ("bed  " .. math.floor(distance) .. "m") or "bed"
						end
					elseif entry.billboard then
						entry.billboard:Destroy()
						entry.billboard = nil
						entry.label = nil
					end
				end
			end
		end

		for bed in pairs(tracked) do
			if not seen[bed] or not bed.Parent then
				drop(bed)
			end
		end
	end))
end

-- chest esp

local chest_esp = render:module{name = "chest esp", description = "chests through walls"}
chest_esp:toggle{name = "team chests", default = true}
chest_esp:toggle{name = "highlight", default = true}
chest_esp:slider{name = "max distance", min = 50, max = 1500, default = 600, suffix = " studs"}
chest_esp:slider{name = "rescan", min = 3, max = 30, default = 8, suffix = " s"}
chest_esp:color{name = "color", default = Color3.fromRGB(255, 196, 108)}

chest_esp.on_enable = function(self)
	local host = state.ui.host or state.ui.gui
	if not host then
		error("meow: chest esp needs the gui host")
	end

	local tracked = {}
	local running = true

	self.bin:add(function()
		running = false
		for _, entry in pairs(tracked) do
			if entry.highlight then
				entry.highlight:Destroy()
			end
			if entry.billboard then
				entry.billboard:Destroy()
			end
		end
	end)

	local function is_chest(inst)
		local lower = inst.Name:lower()
		if not lower:find("chest", 1, true) then
			return false
		end
		if not self:get("team chests") and inst:GetAttribute("ChestOwner") ~= nil then
			return false
		end
		return true
	end

	-- the descendant walk is spread over frames so a full map does not hitch
	task.spawn(function()
		while running do
			local seen = {}
			local scanned = 0

			for _, inst in ipairs(workspace:GetDescendants()) do
				if not running then
					return
				end
				scanned = scanned + 1
				-- a bedwars map is enormous, yield often so the frame survives
				if scanned % 400 == 0 then
					task.wait()
				end

				if (inst:IsA("Model") or inst:IsA("BasePart")) and is_chest(inst) then
					local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
					if part then
						seen[inst] = true
						local entry = tracked[inst]
						if not entry then
							entry = {}
							tracked[inst] = entry
							-- highlight only, the floating text was noise
							if self:get("highlight") then
								entry.highlight = through_wall_highlight(inst, host, self:get("color"))
							end
						end
					end
				end
			end

			for inst, entry in pairs(tracked) do
				if not seen[inst] or not inst.Parent then
					if entry.highlight then
						entry.highlight:Destroy()
					end
					if entry.billboard then
						entry.billboard:Destroy()
					end
					tracked[inst] = nil
				end
			end

			for _ = 1, math.floor(self:get("rescan") * 20) do
				if not running then
					return
				end
				task.wait(0.05)
			end
		end
	end)
end

-- texture pack
-- the cat client loadstrings a script out of a third party repo for this. the
-- packs themselves are just roblox model assets, so this loads the model and
-- does the swap here instead of running someone elses code inside the client

local pack_ids = {
	["acidic"] = 14245759641,
	["devourer"] = 14258977192,
	["enlightened"] = 14261862180,
	["fat cat"] = 100570768622198,
	["fury"] = 14331255019,
	["makima"] = 14335043180,
	["moon"] = 14271708146,
	["nebula"] = 14654171957,
	["onyx"] = 14334779267,
	["prime"] = 14479023830,
	["simply"] = 117028342668949,
	["vile"] = 14247192725,
	["violets dreams"] = 14248304333,
	["wichtiger"] = 14320382383,
}

local pack_names = {
	"simply",
	"acidic",
	"devourer",
	"enlightened",
	"fat cat",
	"fury",
	"makima",
	"moon",
	"nebula",
	"onyx",
	"prime",
	"vile",
	"violets dreams",
	"wichtiger",
}

local texture_pack = render:module{name = "texture pack", description = "replaces the held item models"}
texture_pack:dropdown{name = "pack", values = pack_names, default = "simply"}
texture_pack:input{name = "custom model id", placeholder = "optional asset id"}
texture_pack:slider{name = "scale", min = 0.5, max = 2.5, default = 1.375, decimals = 3}

local function strip_physics(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Massless = true
			end)
		end
	end
	if model:IsA("BasePart") then
		pcall(function()
			model.CanCollide = false
			model.CanQuery = false
		end)
	end
end

-- the offsets every pack script uses, a sword lies along one axis and the tools
-- along another, then the whole thing gets a yaw of minus fifty
local function offset_for(name)
	local lower = name:lower()
	if lower:find("sword", 1, true) or lower:find("knife", 1, true) then
		return CFrame.Angles(0, math.rad(-100), math.rad(-90))
	end
	return CFrame.new(0, 0.45, 0) * CFrame.Angles(0, math.rad(-10), math.rad(-95))
end

texture_pack.on_enable = function(self)
	local custom = tostring(self:get("custom model id") or ""):match("%d+")
	local id = custom and tonumber(custom) or pack_ids[self:get("pack")]
	if not id then
		notify.push("texture pack could not resolve that id")
		error("no pack id")
	end

	local ok, objects = pcall(function()
		return game:GetObjects("rbxassetid://" .. tostring(id))
	end)
	local source = ok and type(objects) == "table" and objects[1] or nil
	if not source then
		notify.push("texture pack could not load asset " .. tostring(id))
		error("asset load failed")
	end

	strip_physics(source)
	self.bin:add(source)

	-- packs name their meshes loosely, sword, Sword, wood_sword, so the lookup
	-- takes an exact hit first and then falls back to a keyword match
	local replacements = {}
	local ordered = {}
	for _, child in ipairs(source:GetChildren()) do
		local key = child.Name:lower()
		replacements[key] = child
		table.insert(ordered, {key = key, node = child})
	end

	local function match_for(name)
		local lower = name:lower()
		local exact = replacements[lower]
		if exact then
			return exact
		end

		for _, entry in ipairs(ordered) do
			if lower:find(entry.key, 1, true) or entry.key:find(lower, 1, true) then
				return entry.node
			end
		end

		-- last resort, match on the tool family so a wood axe finds axe
		for _, family in ipairs({"sword", "pickaxe", "axe", "shears", "bow", "wand"}) do
			if lower:find(family, 1, true) then
				for _, entry in ipairs(ordered) do
					if entry.key:find(family, 1, true) then
						return entry.node
					end
				end
			end
		end

		return nil
	end

	local applied = {}

	self.bin:add(function()
		for handle, entry in pairs(applied) do
			if entry.clone then
				entry.clone:Destroy()
			end
			if handle and handle.Parent then
				pcall(function()
					handle.Transparency = entry.transparency or 0
				end)
			end
		end
	end)

	local function dress(item)
		if not item or not item.Parent then
			return
		end

		local replacement = match_for(item.Name)
		if not replacement then
			return
		end

		-- the handle can lag the item by a frame, wait for it rather than miss
		local handle = item:FindFirstChild("Handle")
		if not handle then
			for _ = 1, 20 do
				task.wait()
				handle = item:FindFirstChild("Handle")
				if handle or not item.Parent then
					break
				end
			end
		end

		if not handle or not handle:IsA("BasePart") or applied[handle] then
			return
		end

		local clone = replacement:Clone()
		strip_physics(clone)

		local anchor = clone:IsA("Model") and clone.PrimaryPart or clone
		if not anchor then
			clone:Destroy()
			return
		end

		clone.Parent = item
		anchor.Anchored = false
		anchor.CFrame = handle.CFrame * offset_for(item.Name) * CFrame.Angles(0, math.rad(-50), 0)
		anchor.Size = anchor.Size * self:get("scale")

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchor
		weld.Part1 = handle
		weld.Parent = anchor

		applied[handle] = {clone = clone, transparency = handle.Transparency}
		handle.Transparency = 1
	end

	-- the viewmodel is rebuilt on respawn, so it is watched rather than grabbed
	local function bind(viewmodel)
		if not viewmodel then
			return
		end
		for _, child in ipairs(viewmodel:GetChildren()) do
			task.spawn(dress, child)
		end

		-- no fixed delay, the dress call waits on the handle itself
		self.bin:add(viewmodel.ChildAdded:Connect(function(child)
			task.spawn(dress, child)
		end))

		self.bin:add(viewmodel.DescendantAdded:Connect(function(node)
			if node:IsA("BasePart") and node.Name == "Handle" and node.Parent then
				task.spawn(dress, node.Parent)
			end
		end))
	end

	local camera = workspace.CurrentCamera
	if camera then
		bind(camera:FindFirstChild("Viewmodel"))
		self.bin:add(camera.ChildAdded:Connect(function(child)
			if child.Name == "Viewmodel" then
				bind(child)
			end
		end))
	end
end

-- crosshair

local crosshair = render:module{name = "crosshair", description = "static crosshair at screen center"}
crosshair:slider{name = "length", min = 2, max = 20, default = 7}
crosshair:slider{name = "gap", min = 0, max = 20, default = 4}
crosshair:slider{name = "thickness", min = 1, max = 5, default = 2}
crosshair:toggle{name = "dot", default = false}
crosshair:color{name = "color", default = Color3.fromRGB(255, 255, 255)}

crosshair.on_enable = function(self)
	local gui = state.ui.gui
	if not gui then
		error("meow: crosshair needs the client gui")
	end

	local holder = new("Frame", {
		Name = "crosshair",
		Parent = gui,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	})
	self.bin:add(holder)

	local arms = {}
	for index = 1, 4 do
		arms[index] = new("Frame", {
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			BackgroundColor3 = self:get("color"),
		})
	end

	local dot = new("Frame", {
		Parent = holder,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		BackgroundColor3 = self:get("color"),
		Visible = false,
	}, {util.corner(2)})

	local function layout()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		local cx, cy = viewport.X / 2, viewport.Y / 2
		local length = self:get("length")
		local gap = self:get("gap")
		local thick = self:get("thickness")
		local color = self:get("color")

		arms[1].Size = UDim2.fromOffset(thick, length)
		arms[1].Position = UDim2.fromOffset(cx, cy - gap - length / 2)
		arms[2].Size = UDim2.fromOffset(thick, length)
		arms[2].Position = UDim2.fromOffset(cx, cy + gap + length / 2)
		arms[3].Size = UDim2.fromOffset(length, thick)
		arms[3].Position = UDim2.fromOffset(cx - gap - length / 2, cy)
		arms[4].Size = UDim2.fromOffset(length, thick)
		arms[4].Position = UDim2.fromOffset(cx + gap + length / 2, cy)

		for _, arm in ipairs(arms) do
			arm.BackgroundColor3 = color
		end

		dot.Visible = self:get("dot")
		dot.Size = UDim2.fromOffset(thick + 1, thick + 1)
		dot.Position = UDim2.fromOffset(cx, cy)
		dot.BackgroundColor3 = color
	end

	layout()
	for _, option in ipairs(self.option_order) do
		self.bin:add(option:listen(layout))
	end
	self.bin:add(run_service.RenderStepped:Connect(layout))
end

-- fov circle, shows the aim assist radius

local fov_circle = render:module{name = "fov circle", description = "draws the aim assist radius"}
fov_circle:slider{name = "radius", min = 20, max = 400, default = 110, suffix = " px"}
fov_circle:toggle{name = "match aim assist", default = true}
fov_circle:slider{name = "thickness", min = 1, max = 4, default = 1}
fov_circle:color{name = "color", default = Color3.fromRGB(198, 134, 255)}

fov_circle.on_enable = function(self)
	local gui = state.ui.gui
	if not gui then
		error("meow: fov circle needs the client gui")
	end

	-- a square with a full corner radius is a circle, the stroke draws the ring
	local circle = new("Frame", {
		Name = "fov",
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, {
		new("UICorner", {CornerRadius = UDim.new(1, 0)}),
		util.stroke(self:get("color"), self:get("thickness"), 0.25),
	})
	self.bin:add(circle)

	local stroke = circle:FindFirstChildOfClass("UIStroke")

	self.bin:add(run_service.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

		local radius = self:get("radius")
		if self:get("match aim assist") then
			local aim = manager.find("aim assist")
			if aim then
				radius = aim:get("fov") or radius
			end
		end

		circle.Position = UDim2.fromOffset(viewport.X / 2, viewport.Y / 2)
		circle.Size = UDim2.fromOffset(radius * 2, radius * 2)
		stroke.Color = self:get("color")
		stroke.Thickness = self:get("thickness")
	end))
end

-- object esp, labels anything whose name matches a keyword

local objects = render:module{name = "object esp", description = "labels beds, chests and generators"}
objects:dropdown{
	name = "keywords",
	values = {"bed", "chest", "generator", "spawner", "shop", "forge"},
	default = {"bed", "chest", "generator"},
	multi = true,
}
objects:slider{name = "max distance", min = 50, max = 1500, default = 450, suffix = " studs"}
objects:slider{name = "rescan", min = 3, max = 30, default = 8, suffix = " s"}
objects:color{name = "color", default = Color3.fromRGB(126, 217, 141)}

objects.on_enable = function(self)
	local host = state.ui.host or state.ui.gui
	if not host then
		error("meow: object esp needs the gui host")
	end

	local tags = {}
	local running = true

	self.bin:add(function()
		running = false
		for inst, tag in pairs(tags) do
			if tag then
				tag:Destroy()
			end
			tags[inst] = nil
		end
	end)

	local function matches(name)
		local lower = name:lower()
		for _, key in ipairs(self:get("keywords")) do
			if lower:find(key, 1, true) then
				return true
			end
		end
		return false
	end

	local function label_for(inst)
		local billboard = new("BillboardGui", {
			Name = "meow_object",
			Parent = host,
			Adornee = inst,
			AlwaysOnTop = true,
			Size = UDim2.fromOffset(180, 20),
			StudsOffset = Vector3.new(0, 1.6, 0),
			MaxDistance = self:get("max distance"),
		})

		local text = new("TextLabel", {
			Parent = billboard,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = inst.Name:lower(),
			TextSize = theme.size.small,
			TextColor3 = self:get("color"),
			TextStrokeTransparency = 0.45,
		})
		theme.apply_font(text, "semibold")

		return billboard
	end

	-- the descendant walk is spread across frames so a big map does not hitch
	task.spawn(function()
		while running do
			local scanned = 0
			local seen = {}

			for _, inst in ipairs(workspace:GetDescendants()) do
				if not running then
					return
				end
				scanned = scanned + 1
				-- a bedwars map is enormous, yield often so the frame survives
				if scanned % 400 == 0 then
					task.wait()
				end
				if (inst:IsA("BasePart") or inst:IsA("Model")) and matches(inst.Name) then
					seen[inst] = true
					if not tags[inst] then
						tags[inst] = label_for(inst)
					end
				end
			end

			for inst, tag in pairs(tags) do
				if not seen[inst] or not inst.Parent then
					if tag then
						tag:Destroy()
					end
					tags[inst] = nil
				end
			end

			for _ = 1, math.floor(self:get("rescan") * 20) do
				if not running then
					return
				end
				task.wait(0.05)
			end
		end
	end)
end

-- no fog, clears the haze without touching brightness

local nofog = render:module{name = "no fog", description = "clears atmosphere and fog"}

nofog.on_enable = function(self)
	local saved_end = lighting.FogEnd
	local saved_start = lighting.FogStart
	local atmospheres = {}

	-- density is faded rather than the instance being reparented, pulling it out
	-- of lighting makes the whole scene pop when it comes back
	for _, inst in ipairs(lighting:GetChildren()) do
		if inst:IsA("Atmosphere") then
			atmospheres[inst] = {density = inst.Density, haze = inst.Haze}
			inst.Density = 0
			inst.Haze = 0
		end
	end

	lighting.FogEnd = 100000
	lighting.FogStart = 100000

	self.bin:add(function()
		pcall(function()
			lighting.FogEnd = saved_end
			lighting.FogStart = saved_start
		end)
		for inst, values in pairs(atmospheres) do
			if inst and inst.Parent then
				pcall(function()
					inst.Density = values.density
					inst.Haze = values.haze
				end)
			end
		end
	end)
end

return true
