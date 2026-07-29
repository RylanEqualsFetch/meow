-- colors and fonts, accent and font family are both live swappable

local theme = {
	background = Color3.fromRGB(13, 13, 17),
	surface = Color3.fromRGB(21, 21, 27),
	surface_light = Color3.fromRGB(29, 29, 38),
	surface_hover = Color3.fromRGB(37, 37, 47),
	outline = Color3.fromRGB(41, 41, 54),
	text = Color3.fromRGB(240, 240, 247),
	text_dim = Color3.fromRGB(138, 138, 156),
	text_faint = Color3.fromRGB(92, 92, 110),
	good = Color3.fromRGB(126, 217, 141),
	bad = Color3.fromRGB(228, 106, 118),
	accent = Color3.fromRGB(198, 134, 255),
	accent_dark = Color3.fromRGB(128, 86, 168),
}

-- families that ship with the client, no asset downloads
theme.families = {
	["builder sans"] = "rbxasset://fonts/families/BuilderSans.json",
	["montserrat"] = "rbxasset://fonts/families/Montserrat.json",
	["nunito"] = "rbxasset://fonts/families/Nunito.json",
	["roboto"] = "rbxasset://fonts/families/Roboto.json",
	["gotham"] = "rbxasset://fonts/families/GothamSSm.json",
	["ubuntu"] = "rbxasset://fonts/families/Ubuntu.json",
	["source sans"] = "rbxasset://fonts/families/SourceSansPro.json",
}

theme.family_order = {
	"builder sans",
	"montserrat",
	"nunito",
	"roboto",
	"gotham",
	"ubuntu",
	"source sans",
}

-- montserrat by default, the dropdown in settings swaps it live
theme.family = "montserrat"

local weights = {
	regular = Enum.FontWeight.Regular,
	medium = Enum.FontWeight.Medium,
	semibold = Enum.FontWeight.SemiBold,
	bold = Enum.FontWeight.Bold,
}

local accent_targets = {}
local font_targets = {}
local accent_hooks = {}
local font_hooks = {}

function theme.font(weight)
	local family = theme.families[theme.family] or theme.families["builder sans"]
	return Font.new(family, weights[weight or "regular"] or Enum.FontWeight.Regular)
end

-- sets the face now and keeps it in sync when the family changes
function theme.apply_font(inst, weight)
	weight = weight or "regular"
	table.insert(font_targets, {inst = inst, weight = weight})
	inst.FontFace = theme.font(weight)
	return inst
end

function theme.on_font(fn)
	table.insert(font_hooks, fn)
	return fn
end

function theme.set_family(name)
	if not theme.families[name] then
		return
	end
	theme.family = name
	for index = #font_targets, 1, -1 do
		local target = font_targets[index]
		local ok = pcall(function()
			target.inst.FontFace = theme.font(target.weight)
		end)
		if not ok then
			table.remove(font_targets, index)
		end
	end

	for index = #font_hooks, 1, -1 do
		local ok = pcall(font_hooks[index])
		if not ok then
			table.remove(font_hooks, index)
		end
	end
end

-- tint an instance property with the accent so it follows theme changes
function theme.tint(inst, prop, shade)
	shade = shade or "accent"
	table.insert(accent_targets, {inst = inst, prop = prop, shade = shade})
	inst[prop] = theme[shade]
	return inst
end

function theme.on_accent(fn)
	table.insert(accent_hooks, fn)
	return fn
end

function theme.set_accent(color)
	theme.accent = color
	theme.accent_dark = color:Lerp(Color3.new(0, 0, 0), 0.36)

	for index = #accent_targets, 1, -1 do
		local target = accent_targets[index]
		local ok = pcall(function()
			target.inst[target.prop] = theme[target.shade]
		end)
		if not ok then
			table.remove(accent_targets, index)
		end
	end

	for _, hook in ipairs(accent_hooks) do
		pcall(hook, color)
	end
end

function theme.reset_bindings()
	accent_targets = {}
	font_targets = {}
	accent_hooks = {}
	font_hooks = {}
end

return theme
