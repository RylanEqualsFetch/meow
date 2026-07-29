-- main window, category rail on the left, module rows on the right

local util = meow.load("src/core/util.lua")
local theme = meow.load("src/ui/theme.lua")
local manager = meow.load("src/core/manager.lua")
local logo = meow.load("src/ui/logo.lua")

local new = util.new
local tween = util.tween
local user_input = util.services.UserInputService

local library = {}

local window_width = 620
local window_height = 428
local rail_width = 148

-- normalized drag inside a frame, alpha is clamped 0 to 1 on both axes
local function bind_drag(frame, bin, callback)
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

local function make_pill(parent, width, height, position)
	local pill = new("Frame", {
		Parent = parent,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = position,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
	}, {util.corner(height / 2)})

	local knob = new("Frame", {
		Parent = pill,
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.fromOffset(height - 6, height - 6),
		BackgroundColor3 = theme.text_faint,
		BorderSizePixel = 0,
	}, {util.corner((height - 6) / 2)})

	local function render(on, instant)
		local speed = instant and 0 or 0.16
		if on then
			tween(pill, {BackgroundColor3 = theme.accent}, speed)
			tween(knob, {
				Position = UDim2.fromOffset(width - height + 3, 3),
				BackgroundColor3 = Color3.new(1, 1, 1),
			}, speed)
		else
			tween(pill, {BackgroundColor3 = theme.surface_light}, speed)
			tween(knob, {
				Position = UDim2.fromOffset(3, 3),
				BackgroundColor3 = theme.text_faint,
			}, speed)
		end
	end

	return pill, render
end

local controls = {}

function controls.toggle(parent, option, bin)
	local row = new("Frame", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
	})

	new("TextLabel", {
		Parent = row,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -46, 1, 0),
		Font = theme.font,
		Text = option.name,
		TextSize = 12,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local pill, render = make_pill(row, 28, 14, UDim2.new(1, 0, 0.5, 0))
	render(option.value, true)

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
	bin:add(option:listen(function(value)
		render(value)
	end))

	return row
end

function controls.slider(parent, option, bin)
	local row = new("Frame", {
		Parent = parent,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 32),
	})

	new("TextLabel", {
		Parent = row,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 16),
		Font = theme.font,
		Text = option.name,
		TextSize = 12,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local value_label = new("TextLabel", {
		Parent = row,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(60, 16),
		Font = theme.font_medium,
		Text = tostring(option.value) .. option.suffix,
		TextSize = 12,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local track = new("Frame", {
		Parent = row,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 5),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
	}, {util.corner(3)})

	local fill = new("Frame", {
		Parent = track,
		Size = UDim2.fromScale(0, 1),
		BorderSizePixel = 0,
	}, {util.corner(3)})
	theme.tint(fill, "BackgroundColor3")

	local function render(value)
		local alpha = (value - option.min) / math.max(option.max - option.min, 0.0001)
		fill.Size = UDim2.fromScale(util.clamp(alpha, 0, 1), 1)
		value_label.Text = tostring(value) .. option.suffix
	end

	render(option.value)

	local hit = new("Frame", {
		Parent = row,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 16),
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
	}, {util.list(4)})

	local header = new("TextButton", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 1,
	}, {util.corner(5)})

	new("TextLabel", {
		Parent = header,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Font = theme.font,
		Text = option.name,
		TextSize = 12,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local value_label = new("TextLabel", {
		Parent = header,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0.5, -12, 1, 0),
		Font = theme.font_medium,
		Text = "",
		TextSize = 12,
		TextColor3 = theme.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local list = new("Frame", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 2,
	}, {util.list(3)})

	local function selected_text()
		if not option.multi then
			return tostring(option.value)
		end
		local parts = {}
		for _, entry in ipairs(option.value) do
			table.insert(parts, entry)
		end
		if #parts == 0 then
			return "none"
		end
		return table.concat(parts, ", ")
	end

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

	local function render()
		value_label.Text = selected_text()
		for entry, button in pairs(entries) do
			local picked = is_picked(entry)
			tween(button, {
				BackgroundColor3 = picked and theme.accent_dark or theme.surface_light,
			}, 0.12)
			button.TextColor3 = picked and theme.text or theme.text_dim
		end
	end

	for _, entry in ipairs(option.values) do
		local button = new("TextButton", {
			Parent = list,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = theme.surface_light,
			BorderSizePixel = 0,
			Font = theme.font,
			Text = "  " .. entry,
			TextSize = 12,
			TextColor3 = theme.text_dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = false,
		}, {util.corner(4)})

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
	}, {util.list(6)})

	local header = new("TextButton", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = 1,
	})

	new("TextLabel", {
		Parent = header,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 1, 0),
		Font = theme.font,
		Text = option.name,
		TextSize = 12,
		TextColor3 = theme.text_dim,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local swatch = new("Frame", {
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(30, 14),
		BackgroundColor3 = option.value,
		BorderSizePixel = 0,
	}, {util.corner(4), util.stroke(theme.outline, 1, 0.3)})

	local panel = new("Frame", {
		Parent = row,
		Size = UDim2.new(1, 0, 0, 116),
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 2,
	})

	local square = new("Frame", {
		Parent = panel,
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundColor3 = Color3.fromRGB(255, 0, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {util.corner(5)})

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
	}, {util.corner(4), util.stroke(Color3.new(1, 1, 1), 2, 0)})

	local hue_bar = new("Frame", {
		Parent = panel,
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, {
		util.corner(6),
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
		Size = UDim2.fromOffset(6, 16),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, {util.corner(3)})

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

function controls.button(parent, option, bin)
	local button = new("TextButton", {
		Parent = parent,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = theme.surface_light,
		BorderSizePixel = 0,
		Font = theme.font_medium,
		Text = option.name,
		TextSize = 12,
		TextColor3 = theme.text,
		AutoButtonColor = false,
	}, {util.corner(5)})

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
	local self = {visible = true, pages = {}, closed = util.signal()}

	local window = new("Frame", {
		Name = "window",
		Parent = gui,
		Size = UDim2.fromOffset(window_width, window_height),
		Position = UDim2.new(0.5, -window_width / 2, 0.5, -window_height / 2),
		BackgroundColor3 = theme.background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, {
		util.corner(12),
		util.stroke(theme.outline, 1, 0.1),
	})
	bin:add(window)
	self.frame = window

	local header = new("Frame", {
		Parent = window,
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
	})

	local mark = logo.create(header, {size = 24, position = UDim2.fromOffset(18, 16), zindex = 3})

	new("TextLabel", {
		Parent = header,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18 + mark.width + 12, 16),
		Size = UDim2.fromOffset(120, mark.height),
		Font = theme.font,
		Text = meow.version,
		TextSize = 11,
		TextColor3 = theme.text_faint,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})

	local close = new("TextButton", {
		Parent = header,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = theme.surface,
		BorderSizePixel = 0,
		Font = theme.font_bold,
		Text = "x",
		TextSize = 12,
		TextColor3 = theme.text_dim,
		AutoButtonColor = false,
	}, {util.corner(6)})

	new("Frame", {
		Parent = window,
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = theme.outline,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	})

	local rail = new("Frame", {
		Parent = window,
		Position = UDim2.fromOffset(0, 59),
		Size = UDim2.new(0, rail_width, 1, -59),
		BackgroundTransparency = 1,
	}, {
		util.list(4),
		util.padding(12, 12, 12, 10),
	})

	new("Frame", {
		Parent = window,
		Position = UDim2.fromOffset(rail_width, 59),
		Size = UDim2.new(0, 1, 1, -59),
		BackgroundColor3 = theme.outline,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
	})

	local content = new("Frame", {
		Parent = window,
		Position = UDim2.fromOffset(rail_width + 1, 59),
		Size = UDim2.new(1, -rail_width - 1, 1, -59),
		BackgroundTransparency = 1,
	})

	util.drag(window, header, bin)

	local buttons = {}
	local active

	local function select(name)
		active = name
		for page_name, page in pairs(self.pages) do
			page.Visible = page_name == name
		end
		for button_name, button in pairs(buttons) do
			local picked = button_name == name
			tween(button, {
				BackgroundTransparency = picked and 0 or 1,
				TextColor3 = picked and theme.text or theme.text_dim,
			}, 0.14)
			local bar = button:FindFirstChild("indicator")
			if bar then
				tween(bar, {
					Size = UDim2.fromOffset(3, picked and 16 or 0),
					BackgroundTransparency = picked and 0 or 1,
				}, 0.14)
			end
		end
	end

	self.select = function(_, name)
		select(name)
	end

	-- keybind capture, one listener at a time
	local capturing

	local function start_capture(mod, label)
		if capturing then
			capturing()
		end
		label.Text = "..."
		local connection
		connection = user_input.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			connection:Disconnect()
			capturing = nil
			if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
				mod:set_key(nil)
				label.Text = ""
			else
				mod:set_key(input.KeyCode)
				label.Text = util.key_name(input.KeyCode)
			end
		end)
		capturing = function()
			connection:Disconnect()
			capturing = nil
			label.Text = mod.key and util.key_name(mod.key) or ""
		end
	end

	local function build_module(page, mod)
		local row = new("Frame", {
			Parent = page,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = theme.surface,
			BorderSizePixel = 0,
			ClipsDescendants = true,
		}, {
			util.corner(8),
			util.list(0),
		})

		local row_header = new("TextButton", {
			Parent = row,
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 1,
		})

		local name_label = new("TextLabel", {
			Parent = row_header,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -130, 1, 0),
			Font = theme.font_medium,
			Text = mod.name,
			TextSize = 13,
			TextColor3 = theme.text_dim,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local key_label = new("TextLabel", {
			Parent = row_header,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -80, 0.5, 0),
			Size = UDim2.fromOffset(70, 16),
			Font = theme.font,
			Text = mod.key and util.key_name(mod.key) or "",
			TextSize = 11,
			TextColor3 = theme.text_faint,
			TextXAlignment = Enum.TextXAlignment.Right,
		})

		local options_frame
		local expanded = false
		local chevron

		if #mod.option_order > 0 then
			chevron = new("TextButton", {
				Parent = row_header,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -56, 0.5, 0),
				Size = UDim2.fromOffset(16, 16),
				BackgroundTransparency = 1,
				Font = theme.font_bold,
				Text = "+",
				TextSize = 14,
				TextColor3 = theme.text_faint,
				AutoButtonColor = false,
			})

			options_frame = new("Frame", {
				Parent = row,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Visible = false,
				LayoutOrder = 2,
			}, {
				util.list(8),
				util.padding(2, 12, 14, 14),
			})

			for _, option in ipairs(mod.option_order) do
				local builder = controls[option.kind]
				if builder then
					builder(options_frame, option, bin)
				end
			end

			bin:add(chevron.MouseButton1Click:Connect(function()
				expanded = not expanded
				options_frame.Visible = expanded
				chevron.Text = expanded and "-" or "+"
			end))
		end

		local pill, render_pill = make_pill(row_header, 34, 18, UDim2.new(1, -14, 0.5, 0))
		render_pill(mod.enabled, true)

		local function render_state(enabled)
			render_pill(enabled)
			tween(name_label, {TextColor3 = enabled and theme.text or theme.text_dim}, 0.14)
			tween(row, {BackgroundColor3 = enabled and theme.surface_light or theme.surface}, 0.14)
		end

		render_state(mod.enabled)

		bin:add(row_header.MouseButton1Click:Connect(function()
			mod:toggle_state()
		end))

		bin:add(row_header.MouseButton2Click:Connect(function()
			start_capture(mod, key_label)
		end))

		bin:add(row_header.MouseEnter:Connect(function()
			if not mod.enabled then
				tween(row, {BackgroundColor3 = theme.surface_hover}, 0.12)
			end
		end))

		bin:add(row_header.MouseLeave:Connect(function()
			if not mod.enabled then
				tween(row, {BackgroundColor3 = theme.surface}, 0.12)
			end
		end))

		bin:add(manager.toggled:connect(function(changed, enabled)
			if changed == mod then
				render_state(enabled)
			end
		end))

		-- keeps the bind label honest after a config load or a clear
		bin:add(manager.changed:connect(function()
			if not capturing then
				key_label.Text = mod.key and util.key_name(mod.key) or ""
			end
		end))

		return row
	end

	for _, category in ipairs(manager.category_order) do
		local button = new("TextButton", {
			Parent = rail,
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = theme.surface,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = theme.font_medium,
			Text = category.name,
			TextSize = 13,
			TextColor3 = theme.text_dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = false,
			LayoutOrder = category.index,
		}, {
			util.corner(7),
			util.padding(0, 0, 16, 0),
		})

		local indicator = new("Frame", {
			Name = "indicator",
			Parent = button,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -10, 0.5, 0),
			Size = UDim2.fromOffset(3, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {util.corner(2)})
		theme.tint(indicator, "BackgroundColor3")

		buttons[category.name] = button

		local page = new("ScrollingFrame", {
			Parent = content,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = theme.outline,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, {
			util.list(6),
			util.padding(12, 14, 14, 14),
		})

		self.pages[category.name] = page

		for _, mod in ipairs(category.modules) do
			-- hidden only keeps a module out of the hud list, it still gets a row
			build_module(page, mod)
		end

		bin:add(button.MouseButton1Click:Connect(function()
			select(category.name)
		end))
	end

	if manager.category_order[1] then
		select(manager.category_order[1].name)
	end

	function self:set_visible(visible)
		self.visible = visible and true or false
		if self.visible then
			window.Visible = true
			window.Size = UDim2.fromOffset(window_width * 0.96, window_height * 0.96)
			tween(window, {Size = UDim2.fromOffset(window_width, window_height)}, 0.18, Enum.EasingStyle.Back)
		else
			tween(window, {Size = UDim2.fromOffset(window_width * 0.96, window_height * 0.96)}, 0.12)
			task.delay(0.12, function()
				if not self.visible and window.Parent then
					window.Visible = false
				end
			end)
		end
	end

	bin:add(close.MouseButton1Click:Connect(function()
		self:set_visible(false)
		self.closed:fire()
	end))

	bin:add(close.MouseEnter:Connect(function()
		tween(close, {BackgroundColor3 = theme.bad, TextColor3 = theme.text}, 0.12)
	end))
	bin:add(close.MouseLeave:Connect(function()
		tween(close, {BackgroundColor3 = theme.surface, TextColor3 = theme.text_dim}, 0.12)
	end))

	bin:add(function()
		mark:destroy()
	end)

	return self
end

return library
