-- animated meow wordmark
-- each letter lights up in order with a stacked stroke bloom, then the whole word fades and repeats

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")

local new = util.new
local tween = util.tween

local logo = {}

local word = "meow"
local glow_layers = 3

local base_dim = 0.72
local glow_dim = 1

local function build_letter(parent, letter, size, offset, order)
	local width, height = util.text_width(letter, size, theme.font_bold)
	local cell = new("Frame", {
		Name = "letter_" .. order,
		Parent = parent,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(offset, 0),
		Size = UDim2.fromOffset(math.ceil(width), math.ceil(height * 1.25)),
	})

	local glows = {}
	for layer = 1, glow_layers do
		local label = new("TextLabel", {
			Parent = cell,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = theme.font_bold,
			Text = letter,
			TextSize = size,
			TextColor3 = theme.accent,
			TextTransparency = glow_dim,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 2,
		}, {
			new("UIStroke", {
				Color = theme.accent,
				Thickness = layer * 1.7,
				Transparency = 0.45 + layer * 0.16,
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		})
		theme.tint(label, "TextColor3")
		theme.tint(label:FindFirstChildOfClass("UIStroke"), "Color")
		glows[layer] = label
	end

	local base = new("TextLabel", {
		Parent = cell,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = theme.font_bold,
		Text = letter,
		TextSize = size,
		TextColor3 = theme.text,
		TextTransparency = base_dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
	})

	return {
		cell = cell,
		base = base,
		glows = glows,
		width = math.ceil(width),
		height = math.ceil(height * 1.25),
	}
end

-- opts: size, position, anchor, parent, spacing
function logo.create(parent, opts)
	opts = opts or {}
	local size = opts.size or 26
	local spacing = opts.spacing or math.floor(size * 0.08)

	local holder = new("Frame", {
		Name = "logo",
		Parent = parent,
		BackgroundTransparency = 1,
		Position = opts.position or UDim2.fromOffset(0, 0),
		AnchorPoint = opts.anchor or Vector2.new(0, 0),
		Size = UDim2.fromOffset(10, 10),
		ZIndex = opts.zindex or 2,
	})

	local letters = {}
	local offset = 0
	local tallest = 0

	for index = 1, #word do
		local letter = word:sub(index, index)
		local built = build_letter(holder, letter, size, offset, index)
		offset = offset + built.width + spacing
		tallest = math.max(tallest, built.height)
		letters[index] = built
	end

	holder.Size = UDim2.fromOffset(math.max(offset - spacing, 1), tallest)

	local self = {
		frame = holder,
		letters = letters,
		width = offset - spacing,
		height = tallest,
		alive = true,
	}

	local function light(built, on, speed)
		speed = speed or 0.22
		tween(built.base, {
			TextTransparency = on and 0 or base_dim,
			TextColor3 = on and Color3.new(1, 1, 1) or theme.text,
		}, speed)
		for layer, glow in ipairs(built.glows) do
			tween(glow, {TextTransparency = on and (0.24 + layer * 0.2) or glow_dim}, speed)
			local glow_stroke = glow:FindFirstChildOfClass("UIStroke")
			if glow_stroke then
				tween(glow_stroke, {
					Transparency = on and (0.28 + layer * 0.17) or 1,
				}, speed)
			end
		end
	end

	-- the writing loop, letters land one after another then the word breathes out
	task.spawn(function()
		while self.alive and holder.Parent do
			for index = 1, #letters do
				if not self.alive then
					return
				end
				light(letters[index], true, 0.14)
				task.wait(0.11)
			end

			task.wait(1.8)

			for index = 1, #letters do
				if not self.alive then
					return
				end
				light(letters[index], false, 0.3)
				task.wait(0.06)
			end

			task.wait(0.45)
		end
	end)

	function self:set_visible(visible)
		holder.Visible = visible and true or false
	end

	function self:destroy()
		self.alive = false
		holder:Destroy()
	end

	return self
end

return logo
