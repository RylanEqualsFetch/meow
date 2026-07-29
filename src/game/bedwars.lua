-- bedwars adapter
-- resolves the games own knit controllers and entity helpers at runtime, so
-- combat goes through the same calls the real client makes instead of guessed
-- remote arguments. every lookup is lazy, cached and wrapped

local util = meow.load("src/core/util.lua")

local replicated = util.services.ReplicatedStorage
local collection = util.services.CollectionService
local players = util.services.Players

local bedwars = {}

local cache = {}

-- a miss is only remembered briefly, the client can be injected before the game
-- has required its own modules and a permanent negative would never recover
local misses = {}
local retry_after = 2

local function loaded_modules()
	local fn = getloadedmodules
	if type(fn) ~= "function" then
		return nil
	end
	local ok, list = pcall(fn)
	if ok and type(list) == "table" then
		return list
	end
	return nil
end

-- finds a module by instance name, preferring one the game already required
local function find_module(name)
	local modules = loaded_modules()
	if modules then
		for _, module in ipairs(modules) do
			if module.Name == name and module:IsDescendantOf(game) then
				return module
			end
		end
	end

	local found
	local ok = pcall(function()
		for _, inst in ipairs(replicated:GetDescendants()) do
			if inst:IsA("ModuleScript") and inst.Name == name then
				found = inst
				break
			end
		end
	end)

	if ok then
		return found
	end
	return nil
end

local function require_module(name)
	local hit = cache[name]
	if hit then
		return hit
	end

	local missed_at = misses[name]
	if missed_at and os.clock() - missed_at < retry_after then
		return nil
	end

	local module = find_module(name)
	if not module then
		misses[name] = os.clock()
		return nil
	end

	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" then
		misses[name] = os.clock()
		return nil
	end

	cache[name] = result
	misses[name] = nil
	return result
end

function bedwars.forget()
	cache = {}
	misses = {}
end

function bedwars.knit()
	local knit = require_module("KnitClient")
	if knit and type(knit.Controllers) == "table" then
		return knit
	end
	return nil
end

function bedwars.controller(name)
	local knit = bedwars.knit()
	if not knit then
		return nil
	end
	local ok, controller = pcall(function()
		return knit.Controllers[name]
	end)
	if ok and type(controller) == "table" then
		return controller
	end
	return nil
end

function bedwars.sword()
	return bedwars.controller("SwordController")
end

function bedwars.entity_util()
	local module = require_module("entity-util")
	if not module then
		return nil
	end
	-- the util is exported either directly or under default
	if type(module.getLocalPlayerEntity) == "function" then
		return module
	end
	if type(module.default) == "table" and type(module.default.getLocalPlayerEntity) == "function" then
		return module.default
	end
	return nil
end

function bedwars.world_util()
	local module = require_module("game-world-util")
	if not module then
		return nil
	end
	if type(module.getEntitiesWithinBox) == "function" then
		return module
	end
	if type(module.default) == "table" and type(module.default.getEntitiesWithinBox) == "function" then
		return module.default
	end
	return nil
end

-- true once the knit client and the sword controller are both reachable
function bedwars.ready()
	return bedwars.sword() ~= nil
end

function bedwars.local_entity()
	local entity_util = bedwars.entity_util()
	if not entity_util then
		return nil
	end
	local ok, entity = pcall(function()
		return entity_util:getLocalPlayerEntity()
	end)
	if ok then
		return entity
	end
	return nil
end

-- the games own target picker, it already honours teams, line of sight and
-- match state. range is ours, which is what makes reach work
function bedwars.target_in_range(range, charge)
	local sword = bedwars.sword()
	if not sword then
		return nil
	end
	local ok, target = pcall(function()
		return sword:getTargetInRegion(range, charge)
	end)
	if ok then
		return target
	end
	return nil
end

function bedwars.attack(entity, charge)
	local sword = bedwars.sword()
	if not sword or not entity then
		return false
	end
	local ok, result = pcall(function()
		return sword:attackEntity(entity, nil, charge)
	end)
	return ok and result ~= false
end

function bedwars.hand_item()
	local sword = bedwars.sword()
	if not sword then
		return nil
	end
	local ok, item = pcall(function()
		return sword:getHandItem()
	end)
	if ok then
		return item
	end
	return nil
end

function bedwars.can_attack(entity)
	local mine = bedwars.local_entity()
	if not mine or not entity then
		return false
	end
	local ok, result = pcall(function()
		return mine:canAttack(entity)
	end)
	return ok and result == true
end

function bedwars.entity_instance(entity)
	if not entity then
		return nil
	end
	local ok, instance = pcall(function()
		return entity:getInstance()
	end)
	if ok then
		return instance
	end
	return nil
end

-- every attackable entity inside a box centred on the player
function bedwars.entities_in_range(range)
	local world = bedwars.world_util()
	local character = util.character()
	local root = util.root()
	if not world or not character or not root then
		return {}
	end

	local size = Vector3.new(range * 2, math.max(range * 2, 8), range * 2)
	local ok, list = pcall(function()
		return world.getEntitiesWithinBox(CFrame.new(root.Position), size)
	end)
	if not ok or type(list) ~= "table" then
		return {}
	end

	local out = {}
	for _, entity in pairs(list) do
		local instance = bedwars.entity_instance(entity)
		if instance and instance ~= character and instance.PrimaryPart then
			local distance = (instance.PrimaryPart.Position - root.Position).Magnitude
			if distance <= range and bedwars.can_attack(entity) then
				table.insert(out, {entity = entity, instance = instance, distance = distance})
			end
		end
	end

	table.sort(out, function(a, b)
		return a.distance < b.distance
	end)

	return out
end

-- beds carry a collection service tag in this game, which beats name matching
function bedwars.beds()
	local ok, tagged = pcall(function()
		return collection:GetTagged("bed")
	end)
	if ok and type(tagged) == "table" then
		return tagged
	end
	return {}
end

function bedwars.team_of(player)
	player = player or players.LocalPlayer
	if not player then
		return nil
	end
	if player.Team then
		return player.Team.Name
	end
	return player:GetAttribute("Team") or player:GetAttribute("team")
end

return bedwars
