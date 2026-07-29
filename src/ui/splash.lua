-- loading card, the wordmark animates while the client boots

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local logo = meow.load("src/ui/logo.lua")

local new = util.new
local tween = util.tween

local splash = {}

function splash.create(gui)
	local card = new("Frame", {
		Name = "splash",
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(290, 132),
		BackgroundColor3 = theme.background,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 40,
	}, {
		util.corner(theme.round.panel),
		util.stroke(theme.outline, 1, 1),
	})

	local card_stroke = card:FindFirstChildOfClass("UIStroke")

	local mark = logo.create(card, {
		size = 40,
		position = UDim2.new(0.5, 0, 0, 26),
		anchor = Vector2.new(0.5, 0),
		zindex = 42,
	})

	local status = new("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.new(1, -40, 0, 16),
		Text = "starting",
		TextSize = theme.size.tiny,
		TextColor3 = theme.text_dim,
		TextTransparency = 1,
		ZIndex = 42,
	})
	theme.apply_font(status, "medium")

	local track = new("Frame", {
		Parent = card,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.new(1, -44, 0, 3),
		BackgroundColor3 = theme.surface_light,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 42,
	}, {util.corner(2)})

	local fill = new("Frame", {
		Parent = track,
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 43,
	}, {util.corner(2)})
	theme.tint(fill, "BackgroundColor3")

	-- fade the card in, the wordmark is already writing itself
	tween(card, {BackgroundTransparency = 0.04}, 0.26)
	tween(card_stroke, {Transparency = 0.25}, 0.26)
	tween(status, {TextTransparency = 0}, 0.3)
	tween(track, {BackgroundTransparency = 0}, 0.3)
	tween(fill, {BackgroundTransparency = 0}, 0.3)

	local self = {frame = card, mark = mark}

	function self:set(alpha, text)
		fill.Size = UDim2.fromScale(0, 1)
		tween(fill, {Size = UDim2.fromScale(util.clamp(alpha, 0, 1), 1)}, 0.2)
		if text then
			status.Text = text
		end
	end

	function self:finish()
		tween(card, {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.44, 0),
		}, 0.28)
		tween(card_stroke, {Transparency = 1}, 0.2)
		tween(status, {TextTransparency = 1}, 0.2)
		tween(track, {BackgroundTransparency = 1}, 0.2)
		tween(fill, {BackgroundTransparency = 1}, 0.2)

		task.delay(0.32, function()
			mark:destroy()
			if card.Parent then
				card:Destroy()
			end
		end)
	end

	return self
end

return splash
