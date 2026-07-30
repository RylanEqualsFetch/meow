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
	local roots = {replicated}
	local player = players.LocalPlayer
	local scripts = player and player:FindFirstChild("PlayerScripts")
	if scripts then
		table.insert(roots, scripts)
	end

	for _, place in ipairs(roots) do
		pcall(function()
			for _, inst in ipairs(place:GetDescendants()) do
				if inst:IsA("ModuleScript") and inst.Name == name then
					found = inst
					break
				end
			end
		end)
		if found then
			break
		end
	end

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

	-- cat requires the knit package directly and that is the correct route on this
	-- build. the upvalue dig below came from vape, whose bedwars code targets the
	-- old game, they have since reworked into blockwars
	local direct = require_instance(dig(
		replicated,
		"rbxts_include",
		"node_modules",
		"@easy-games",
		"knit",
		"src"
	))
	if direct and type(direct.KnitClient) == "table" and type(direct.KnitClient.Controllers) == "table" then
		return remember("knit", direct.KnitClient)
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

	-- cat reads the table straight off the module as .items. the upvalue dig below
	-- is vapes route and it targets the old game, so it is only a fallback now
	if exported and type(exported.items) == "table" then
		return remember("item_meta", exported.items)
	end

	local getter = exported and exported.getItemMeta

	if type(getter) ~= "function" then
		-- the path moves between updates, fall back to the module by name
		local searched = search_module_cached("item-meta")
		getter = searched and searched.getItemMeta
	end

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

function bedwars.balloon_controller()
	return bedwars.controller("BalloonController")
end

-- flight is legal to the server while you have an inflated balloon, which is the
-- whole basis of cats fly. this keeps one inflated and stops it deflating
function bedwars.inflated_balloons()
	local character = util.character()
	if not character then
		return 0
	end
	local ok, value = pcall(function()
		return character:GetAttribute("InflatedBalloons")
	end)
	if ok and type(value) == "number" then
		return value
	end
	return 0
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

-- the net client every gameplay remote goes through
function bedwars.remotes_client()
	local hit = fresh("remotes_client")
	if hit then
		return hit
	end
	if not ready_to_retry("remotes_client") then
		return nil
	end

	local exported = require_instance(dig(replicated, "TS", "remotes"))
	local value = exported and exported.default and exported.default.Client

	-- the path moves between updates, fall back to the module by name
	if type(value) ~= "table" then
		local searched = search_module_cached("remotes")
		value = searched and searched.default and searched.default.Client
	end

	return remember("remotes_client", type(value) == "table" and value or nil)
end

-- the block engine has its own remote table, damage block lives there
function bedwars.block_remotes()
	local hit = fresh("block_remotes")
	if hit then
		return hit
	end
	if not ready_to_retry("block_remotes") then
		return nil
	end

	local exported = require_instance(dig(
		replicated,
		"rbxts_include",
		"node_modules",
		"@easy-games",
		"block-engine",
		"out",
		"shared",
		"remotes"
	))
	local remotes = exported and exported.BlockEngineRemotes
	local value = remotes and remotes.Client
	return remember("block_remotes", type(value) == "table" and value or nil)
end

function bedwars.sync_events()
	local hit = fresh("sync_events")
	if hit then
		return hit
	end
	if not ready_to_retry("sync_events") then
		return nil
	end

	local module = search_module_cached("client-sync-events")
	if type(module) ~= "table" then
		return remember("sync_events", nil)
	end
	if type(module.BeforeSwordSwing) == "table" then
		return remember("sync_events", module)
	end
	if type(module.default) == "table" and type(module.default.BeforeSwordSwing) == "table" then
		return remember("sync_events", module.default)
	end
	return remember("sync_events", nil)
end

-- swaps the held item without touching the hotbar ui, same call vape makes
function bedwars.equip(tool)
	local client = bedwars.remotes_client()
	local character = util.character()
	if not client or not tool or not character then
		return false
	end

	local slot = character:FindFirstChild("HandInvItem")
	if slot and slot.Value == tool then
		return true
	end

	local ok = pcall(function()
		client:Get("EquipItem"):CallServerAsync({hand = tool})
	end)

	if ok and slot then
		pcall(function()
			slot.Value = tool
		end)
	end
	return ok
end

-- every tool the character is carrying, keyed by the break type its meta says
function bedwars.tools_by_break_type()
	local character = util.character()
	local meta = bedwars.item_meta()
	local out = {}
	if not character or not meta then
		return out
	end

	local player = players.LocalPlayer
	local containers = {character}
	local backpack = player and player:FindFirstChild("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end

	for _, container in ipairs(containers) do
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				local entry = meta[tool.Name]
				local block = entry and entry.block
				local breaks = entry and entry.breakBlock
				if type(breaks) == "table" and type(breaks.breakType) == "string" then
					out[breaks.breakType] = out[breaks.breakType] or tool
				elseif type(block) == "table" and type(block.breakType) == "string" then
					out[block.breakType] = out[block.breakType] or tool
				end
			end
		end
	end

	return out
end

-- the break type a block wants, read off its own meta entry
function bedwars.break_type_of(block_name)
	local meta = bedwars.item_meta()
	local entry = meta and meta[block_name]
	local block = entry and entry.block
	if type(block) == "table" and type(block.breakType) == "string" then
		return block.breakType
	end
	return nil
end

function bedwars.damage_block(block_position, hit_position)
	local remotes = bedwars.block_remotes()
	if not remotes then
		return false
	end

	local ok = pcall(function()
		remotes:Get("DamageBlock"):CallServerAsync({
			blockRef = {blockPosition = block_position},
			hitPosition = hit_position,
			hitNormal = Vector3.FromNormalId(Enum.NormalId.Top),
		})
	end)
	return ok
end

-- the tool the server currently thinks is in your hand
function bedwars.held_tool()
	local character = util.character()
	if not character then
		return nil
	end

	local slot = character:FindFirstChild("HandInvItem")
	if slot and slot.Value then
		return slot.Value
	end

	return character:FindFirstChildOfClass("Tool")
end

function bedwars.is_sword(tool)
	if not tool then
		return false
	end

	local meta = bedwars.item_meta()
	local entry = meta and meta[tool.Name]
	if type(entry) == "table" and type(entry.sword) == "table" then
		return true
	end

	-- the meta is not always reachable, the name is a good enough second pass
	local lower = tool.Name:lower()
	return lower:find("sword", 1, true) ~= nil or lower:find("scythe", 1, true) ~= nil
end

-- the hardest hitting sword you are carrying, hand or backpack
function bedwars.best_sword()
	local character = util.character()
	if not character then
		return nil
	end

	local meta = bedwars.item_meta()

	local player = players.LocalPlayer
	local containers = {character}
	local backpack = player and player:FindFirstChild("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end

	local best, best_damage

	for _, container in ipairs(containers) do
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				local entry = meta and meta[tool.Name]
				local sword = type(entry) == "table" and entry.sword or nil

				if type(sword) == "table" then
					local damage = tonumber(sword.damage) or tonumber(sword.attackDamage) or 1
					if not best_damage or damage > best_damage then
						best, best_damage = tool, damage
					end
				elseif bedwars.is_sword(tool) then
					-- no meta entry, keep it as a candidate with the lowest score
					if not best_damage then
						best, best_damage = tool, 0
					end
				end
			end
		end
	end

	return best
end

-- the block selector, cat reaches place and break range by widening the range
-- argument on its mouse info call
function bedwars.block_selector()
	local hit = fresh("block_selector")
	if hit then
		return hit
	end
	if not ready_to_retry("block_selector") then
		return nil
	end

	local searched = search_module_cached("block-selector")
	local value = searched and (searched.BlockSelector or searched.default)
	if type(value) ~= "table" then
		value = searched
	end

	if type(value) == "table" and type(value.getMouseInfo) == "function" then
		return remember("block_selector", value)
	end
	return remember("block_selector", nil)
end

-- movement modifiers
-- the sprint controller keeps a modifier list and recomputes moveSpeedMultiplier
-- from it on every reconcile, then setSpeed does base times that multiplier and
-- only clamps when maxSpeed is set, which it is not by default. a modifier
-- carrying constantSpeedMultiplier overrides the whole computed value

function bedwars.sprint_controller()
	return bedwars.controller("SprintController")
end

function bedwars.movement_modifiers()
	local sprint = bedwars.sprint_controller()
	if not sprint or type(sprint.getMovementStatusModifier) ~= "function" then
		return nil
	end
	local ok, host = pcall(function()
		return sprint:getMovementStatusModifier()
	end)
	if ok and type(host) == "table" then
		return host
	end
	return nil
end

-- returns a handle, destroy it to take the modifier back off
function bedwars.add_movement_modifier(properties, priority)
	local host = bedwars.movement_modifiers()
	if not host or type(host.addModifier) ~= "function" then
		return nil
	end

	local ok, handle = pcall(function()
		return host:addModifier(properties, priority)
	end)
	if ok and handle then
		return handle
	end
	return nil
end

function bedwars.remove_movement_modifier(handle)
	if not handle then
		return
	end
	pcall(function()
		if type(handle.destroy) == "function" then
			handle:destroy()
		elseif type(handle.Destroy) == "function" then
			handle:Destroy()
		elseif type(handle) == "function" then
			handle()
		end
	end)
end

function bedwars.local_kit()
	local player = players.LocalPlayer
	if not player then
		return nil
	end
	local ok, kit = pcall(function()
		return player:GetAttribute("Kit")
	end)
	if ok and kit ~= nil then
		return tostring(kit)
	end
	return nil
end

-- sword range requests
-- more than one module wants the swords to reach further, the aura and the reach
-- module both do, so the requests are pooled. the highest wins, originals are
-- kept once and only put back when the last requester lets go. a sword is never
-- moved down, a diamond already reaches 24 and a lower request must not nerf it

local reach_requests = {}
local reach_originals = {}

local function reach_target()
	local wanted
	for _, value in pairs(reach_requests) do
		if not wanted or value > wanted then
			wanted = value
		end
	end
	return wanted
end

local function write_sword_ranges(wanted)
	local touched = false

	local constants = bedwars.combat_constant()
	if constants then
		if wanted then
			constants.RAYCAST_SWORD_CHARACTER_DISTANCE = wanted + 2
			constants.REGION_SWORD_CHARACTER_DISTANCE = wanted + 2
		else
			constants.RAYCAST_SWORD_CHARACTER_DISTANCE = 14.4
			constants.REGION_SWORD_CHARACTER_DISTANCE = 12.6
		end
		touched = true
	end

	local meta = bedwars.item_meta()
	if not meta then
		return touched
	end

	for name, entry in pairs(meta) do
		if type(entry) == "table" and type(entry.sword) == "table" then
			if reach_originals[name] == nil then
				reach_originals[name] = entry.sword.attackRange or false
			end

			local original = reach_originals[name] or 0
			if wanted then
				entry.sword.attackRange = math.max(wanted, original)
			else
				entry.sword.attackRange = reach_originals[name] or nil
			end
			touched = true
		end
	end

	if not wanted then
		reach_originals = {}
	end

	return touched
end

-- returns true when something was actually patched
function bedwars.request_reach(key, studs)
	reach_requests[key] = studs
	return write_sword_ranges(reach_target())
end

function bedwars.release_reach(key)
	reach_requests[key] = nil
	write_sword_ranges(reach_target())
end

function bedwars.current_reach()
	return reach_target()
end

-- the swing remote
-- taken from sendServerRequest in the current client rather than from vape,
-- which matters. the live client sends through the net wrapper with
-- Client:Get("SwordHit"):SendToServer, not FireServer on the raw remote, and the
-- range the server checks is selfPosition, which is the character pivot

local max_server_reach = 14.399

function bedwars.attack_remote()
	local hit = fresh("attack_remote")
	if hit then
		return hit
	end
	if not ready_to_retry("attack_remote") then
		return nil
	end

	local client = bedwars.remotes_client()
	if client then
		local ok, wrapper = pcall(function()
			return client:Get("SwordHit")
		end)
		if ok and type(wrapper) == "table" then
			return remember("attack_remote", wrapper)
		end
	end

	return remember("attack_remote", nil)
end

-- the raw remote instance, only used if the wrapper will not send
function bedwars.attack_remote_instance()
	local wrapper = bedwars.attack_remote()
	if wrapper and typeof(wrapper.instance) == "Instance" then
		return wrapper.instance
	end

	local found
	pcall(function()
		for _, inst in ipairs(replicated:GetDescendants()) do
			if inst:IsA("RemoteEvent") and inst.Name == "SwordHit" then
				found = inst
				break
			end
		end
	end)
	return found
end

local function pivot_of(model)
	local ok, cframe = pcall(function()
		return model:GetPivot()
	end)
	if ok and cframe then
		return cframe.Position
	end
	local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	return part and part.Position or nil
end

-- one hit, built exactly the way the client builds it
function bedwars.swing_at(character, weapon)
	local wrapper = bedwars.attack_remote()
	local instance = not wrapper and bedwars.attack_remote_instance() or nil
	if not wrapper and not instance then
		return false
	end

	local me = util.character()
	if not character or not weapon or not me then
		return false
	end

	local self_position = pivot_of(me)
	local target_position = pivot_of(character)
	if not self_position or not target_position then
		return false
	end

	local delta = target_position - self_position
	local distance = delta.Magnitude
	if distance <= 0 then
		return false
	end

	local direction = CFrame.lookAt(self_position, target_position).LookVector

	-- the server range checks selfPosition, so slide the claimed origin up the
	-- aim vector until the gap it reports is inside the limit
	local claimed = self_position + direction * math.max(distance - max_server_reach, 0)

	local camera = workspace.CurrentCamera
	local payload = {
		weapon = weapon,
		entityInstance = character,
		validate = {
			raycast = camera and {
				cameraPosition = {value = claimed},
				cursorDirection = {value = direction},
			} or nil,
			targetPosition = {value = target_position},
			selfPosition = {value = claimed},
		},
		chargedAttack = {chargeRatio = 0},
	}

	local controller = bedwars.sword()
	if controller then
		pcall(function()
			controller.lastAttack = workspace:GetServerTimeNow()
		end)
	end

	if wrapper then
		local ok = pcall(function()
			wrapper:SendToServer(payload)
		end)
		if ok then
			return true
		end
	end

	if not instance then
		instance = bedwars.attack_remote_instance()
	end
	if instance then
		return pcall(function()
			instance:FireServer(payload)
		end)
	end

	return false
end

bedwars.max_server_reach = max_server_reach

-- hand spoofing
-- attackEntity and swingSwordInRegion both start by asking the sword controller
-- for the held item and then read that items meta. overriding what that call
-- returns for the duration of a swing makes the client build the swing as if
-- the sword were in hand, with no equip remote and nothing visible changing

local spoof_tool = nil
local spoof_installed = false
local spoof_original = nil

function bedwars.set_hand_spoof(tool)
	spoof_tool = tool
end

function bedwars.hand_spoof_active()
	return spoof_installed
end

function bedwars.install_hand_spoof()
	if spoof_installed then
		return true
	end

	local controller = bedwars.sword()
	if not controller or type(controller.getHandItem) ~= "function" then
		return false
	end

	spoof_original = controller.getHandItem

	controller.getHandItem = function(this, ...)
		local real = spoof_original(this, ...)
		local tool = spoof_tool

		if not tool or not tool.Parent then
			return real
		end

		-- the rest of the shape is kept so anything else reading the hand still
		-- sees the fields it expects, only the tool is swapped underneath
		local copy = {}
		if type(real) == "table" then
			for key, value in pairs(real) do
				copy[key] = value
			end
		end
		copy.tool = tool
		copy.toolType = "sword"
		return copy
	end

	spoof_installed = true
	return true
end

function bedwars.remove_hand_spoof()
	if not spoof_installed then
		return
	end

	local controller = bedwars.sword()
	if controller and spoof_original then
		controller.getHandItem = spoof_original
	end

	spoof_installed = false
	spoof_original = nil
	spoof_tool = nil
end

-- a short report of what resolved, the diagnostics module prints this
function bedwars.report()
	local lines = {}
	local checks = {
		{"knit", bedwars.knit},
		{"sword controller", bedwars.sword},
		{"projectile controller", bedwars.projectile_controller},
		{"combat constant", bedwars.combat_constant},
		{"item meta", bedwars.item_meta},
		{"cps constants", bedwars.cps_constants},
		{"knockback util", bedwars.knockback_util},
		{"sync events", bedwars.sync_events},
		{"net client", bedwars.remotes_client},
		{"block remotes", bedwars.block_remotes},
		{"swing remote", bedwars.attack_remote},
		{"sprint controller", bedwars.sprint_controller},
		{"movement modifiers", bedwars.movement_modifiers},
		{"block selector", bedwars.block_selector},
		{"block placer", bedwars.placer},
		{"entity util", bedwars.entity_util},
		{"world util", bedwars.world_util},
	}

	for _, check in ipairs(checks) do
		local ok, value = pcall(check[2])
		table.insert(lines, check[1] .. ": " .. ((ok and value) and "ok" or "missing"))
	end

	local meta = bedwars.item_meta()
	if meta then
		local swords = 0
		local sample
		for name, entry in pairs(meta) do
			if type(entry) == "table" and type(entry.sword) == "table" then
				swords = swords + 1
				sample = sample or (name .. " range " .. tostring(entry.sword.attackRange))
			end
		end
		table.insert(lines, "sword meta entries: " .. tostring(swords))
		if sample then
			table.insert(lines, "sample: " .. sample)
		end
	end

	local constants = bedwars.combat_constant()
	if constants then
		table.insert(lines, "raycast distance: " .. tostring(constants.RAYCAST_SWORD_CHARACTER_DISTANCE))
	end

	table.insert(lines, "kit: " .. tostring(bedwars.local_kit()))

	local sprint = bedwars.sprint_controller()
	if sprint then
		table.insert(lines, "move multiplier: " .. tostring(sprint.moveSpeedMultiplier)
			.. ", max speed: " .. tostring(sprint.maxSpeed))
	end

	table.insert(lines, "reach request: " .. tostring(bedwars.current_reach()))

	local held = bedwars.held_tool()
	local sword = bedwars.best_sword()
	table.insert(lines, "held: " .. (held and held.Name or "none")
		.. ", best sword: " .. (sword and sword.Name or "none")
		.. ", hand spoof: " .. (bedwars.hand_spoof_active() and "installed" or "off"))

	return lines
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
