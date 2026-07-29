-- shared helpers used across the client

local util = {}

util.services = setmetatable({}, {
	__index = function(self, name)
		local service = game:GetService(name)
		rawset(self, name, service)
		return service
	end,
})

local tween_service = util.services.TweenService
local text_service = util.services.TextService
local user_input = util.services.UserInputService

function util.new(class, props, children)
	local inst = Instance.new(class)
	if props then
		for key, value in pairs(props) do
			if key ~= "Parent" then
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function util.tween(inst, props, duration, style, direction)
	local info = TweenInfo.new(
		duration or 0.16,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local anim = tween_service:Create(inst, info, props)
	anim:Play()
	return anim
end

function util.corner(radius)
	return util.new("UICorner", {CornerRadius = UDim.new(0, radius or 6)})
end

function util.stroke(color, thickness, transparency)
	return util.new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function util.padding(top, bottom, left, right)
	return util.new("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or 0),
	})
end

function util.list(padding, direction, alignment)
	return util.new("UIListLayout", {
		Padding = UDim.new(0, padding or 0),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = alignment or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function util.text_width(text, size, font)
	local ok, bounds = pcall(function()
		return text_service:GetTextSize(text, size, font, Vector2.new(4096, 4096))
	end)
	if ok and bounds then
		return bounds.X, bounds.Y
	end
	return #text * size * 0.55, size
end

function util.clamp(value, low, high)
	if value < low then
		return low
	end
	if value > high then
		return high
	end
	return value
end

function util.round(value, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(value * mult + 0.5) / mult
end

function util.lerp(a, b, alpha)
	return a + (b - a) * alpha
end

-- collects connections, instances and teardown callbacks for one clean sweep
function util.bin()
	local items = {}
	local self = {}

	function self:add(item)
		items[#items + 1] = item
		return item
	end

	function self:clean()
		for index = #items, 1, -1 do
			local item = items[index]
			items[index] = nil
			local kind = typeof(item)
			if kind == "RBXScriptConnection" then
				pcall(function()
					item:Disconnect()
				end)
			elseif kind == "Instance" then
				pcall(function()
					item:Destroy()
				end)
			elseif kind == "function" then
				pcall(item)
			elseif kind == "table" and type(item.disconnect) == "function" then
				pcall(function()
					item:disconnect()
				end)
			elseif kind == "table" and type(item.clean) == "function" then
				pcall(function()
					item:clean()
				end)
			end
		end
	end

	self.destroy = self.clean
	return self
end

-- connect returns a connection object so a bin can drop it instead of calling it
function util.signal()
	local self = {handlers = {}}

	function self:connect(fn)
		local handlers = self.handlers
		table.insert(handlers, fn)

		local connection = {connected = true}
		function connection:disconnect()
			if not self.connected then
				return
			end
			self.connected = false
			for index, handler in ipairs(handlers) do
				if handler == fn then
					table.remove(handlers, index)
					return
				end
			end
		end

		return connection
	end

	function self:fire(...)
		for _, handler in ipairs(self.handlers) do
			local ok, err = pcall(handler, ...)
			if not ok then
				warn("meow: signal handler error: " .. tostring(err))
			end
		end
	end

	return self
end

-- opts: {snap = pixels, on_start = fn, on_end = fn}
-- the move is driven from renderstepped against the live mouse location rather
-- than from inputchanged, which is what stopped drags from tracking before
function util.drag(frame, handle, bin, opts)
	handle = handle or frame
	opts = opts or {}

	-- a plain frame never receives input unless it is active
	pcall(function()
		handle.Active = true
	end)

	local run_service = util.services.RunService
	local dragging = false
	local move_connection
	local start_mouse, start_pos

	local function place()
		local mouse = user_input:GetMouseLocation()
		local dx = mouse.X - start_mouse.X
		local dy = mouse.Y - start_mouse.Y

		local x = start_pos.X.Offset + dx
		local y = start_pos.Y.Offset + dy

		local snap = opts.snap
		if snap and snap > 1 then
			x = math.floor(x / snap + 0.5) * snap
			y = math.floor(y / snap + 0.5) * snap
		end

		frame.Position = UDim2.new(start_pos.X.Scale, x, start_pos.Y.Scale, y)
	end

	local function stop()
		if not dragging then
			return
		end
		dragging = false
		if move_connection then
			move_connection:Disconnect()
			move_connection = nil
		end
		if opts.on_end then
			opts.on_end()
		end
	end

	bin:add(handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		dragging = true
		start_mouse = user_input:GetMouseLocation()
		start_pos = frame.Position

		if opts.on_start then
			opts.on_start()
		end

		if move_connection then
			move_connection:Disconnect()
		end
		move_connection = run_service.RenderStepped:Connect(function()
			if not dragging then
				return
			end
			place()
		end)
	end))

	bin:add(user_input.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			stop()
		end
	end))

	bin:add(stop)
end

-- camera writes have to land after the game moves the camera each frame
function util.render_step(name, fn, bin, priority)
	local run_service = util.services.RunService
	priority = priority or (Enum.RenderPriority.Camera.Value + 1)
	run_service:BindToRenderStep(name, priority, fn)
	bin:add(function()
		pcall(function()
			run_service:UnbindFromRenderStep(name)
		end)
	end)
end

function util.key_name(key)
	if typeof(key) ~= "EnumItem" then
		return "none"
	end
	local name = key.Name
	name = name:gsub("^Key", ""):gsub("^Left", "l"):gsub("^Right", "r")
	return name:lower()
end

function util.local_player()
	return util.services.Players.LocalPlayer
end

function util.character(player)
	player = player or util.local_player()
	local char = player and player.Character
	if not char or not char.Parent then
		return nil
	end
	return char
end

function util.root(player)
	local char = util.character(player)
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

function util.humanoid(player)
	local char = util.character(player)
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

function util.alive(player)
	local humanoid = util.humanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

-- team check that works with roblox teams and with the team attributes bedwars uses
function util.same_team(player)
	local me = util.local_player()
	if not me or not player or player == me then
		return true
	end
	if me.Team and player.Team then
		return me.Team == player.Team
	end
	local mine = me:GetAttribute("Team") or me:GetAttribute("team")
	local theirs = player:GetAttribute("Team") or player:GetAttribute("team")
	if mine ~= nil and theirs ~= nil then
		return mine == theirs
	end
	return false
end

return util
