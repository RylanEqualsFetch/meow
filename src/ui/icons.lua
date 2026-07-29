-- icon loader
-- images are downloaded from the repo once, written next to the config and
-- handed to roblox through getcustomasset, same trick the font installer uses.
-- everything is async, a missing or slow icon never holds the ui up

local util = meow.load("src/core/util.lua")

local icons = {}

local folder = "meow/icons"
local min_bytes = 200

icons.resolved = {}
icons.failed = {}

-- a name here can also be a plain roblox asset id, useful for uploaded decals
icons.overrides = {}

local function custom_asset(path)
	local fn = getcustomasset
		or getsynasset
		or (syn and syn.getcustomasset)
		or (fluxus and fluxus.getcustomasset)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, path)
	if ok and type(result) == "string" and #result > 0 then
		return result
	end
	return nil
end

local function http_get(url)
	local req = (syn and syn.request) or (http and http.request) or http_request or request
	if req then
		local ok, res = pcall(req, {Url = url, Method = "GET"})
		if ok and type(res) == "table" and res.Body and #res.Body > 0 then
			local code = res.StatusCode or res.Status or 200
			if code >= 200 and code < 300 then
				return res.Body
			end
		end
	end
	local ok, body = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(body) == "string" and #body > 0 then
		return body
	end
	return nil
end

function icons.available()
	return type(writefile) == "function"
		and type(isfile) == "function"
		and type(isfolder) == "function"
		and type(makefolder) == "function"
		and custom_asset ~= nil
end

-- resolves synchronously, returns a content id or nil. callers should use
-- icons.apply so a slow download never blocks the caller
function icons.fetch(name, extension)
	extension = extension or "png"

	local override = icons.overrides[name]
	if type(override) == "string" and override ~= "" then
		return override
	end
	if type(override) == "number" then
		return "rbxassetid://" .. tostring(override)
	end

	if icons.resolved[name] then
		return icons.resolved[name]
	end
	if icons.failed[name] then
		return nil
	end

	if type(writefile) ~= "function" or type(isfile) ~= "function" then
		icons.failed[name] = true
		return nil
	end

	if not isfolder("meow") then
		makefolder("meow")
	end
	if not isfolder(folder) then
		makefolder(folder)
	end

	local path = folder .. "/" .. name .. "." .. extension

	local present = isfile(path)
	if present then
		local ok, data = pcall(readfile, path)
		present = ok and type(data) == "string" and #data >= min_bytes
	end

	if not present then
		local body = http_get(meow.base .. "assets/icons/" .. name .. "." .. extension)
		if not body or #body < min_bytes then
			icons.failed[name] = true
			return nil
		end
		if not pcall(writefile, path, body) then
			icons.failed[name] = true
			return nil
		end
	end

	local asset = custom_asset(path)
	if not asset then
		icons.failed[name] = true
		return nil
	end

	icons.resolved[name] = asset
	return asset
end

-- points an image label at an icon once it is ready, off the calling thread
function icons.apply(label, name, extension)
	if not label or not name then
		return
	end

	local immediate = icons.resolved[name] or icons.overrides[name]
	if immediate then
		label.Image = type(immediate) == "number" and ("rbxassetid://" .. immediate) or immediate
		label.Visible = true
		return
	end

	task.spawn(function()
		local asset = icons.fetch(name, extension)
		if asset and label and label.Parent then
			label.Image = asset
			label.Visible = true
			util.tween(label, {ImageTransparency = 0}, 0.2)
		end
	end)
end

return icons
