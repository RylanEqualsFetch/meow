-- alignment grid, only visible while a panel is being dragged

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")

local new = util.new
local tween = util.tween

local grid = {}

grid.spacing = 20

function grid.create(gui, bin)
	local holder = new("Frame", {
		Name = "grid",
		Parent = gui,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 0,
	})
	bin:add(holder)

	local lines = {}
	local built_for = Vector2.new(0, 0)
	local shown = 0

	local function clear()
		for _, line in ipairs(lines) do
			line:Destroy()
		end
		lines = {}
	end

	-- lines are rebuilt only when the viewport size actually changes
	local function build()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		if viewport.X == built_for.X and viewport.Y == built_for.Y and #lines > 0 then
			return
		end

		clear()
		built_for = viewport

		local spacing = grid.spacing
		local index = 0

		for x = 0, math.ceil(viewport.X), spacing do
			index = index + 1
			local major = index % 5 == 1
			local line = new("Frame", {
				Parent = holder,
				Position = UDim2.fromOffset(x, 0),
				Size = UDim2.new(0, 1, 1, 0),
				BackgroundColor3 = major and theme.accent or theme.text_faint,
				BackgroundTransparency = major and 0.72 or 0.9,
				BorderSizePixel = 0,
				ZIndex = 0,
			})
			table.insert(lines, line)
		end

		index = 0
		for y = 0, math.ceil(viewport.Y), spacing do
			index = index + 1
			local major = index % 5 == 1
			local line = new("Frame", {
				Parent = holder,
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = major and theme.accent or theme.text_faint,
				BackgroundTransparency = major and 0.72 or 0.9,
				BorderSizePixel = 0,
				ZIndex = 0,
			})
			table.insert(lines, line)
		end
	end

	local self = {frame = holder}

	-- reference counted so dragging one panel while another settles still works
	function self:show()
		shown = shown + 1
		build()
		holder.Visible = true
		for _, line in ipairs(lines) do
			line.BackgroundTransparency = 1
		end
		for _, line in ipairs(lines) do
			tween(line, {BackgroundTransparency = 0.86}, 0.12)
		end
	end

	function self:hide()
		shown = math.max(shown - 1, 0)
		if shown > 0 then
			return
		end
		for _, line in ipairs(lines) do
			tween(line, {BackgroundTransparency = 1}, 0.14)
		end
		task.delay(0.16, function()
			if shown == 0 and holder.Parent then
				holder.Visible = false
			end
		end)
	end

	function self:destroy()
		clear()
		holder:Destroy()
	end

	bin:add(function()
		clear()
	end)

	return self
end

return grid
