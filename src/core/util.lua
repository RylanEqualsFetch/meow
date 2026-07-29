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

function util.drag(frame, handle, bin)
	handle = handle or frame
	local dragging = false
	local start_pos, start_input

	bin:add(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			start_input = input.Position
			start_pos = frame.Position
			local ended
			ended = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					ended:Disconnect()
				end
			end)
		end
	end))

	bin:add(user_input.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - start_input
			frame.Position = UDim2.new(
				start_pos.X.Scale,
				start_pos.X.Offset + delta.X,
				start_pos.Y.Scale,
				start_pos.Y.Offset + delta.Y
			)
		end
	end))
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
