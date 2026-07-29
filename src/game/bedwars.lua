-- bedwars adapter
-- the module paths and the knit lookup are taken straight from the vape v4
-- bedwars base, with a name search behind them so an update that moves a module
-- still resolves. every lookup is lazy, cached and wrapped

local util = meow.load("src/core/util.lua")

local replicated = util.services.ReplicatedStorage
local collection = util.services.CollectionService
local players = util.services.Players

local bedwars = {}

bedwars.block_studs = 3

local cache = {}
local misses = {}
local retry_after = 2

local entity_cache = {value = nil, stamp = 0}
local search_module_raw

local function fresh(name)
	local hit = cache[name]
	if hit ~= nil then
		return hit
	end
	return nil
end

local function ready_to_retry(name)
	local missed_at = misses[name]
	return not missed_at or os.clock() - missed_at >= retry_after
end

local function remember(name, value)
	if value then
		cache[name] = value
		misses[name] = nil
	else
		misses[name] = os.clock()
	end
	return value
end

function bedwars.forget()
	cache = {}
	misses = {}
	bedwars.placer_instance = nil
	entity_cache = {value = nil, stamp = 0}
end

-- walks a path off an instance, every step guarded
local function dig(root, ...)
	local node = root
	for _, step in ipairs({...}) do
		if not node then
			return nil
		end
		local ok, child = pcall(function()
			return node[step]
		end)
		if not ok then
			return nil
		end
		node = child
	end
	return node
end

local function require_instance(inst)
	if not inst then
		return nil
	end
	local ok, result = pcall(require, inst)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

-- the raw search walks every loaded module or the whole of replicated storage,
-- so it is only ever allowed to run once per name until the retry window passes
local function search_module_cached(name)
	local key = "search:" .. name
	local hit = fresh(key)
	if hit then
		return hit
	end
	if not ready_to_retry(key) then
		return nil
	end
	return remember(key, search_module_raw(name))
end

search_module_raw = function(name)
	local fn = getloadedmodules
	if type(fn) == "function" then
		local ok, list = pcall(fn)
		if ok and type(list) == "table" then
			for _, module in ipairs(list) do
				if module.Name == name then
					local value = require_instance(module)
					if value then
						return value
					end
				end
			end
		end
	end

	local found
	pcall(function()
		for _, inst in ipairs(replicated:GetDescendants()) do
			if inst:IsA("ModuleScript") and inst.Name == name then
				found = inst
				break
			end
		end
	end)
	return require_instance(found)
end

-- knit hands its controllers out through an upvalue on setup, same as vape does
function bedwars.knit()
	local hit = fresh("knit")
	if hit then
		return hit
	end
	if not ready_to_retry("knit") then
		return nil
	end

	local player = players.LocalPlayer
	local module = dig(player, "PlayerScripts", "TS", "knit")

	if module then
		local ok, exported = pcall(require, module)
		if ok and type(exported) == "table" then
			if type(exported.setup) == "function" then
				local got, knit = pcall(debug.getupvalue, exported.setup, 9)
				if got and type(knit) == "table" and type(knit.Controllers) == "table" then
					return remember("knit", knit)
				end
			end
			if type(exported.Controllers) == "table" then
				return remember("knit", exported)
			end
		end
	end

	local fallback = search_module_cached("KnitClient")
	if type(fallback) == "table" and type(fallback.Controllers) == "table" then
		return remember("knit", fallback)
	end

	return remember("knit", nil)
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

function bedwars.ready()
	return bedwars.sword() ~= nil
end

local function resolve_table(key, path, field, search_name)
	local hit = fresh(key)
	if hit then
		return hit
	end
	if not ready_to_retry(key) then
		return nil
	end

	local exported = require_instance(dig(replicated, table.unpack(path)))
	local value = exported and exported[field]

	if type(value) ~= "table" and search_name then
		local searched = search_module_cached(search_name)
		value = searched and searched[field]
	end

	return remember(key, type(value) == "table" and value or nil)
end

-- the shared table the client reads its reach limits from
function bedwars.combat_constant()
	return resolve_table(
		"combat_constant",
		{"TS", "combat", "combat-constant"},
		"CombatConstant",
		"combat-constant"
	)
end

-- block placement rate lives here, BLOCK_PLACE_CPS is the cap
function bedwars.cps_constants()
	return resolve_table(
		"cps_constants",
		{"TS", "shared-constants"},
		"CpsConstants",
		"shared-constants"
	)
end

function bedwars.block_controller()
	return resolve_table(
		"block_controller",
		{"rbxts_include", "node_modules", "@easy-games", "block-engine", "out"},
		"BlockEngine"
	)
end

function bedwars.block_placer_class()
	return resolve_table(
		"block_placer",
		{"rbxts_include", "node_modules", "@easy-games", "block-engine", "out", "client", "placement", "block-placer"},
		"BlockPlacer",
		"block-placer"
	)
end

function bedwars.inventory_util()
	return resolve_table(
		"inventory_util",
		{"TS", "inventory", "inventory-util"},
		"InventoryUtil",
		"inventory-util"
	)
end

function bedwars.block_engine()
	local hit = fresh("block_engine")
	if hit then
		return hit
	end
	if not ready_to_retry("block_engine") then
		return nil
	end

	local player = players.LocalPlayer
	local exported = require_instance(
		dig(player, "PlayerScripts", "TS", "lib", "block-engine", "client-block-engine")
	)
	local value = exported and exported.ClientBlockEngine

	if type(value) ~= "table" then
		local searched = search_module_cached("client-block-engine")
		value = searched and searched.ClientBlockEngine
	end

	return remember("block_engine", type(value) == "table" and value or nil)
end

-- a placer bound to the client block engine, same construction vape uses
function bedwars.placer()
	if bedwars.placer_instance then
		return bedwars.placer_instance
	end

	local class = bedwars.block_placer_class()
	local engine = bedwars.block_engine()
	if not class or not engine then
		return nil
	end

	local ok, instance = pcall(function()
		return class.new(engine, "wool_white")
	end)
	if not ok or type(instance) ~= "table" then
		return nil
	end

	bedwars.placer_instance = instance
	return instance
end

function bedwars.place_block(position, item)
	local placer = bedwars.placer()
	local controller = bedwars.block_controller()
	if not placer or not controller then
		return false
	end

	local ok = pcall(function()
		if item then
			placer.blockType = item
		end
		placer:placeBlock(controller:getBlockPosition(position))
	end)
	return ok
end

-- the first block stack sitting in the hotbar
function bedwars.hotbar_block()
	local inventory_util = bedwars.inventory_util()
	if not inventory_util then
		return nil
	end

	local ok, inventory = pcall(function()
		return inventory_util.getInventory(players.LocalPlayer)
	end)
	if not ok or type(inventory) ~= "table" then
		return nil
	end

	local hotbar = inventory.hotbar or inventory.items
	if type(hotbar) ~= "table" then
		return nil
	end

	for _, item in pairs(hotbar) do
		if type(item) == "table" and type(item.itemType) == "string" then
			local name = item.itemType
			if name:find("wool", 1, true)
				or name:find("plank", 1, true)
				or name:find("brick", 1, true)
				or name:find("block", 1, true) then
				return name
			end
		end
	end

	return nil
end

function bedwars.entity_util()
	local hit = fresh("entity_util")
	if hit then
		return hit
	end
	if not ready_to_retry("entity_util") then
		return nil
	end

	local module = search_module_cached("entity-util")
	local value = module
	if module and type(module.getLocalPlayerEntity) ~= "function" and type(module.default) == "table" then
		value = module.default
	end
	if not value or type(value.getLocalPlayerEntity) ~= "function" then
		return remember("entity_util", nil)
	end
	return remember("entity_util", value)
end

-- can_attack asks for this once per entity, so it is held for a frame
function bedwars.local_entity()
	local now = os.clock()
	if entity_cache.value and now - entity_cache.stamp < 0.05 then
		return entity_cache.value
	end

	local entity_util = bedwars.entity_util()
	if not entity_util then
		return nil
	end

	local ok, entity = pcall(function()
		return entity_util:getLocalPlayerEntity()
	end)
	if not ok then
		return nil
	end

	entity_cache.value = entity
	entity_cache.stamp = now
	return entity
end

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

function bedwars.world_util()
	local hit = fresh("world_util")
	if hit then
		return hit
	end
	if not ready_to_retry("world_util") then
		return nil
	end

	local module = search_module_cached("game-world-util")
	if not module then
		return remember("world_util", nil)
	end
	if type(module.getEntitiesWithinBox) == "function" then
		return remember("world_util", module)
	end
	if type(module.default) == "table" and type(module.default.getEntitiesWithinBox) == "function" then
		return remember("world_util", module.default)
	end
	return remember("world_util", nil)
end

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

-- the raw item meta table, swords carry their own attackRange in here which is
-- what the client actually validates against, the shared constant is only the
-- fallback for items that do not define one
function bedwars.item_meta()
	local hit = fresh("item_meta")
	if hit then
		return hit
	end
	if not ready_to_retry("item_meta") then
		return nil
	end

	local module = dig(replicated, "TS", "item", "item-meta")
	local exported = require_instance(module)
	local getter = exported and exported.getItemMeta

	if type(getter) == "function" then
		local ok, value = pcall(debug.getupvalue, getter, 1)
		if ok and type(value) == "table" then
			return remember("item_meta", value)
		end
	end

	return remember("item_meta", nil)
end

function bedwars.knockback_util()
	return resolve_table(
		"knockback_util",
		{"TS", "damage", "knockback-util"},
		"KnockbackUtil",
		"knockback-util"
	)
end

function bedwars.projectile_controller()
	return bedwars.controller("ProjectileController")
end

-- the bow offsets vape reads off an upvalue of the beam function
function bedwars.bow_constants()
	local hit = fresh("bow_constants")
	if hit then
		return hit
	end
	if not ready_to_retry("bow_constants") then
		return nil
	end

	local controller = bedwars.projectile_controller()
	local beam = controller and controller.enableBeam
	if type(beam) ~= "function" then
		return remember("bow_constants", nil)
	end

	local ok, value = pcall(debug.getupvalue, beam, 8)
	if ok and type(value) == "table" then
		return remember("bow_constants", value)
	end
	return remember("bow_constants", nil)
end

-- the distance the client will currently accept a swing at
function bedwars.attack_range()
	local constants = bedwars.combat_constant()
	if constants and type(constants.RAYCAST_SWORD_CHARACTER_DISTANCE) == "number" then
		return constants.RAYCAST_SWORD_CHARACTER_DISTANCE
	end
	return 4.8 * bedwars.block_studs
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
