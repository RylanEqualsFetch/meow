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

local function visible_chain(inst)
	local node = inst
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

-- opts: {snap, threshold, on_start, on_end, state = {moved, zones}}
-- a press anywhere on the panel arms a drag, it only becomes one once the mouse
-- has moved past the threshold, so the same press can still be a click. zones
-- are child rects, sliders and pickers, that must never start a drag
function util.drag(frame, handle, bin, opts)
	handle = handle or frame
	opts = opts or {}

	local shared = opts.state or {}
	shared.zones = shared.zones or {}

	pcall(function()
		handle.Active = true
	end)

	local run_service = util.services.RunService
	local gui_service = util.services.GuiService
	local threshold = opts.threshold or 4

	local armed = false
	local dragging = false
	local loop
	local start_mouse, start_pos

	local function offset()
		local ok, top = pcall(function()
			return gui_service:GetGuiInset()
		end)
		if ok and typeof(top) == "Vector2" then
			return top
		end
		return Vector2.new(0, 0)
	end

	local function inside(rect, point)
		local origin = rect.AbsolutePosition
		local size = rect.AbsoluteSize
		return point.X >= origin.X
			and point.X <= origin.X + size.X
			and point.Y >= origin.Y
			and point.Y <= origin.Y + size.Y
	end

	local function blocked(point)
		for _, zone in ipairs(shared.zones) do
			if zone and zone.Parent and visible_chain(zone) and inside(zone, point) then
				return true
			end
		end
		return false
	end

	-- the move itself is free so it tracks the cursor exactly, the grid is only
	-- applied once on release, which reads far smoother than snapping per frame
	local function place(settle)
		local mouse = user_input:GetMouseLocation()
		local x = start_pos.X.Offset + (mouse.X - start_mouse.X)
		local y = start_pos.Y.Offset + (mouse.Y - start_mouse.Y)

		local snap = opts.snap
		if settle and snap and snap > 1 then
			x = math.floor(x / snap + 0.5) * snap
			y = math.floor(y / snap + 0.5) * snap
			util.tween(frame, {
				Position = UDim2.new(start_pos.X.Scale, x, start_pos.Y.Scale, y),
			}, 0.12)
			return
		end

		frame.Position = UDim2.new(start_pos.X.Scale, x, start_pos.Y.Scale, y)
	end

	local function release()
		if loop then
			loop:Disconnect()
			loop = nil
		end
		armed = false

		if dragging then
			place(true)
			dragging = false
			if opts.on_end then
				opts.on_end()
			end
			-- the click event lands after the release, so hold the flag a moment
			task.delay(0.06, function()
				shared.moved = false
			end)
		else
			shared.moved = false
		end
	end

	local function arm()
		if armed or dragging then
			return
		end
		armed = true
		shared.moved = false
		start_mouse = user_input:GetMouseLocation()
		start_pos = frame.Position

		if loop then
			loop:Disconnect()
		end
		loop = run_service.RenderStepped:Connect(function()
			if not armed and not dragging then
				return
			end

			local mouse = user_input:GetMouseLocation()

			if not dragging then
				local dx = mouse.X - start_mouse.X
				local dy = mouse.Y - start_mouse.Y
				if math.sqrt(dx * dx + dy * dy) < threshold then
					return
				end
				dragging = true
				shared.moved = true
				if opts.on_start then
					opts.on_start()
				end
			end

			place()
		end)
	end

	local function is_press(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	-- the direct event needs no coordinate math at all, it is the reliable path
	bin:add(handle.InputBegan:Connect(function(input)
		if is_press(input) then
			arm()
		end
	end))

	-- the global pass catches presses that a child button swallowed. the input
	-- position and absolute position spaces differ by the top bar inset on some
	-- setups, so both readings are accepted rather than guessing which applies
	bin:add(user_input.InputBegan:Connect(function(input)
		if not is_press(input) then
			return
		end
		if not frame.Visible or not visible_chain(handle) then
			return
		end

		local raw = Vector2.new(input.Position.X, input.Position.Y)
		local shifted = raw + offset()

		if blocked(raw) or blocked(shifted) then
			return
		end
		if inside(handle, raw) or inside(handle, shifted) then
			arm()
		end
	end))

	bin:add(user_input.InputEnded:Connect(function(input)
		if is_press(input) then
			release()
		end
	end))

	bin:add(release)
	return shared
end

-- a spawned thread does not inherit the identity the client was injected with,
-- so anything it does to an Instance fails with "lacking capability Plugin".
-- restoring the config is the loud example, it fires every option listener from
-- a fresh thread. this raises the identity for the life of the thread
function util.spawn(fn, ...)
	local args = table.pack(...)

	task.spawn(function()
		if type(setthreadidentity) == "function" then
			pcall(setthreadidentity, 2)
		end
		fn(table.unpack(args, 1, args.n))
	end)
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

local key_labels = {
	RightShift = "rshift",
	LeftShift = "lshift",
	RightControl = "rctrl",
	LeftControl = "lctrl",
	RightAlt = "ralt",
	LeftAlt = "lalt",
	LeftBracket = "[",
	RightBracket = "]",
	Semicolon = ";",
	Quote = "'",
	Comma = ",",
	Period = ".",
	Slash = "/",
	BackSlash = "\\",
	Minus = "-",
	Equals = "=",
	Backquote = "`",
	CapsLock = "caps",
	Insert = "ins",
	Delete = "del",
	PageUp = "pgup",
	PageDown = "pgdn",
	Backspace = "bksp",
	Return = "enter",
	Space = "space",
	Up = "up",
	Down = "down",
	Left = "left",
	Right = "right",
	Zero = "0",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
}

function util.key_name(key)
	if typeof(key) ~= "EnumItem" then
		return "none"
	end

	local name = key.Name
	local mapped = key_labels[name]
	if mapped then
		return mapped
	end

	if name:match("^KeypadNumber") then
		return "num" .. name:sub(13)
	end
	if name:match("^Keypad") then
		return "num" .. name:sub(7):lower()
	end
	if name:match("^F%d+$") then
		return name:lower()
	end

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
