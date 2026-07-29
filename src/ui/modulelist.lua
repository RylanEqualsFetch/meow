-- vape style enabled module list, top right, widest entry first

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local manager = meow.load("src/core/manager.lua")

local new = util.new
local tween = util.tween

local modulelist = {}

local entry_height = 22
local text_size = theme.size.body

function modulelist.create(gui, bin)
	local holder = new("Frame", {
		Name = "modulelist",
		Parent = gui,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 16),
		Size = UDim2.fromOffset(260, 600),
	}, {
		util.list(1, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right),
	})
	bin:add(holder)

	local entries = {}
	local self = {frame = holder}

	local function refresh_order()
		for _, entry in pairs(entries) do
			-- widest first, layout order takes integers so scale the width up
			entry.frame.LayoutOrder = -math.floor(entry.width * 10)
		end
	end

	local function add(mod)
		if entries[mod] then
			return
		end

		local width = util.text_width(mod.name, text_size, Enum.Font.GothamMedium) + 20
		local frame = new("Frame", {
			Parent = holder,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(width, entry_height),
			ClipsDescendants = false,
		})

		local body = new("Frame", {
			Parent = frame,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, width + 30, 0, 0),
			Size = UDim2.fromOffset(width, entry_height),
			BackgroundColor3 = theme.background,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {util.corner(theme.round.item + 1)})

		local bar = new("Frame", {
			Parent = body,
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(3, 0),
			Position = UDim2.new(0, 0, 0.5, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {util.corner(2)})
		theme.tint(bar, "BackgroundColor3")

		local label = new("TextLabel", {
			Parent = body,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(9, 0),
			Size = UDim2.new(1, -12, 1, 0),
			Text = mod.name,
			TextSize = text_size,
			TextColor3 = theme.text,
			TextTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		theme.apply_font(label, "semibold")

		entries[mod] = {frame = frame, body = body, label = label, bar = bar, width = width}
		refresh_order()

		tween(body, {Position = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 0.2}, 0.22, Enum.EasingStyle.Quint)
		tween(label, {TextTransparency = 0}, 0.22)
		-- the bar grows out of the middle instead of just fading in
		tween(bar, {
			BackgroundTransparency = 0,
			Size = UDim2.fromOffset(3, entry_height - 8),
		}, 0.26, Enum.EasingStyle.Back)
	end

	local function remove(mod)
		local entry = entries[mod]
		if not entry then
			return
		end
		entries[mod] = nil

		tween(entry.body, {
			Position = UDim2.new(1, entry.width + 30, 0, 0),
			BackgroundTransparency = 1,
		}, 0.2, Enum.EasingStyle.Quint)
		tween(entry.label, {TextTransparency = 1}, 0.16)
		tween(entry.bar, {BackgroundTransparency = 1, Size = UDim2.fromOffset(3, 0)}, 0.16)

		task.delay(0.24, function()
			if entry.frame and entry.frame.Parent then
				entry.frame:Destroy()
			end
		end)
		refresh_order()
	end

	bin:add(manager.toggled:connect(function(mod, enabled)
		if mod.hidden then
			return
		end
		if enabled then
			add(mod)
		else
			remove(mod)
		end
	end))

	for _, mod in ipairs(manager.module_order) do
		if mod.enabled and not mod.hidden then
			add(mod)
		end
	end

	function self:set_visible(visible)
		holder.Visible = visible and true or false
	end

	function self:destroy()
		holder:Destroy()
	end

	return self
end

return modulelist
