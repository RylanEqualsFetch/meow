-- vape style layout, a nav panel on the left and one stacked column per category

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local manager = meow.load("src/core/manager.lua")
local state = meow.load("src/core/state.lua")
local logo = meow.load("src/ui/logo.lua")
local grid = meow.load("src/ui/grid.lua")
local icons = meow.load("src/ui/icons.lua")

local new = util.new
local tween = util.tween
local user_input = util.services.UserInputService

local library = {}

local nav_width = 214
local nav_x = 24
local nav_y = 60
local column_width = 222
local column_gap = 10
local column_max_body = 430

-- shared between every draggable panel, tracks whether the current press turned
-- into a drag and which child rects must never start one
local drag_guard = {moved = false, zones = {}}

-- normalized drag inside a frame, alpha is clamped 0 to 1 on both axes
local function bind_drag(frame, bin, callback)
	table.insert(drag_guard.zones, frame)
	local dragging = false

	local function update(position)
		local size = frame.AbsoluteSize
		local origin = frame.AbsolutePosition
		local x = util.clamp((position.X - origin.X) / math.max(size.X, 1), 0, 1)
		local y = util.clamp((position.Y - origin.Y) / math.max(size.Y, 1), 0, 1)
		callback(x, y)
	end

	bin:add(frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			update(input.Position)
		end
	end))

	bin:add(user_input.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	bin:add(user_input.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			update(input.Position)
		end
	end))
end

local function label(parent, props, weight)
	local text = new("TextLabel", props)
	text.Parent = parent
	theme.apply_font(text, weight or "medium")
	return text
end

-- option controls, all sized for the column width

local controls = {}

function controls.toggle(parent, option, bin)
	local row = new("Frame", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
	})

	label(row, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -34, 1, 0),
		Text = option.name,
		TextSize = theme.size.tiny,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, "regular")

	local box = new("Frame", {
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
	}, {util.corner(theme.round.chip)})

	local check = new("Frame", {
		Parent = box,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {util.corner(2)})
	theme.tint(check, "BackgroundColor3")

	local function render(value)
		tween(box, {BackgroundColor3 = value and theme.accent_dark or theme.surface_light}, 0.12)
		tween(check, {
			BackgroundTransparency = value and 0 or 1,
			Size = value and UDim2.fromOffset(6, 6) or UDim2.fromOffset(2, 2),
		}, 0.12)
	end

	render(option.value)

	local button = new("TextButton", {
		Parent = row,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
	})

	bin:add(button.MouseButton1Click:Connect(function()
		option:set(not option.value)
	end))
	bin:add(option:listen(render))

	return row
end

function controls.slider(parent, option, bin)
	local row = new("Frame", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
	})

	label(row, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -62, 0, 15),
		Text = option.name,
		TextSize = theme.size.tiny,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, "regular")

	local value_label = label(row, {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(62, 15),
		Text = tostring(option.value) .. option.suffix,
		TextSize = theme.size.tiny,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, "semibold")

	local track = new("Frame", {
		Parent = row,
		Position = UDim2.fromOffset(0, 21),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
	}, {util.corner(2)})

	local fill = new("Frame", {
		Parent = track,
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
	}, {util.corner(2)})
	theme.tint(fill, "BackgroundColor3")

	local function render(value)
		local alpha = (value - option.min) / math.max(option.max - option.min, 0.0001)
		fill.Size = UDim2.fromScale(util.clamp(alpha, 0, 1), 1)
		value_label.Text = tostring(value) .. option.suffix
	end

	render(option.value)

	local hit = new("Frame", {
		Parent = row,
		Position = UDim2.fromOffset(0, 15),
		Size = UDim2.new(1, 0, 0, 15),
		BackgroundTransparency = 1,
	})

	bind_drag(hit, bin, function(x)
		option:set(option.min + (option.max - option.min) * x)
	end)

	bin:add(option:listen(render))
	return row
end

function controls.dropdown(parent, option, bin)
	local row = new("Frame", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {util.list(3)})

	local header = new("TextButton", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 1,
	}, {util.corner(theme.round.item)})

	label(header, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		Text = option.name,
		TextSize = theme.size.tiny,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, "regular")

	local value_label = label(header, {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0.55, -12, 1, 0),
		Text = "",
		TextSize = theme.size.tiny,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, "semibold")

	local list = new("Frame", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 2,
	}, {util.list(2)})

	local entries = {}

	local function is_picked(entry)
		if not option.multi then
			return option.value == entry
		end
		for _, picked in ipairs(option.value) do
			if picked == entry then
				return true
			end
		end
		return false
	end

	local function selected_text()
		if not option.multi then
			return tostring(option.value)
		end
		if #option.value == 0 then
			return "none"
		end
		return table.concat(option.value, ", ")
	end

	local function render()
		value_label.Text = selected_text()
		for entry, button in pairs(entries) do
			local picked = is_picked(entry)
			tween(button, {BackgroundColor3 = picked and theme.accent_dark or theme.surface}, 0.12)
			button.TextColor3 = picked and theme.text or theme.text_dim
		end
	end

	for _, entry in ipairs(option.values) do
		local button = new("TextButton", {
			Parent = list,
			Size = UDim2.new(1, 0, 0, 21),
			BackgroundColor3 = theme.surface,
			BorderSizePixel = 0,
			Text = "  " .. entry,
			TextSize = theme.size.tiny,
			TextColor3 = theme.text_dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = false,
		}, {util.corner(theme.round.chip)})
		theme.apply_font(button, "regular")

		entries[entry] = button

		bin:add(button.MouseButton1Click:Connect(function()
			if option.multi then
				local picked = {}
				local removed = false
				for _, value in ipairs(option.value) do
					if value == entry then
						removed = true
					else
						table.insert(picked, value)
					end
				end
				if not removed then
					table.insert(picked, entry)
				end
				option:set(picked)
			else
				option:set(entry)
				list.Visible = false
			end
			render()
		end))
	end

	bin:add(header.MouseButton1Click:Connect(function()
		list.Visible = not list.Visible
	end))
	bin:add(option:listen(render))

	render()
	return row
end

function controls.color(parent, option, bin)
	local row = new("Frame", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, {util.list(5)})

	local header = new("TextButton", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 1,
	})

	label(header, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -38, 1, 0),
		Text = option.name,
		TextSize = theme.size.tiny,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, "regular")

	local swatch = new("Frame", {
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(28, 14),
		BackgroundColor3 = option.value,
		BorderSizePixel = 0,
	}, {util.corner(theme.round.chip), util.stroke(theme.outline, 1, 0.3)})

	local panel = new("Frame", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 108),
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 2,
	})

	local square = new("Frame", {
		Parent = panel,
		Size = UDim2.new(1, 0, 0, 86),
		BackgroundColor3 = Color3.fromRGB(255, 0, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {util.corner(theme.round.item)})

	new("Frame", {
		Parent = square,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, {
		new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	new("Frame", {
		Parent = square,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})

	local cursor = new("Frame", {
		Parent = square,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, {util.corner(theme.round.chip), util.stroke(Color3.new(1, 1, 1), 2, 0)})

	local hue_bar = new("Frame", {
		Parent = panel,
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, {
		util.corner(theme.round.item),
		new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(0.34, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(0.84, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
			}),
		}),
	})

	local hue_knob = new("Frame", {
		Parent = hue_bar,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(5, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, {util.corner(theme.round.item)})

	local hue, sat, val = Color3.toHSV(option.value)

	local function push()
		option:set(Color3.fromHSV(hue, sat, val))
	end

	local function render(color)
		hue, sat, val = Color3.toHSV(color)
		swatch.BackgroundColor3 = color
		square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		cursor.Position = UDim2.fromScale(sat, 1 - val)
		hue_knob.Position = UDim2.new(hue, 0, 0.5, 0)
	end

	render(option.value)

	bind_drag(square, bin, function(x, y)
		sat = x
		val = 1 - y
		push()
	end)

	bind_drag(hue_bar, bin, function(x)
		hue = x
		push()
	end)

	bin:add(header.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end))
	bin:add(option:listen(render))

	return row
end

function controls.input(parent, option, bin)
	local row = new("Frame", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
	})

	label(row, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Text = option.name,
		TextSize = theme.size.tiny,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, "regular")

	local box = new("TextBox", {
		Parent = row,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
		Text = tostring(option.value or ""),
		PlaceholderText = option.placeholder or "",
		PlaceholderColor3 = theme.text_faint,
		TextSize = theme.size.tiny,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, {
		util.corner(theme.round.chip),
		util.padding(0, 0, 8, 8),
	})
	theme.apply_font(box, "medium")

	-- the box is a no drag zone, typing in it must never move the panel
	table.insert(drag_guard.zones, box)

	bin:add(box.FocusLost:Connect(function()
		option:set(box.Text)
	end))
	bin:add(option:listen(function(value)
		if box.Text ~= tostring(value) then
			box.Text = tostring(value)
		end
	end))

	return row
end

function controls.button(parent, option, bin)
	local button = new("TextButton", {
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
		Text = option.name,
		TextSize = theme.size.tiny,
		TextColor3 = theme.text,
		AutoButtonColor = false,
	}, {util.corner(theme.round.item)})
	theme.apply_font(button, "medium")

	bin:add(button.MouseEnter:Connect(function()
		tween(button, {BackgroundColor3 = theme.surface_hover}, 0.12)
	end))
	bin:add(button.MouseLeave:Connect(function()
		tween(button, {BackgroundColor3 = theme.surface_light}, 0.12)
	end))
	bin:add(button.MouseButton1Click:Connect(function()
		if option.action then
			local ok, err = pcall(option.action, option)
			if not ok then
				warn("meow: button action error: " .. tostring(err))
			end
		end
	end))

	return button
end

function library.create(gui, bin)
	local self = {visible = true, columns = {}, closed = util.signal()}

	local snap_grid = grid.create(gui, bin)

	-- every panel drags on the same grid and snaps to it. the threshold lets a
	-- press on a module row still be a click when the mouse does not move
	local drag_opts = {
		snap = grid.spacing,
		threshold = 5,
		state = drag_guard,
		on_start = function()
			snap_grid:show()
		end,
		on_end = function()
			snap_grid:hide()
		end,
	}

	local root = new("Frame", {
		Name = "ui",
		Parent = gui,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})
	bin:add(root)
	self.frame = root

	-- keybind capture, one listener at a time
	local capturing

	local function start_capture(mod, finish)
		if capturing then
			capturing()
		end

		local connection
		connection = user_input.InputBegan:Connect(function(input, processed)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end

			local key = input.KeyCode
			local clearing = key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace

			-- roblox marks escape as processed because it opens its own menu,
			-- so a clear has to be let through anyway
			if processed and not clearing then
				return
			end

			connection:Disconnect()
			capturing = nil

			if clearing then
				mod:set_key(nil)
			else
				mod:set_key(key)
			end
			finish()
		end)

		capturing = function()
			connection:Disconnect()
			capturing = nil
			finish()
		end
	end

	-- one module entry inside a column
	local function build_module(parent, mod, order)
		local holder = new("Frame", {
			Parent = parent,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, {util.list(3)})

		local button = new("TextButton", {
			Parent = holder,
			Size = UDim2.new(1, 0, 0, 33),
			BackgroundColor3 = theme.surface,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
		}, {util.corner(theme.round.item)})

		local name_label = label(button, {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(11, 0),
			Size = UDim2.new(1, -58, 1, 0),
			Text = mod.name,
			TextSize = theme.size.body + 1,
			TextColor3 = theme.text_soft,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, "semibold")

		-- a keycap chip, it only shows once bound or while the row is hovered
		local key_chip = new("TextButton", {
			Parent = button,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -9, 0.5, 0),
			Size = UDim2.fromOffset(30, 17),
			BackgroundColor3 = theme.surface_light,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Text = "",
			TextSize = theme.size.tiny - 1,
			TextColor3 = theme.text_dim,
			AutoButtonColor = false,
			Visible = mod.key ~= nil,
		}, {
			util.corner(theme.round.chip),
			util.stroke(theme.outline, 1, 0.35),
		})
		theme.apply_font(key_chip, "semibold")

		local hovered = false
		local binding = false

		local function render_key()
			if binding then
				key_chip.Visible = true
				key_chip.Text = "press"
				key_chip.TextColor3 = theme.accent
				key_chip.Size = UDim2.fromOffset(42, 17)
				return
			end

			if mod.key then
				local text = util.key_name(mod.key)
				key_chip.Visible = true
				key_chip.Text = text
				key_chip.TextColor3 = theme.text_dim
				key_chip.Size = UDim2.fromOffset(
					math.max(26, util.text_width(text, theme.size.tiny, Enum.Font.Gotham) + 14),
					17
				)
			else
				key_chip.Visible = hovered
				key_chip.Text = "bind"
				key_chip.TextColor3 = theme.text_faint
				key_chip.Size = UDim2.fromOffset(34, 17)
			end
		end

		render_key()

		-- the options panel, opened with a right click on the row
		local options_frame

		if #mod.option_order > 0 then
			options_frame = new("Frame", {
				Parent = holder,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = theme.background,
				BorderSizePixel = 0,
				Visible = false,
				LayoutOrder = 2,
			}, {
				util.corner(theme.round.item),
				util.stroke(theme.outline, 1, 0.4),
				util.list(7),
				util.padding(9, 10, 10, 10),
			})

			for _, option in ipairs(mod.option_order) do
				local builder = controls[option.kind]
				if builder then
					builder(options_frame, option, bin)
				end
			end
		end

		-- only the name reacts now, no fill and no bar
		local name_glow = util.stroke(theme.accent, 1, 1)
		name_glow.Parent = name_label
		theme.tint(name_glow, "Color")

		local function render_state(enabled, instant)
			local speed = instant and 0 or 0.16
			tween(name_label, {TextColor3 = enabled and theme.accent or theme.text_soft}, speed)
			tween(name_glow, {Transparency = enabled and 0.55 or 1}, speed)
		end

		render_state(mod.enabled, true)

		bin:add(button.MouseButton1Click:Connect(function()
			if drag_guard.moved then
				return
			end
			mod:toggle_state()
		end))

		bin:add(key_chip.MouseButton1Click:Connect(function()
			if drag_guard.moved then
				return
			end
			binding = true
			render_key()
			start_capture(mod, function()
				binding = false
				render_key()
			end)
		end))

		-- inputbegan rather than mousebutton2click, the click event does not
		-- always survive a game that binds the right mouse button itself
		local function set_options(open)
			if not options_frame then
				return
			end
			if open then
				options_frame.Visible = true
				options_frame.BackgroundTransparency = 1
				options_frame.Position = UDim2.fromOffset(0, -6)
				tween(options_frame, {
					BackgroundTransparency = 0,
					Position = UDim2.fromOffset(0, 0),
				}, 0.18, Enum.EasingStyle.Quint)
			else
				tween(options_frame, {BackgroundTransparency = 1}, 0.12)
				task.delay(0.12, function()
					if options_frame and options_frame.Parent then
						options_frame.Visible = false
					end
				end)
			end
		end

		bin:add(button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and options_frame then
				set_options(not options_frame.Visible)
			end
		end))

		bin:add(button.MouseEnter:Connect(function()
			hovered = true
			render_key()
			tween(button, {BackgroundColor3 = theme.surface_hover}, 0.12)
		end))

		bin:add(button.MouseLeave:Connect(function()
			hovered = false
			render_key()
			tween(button, {BackgroundColor3 = theme.surface}, 0.12)
		end))

		bin:add(manager.toggled:connect(function(changed, enabled)
			if changed == mod then
				render_state(enabled)
			end
		end))

		-- keeps the bind chip honest after a config load or a clear
		bin:add(manager.changed:connect(function()
			if not capturing then
				render_key()
			end
		end))

		return holder
	end

	-- one draggable column per category
	local function build_column(category, index)
		local saved = state.columns[category.name] or {}

		local frame = new("Frame", {
			Name = category.name,
			Parent = root,
			Position = UDim2.fromOffset(
				saved.x or (nav_x + nav_width + 16 + (index - 1) * (column_width + column_gap)),
				saved.y or nav_y
			),
			Size = UDim2.fromOffset(column_width, 40),
			BackgroundColor3 = theme.background,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Visible = saved.open ~= false,
		}, {
			util.corner(theme.round.panel),
			util.stroke(theme.outline, 1, 0.15),
		})

		local header = new("TextButton", {
			Parent = frame,
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
		})

		local accent_dot = new("Frame", {
			Parent = header,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(3, 12),
			BorderSizePixel = 0,
		}, {util.corner(2)})
		theme.tint(accent_dot, "BackgroundColor3")

		local header_icon = new("ImageLabel", {
			Parent = header,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 21, 0.5, 0),
			Size = UDim2.fromOffset(15, 15),
			BackgroundTransparency = 1,
			ImageTransparency = 1,
			Visible = false,
			ScaleType = Enum.ScaleType.Fit,
		})
		theme.tint(header_icon, "ImageColor3")

		local header_label = label(header, {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(23, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Text = category.name,
			TextSize = theme.size.title,
			TextColor3 = theme.text,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, "semibold")

		task.spawn(function()
			local asset = icons.fetch(category.name)
			if asset and header_icon.Parent then
				header_icon.Image = asset
				header_icon.Visible = true
				tween(header_icon, {ImageTransparency = 0}, 0.2)
				tween(header_label, {Position = UDim2.fromOffset(42, 0)}, 0.2)
			end
		end)

		local count = label(header, {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -28, 0.5, 0),
			Size = UDim2.fromOffset(24, 14),
			Text = tostring(#category.modules),
			TextSize = theme.size.tiny - 1,
			TextColor3 = theme.text_faint,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, "regular")

		local chevron = new("TextButton", {
			Parent = header,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1,
			Text = "^",
			TextSize = theme.size.small,
			TextColor3 = theme.text_faint,
			AutoButtonColor = false,
		})
		theme.apply_font(chevron, "bold")

		local body = new("ScrollingFrame", {
			Parent = frame,
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = theme.outline,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, {
			util.list(4),
			util.padding(2, 10, 10, 10),
		})

		for order, mod in ipairs(category.modules) do
			build_module(body, mod, order)
		end

		local layout = body:FindFirstChildOfClass("UIListLayout")
		local collapsed = saved.collapsed == true

		local function resize()
			if collapsed then
				body.Visible = false
				tween(frame, {Size = UDim2.fromOffset(column_width, 36)}, 0.14)
				return
			end
			body.Visible = true
			local content = layout.AbsoluteContentSize.Y + 12
			local height = math.min(content, column_max_body)
			body.Size = UDim2.new(1, 0, 0, height)
			tween(frame, {Size = UDim2.fromOffset(column_width, 36 + height)}, 0.14)
		end

		resize()
		bin:add(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize))

		util.drag(frame, header, bin, drag_opts)

		local column = {frame = frame, category = category.name}

		function column:set_open(open)
			open = open and true or false

			if open then
				frame.Visible = true
				frame.BackgroundTransparency = 1
				local target = frame.Position
				frame.Position = UDim2.new(
					target.X.Scale,
					target.X.Offset,
					target.Y.Scale,
					target.Y.Offset + 10
				)
				tween(frame, {BackgroundTransparency = 0.05, Position = target}, 0.2, Enum.EasingStyle.Quint)
			else
				tween(frame, {BackgroundTransparency = 1}, 0.12)
				task.delay(0.12, function()
					if frame.Parent and frame.BackgroundTransparency > 0.9 then
						frame.Visible = false
					end
				end)
			end

			state.columns[category.name] = state.columns[category.name] or {}
			state.columns[category.name].open = open
		end

		function column:is_open()
			return frame.Visible
		end

		function column:set_collapsed(value)
			collapsed = value and true or false
			chevron.Text = collapsed and "v" or "^"
			state.columns[category.name] = state.columns[category.name] or {}
			state.columns[category.name].collapsed = collapsed
			resize()
		end

		column:set_collapsed(collapsed)

		bin:add(chevron.MouseButton1Click:Connect(function()
			column:set_collapsed(not collapsed)
		end))

		-- remember where the user parks each column
		bin:add(frame:GetPropertyChangedSignal("Position"):Connect(function()
			local entry = state.columns[category.name] or {}
			entry.x = frame.Position.X.Offset
			entry.y = frame.Position.Y.Offset
			entry.open = frame.Visible
			entry.collapsed = collapsed
			state.columns[category.name] = entry
		end))

		count.Text = tostring(#category.modules)
		return column
	end

	for index, category in ipairs(manager.category_order) do
		self.columns[category.name] = build_column(category, index)
	end

	-- nav panel

	local nav = new("Frame", {
		Name = "nav",
		Parent = root,
		Position = UDim2.fromOffset(state.nav_x or nav_x, state.nav_y or nav_y),
		Size = UDim2.fromOffset(nav_width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = theme.background,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, {
		util.corner(theme.round.panel),
		util.stroke(theme.outline, 1, 0.15),
		util.list(0),
		util.padding(0, 12, 0, 0),
	})

	local nav_header = new("Frame", {
		Parent = nav,
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	})

	local mark = logo.create(nav_header, {size = 24, position = UDim2.fromOffset(16, 16), zindex = 3})

	label(nav_header, {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 22),
		Size = UDim2.fromOffset(70, 14),
		Text = meow.version,
		TextSize = theme.size.tiny - 1,
		TextColor3 = theme.text_faint,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, "regular")

	util.drag(nav, nav_header, bin, drag_opts)

	local function section(title, order)
		local holder = new("Frame", {
			Parent = nav,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, {util.list(2), util.padding(6, 4, 10, 10)})

		if title then
			local caption = label(holder, {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 18),
				Text = title,
				TextSize = theme.size.tiny - 2,
				TextColor3 = theme.text_faint,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 0,
			}, "semibold")
			caption.Parent = holder
		end

		return holder
	end

	local function nav_row(parent, text, order, icon_name)
		local button = new("TextButton", {
			Parent = parent,
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = theme.surface,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
		}, {util.corner(theme.round.item)})

		local icon = new("ImageLabel", {
			Parent = button,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			ImageTransparency = 1,
			Visible = false,
			ScaleType = Enum.ScaleType.Fit,
		})
		theme.tint(icon, "ImageColor3")

		local text_label = label(button, {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(11, 0),
			Size = UDim2.new(1, -34, 1, 0),
			Text = text,
			TextSize = theme.size.body,
			TextColor3 = theme.text_dim,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, "medium")

		-- the label slides over only once an icon actually resolves
		if icon_name then
			task.spawn(function()
				local asset = icons.fetch(icon_name)
				if asset and icon.Parent then
					icon.Image = asset
					icon.Visible = true
					tween(icon, {ImageTransparency = 0}, 0.2)
					tween(text_label, {Position = UDim2.fromOffset(34, 0)}, 0.2)
				end
			end)
		end

		local mark_label = label(button, {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(12, 14),
			Text = ">",
			TextSize = theme.size.tiny,
			TextColor3 = theme.text_faint,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, "bold")

		return button, text_label, mark_label
	end

	local categories_section = section(nil, 2)

	for index, category in ipairs(manager.category_order) do
		local column = self.columns[category.name]
		local button, text_label, mark_label = nav_row(categories_section, category.name, index, category.name)

		local function render()
			local open = column:is_open()
			tween(button, {BackgroundTransparency = open and 0 or 1}, 0.12)
			tween(text_label, {TextColor3 = open and theme.text or theme.text_dim}, 0.12)
			mark_label.Text = open and "v" or ">"
			if open then
				button.BackgroundColor3 = theme.surface
			end
		end

		render()

		bin:add(button.MouseButton1Click:Connect(function()
			column:set_open(not column:is_open())
			render()
		end))

		bin:add(button.MouseEnter:Connect(function()
			tween(text_label, {Position = UDim2.fromOffset(text_label.Position.X.Offset + 3, 0)}, 0.12)
			if not column:is_open() then
				tween(button, {BackgroundTransparency = 0.6}, 0.12)
			end
		end))

		bin:add(button.MouseLeave:Connect(function()
			tween(text_label, {Position = UDim2.fromOffset(icon.Visible and 34 or 11, 0)}, 0.12)
			render()
		end))
	end

	local overlays_section = section("overlays", 3)

	local overlay_modules = {"watermark", "module list"}
	for index, name in ipairs(overlay_modules) do
		local mod = manager.modules["settings/" .. name]
		if mod then
			local button, text_label, mark_label = nav_row(overlays_section, name, index)
			mark_label.Text = ""

			local dot = new("Frame", {
				Parent = button,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(7, 7),
				BackgroundColor3 = theme.surface_light,
				BorderSizePixel = 0,
			}, {util.corner(theme.round.chip)})

			local function render(enabled)
				tween(dot, {BackgroundColor3 = enabled and theme.accent or theme.surface_light}, 0.12)
				tween(text_label, {TextColor3 = enabled and theme.text or theme.text_dim}, 0.12)
			end

			render(mod.enabled)

			bin:add(button.MouseButton1Click:Connect(function()
				mod:toggle_state()
			end))

			bin:add(manager.toggled:connect(function(changed, enabled)
				if changed == mod then
					render(enabled)
				end
			end))
		end
	end

	local misc_section = section("misc", 4)

	local hide_button, hide_label = nav_row(misc_section, "hide menu", 1)
	hide_label.TextColor3 = theme.text_dim
	bin:add(hide_button.MouseButton1Click:Connect(function()
		self:set_visible(false)
		self.closed:fire()
	end))
	bin:add(hide_button.MouseEnter:Connect(function()
		tween(hide_button, {BackgroundTransparency = 0.6}, 0.12)
	end))
	bin:add(hide_button.MouseLeave:Connect(function()
		tween(hide_button, {BackgroundTransparency = 1}, 0.12)
	end))

	local unload_button, unload_label, unload_mark = nav_row(misc_section, "unload", 2)
	unload_mark.Text = "x"
	unload_label.TextColor3 = theme.bad
	unload_mark.TextColor3 = theme.bad

	bin:add(unload_button.MouseEnter:Connect(function()
		tween(unload_button, {BackgroundColor3 = theme.bad, BackgroundTransparency = 0.82}, 0.12)
	end))
	bin:add(unload_button.MouseLeave:Connect(function()
		tween(unload_button, {BackgroundTransparency = 1}, 0.12)
	end))
	bin:add(unload_button.MouseButton1Click:Connect(function()
		task.spawn(function()
			if type(meow.unload) == "function" then
				meow.unload()
			end
		end)
	end))

	-- remember where the nav sits
	bin:add(nav:GetPropertyChangedSignal("Position"):Connect(function()
		state.nav_x = nav.Position.X.Offset
		state.nav_y = nav.Position.Y.Offset
	end))

	function self:set_visible(visible)
		self.visible = visible and true or false
		root.Visible = self.visible
	end

	self.grid = snap_grid

	function self:select(name)
		local column = self.columns[name]
		if column then
			column:set_open(true)
		end
	end

	bin:add(function()
		mark:destroy()
	end)

	return self
end

return library
