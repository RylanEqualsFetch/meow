-- installs font families roblox does not ship
-- the ttf faces are downloaded once, written next to the config, and referenced
-- from a generated family manifest through getcustomasset

local util = meow.load("src/core/util.lua")

local http_service = util.services.HttpService

local fonts = {}

local folder = "meow/fonts"
local min_face_bytes = 20000

fonts.installed = {}

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

function fonts.available()
	if type(writefile) ~= "function" or type(isfile) ~= "function" then
		return false, "executor cannot write files"
	end
	if type(makefolder) ~= "function" or type(isfolder) ~= "function" then
		return false, "executor cannot make folders"
	end
	local probe = getcustomasset
		or getsynasset
		or (syn and syn.getcustomasset)
		or (fluxus and fluxus.getcustomasset)
	if type(probe) ~= "function" then
		return false, "executor has no getcustomasset"
	end
	return true
end

-- def: {key, name, faces = {{file, name, weight}}}
-- returns a content id usable with Font.new, or nil plus a reason
function fonts.install(def, on_progress)
	if fonts.installed[def.key] then
		return fonts.installed[def.key]
	end

	local ok, reason = fonts.available()
	if not ok then
		return nil, reason
	end

	if not isfolder("meow") then
		makefolder("meow")
	end
	if not isfolder(folder) then
		makefolder(folder)
	end

	local entries = {}
	local total = #def.faces

	for index, face in ipairs(def.faces) do
		local path = folder .. "/" .. face.file

		local present = isfile(path)
		if present then
			local read_ok, data = pcall(readfile, path)
			-- a truncated or half written file is worse than no file
			present = read_ok and type(data) == "string" and #data >= min_face_bytes
		end

		if not present then
			if on_progress then
				on_progress(index / total, "downloading " .. face.name:lower())
			end
			local body = http_get(meow.base .. "assets/fonts/" .. face.file)
			if not body or #body < min_face_bytes then
				return nil, "download failed for " .. face.file
			end
			if not pcall(writefile, path, body) then
				return nil, "write failed for " .. face.file
			end
		end

		local asset = custom_asset(path)
		if not asset then
			return nil, "getcustomasset rejected " .. face.file
		end

		table.insert(entries, {
			name = face.name,
			weight = face.weight,
			style = "normal",
			assetId = asset,
		})
	end

	local manifest_path = folder .. "/" .. def.key .. ".json"
	local encoded_ok, encoded = pcall(function()
		return http_service:JSONEncode({name = def.name, faces = entries})
	end)
	if not encoded_ok then
		return nil, "manifest encode failed"
	end
	if not pcall(writefile, manifest_path, encoded) then
		return nil, "manifest write failed"
	end

	local family = custom_asset(manifest_path)
	if not family then
		return nil, "getcustomasset rejected the manifest"
	end

	fonts.installed[def.key] = family
	return family
end

fonts.inter = {
	key = "inter",
	name = "Inter",
	faces = {
		{file = "Inter-Regular.ttf", name = "Regular", weight = 400},
		{file = "Inter-Medium.ttf", name = "Medium", weight = 500},
		{file = "Inter-SemiBold.ttf", name = "SemiBold", weight = 600},
		{file = "Inter-Bold.ttf", name = "Bold", weight = 700},
	},
}

return fonts
