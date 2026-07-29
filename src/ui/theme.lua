-- colors and fonts, accent is live swappable

local theme = {
	background = Color3.fromRGB(13, 13, 17),
	surface = Color3.fromRGB(20, 20, 26),
	surface_light = Color3.fromRGB(29, 29, 38),
	surface_hover = Color3.fromRGB(36, 36, 46),
	outline = Color3.fromRGB(41, 41, 54),
	text = Color3.fromRGB(238, 238, 246),
	text_dim = Color3.fromRGB(132, 132, 150),
	text_faint = Color3.fromRGB(88, 88, 104),
	good = Color3.fromRGB(126, 217, 141),
	bad = Color3.fromRGB(228, 106, 118),
	accent = Color3.fromRGB(198, 134, 255),
	accent_dark = Color3.fromRGB(128, 86, 168),
	font = Enum.Font.Gotham,
	font_medium = Enum.Font.GothamMedium,
	font_bold = Enum.Font.GothamBold,
}

local targets = {}
local hooks = {}

-- tint an instance property with the accent so it follows theme changes
function theme.tint(inst, prop, shade)
	shade = shade or "accent"
	table.insert(targets, {inst = inst, prop = prop, shade = shade})
	inst[prop] = theme[shade]
	return inst
end

function theme.on_accent(fn)
	table.insert(hooks, fn)
	return fn
end

function theme.set_accent(color)
	theme.accent = color
	theme.accent_dark = color:Lerp(Color3.new(0, 0, 0), 0.36)

	for index = #targets, 1, -1 do
		local target = targets[index]
		local ok = pcall(function()
			target.inst[target.prop] = theme[target.shade]
		end)
		if not ok then
			table.remove(targets, index)
		end
	end

	for _, hook in ipairs(hooks) do
		pcall(hook, color)
	end
end

function theme.reset_bindings()
	targets = {}
	hooks = {}
end

return theme
