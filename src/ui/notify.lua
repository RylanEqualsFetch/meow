-- bottom right toasts

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local state = meow.load("src/core/state.lua")

local new = util.new
local tween = util.tween

local notify = {}

local holder

function notify.init(gui, bin)
	holder = new("Frame", {
		Name = "notifications",
		Parent = gui,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(300, 400),
	}, {
		util.list(6, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right),
	})
	holder:FindFirstChildOfClass("UIListLayout").VerticalAlignment = Enum.VerticalAlignment.Bottom
	bin:add(holder)
	bin:add(function()
		holder = nil
	end)
	return holder
end

function notify.push(text, duration)
	if not holder or not holder.Parent or not state.notifications then
		return
	end
	duration = duration or 3

	local width = math.min(util.text_width(text, 13, Enum.Font.Gotham) + 34, 290)

	local frame = new("Frame", {
		Parent = holder,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, 32),
	})

	local body = new("Frame", {
		Parent = frame,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, width + 20, 0, 0),
		Size = UDim2.fromOffset(width, 32),
		BackgroundColor3 = theme.surface,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		util.corner(theme.round.item),
		util.stroke(theme.outline, 1, 0.3),
	})

	local bar = new("Frame", {
		Parent = body,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromOffset(2, 20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {util.corner(1)})
	theme.tint(bar, "BackgroundColor3")

	local label = new("TextLabel", {
		Parent = body,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -18, 1, 0),
		Text = text,
		TextSize = theme.size.body,
		TextColor3 = theme.text,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	theme.apply_font(label, "medium")

	tween(body, {Position = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 0.05}, 0.22, Enum.EasingStyle.Quint)
	tween(label, {TextTransparency = 0}, 0.22)
	tween(bar, {BackgroundTransparency = 0}, 0.22)

	task.delay(duration, function()
		if not frame.Parent then
			return
		end
		tween(body, {Position = UDim2.new(1, width + 20, 0, 0), BackgroundTransparency = 1}, 0.2, Enum.EasingStyle.Quint)
		tween(label, {TextTransparency = 1}, 0.16)
		tween(bar, {BackgroundTransparency = 1}, 0.16)
		task.delay(0.24, function()
			if frame and frame.Parent then
				frame:Destroy()
			end
		end)
	end)
end

return notify
