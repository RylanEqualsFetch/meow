-- meow loader
-- resolves the newest commit on the branch and runs the client from it
-- raw urls pinned to a commit sha are immutable so there is no cdn cache to fight

local repo = "RylanEqualsFetch/meow"
local branch = "main"

local http_service = game:GetService("HttpService")

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

-- newest commit on the branch, nil when the api is unreachable or rate limited
-- the plain api url gets served from cache and can hand back the previous commit
-- for a while after a push, so every call carries a nonce
local function resolve_commit()
	local nonce = tostring(math.floor(tick() * 1000)) .. tostring(math.random(1, 1e6))
	local body = http_get("https://api.github.com/repos/" .. repo .. "/commits/" .. branch .. "?nocache=" .. nonce)
	if not body then
		return nil
	end
	local ok, data = pcall(function()
		return http_service:JSONDecode(body)
	end)
	if ok and type(data) == "table" and type(data.sha) == "string" then
		return data.sha
	end
	-- the decode can fail on odd payloads, pull the sha straight out of the text
	return body:match('"sha"%s*:%s*"(%x+)"')
end

local commit = resolve_commit()
local base = "https://raw.githubusercontent.com/" .. repo .. "/" .. (commit or branch) .. "/"

local can_write = isfile and readfile and writefile and isfolder and makefolder
local cache_dir

if can_write and commit then
	if not isfolder("meow") then
		makefolder("meow")
	end
	if not isfolder("meow/cache") then
		makefolder("meow/cache")
	end
	cache_dir = "meow/cache/" .. commit:sub(1, 12)
	if not isfolder(cache_dir) then
		makefolder(cache_dir)
	end
	-- drop caches from older commits so the disk does not grow forever
	if listfiles and delfolder then
		local ok, entries = pcall(listfiles, "meow/cache")
		if ok then
			for _, entry in ipairs(entries) do
				if not entry:find(commit:sub(1, 12), 1, true) then
					pcall(delfolder, entry)
				end
			end
		end
	end
end

local function cache_key(path)
	return cache_dir .. "/" .. path:gsub("[/\\]", "_")
end

local function fetch(path)
	local key
	if cache_dir then
		key = cache_key(path)
		if isfile(key) then
			local ok, data = pcall(readfile, key)
			if ok and type(data) == "string" and #data > 0 then
				return data
			end
		end
	end

	local url = base .. path
	if not commit then
		-- no pinned sha means the branch url can be served stale, bust it
		url = url .. "?nocache=" .. tostring(tick())
	end

	local source = http_get(url)
	if not source then
		error("meow: failed to fetch " .. path, 0)
	end
	if key then
		pcall(writefile, key, source)
	end
	return source
end

local genv = (getgenv and getgenv()) or _G

-- tear down a previous session before replacing it
local previous = rawget(genv, "meow")
if type(previous) == "table" and type(previous.unload) == "function" then
	pcall(previous.unload)
end

local env = {
	repo = repo,
	branch = branch,
	commit = commit,
	version = commit and commit:sub(1, 7) or "head",
	base = base,
	cache_dir = cache_dir,
	loaded = {},
	fetch = fetch,
}

function env.load(path, ...)
	local cached = env.loaded[path]
	if cached ~= nil then
		return cached
	end

	local source = fetch(path)
	local ok, chunk, err = pcall(loadstring, source, "=meow/" .. path)
	if not ok or not chunk then
		-- some executors reject the chunk name argument
		chunk, err = loadstring(source)
	end
	if not chunk then
		error("meow: compile error in " .. path .. ": " .. tostring(err), 0)
	end

	local result = chunk(...)
	if result == nil then
		result = true
	end
	env.loaded[path] = result
	return result
end

function env.reload(path, ...)
	env.loaded[path] = nil
	if cache_dir and isfile(cache_key(path)) and delfile then
		pcall(delfile, cache_key(path))
	end
	return env.load(path, ...)
end

genv.meow = env

local ok, err = pcall(env.load, "src/init.lua")
if not ok then
	genv.meow = nil
	error("meow: " .. tostring(err), 0)
end

return env
