-- top left hud, animated wordmark plus fps and ping

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local logo = meow.load("src/ui/logo.lua")

local new = util.new

local watermark = {}

local function ping_value()
	local ok, value = pcall(function()
		local stats = game:GetService("Stats")
		local item = stats.Network.ServerStatsItem["Data Ping"]
		return math.floor(item:GetValue())
	end)
	if ok and type(value) == "number" then
		return value
	end
	return 0
end

function watermark.create(gui, bin, opts)
	local holder = new("Frame", {
		Name = "watermark",
		Parent = gui,
		BackgroundColor3 = theme.background,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromOffset(18, 16),
		Size = UDim2.fromOffset(168, 54),
		BorderSizePixel = 0,
	}, {
		util.corner(theme.round.panel),
		util.stroke(theme.outline, 1, 0.25),
		util.padding(8, 8, 12, 12),
	})
	bin:add(holder)

	local accent_bar = new("Frame", {
		Parent = holder,
		Position = UDim2.fromOffset(-12, 8),
		Size = UDim2.fromOffset(3, 38),
		BorderSizePixel = 0,
	}, {util.corner(2)})
	theme.tint(accent_bar, "BackgroundColor3")

	local mark = logo.create(holder, {size = 22, position = UDim2.fromOffset(0, 0), zindex = 3})

	local stats = new("TextLabel", {
		Parent = holder,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, mark.height + 1),
		Size = UDim2.new(1, 0, 0, 14),
		Text = "loading",
		TextSize = theme.size.tiny,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	theme.apply_font(stats, "medium")

	holder.Size = UDim2.fromOffset(math.max(mark.width + 60, 150), mark.height + 30)

	local run_service = util.services.RunService
	local frames = 0
	local elapsed = 0
	local fps = 60

	bin:add(run_service.RenderStepped:Connect(function(delta)
		frames = frames + 1
		elapsed = elapsed + delta
		if elapsed >= 0.5 then
			fps = math.floor(frames / elapsed + 0.5)
			frames = 0
			elapsed = 0
			stats.Text = fps .. " fps  |  " .. ping_value() .. " ms  |  " .. meow.version
		end
	end))

	local self = {frame = holder, mark = mark}

	-- slides in from the left once the splash is done
	function self:intro()
		local target = holder.Position
		holder.Position = UDim2.fromOffset(target.X.Offset - 26, target.Y.Offset)
		holder.BackgroundTransparency = 1
		accent_bar.BackgroundTransparency = 1
		stats.TextTransparency = 1
		holder.Visible = true

		util.tween(holder, {Position = target, BackgroundTransparency = 0.15}, 0.34, Enum.EasingStyle.Quint)
		util.tween(accent_bar, {BackgroundTransparency = 0}, 0.34)
		util.tween(stats, {TextTransparency = 0}, 0.34)
	end

	function self:set_visible(visible)
		holder.Visible = visible and true or false
	end

	function self:destroy()
		mark:destroy()
		holder:Destroy()
	end

	util.drag(holder, holder, bin, opts and opts.drag)
	return self
end

return watermark
