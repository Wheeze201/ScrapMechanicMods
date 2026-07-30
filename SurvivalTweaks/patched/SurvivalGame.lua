-- [SurvivalTweaks] Vanilla 1.0 SurvivalGame.lua patched with Survival Tweaks
-- (adds /build, /blueprints, /export, /destroy - blueprint building that consumes
--  inventory materials - and /falldamage)
-- IMPORTANT: the game runs a compiled bundle (Cache\Bundle\core_data.cbo), not these
-- .lua files. Editing a script has NO effect until that bundle is deleted so the game
-- rebuilds it. install.bat/uninstall.bat handle this automatically.
dofile( "$SURVIVAL_DATA/Scripts/game/survival_loot.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/BeaconManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/DialogManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/EffectManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ElevatorManager.lua"  )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/MinidungeonElevatorManager.lua"  )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/RespawnManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_harvestable.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_units.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/recipes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestEntityManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/RaidManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/TileStorageManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/KinematicManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WarehouseManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/UndergroundElevatorManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/ScannerbotManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/RecipeManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/TutorialManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/WeatherManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/PatrolManager.lua" )
dofile( "$CUSTOMIZATION_DATA/Scripts/game/quest_reward_util.lua" )


















---@class SurvivalGame : GameClass
---@field sv table
---@field cl table
---@field warehouses table
SurvivalGame = class( nil )
SurvivalGame.enableLimitedInventory = true
SurvivalGame.enableRestrictions = true
SurvivalGame.enableFuelConsumption = true
SurvivalGame.enableAmmoConsumption = true
SurvivalGame.enableUpgrade = true

local SyncInterval = 400 -- 400 ticks | 10 seconds

-- [SurvivalTweaks] helpers for counting/consuming blueprint materials.
-- The material cost comes from sm.creation.getBlueprintCost - the engine's own
-- function, the same one the Scrap City garage uses. It understands 1.0 blueprints
-- (block bounds, joints, container contents, parts that map to a different item id)
-- which a hand-rolled parser of the .blueprint JSON does not.
-- It takes either a file path or a parsed blueprint table, and returns
--   { { uuid = <Uuid>, quantity = <number> }, ... }

-- returns cost, nil on success | nil, errorMessage on failure
local function blueprintCost( blueprintOrPath )
	local ok, content = pcall( sm.creation.getBlueprintCost, blueprintOrPath )
	if not ok then return nil, tostring( content ) end
	if type( content ) ~= "table" then return nil, "getBlueprintCost returned "..type( content ) end
	return content, nil
end

-- returns { { uuid = <Uuid>, quantity = <shortfall> }, ... } - empty when everything is covered
local function missingFromContainer( container, content )
	local missing = {}
	for _, shapeData in ipairs( content ) do
		local available = sm.container.totalQuantity( container, shapeData.uuid )
		if available < shapeData.quantity then
			missing[#missing + 1] = { uuid = shapeData.uuid, quantity = shapeData.quantity - available }
		end
	end
	return missing
end

-- all-or-nothing: mustSpendAll = true, so a failed transaction takes nothing
local function spendFromContainer( container, content )
	if not sm.container.beginTransaction() then return false end
	for _, shapeData in ipairs( content ) do
		sm.container.spend( container, shapeData.uuid, shapeData.quantity, true )
	end
	return sm.container.endTransaction()
end

-- [SurvivalTweaks] blueprint lookup.
--
-- A creation saved the normal way - on a lift, "Save blueprint" - is stored as a UGC
-- content folder under the user profile and the engine registers it under the path
-- alias $CONTENT_<localId>, the same path the Scrap City garage's blueprint picker
-- hands to GarageConsole.cl_e_trackBlueprint. So $CONTENT_<localId>/blueprint.json is
-- readable from script; what is NOT available is any way to list a directory, so the
-- name -> localId map has to come from somewhere else. refresh-blueprints.bat writes
-- it into the file below. Re-run that script after saving new blueprints on a lift.
local USER_BLUEPRINT_INDEX = "$SURVIVAL_DATA/LocalBlueprints/_userblueprints.json"

-- /export writes here rather than straight into LocalBlueprints, which is where the
-- game keeps its own ~900 level-decoration blueprints - mixing the two makes the
-- player's own creations impossible to pick out of a listing.
local EXPORT_DIR = "$SURVIVAL_DATA/LocalBlueprints/Exported/"

-- "Car mk1", "car_mk1" and "CARMK1" all collapse to the same key. The chat parser
-- splits on spaces and nobody wants to reproduce exact capitalisation from memory.
local function blueprintKey( name )
	return ( tostring( name ):lower():gsub( "[^%w]", "" ) )
end

local function fileExists( path )
	local ok, exists = pcall( sm.json.fileExists, path )
	if ok then return exists == true end
	-- sm.json.fileExists is only ever called from client scripts in the vanilla code
	-- (GarageConsole). If it turns out not to be callable here, opening the file is a
	-- slower but equivalent answer - without this, every lookup would report "missing".
	local opened, data = pcall( sm.json.open, path )
	return opened and type( data ) == "table"
end

-- reads the index fresh every time: it is a tiny file and it changes behind the
-- game's back whenever the refresh script runs
local function loadBlueprintIndex()
	local ok, index = pcall( sm.json.open, USER_BLUEPRINT_INDEX )
	if not ok or type( index ) ~= "table" then
		return { blueprints = {}, exports = {} }
	end
	index.blueprints = type( index.blueprints ) == "table" and index.blueprints or {}
	index.exports = type( index.exports ) == "table" and index.exports or {}
	return index
end

-- Resolves a name the way the player expects: their own saved blueprints first,
-- /export files as the fallback. Returns path, displayName, source | nil.
local function resolveBlueprint( name )
	if name == nil or name == "" then return nil end
	name = tostring( name )
	local wanted = blueprintKey( name )
	if wanted == "" then return nil end

	for _, entry in ipairs( loadBlueprintIndex().blueprints ) do
		if type( entry ) == "table" and entry.id and blueprintKey( entry.key or entry.name or "" ) == wanted then
			local path = "$CONTENT_" .. tostring( entry.id ) .. "/blueprint.json"
			if fileExists( path ) then
				return path, tostring( entry.name or name ), "blueprint"
			end
		end
	end

	-- a raw local id works too, so a blueprint saved since the last refresh is still
	-- reachable (the folder name under User/<user>/Blueprints is the id)
	if string.find( name, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$" ) then
		local path = "$CONTENT_" .. name .. "/blueprint.json"
		if fileExists( path ) then
			return path, name, "blueprint"
		end
	end

	local exported = EXPORT_DIR .. name .. ".blueprint"
	if fileExists( exported ) then
		return exported, name, "export"
	end

	-- exports made before /export moved into Exported/, and the game's own asset
	-- blueprints, which are occasionally handy to place
	local legacy = "$SURVIVAL_DATA/LocalBlueprints/" .. name .. ".blueprint"
	if fileExists( legacy ) then
		return legacy, name, "export"
	end

	return nil
end

function SurvivalGame.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.data = self.data
		printf( "Seed: %.0f", self.sv.saved.data.seed )
		self.sv.saved.overworld = sm.world.createWorld( "$SURVIVAL_DATA/Scripts/game/worlds/Overworld.lua", "Overworld", { dev = self.sv.saved.data.dev }, self.sv.saved.data.seed )
	else
		if self.sv.saved.overworld and not sm.exists( self.sv.saved.overworld ) then
			-- Load overworld to create TileStorageKeys
			sm.world.loadWorld( self.sv.saved.overworld )
		end
	end
	self.sv.saved.lootTier = self.sv.saved.lootTier or 1
	g_lootTier = self.sv.saved.lootTier

	-- [SurvivalTweaks] fall damage switch, stored per world so it survives rejoining.
	-- Read by BasePlayer.server_onCollision. `or` cannot express a boolean default here -
	-- `saved.x or true` is true even when the player turned it off - hence the nil test.
	if self.sv.saved.disableFallDamage == nil then
		self.sv.saved.disableFallDamage = true
	end
	g_disableFallDamage = self.sv.saved.disableFallDamage

	self.storage:save( self.sv.saved )

	self.data = nil








	
	self:loadCraftingRecipes()
	g_enableCollisionTumble = true


	g_kinematicManager = KinematicManager()
	g_kinematicManager:sv_onCreate()

	WorldManager.Sv_OnCreate()

	g_respawnManager = RespawnManager()
	g_respawnManager:sv_onCreate( self.sv.saved.overworld )

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	g_unitManager = UnitManager()
	g_unitManager:sv_onCreate( self.sv.saved.overworld )

	self.sv.questManager = sm.storage.load( STORAGE_CHANNEL_QUESTMANAGER )
	if not self.sv.questManager then
		self.sv.questManager = sm.scriptableObject.createScriptableObject( sm.uuid.new( "83b0cc7e-b164-47b8-a83c-0d33ba5f72ec" ) )
		sm.storage.save( STORAGE_CHANNEL_QUESTMANAGER, self.sv.questManager )
	end

	self.sv.scannerbotManager = sm.scriptableObject.createScriptableObject( sm.uuid.new( "2760488f-98a9-4cad-9d24-0b9fca45f91f" ), nil, self.sv.saved.overworld )

	self.sv.undergroundWorlds = sm.storage.load( STORAGE_CHANNEL_UNDERGROUND_WORLDS )
	if not self.sv.undergroundWorlds then
		self.sv.undergroundWorlds = {}
		sm.storage.save( STORAGE_CHANNEL_UNDERGROUND_WORLDS, self.sv.undergroundWorlds )
	end



	self.sv.time = sm.storage.load( STORAGE_CHANNEL_TIME )
	if self.sv.time then
		print( "Loaded timeData:" )
		print( self.sv.time )
	else
		self.sv.time = {}
		self.sv.time.timeOfDay = GAME_START_TIME -- 06:00
		self.sv.time.timeProgress = true
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
	end
	self.sv.gotoLocations = { "marker", "start", "mechanicstation", "hideout", "mainelevator", "excavation", "questfarmer", "questwarehouse", "garage", "scannerbot", "void",
		"underground1", "underground2", "underground3", "underground4", "underground5", "underground6", "underground7", "underground8" }
	self.network:setClientData( { dev = g_survivalDev, gotoLocations = self.sv.gotoLocations }, 1 )
	self:sv_updateClientData()

	self.sv.syncTimer = Timer()
	self.sv.syncTimer:start( 0 )




end

function SurvivalGame.server_onDestroy( self )



end

function SurvivalGame.server_onRefresh( self )
	g_craftingRecipeSets = nil
	self:loadCraftingRecipes()
end

function SurvivalGame.server_onUnload( self )
	TileStorageManager.Sv_Save()
end

function SurvivalGame.client_onCreate( self )
	self.cl = {}
	self.cl.time = {}
	self.cl.time.timeOfDay = 0.0
	if sm.isHost then
		-- Host sets time immediately to avoid incorrect time during startup
		self.cl.time.timeOfDay = self.sv.time.timeOfDay
		local todWraped = math.fmod( self.cl.time.timeOfDay, 1 )
		sm.game.setTimeOfDay( todWraped )
	end
	self.cl.time.timeProgress = true
	self.cl.overworld = nil
	self.cl.gotoLocations = {}

	if not sm.isHost then
		self:loadCraftingRecipes()
		g_enableCollisionTumble = true
	end

	WorldManager.Cl_OnCreate()

	if g_respawnManager == nil then
		assert( not sm.isHost )
		g_respawnManager = RespawnManager()
	end
	g_respawnManager:cl_onCreate()

	if g_beaconManager == nil then
		assert( not sm.isHost )
		g_beaconManager = BeaconManager()
	end
	g_beaconManager:cl_onCreate()

	if g_unitManager == nil then
		assert( not sm.isHost )
		g_unitManager = UnitManager()
	end

	g_radioTransmitter = sm.effect.createEffect( "Radio - Transmitter" )
	g_radioTransmitter:setWorldAny()
	g_boomboxTransmitter = sm.effect.createEffect( "Boombox - Transmitter" )
	g_boomboxTransmitter:setWorldAny()

	-- Survival HUD
	g_survivalHud = sm.gui.createSurvivalHudGui()
	assert(g_survivalHud)
	g_survivalHud:setVisible( "StatusPanel", false )
	g_survivalHud:setVisible( "BreathPanel", false )

	-- Compass HUD
	self.cl.compassEnabled = sm.game.getSettingBoolean( "CompassHud" )
	g_compassHud = sm.gui.createCompassHudGui()
	assert(g_compassHud)
	self:cl_compassHudEnable( self.cl.compassEnabled )

	self.cl.renderManager = sm.clientScriptableObject.createScriptableObject( sm.uuid.new( "54563daa-dd25-4f43-9e49-7e58bd59f66a" ) )

	-- [SurvivalTweaks] bind here, like CreativeGame does. bindChatCommands() only
	-- runs from a client-data callback, which is not a guaranteed path.
	self:sim_bindCommands()




end

-- [SurvivalTweaks] binds the mod's chat commands exactly once, and records the
-- outcome so it can be reported in chat once the loading screen is gone.
function SurvivalGame.sim_bindCommands( self )
	self.cl = self.cl or {}
	if self.cl.simBound then return end
	self.cl.simBound = true

	local report = {}

	local function bind( names, args, help )
		for _, name in ipairs( names ) do
			local ok, err = pcall( sm.game.bindChatCommand, name, args, "cl_onChatCommand", help )
			if ok then
				report[#report + 1] = "#00ff00" .. name .. "#ffffff"
				return name
			end
			report[#report + 1] = "#ff0000" .. name .. " failed (" .. tostring( err ) .. ")#ffffff"
		end
		return nil
	end

	-- the extra optional words let a blueprint saved as "Car mk1" be typed as-is;
	-- the chat parser has no quoting, so a name arrives split across arguments
	local nameArgs = { { "string", "name", false }, { "string", "...", true }, { "string", "...", true }, { "string", "...", true } }

	bind( { "/export", "/bpexport" }, { { "string", "name", false } }, "Exports aimed creation to $SURVIVAL_DATA/LocalBlueprints/Exported/<name>.blueprint" )
	bind( { "/build", "/bpbuild" }, nameArgs, "Builds <name> - one of your saved blueprints, or an /export - from the materials in your inventory" )
	bind( { "/blueprints", "/bplist" }, {}, "Lists the creations /build can place" )
	bind( { "/destroy", "/bpdestroy" }, {}, "Destroys aimed creation and drops its parts as loot (autosaved, rebuild with /build autosave)" )
	-- optional bool: bare /falldamage toggles, /falldamage on|off sets it explicitly
	bind( { "/falldamage" }, { { "bool", "enabled", true } }, "Turns fall damage on or off for this world (off by default)" )

	self.cl.simReport = table.concat( report, ", " )
end

function SurvivalGame.bindChatCommands( self )
	self:sim_bindCommands()
	if sm.isHost then
		sm.game.bindChatCommand( "/kick", { { "string", "player name", false } }, "cl_onChatCommand", "Kick a player from server" )
		sm.game.bindChatCommand( "/ban", { { "string", "player name", false } }, "cl_onChatCommand", "Ban a player from server" )
	end




	local addCheats = g_survivalDev

	if addCheats then
		-- [SurvivalTweaks] free spawning is a cheat, so it lives with the other cheats.
		-- /build is the survival-legal way in: it charges the materials.
		pcall( sm.game.bindChatCommand, "/import", { { "string", "name", false }, { "string", "...", true }, { "string", "...", true }, { "string", "...", true } }, "cl_onChatCommand", "Spawns <name> with NO material cost" )
		sm.game.bindChatCommand( "/ammo", { { "int", "quantity", true } }, "cl_onChatCommand", "Give ammo (default 100)" )
		sm.game.bindChatCommand( "/spudgun", {}, "cl_onChatCommand", "Give the spudgun" )
		sm.game.bindChatCommand( "/gatling", {}, "cl_onChatCommand", "Give the potato gatling gun" )
		sm.game.bindChatCommand( "/shotgun", {}, "cl_onChatCommand", "Give the fries shotgun" )
		sm.game.bindChatCommand( "/sunshake", {}, "cl_onChatCommand", "Give 1 sunshake" )
		sm.game.bindChatCommand( "/baguette", {}, "cl_onChatCommand", "Give 1 revival baguette" )
		sm.game.bindChatCommand( "/keycard", {}, "cl_onChatCommand", "Give 1 keycard" )
		sm.game.bindChatCommand( "/powercore", {}, "cl_onChatCommand", "Give 1 powercore" )
		sm.game.bindChatCommand( "/components", { { "int", "quantity", true } }, "cl_onChatCommand", "Give <quantity> components (default 10)" )
		sm.game.bindChatCommand( "/glowsticks", { { "int", "quantity", true } }, "cl_onChatCommand", "Give <quantity> components (default 10)" )
		sm.game.bindChatCommand( "/foodplease", {}, "cl_onChatCommand", "Give 5 of each edible type" )
		sm.game.bindChatCommand( "/seedsplease", {}, "cl_onChatCommand", "Give 20 of each seed type and some soil" )
		sm.game.bindChatCommand( "/tumble", { { "bool", "enable", true } }, "cl_onChatCommand", "Set tumble state" )
		sm.game.bindChatCommand( "/god", {}, "cl_onChatCommand", "Mechanic characters will take no damage" )
		sm.game.bindChatCommand( "/limited", {}, "cl_onChatCommand", "Use the limited inventory" )
		sm.game.bindChatCommand( "/unlimited", {}, "cl_onChatCommand", "Use the unlimited inventory" )
		sm.game.bindChatCommand( "/timeofday", { { "number", "timeOfDay", true } }, "cl_onChatCommand", "Sets the time of the day as a fraction (0.5=mid day)" )
		sm.game.bindChatCommand( "/timeprogress", { { "bool", "enabled", true } }, "cl_onChatCommand", "Enables or disables time progress" )
		
		
		local autocomplete = {}
		for k, _ in pairs( g_unitSpawnNames ) do
			autocomplete[#autocomplete+1] = k
		end
		sm.game.bindChatCommand( "/spawn", { { "string", "unitName", true, autocomplete }, { "int", "amount", true } }, "cl_onChatCommand", "Spawn a unit: 'woc', 'tapebot', 'totebot', 'haybot'" )

		local existingKits = { "start", "trashbot", "mechanic", "tutorial", "pipe", "food", "seed" }
		
		sm.game.bindChatCommand( "/starterkit", { { "string", "name", true, existingKits } }, "cl_onChatCommand", "Spawn a starter kit" )
		sm.game.bindChatCommand( "/die", {}, "cl_onChatCommand", "Kill the player" )
		sm.game.bindChatCommand( "/unstuck", {}, "cl_onChatCommand", "Unstuck the player" )
		sm.game.bindChatCommand( "/sethp", { { "number", "hp", false } }, "cl_onChatCommand", "Set player hp value" )
		sm.game.bindChatCommand( "/setbreath", { { "number", "breath", false } }, "cl_onChatCommand", "Set player breath value" )
		sm.game.bindChatCommand( "/aggroall", {}, "cl_onChatCommand", "All hostile units will be made aware of the player's position" )
		
		sm.game.bindChatCommand( "/stopraid", {}, "cl_onChatCommand", "Cancel all incoming raids" )
		sm.game.bindChatCommand( "/disableraids", { { "bool", "enabled", false } }, "cl_onChatCommand", "Disable raids if true" )
		sm.game.bindChatCommand( "/noaggro", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles the player as a target" )
		sm.game.bindChatCommand( "/exportmultishape", {}, "cl_onChatCommand", "Exports a blueprint shape file" )
		



























































































































	end
end

function SurvivalGame.client_onClientDataUpdate( self, clientData, channel )
	if channel == 2 then
		self.cl.time = clientData.time
	elseif channel == 1 then
		g_survivalDev = clientData.dev
		self.cl.gotoLocations = clientData.gotoLocations
		self:bindChatCommands()
	end
end


function SurvivalGame.loadCraftingRecipes( self )
	local recipeSets = sm.json.open( "$SURVIVAL_DATA/CraftingRecipes/craftbot/craftbot.json" )
	recipeSets.workbench = "$SURVIVAL_DATA/CraftingRecipes/workbench.json"
	recipeSets.portablecrafter = "$SURVIVAL_DATA/CraftingRecipes/portablecrafter.json"
	recipeSets.dispenser = "$SURVIVAL_DATA/CraftingRecipes/dispenser.json"
	recipeSets.cookbot = "$SURVIVAL_DATA/CraftingRecipes/cookbot.json"
	recipeSets.dressbot = "$SURVIVAL_DATA/CraftingRecipes/dressbot.json"
	recipeSets.mininghubDispenser = "$SURVIVAL_DATA/CraftingRecipes/mininghubDispenser.json"
	recipeSets.sawtable = "$SURVIVAL_DATA/CraftingRecipes/sawtable.json"
	LoadCraftingRecipes( recipeSets )
end

function SurvivalGame.server_onFixedUpdate( self, timeStep )
	-- Update time







		if self.sv.time.timeProgress then
			self.sv.time.timeOfDay = self.sv.time.timeOfDay + ( timeStep / DAYCYCLE_TIME )
		end




	if WeatherManager.Get() then
		WeatherManager.Get():sv_setTimeOfDay( self.cl.time.timeOfDay )
	end

	-- Client and save sync
	self.sv.syncTimer:tick()
	if self.sv.syncTimer:done() then
		self.sv.syncTimer:start( SyncInterval )
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
		self:sv_updateClientData()
	end

	g_unitManager:sv_onFixedUpdate()

	if g_respawnManager then
		g_respawnManager:sv_onFixedUpdate()
	end




end

function SurvivalGame.sv_updateClientData( self )
	self.network:setClientData( { time = self.sv.time }, 2 )
end

function SurvivalGame.client_onUpdate( self, dt )
	-- Update time







		if self.cl.time.timeProgress then
			self.cl.time.timeOfDay = self.cl.time.timeOfDay + ( dt / DAYCYCLE_TIME )
		end




	if WeatherManager.Get() then
		WeatherManager.Get():cl_setTimeOfDay( self.cl.time.timeOfDay )
	end

	local todWraped = math.fmod( self.cl.time.timeOfDay, 1 )
	sm.game.setTimeOfDay( todWraped )

	-- Update lighting values
	local index = 1
	while index < #DAYCYCLE_LIGHTING_TIMES and todWraped >= DAYCYCLE_LIGHTING_TIMES[index + 1] do
		index = index + 1
	end
	assert( index <= #DAYCYCLE_LIGHTING_TIMES )

	local light = 0.0
	if index < #DAYCYCLE_LIGHTING_TIMES then
		local p = ( todWraped - DAYCYCLE_LIGHTING_TIMES[index] ) / ( DAYCYCLE_LIGHTING_TIMES[index + 1] - DAYCYCLE_LIGHTING_TIMES[index] )
		light = sm.util.lerp( DAYCYCLE_LIGHTING_VALUES[index], DAYCYCLE_LIGHTING_VALUES[index + 1], p )
	else
		light = DAYCYCLE_LIGHTING_VALUES[index]
	end
	
	sm.render.setOutdoorLighting( light )




end

function SurvivalGame.client_onFixedUpdate( self, dt )
	
	local compassSetting = sm.game.getSettingBoolean( "CompassHud" )
	if self.cl.compassEnabled ~= compassSetting then
		self.cl.compassEnabled = compassSetting
		self:cl_compassHudEnable( self.cl.compassEnabled )
	end
end

function SurvivalGame.cl_compassHudEnable( self, enable )
	if enable == true then
		g_compassHud:open()
	else
		g_compassHud:close()
	end
end

function SurvivalGame.client_showMessage( self, msg )
	sm.gui.chatMessage( msg )
end

function SurvivalGame.cl_onChatCommand( self, params )
	if params[1] == "/ammo" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_plantables_potato, quantity = ( params[2] or 100 ) } )
	elseif params[1] == "/spudgun" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_spudgun, quantity = 1 } )
	elseif params[1] == "/gatling" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_gatling, quantity = 1 } )
	elseif params[1] == "/shotgun" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = tool_shotgun, quantity = 1 } )
	elseif params[1] == "/sunshake" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_sunshake, quantity = 1 } )
	elseif params[1] == "/baguette" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_longsandwich, quantity = 1 } )
	elseif params[1] == "/keycard" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_survivalobject_keycard, quantity = 1 } )
	elseif params[1] == "/powercore" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_survivalobject_powercore, quantity = 1 } )
	elseif params[1] == "/components" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_component, quantity = ( params[2] or 10 ) } )
	elseif params[1] == "/glowsticks" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = obj_consumable_glowstick, quantity = ( params[2] or 20 ) } )
	elseif params[1] == "/foodplease" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_resource_corn, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_plantables_tomato, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_plantables_carrot, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_plantables_redbeet, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_plantables_banana, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_plantables_blueberry, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_plantables_orange, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_plantables_broccoli, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_plantables_pineapple, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_consumable_milk, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_consumable_pizzaburger, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_consumable_carrotburger, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_consumable_sunshake, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_consumable_tea, quantity = 5 } )
	elseif params[1] == "/seedsplease" then
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_consumable_soilbag, quantity = 5 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_potato, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_tomato, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_carrot, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_redbeet, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_banana, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_blueberry, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_orange, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_broccoli, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_pineapple, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_chili, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_pigmentflower, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_seed_cotton, quantity = 20 } )
		self.network:sendToServer( "sv_giveItem", { player = sm.localPlayer.getPlayer(), item = ITEMS.obj_consumable_soilbag, quantity = 45 } )
	elseif params[1] == "/god" then
		self.network:sendToServer( "sv_switchGodMode" )
	elseif params[1] == "/unlimited" then
		self.network:sendToServer( "sv_setLimitedInventory", false )
	elseif params[1] == "/limited" then
		self.network:sendToServer( "sv_setLimitedInventory", true )
	elseif params[1] == "/timeofday" then
		self.network:sendToServer( "sv_setTimeOfDay", params[2] )
	elseif params[1] == "/timeprogress" then
		self.network:sendToServer( "sv_setTimeProgress", params[2] )
	elseif params[1] == "/die" then
		self.network:sendToServer( "sv_killPlayer", { player = sm.localPlayer.getPlayer() } )
	elseif params[1] == "/unstuck" then
		sm.event.sendToPlayer( sm.localPlayer.getPlayer(), "cl_e_unstuck" )
	elseif params[1] == "/spawn" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			local spawnParams = {
				uuid = sm.uuid.getNil(),
				world = sm.localPlayer.getPlayer().character:getWorld(),
				position = rayCastResult.pointWorld,
				yaw = 0.0,
				amount = 1,
				customParams = { tetherPoint = rayCastResult.pointWorld }
			}
			if g_unitSpawnNames[params[2]] then
				spawnParams.uuid = g_unitSpawnNames[params[2]]
			else
				spawnParams.uuid = sm.uuid.new( params[2] )
			end
			if params[3] then
				spawnParams.amount = params[3]
			end
			self.network:sendToServer( "sv_spawnUnit", spawnParams )
		end
	
	
	elseif params[1] == "/noaggro" then
		if type( params[2] ) == "boolean" then
			self.network:sendToServer( "sv_n_switchAggroMode", { aggroMode = not params[2] } )
		else
			self.network:sendToServer( "sv_n_switchAggroMode", { aggroMode = not sm.game.getEnableAggro() } )
		end
	-- [SurvivalTweaks] blueprint export/build/destroy
	elseif params[1] == "/export" or params[1] == "/bpexport" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid and rayCastResult.type == "body" then
			self.network:sendToServer( "sv_exportCreation", {
				name = params[2],
				body = rayCastResult:getBody()
			} )
		else
			sm.gui.chatMessage( "#ff0000Aim at a creation to export it" )
		end
	elseif params[1] == "/blueprints" or params[1] == "/bplist" then
		self:cl_sim_listBlueprints()
	elseif params[1] == "/falldamage" then
		-- params[2] is nil when the argument is omitted, which means "toggle"
		self.network:sendToServer( "sv_sim_switchFallDamage", { enabled = params[2] } )
	elseif params[1] == "/import" or params[1] == "/bpimport" or params[1] == "/build" or params[1] == "/bpbuild" then
		-- the name arrives split across arguments when it contains spaces
		local nameParts = {}
		for i = 2, #params do
			if type( params[i] ) == "string" and params[i] ~= "" then
				nameParts[#nameParts + 1] = params[i]
			end
		end
		local name = table.concat( nameParts, " " )

		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			local importParams = {
				world = sm.localPlayer.getPlayer().character:getWorld(),
				name = name,
				position = rayCastResult.pointWorld
			}
			if params[1] == "/build" or params[1] == "/bpbuild" then
				importParams.consume = true
				importParams.player = sm.localPlayer.getPlayer()
			end
			self.network:sendToServer( "sv_importCreation", importParams )
		else
			sm.gui.chatMessage( "#ff0000Aim at the ground where the creation should be placed" )
		end
	elseif params[1] == "/destroy" or params[1] == "/bpdestroy" then
		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid and rayCastResult.type == "body" then
			self.network:sendToServer( "sv_destroyCreation", {
				world = sm.localPlayer.getPlayer().character:getWorld(),
				body = rayCastResult:getBody(),
				position = rayCastResult.pointWorld,
				player = sm.localPlayer.getPlayer()
			} )
		else
			sm.gui.chatMessage( "#ff0000Aim at a creation to destroy it" )
		end




























































































































































































































	else
		self.network:sendToServer( "sv_onChatCommand", params )
	end
end

function SurvivalGame.sv_reloadTile( self, params )
	local xMin,xMax,yMin,yMax
	if params.pos then
		xMin,xMax,yMin,yMax = GetTileRanges( params.pos, params.world.id )
	elseif params.cell then
		xMin,xMax,yMin,yMax = GetTileRangesFromCell( params.cell.x, params.cell.y, params.world.id )
	end
	self.network:sendToClients( "cl_reloadTile", { world = params.world, xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax } )
end

function SurvivalGame.cl_reloadTile( self, params )
	for x = params.xMin, params.xMax do
		for y = params.yMin, params.yMax do
			params.world:reloadCell( x, y )
		end
	end
end

function SurvivalGame.sv_reloadCell( self, params, player )
	self.sv.saved.overworld:loadCell( params.x, params.y, player )
	self.network:sendToClients( "cl_reloadCell", params )
end

function SurvivalGame.sv_loadCell( self, params )
	if not sm.exists( self.sv.saved.overworld ) then
		sm.world.loadWorld( self.sv.saved.overworld )
	end

	if self.handle then
		self.handle:release()
	end

	self.handle = self.sv.saved.overworld:loadCellWithHandle( params.x, params.y, nil )
end

function SurvivalGame.sv_releaseCell( self )
	if self.handle then
		self.handle:release()
		self.handle = nil
	end
end
























































function SurvivalGame.sv_n_chemicaltower( self )
	EffectManager.Cl_PlayNamedCinematic( { name = "cinematic.chemicaltower", callbackData = { world = self.sv.saved.overworld } } )
end

function SurvivalGame.cl_reloadCell( self, params )
	for x = -2, 2 do
		for y = -2, 2 do
			params.world:reloadCell( params.x+x, params.y+y )
		end
	end
end

function SurvivalGame.sv_giveItem( self, params )
	sm.container.beginTransaction()
	sm.container.collect( params.player:getInventory(), params.item, params.quantity, false )
	sm.container.endTransaction()
end

function SurvivalGame.cl_n_onJoined( self, params )
	self.cl.playIntroCinematic = params.newPlayer
end

function SurvivalGame.client_onLoadingScreenLifted( self )
	-- [SurvivalTweaks] visible proof the patched script is live, plus bind results
	sm.gui.chatMessage( "#00ff00[SurvivalTweaks]#ffffff ready: " .. tostring( self.cl and self.cl.simReport or "#ff0000no commands bound" ) )

	EffectManager.Cl_OnLoadingScreenLifted()
	TutorialManager.Cl_OnLoadingScreenLifted()

	self.network:sendToServer( "sv_n_loadingScreenLifted" )
	if self.cl.playIntroCinematic and not g_survivalDev then
		EffectManager.Cl_PlayNamedCinematic( { name = "cinematic.survivalstart01", callbackData = { world = self.cl.overworld }, forceCameraData = true } )
	end
end

function SurvivalGame.sv_n_loadingScreenLifted( self, _, player )
	if not g_survivalDev then
		QuestManager.Sv_TryActivateQuest( "quest_tutorial" )
	end
end

function SurvivalGame.client_onLanguageChange( self, newLanguage )
	DialogManager.Cl_OnLanguageChange( newLanguage )
end

function SurvivalGame.client_onUnstuck( self )
	sm.event.sendToPlayer( sm.localPlayer.getPlayer(), "cl_e_unstuck" )
end

function SurvivalGame.sv_switchGodMode( self )
	g_godMode = not g_godMode
	self.network:sendToClients( "client_showMessage", "GODMODE: " .. ( g_godMode and "On" or "Off" ) )
end

-- [SurvivalTweaks] /falldamage - modelled on sv_switchGodMode above, but the setting is
-- written to the world save so it survives rejoining. Only the server needs the global:
-- BasePlayer.server_onCollision, the one place that reads it, is server side.
function SurvivalGame.sv_sim_switchFallDamage( self, params )
	local enabled
	if type( params ) == "table" and type( params.enabled ) == "boolean" then
		enabled = params.enabled
	else
		enabled = g_disableFallDamage == true -- no argument: flip it
	end

	g_disableFallDamage = not enabled
	self.sv.saved.disableFallDamage = g_disableFallDamage
	self.storage:save( self.sv.saved )

	self.network:sendToClients( "client_showMessage", "FALL DAMAGE: " .. ( enabled and "#ff0000On" or "#00ff00Off" ) )
end

function SurvivalGame.sv_n_switchAggroMode( self, params )
	sm.game.setEnableAggro(params.aggroMode )
	self.network:sendToClients( "client_showMessage", "AGGRO: " .. ( params.aggroMode and "On" or "Off" ) )
end

function SurvivalGame.sv_enableRestrictions( self, state )
	sm.game.setEnableRestrictions( state )
	self.network:sendToClients( "client_showMessage", ( state and "Restricted" or "Unrestricted"  ) )
end

function SurvivalGame.sv_setLimitedInventory( self, state )
	sm.game.setLimitedInventory( state )
	self.network:sendToClients( "client_showMessage", ( state and "Limited inventory" or "Unlimited inventory"  ) )
end










































function SurvivalGame.sv_setTimeOfDay( self, timeOfDay )
	if timeOfDay then
		self.sv.time.timeOfDay = math.floor( self.sv.time.timeOfDay ) + sm.util.clamp( timeOfDay, 0.0, 0.9999 )
		self.sv.syncTimer.count = self.sv.syncTimer.ticks -- Force sync
	end
	self.network:sendToClients( "client_showMessage", ( "Time of day set to "..self.sv.time.timeOfDay ) )
end

function SurvivalGame.sv_setTimeProgress( self, timeProgress )
	if timeProgress ~= nil then
		self.sv.time.timeProgress = timeProgress
		self.sv.syncTimer.count = self.sv.syncTimer.ticks -- Force sync
	end
	self.network:sendToClients( "client_showMessage", ( "Time scale set to "..( self.sv.time.timeProgress and "on" or "off ") ) )
end

function SurvivalGame.sv_killPlayer( self, params )
	params.damage = 9999
	params.source = "shock"
	sm.event.sendToPlayer( params.player, "sv_e_receiveDamage", params )
end


















function SurvivalGame.sv_spawnUnit( self, params )
	sm.event.sendToWorld( params.world, "sv_e_spawnUnit", params )
end











function SurvivalGame.sv_spawnHarvestable( self, params )
	sm.event.sendToWorld( params.world, "sv_spawnHarvestable", params )
end

-- [SurvivalTweaks] export with automatic backup of an existing blueprint of the same name
function SurvivalGame.sv_exportCreation( self, params )
	local target = EXPORT_DIR..params.name..".blueprint"

	local success, existing = pcall( sm.json.open, target )
	if success and existing then
		sm.json.save( existing, EXPORT_DIR..params.name.."_backup.blueprint" )
		self.network:sendToClients( "client_showMessage", "A blueprint named '"..params.name.."' already existed and was backed up. Restore it with #00ff00/build "..params.name.."_backup" )
	end
	local obj = sm.json.parseJsonString( sm.creation.exportToString( params.body ) )
	sm.json.save( obj, target )
	self.network:sendToClients( "client_showMessage", "Exported #00ff00"..params.name )
end

-- [SurvivalTweaks] /build consumes materials from the player inventory, /import (dev cheat) does not
function SurvivalGame.sv_importCreation( self, params, caller )
	local path, displayName = resolveBlueprint( params.name )
	if not path then
		return self.network:sendToClients( "client_showMessage", "#ff0000No blueprint or export named '"..tostring( params.name ).."'. #ffffffUse #00ff00/blueprints#ffffff to see what is available." )
	end

	if not params.consume then
		sm.creation.importFromFile( params.world, path, params.position )
		return
	end

	local player = params.player or caller
	if not player then
		return self.network:sendToClients( "client_showMessage", "#ff0000/build could not identify the player" )
	end

	local opened, data = pcall( sm.json.open, path )
	if not opened or type( data ) ~= "table" or not data.bodies then
		return self.network:sendToClients( "client_showMessage", "#ff0000Blueprint '"..tostring( displayName ).."' could not be read!" )
	end

	-- cost is computed from the table we just parsed, not from the path again, so a
	-- blueprint written moments ago (/export, /destroy) is priced from its real contents
	local content, costError = blueprintCost( data )
	if not content then
		return self.network:sendToClients( "client_showMessage", "#ff0000Could not read the cost of '"..tostring( displayName ).."': "..tostring( costError ) )
	end

	-- a blueprint from an older game version can name parts that no longer exist
	local unknown = {}
	local usable = {}
	for _, shapeData in ipairs( content ) do
		if sm.shape.uuidExists( shapeData.uuid ) then
			usable[#usable + 1] = shapeData
		else
			unknown[#unknown + 1] = { uuid = tostring( shapeData.uuid ), quantity = shapeData.quantity }
		end
	end
	if #unknown > 0 then
		self.network:sendToClients( "client_sim_reportParts", { title = "#ff0000This blueprint uses parts that do not exist in this version:", parts = unknown } )
		return
	end

	local inventory = player:getInventory()
	local missing = missingFromContainer( inventory, usable )

	if #missing > 0 then
		local report = {}
		for _, entry in ipairs( missing ) do
			report[#report + 1] = { uuid = tostring( entry.uuid ), quantity = entry.quantity }
		end
		self.network:sendToClients( "client_sim_reportParts", { title = "#ff0000Not enough materials to build '"..tostring( displayName ).."'. Missing:", parts = report, alert = "Missing materials - see chat" } )
		return
	end

	if not spendFromContainer( inventory, usable ) then
		return self.network:sendToClients( "client_showMessage", "#ff0000Could not take the materials out of your inventory - nothing was built." )
	end

	sm.creation.importFromFile( params.world, path, params.position )
	self.network:sendToClients( "client_showMessage", "Built #00ff00"..tostring( displayName ).."#ffffff from your materials." )
end

-- [SurvivalTweaks] destroy aimed creation and drop all of its parts as loot
function SurvivalGame.sv_destroyCreation( self, params )
	local data = sm.json.parseJsonString( sm.creation.exportToString( params.body ) )

	-- Cost comes from the in-memory creation, NEVER from a path we just wrote to:
	-- the engine serves the previous contents of a freshly written blueprint path,
	-- which refunded the last autosave's parts instead of this creation's.
	local content, costError = blueprintCost( data )
	if not content then
		return self.network:sendToClients( "client_showMessage", "#ff0000Could not read the creation's part list: "..tostring( costError ).." - nothing was destroyed." )
	end

	sm.json.save( data, EXPORT_DIR.."autosave.blueprint" )

	local loot = {}
	for _, shapeData in ipairs( content ) do
		if sm.shape.uuidExists( shapeData.uuid ) then
			loot[#loot + 1] = { uuid = shapeData.uuid, quantity = shapeData.quantity }
		end
	end
	SpawnLoot( params.player, loot, params.player:getCharacter().worldPosition )

	for _, shape in pairs( params.body:getCreationShapes() ) do
		sm.shape.destroyShape( shape )
	end

	self.network:sendToClients( "client_showMessage", "Creation destroyed. It was autosaved - rebuild it with #00ff00/build autosave" )
end

function SurvivalGame.client_showAlert( self, msg )
	sm.gui.displayAlertText( msg )
end

-- [SurvivalTweaks] part lists are formatted client-side: sm.shape.getShapeTitle reads
-- the localisation tables, which are a client thing. Calling it on the server aborted the
-- whole handler, which is why the "missing materials" list never reached the chat.
-- [SurvivalTweaks] /blueprints - purely client side, it only reads the index file
function SurvivalGame.cl_sim_listBlueprints( self )
	local index = loadBlueprintIndex()

	sm.gui.chatMessage( "#00ff00Blueprints#ffffff (saved on a lift):" )
	if #index.blueprints == 0 then
		sm.gui.chatMessage( "  #808080none indexed - run refresh-blueprints.bat and rejoin" )
	else
		for _, entry in ipairs( index.blueprints ) do
			sm.gui.chatMessage( "  #ffff00" .. tostring( entry.name ) )
		end
	end

	sm.gui.chatMessage( "#00ff00Exports#ffffff (/export):" )
	if #index.exports == 0 then
		sm.gui.chatMessage( "  #808080none" )
	else
		for _, name in ipairs( index.exports ) do
			sm.gui.chatMessage( "  #ffff00" .. tostring( name ) )
		end
	end

	if index.generated then
		sm.gui.chatMessage( "#808080Index from " .. tostring( index.generated ) .. " - re-run refresh-blueprints.bat after saving new blueprints." )
	end
end

function SurvivalGame.client_sim_reportParts( self, params )
	if params.alert then
		sm.gui.displayAlertText( params.alert )
	end
	sm.gui.chatMessage( params.title )
	for _, entry in ipairs( params.parts ) do
		local ok, title = pcall( sm.shape.getShapeTitle, sm.uuid.new( entry.uuid ) )
		if not ok or title == nil or title == "" then title = entry.uuid end
		sm.gui.chatMessage( "  #ffff00"..entry.quantity.."x #ffffff"..tostring( title ) )
	end
end

function SurvivalGame.sv_onChatCommand( self, params, player )

	if params[1] == "/kick" then
		if params[2] ~= nil then
			self:sv_kickPlayer( params[2] )
		end
	elseif params[1] == "/ban" then
		if params[2] ~= nil then
			self:sv_banPlayer( params[2] )
		end
	elseif params[1] == "/tumble" then
		if params[2] ~= nil then
			player.character:setTumbling( params[2] )
		else
			player.character:setTumbling( not player.character:isTumbling() )
		end
		if player.character:isTumbling() then
			self.network:sendToClients( "client_showMessage", "Player is tumbling" )
		else
			self.network:sendToClients( "client_showMessage", "Player is not tumbling" )
		end
	elseif params[1] == "/sethp" then
		sm.event.sendToPlayer( player, "sv_e_debug", { hp = params[2] } )

	elseif params[1] == "/setbreath" then
		sm.event.sendToPlayer( player, "sv_e_debug", { breath = params[2] } )
























































































































































































































































































































































































































































































































































































































	else
		params.player = player
		if sm.exists( player.character ) then
			sm.event.sendToWorld( player.character:getWorld(), "sv_e_onChatCommand", params )
		end
	end
end

function SurvivalGame.server_onPlayerJoined( self, player, newPlayer )
	print( player.name, "joined the game" )
	self.sv.gotoLocations = self.sv.gotoLocations or {}
	self.sv.gotoLocations[#self.sv.gotoLocations+1] = string.lower( player.name )
	self.network:setClientData( { dev = g_survivalDev, gotoLocations = self.sv.gotoLocations }, 1 )
	WeatherManager.Sv_PlayerJoined( player )
	if newPlayer then --Player is first time joiners
		local inventory = player:getInventory()
		
		sm.container.beginTransaction()
		
		if g_survivalDev then
			if not sm.game.getLimitedInventory() then
				inventory = player:getHotbar()
			end
			--Hotbar
			sm.container.setItem( inventory, 0, ITEMS.tool_sledgehammer, 1 )
			sm.container.setItem( inventory, 1, ITEMS.tool_lift, 1 )
			sm.container.setItem( inventory, 2, ITEMS.tool_spudgun, 1 )
			sm.container.setItem( inventory, 3, ITEMS.obj_consumable_glowstick, 20 )
			sm.container.setItem( inventory, 9, ITEMS.tool_connect, 1 )

			--Actual inventory
			sm.container.setItem( inventory, 10, ITEMS.tool_paint, 1 )
			sm.container.setItem( inventory, 11, ITEMS.tool_weld, 1 )
		else
			sm.container.setItem( inventory, 0, ITEMS.tool_sledgehammer, 1 )
			sm.container.setItem( inventory, 1, ITEMS.tool_lift, 1 )
		end

		sm.container.endTransaction()

		local spawnPoint = g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
		if not sm.exists( self.sv.saved.overworld ) then
			sm.world.loadWorld( self.sv.saved.overworld )
		end
		self.sv.saved.overworld:loadCell( math.floor( spawnPoint.x/64 ), math.floor( spawnPoint.y/64 ), player, "sv_createNewPlayer" )
		self.network:sendToClient( player, "cl_n_onJoined", { newPlayer = newPlayer } )
	else
		local inventory = player:getInventory()

		local sledgehammerCount = sm.container.totalQuantity( inventory, ITEMS.tool_sledgehammer )
		if sledgehammerCount == 0 then
			sm.container.beginTransaction()
			sm.container.collect( inventory, ITEMS.tool_sledgehammer, 1 )
			sm.container.endTransaction()
		elseif sledgehammerCount > 1 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, ITEMS.tool_sledgehammer, sledgehammerCount - 1 )
			sm.container.endTransaction()
		end

		local tool_lift_creative = sm.uuid.new( "5cc12f03-275e-4c8e-b013-79fc0f913e1b" )
		local creativeLiftCount = sm.container.totalQuantity( inventory, tool_lift_creative )
		if creativeLiftCount > 0 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, tool_lift_creative, creativeLiftCount )
			sm.container.endTransaction()
		end

		local liftCount = sm.container.totalQuantity( inventory, ITEMS.tool_lift )
		if liftCount == 0 then
			sm.container.beginTransaction()
			sm.container.collect( inventory, ITEMS.tool_lift, 1 )
			sm.container.endTransaction()
		elseif liftCount > 1 then
			sm.container.beginTransaction()
			sm.container.spend( inventory, ITEMS.tool_lift, liftCount - 1 )
			sm.container.endTransaction()
		end
	end

	if player.id > 1 then --Too early for self. Questmanager is not created yet...
		QuestManager.Sv_SendEvent( QuestEvent.PlayerJoined, { player = player } )
	end
end

function SurvivalGame.server_onPlayerLeft( self, player )
	print( player.name, "left the game" )
	for i, name in ipairs( self.sv.gotoLocations ) do
		if name == string.lower( player.name ) then
			self.sv.gotoLocations[i] = nil
			break
		end
	end
	self.network:setClientData( { dev = g_survivalDev, gotoLocations = self.sv.gotoLocations }, 1 )
	if player.id > 1 then
		QuestManager.Sv_SendEvent( QuestEvent.PlayerLeft, { player = player } )
	end
	if player.id ~= sm.player.getHostPlayer().id then
		local carryInventory = player:getCarry()
		local currentCarry = carryInventory:getItem( 0 )
		if currentCarry and currentCarry.uuid ~= sm.uuid.getNil() then
			local character = player:getCharacter()
			if character and sm.exists( character ) then
				local world = character:getWorld()
				local subdivideRatio = 0.25
				local halfShapeSize = sm.item.getShapeSize( currentCarry.uuid ) * 0.5 * subdivideRatio
				local spawnPos = character:getWorldPosition() + sm.vec3.new( 0, 0, halfShapeSize.z + 1 )
				local shapePlacement = {
					worldPosition = spawnPos,
					worldRotation = sm.item.getShapeRotation( currentCarry.uuid ),
				}
				sm.event.sendToWorld( world, "sv_e_dropCarryShape",{
					itemA = currentCarry.uuid,
					characterShape = sm.item.getCharacterShape( currentCarry.uuid ),
					player = player,
					color = player:getCarryColor(),
					shapePlacement = shapePlacement,
					containerA = carryInventory,
					raycastNormal = sm.vec3.new( 0, 0, -1 ),
					aimPosition = spawnPos,
					quantityA = currentCarry.quantity
				},sm.event.types.instant )
			end
		end
	end
end

function SurvivalGame.sv_kickPlayer( self, name )
	local players = sm.player.getAllPlayers()

	for _, player in ipairs( players ) do
		if player:getName() == name then
			sm.game.kickPlayer( player )
		end
	end
end

function SurvivalGame.sv_banPlayer( self, name )
	local players = sm.player.getAllPlayers()

	for _, player in ipairs( players ) do
		if player:getName() == name then
			sm.game.banPlayer( player )
		end
	end
end

function SurvivalGame.sv_e_createUndergroundElevatorDestination( self, params )
	print( "------------------------------------------------" )
	print( "Creating underground elevator destination" )
	print( params )
	print( "------------------------------------------------" )

	assert( params.depth, "Underground elevator destination depth is nil" )
	assert( params.elevatorName, "Underground elevator name is nil" )
	assert( params.connectionTag, "Underground elevator connection tag is nil" )

	if params.depth == 0 then
		if not sm.exists( self.sv.saved.overworld ) then
			sm.world.loadWorld( self.sv.saved.overworld )
		end
		UndergroundElevatorManager.Sv_LoadDestinationWorldCell( self.sv.saved.overworld, params.elevatorName, params.connectionTag )
		return
	end

	if self.sv.undergroundWorlds[params.depth] then
		print( "Underground world already exists, loading..." )
		if not sm.exists( self.sv.undergroundWorlds[params.depth] ) then
			sm.world.loadWorld( self.sv.undergroundWorlds[params.depth] )
		end
	else
		local def = UNDERGROUND_DEFS[params.depth]
		local world = sm.world.createWorld( def.script.file, def.script.class, { depth = params.depth, worldFilePath = def.world }, math.random( 1073741823 ) )
		self.sv.undergroundWorlds[params.depth] = world
		sm.storage.save( STORAGE_CHANNEL_UNDERGROUND_WORLDS, self.sv.undergroundWorlds )
	end
	UndergroundElevatorManager.Sv_LoadDestinationWorldCell( self.sv.undergroundWorlds[params.depth], params.elevatorName, params.connectionTag )
end


function SurvivalGame.sv_createNewPlayer( self, world, x, y, player )
	local params = { player = player, x = x, y = y }
	sm.event.sendToWorld( self.sv.saved.overworld, "sv_spawnNewCharacter", params )
end

function SurvivalGame.sv_spawnEjectedPlayer( self, world, x, y, player )
	local cellPosition = sm.vec3.new( x * 64.0, y * 64.0, 0 )
	local fallbackPosition = cellPosition + sm.vec3.one() * 32.0

	local yaw = 0
	local pitch = 0
	local spawnPosition = nil

	local findEjectNode = function()
		local xMin,xMax,yMin,yMax = GetTileRangesFromCell( x, y, world.id )
		for xit = xMin, xMax, 1 do
			for yit = yMin, yMax, 1 do
				local nodes = sm.cell.getNodesByTag( xit, yit, "WAREHOUSE_EJECT", world )
				if #nodes > 0 then
					local spawnerIndex = ( ( player.id - 1 ) % #nodes ) + 1 -- distribute players over multiple nodes
					local spawnNode = nodes[spawnerIndex]
					local spawnPosition = spawnNode.position + sm.vec3.new( 0, 0, 0.7 )
			
					local spawnDirection = spawnNode.rotation * sm.vec3.new( 0, 0, 1 )
					local spawnYaw = math.atan2( spawnDirection.y, spawnDirection.x ) - math.pi/2
					return spawnPosition, spawnYaw
				end
			end
		end
		return fallbackPosition, yaw
	end
	spawnPosition, yaw = findEjectNode()

	local character = sm.character.createCharacter( player, world, spawnPosition, yaw, pitch )
	player:setCharacter( character )
	character:setTumbling( true )
end

function SurvivalGame.sv_recreatePlayerCharacter( self, world, x, y, player, params )
	local yaw = math.atan2( params.dir.y, params.dir.x ) - math.pi/2
	local pitch = math.asin( params.dir.z )
	local newCharacter
	local pos = params.pos










	if params.world then
		newCharacter = sm.character.createCharacter( player, params.world, pos, yaw, pitch )
	else
		newCharacter = sm.character.createCharacter( player, self.sv.saved.overworld, pos, yaw, pitch )
	end
	player:setCharacter( newCharacter )
	if params.fadeFromBlack then
		sm.event.sendToPlayer( player, "sv_endFadeToBlack", { duration = 2.0, force = true }, sm.event.types.instant )
	end
	print( "Recreate character in new world" )
	print( params )
end











function SurvivalGame.sv_e_recreatePlayerInWorld( self, params )
	local world = params.world
	if not sm.exists( world ) then
		sm.world.loadWorld( world )

	end
	local cellX = math.floor( params.pos.x / 64 )
	local cellY = math.floor( params.pos.y / 64 )
	
	if params.fadeFromBlack then
		sm.event.sendToPlayer( params.player, "sv_endFadeToBlack", { duration = 2.0, force = true }, sm.event.types.instant )
	end

	world:loadCell( cellX, cellY, params.player, "sv_recreatePlayerCharacter", { pos = params.pos, dir = params.dir, world = world } )
end

function SurvivalGame.sv_e_respawn( self, params )
	if params.player.character and sm.exists( params.player.character ) then
		g_respawnManager:sv_requestRespawnCharacter( params.player )
	else
		local spawnPoint = g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
		if not sm.exists( self.sv.saved.overworld ) then
			sm.world.loadWorld( self.sv.saved.overworld )
		end
		self.sv.saved.overworld:loadCell( math.floor( spawnPoint.x/64 ), math.floor( spawnPoint.y/64 ), params.player, "sv_createNewPlayer" )
	end
end

function SurvivalGame.sv_e_warehouseEject( self, params )
	local warehouse = WarehouseManager.Sv_GetWarehouseFromIndex( params.warehouseIndex )
	local spawnCoords
	if warehouse and warehouse.exits and warehouse.exits[1] then
		spawnCoords = warehouse.exits[1]
	else
		sm.log.error( "Failed to find an exit to eject from, for warehouse: ", params.warehouseIndex )
		local spawnPoint = g_survivalDev and SURVIVAL_DEV_SPAWN_POINT or START_AREA_SPAWN_POINT
		spawnCoords = { x = math.floor( spawnPoint.x / 64.0 ), y = math.floor( spawnPoint.y / 64.0 ) }
	end
	if not sm.exists( self.sv.saved.overworld ) then
		sm.world.loadWorld( self.sv.saved.overworld )
	end
	self.sv.saved.overworld:loadCell( spawnCoords.x, spawnCoords.y, params.player, "sv_spawnEjectedPlayer" )
end

function SurvivalGame.sv_loadedRespawnCell( self, world, x, y, player )
	g_respawnManager:sv_respawnCharacter( player, world )
end

function SurvivalGame.sv_e_onSpawnPlayerCharacter( self, player )
	if player.character and sm.exists( player.character ) then
		g_respawnManager:sv_onSpawnCharacter( player )
		g_beaconManager:sv_onSpawnCharacter( player )
	else
		sm.log.warning("SurvivalGame.sv_e_onSpawnPlayerCharacter for a character that doesn't exist")
	end
end

function SurvivalGame.sv_e_markBag( self, params )
	self.network:sendToClient( params.player, "cl_n_markBag", params.bags )
end

function SurvivalGame.cl_n_markBag( self, params )
	g_respawnManager:cl_markBag( params )
end

function SurvivalGame.sv_e_unmarkBag( self, player )
	self.network:sendToClient( player, "cl_n_unmarkBag" )
end

function SurvivalGame.cl_n_unmarkBag( self )
	g_respawnManager:cl_unmarkBag()
end

function SurvivalGame.sv_e_removeBag( self, params )
	self.network:sendToClient( params.player, "cl_e_removeBag", params.bags )
end

function SurvivalGame.cl_e_removeBag( self, params )
	g_respawnManager:cl_removeBag( params )
end

-- Beacons
function SurvivalGame.sv_e_createBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_createBeacon", params )
	else
		sm.log.warning( "SurvivalGame.sv_e_createBeacon in a world that doesn't exist" )
	end
end

function SurvivalGame.sv_e_destroyBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_destroyBeacon", params )
	else
		sm.log.warning( "SurvivalGame.sv_e_destroyBeacon in a world that doesn't exist" )
	end
end

function SurvivalGame.sv_e_unloadBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_unloadBeacon", params )
	else
		sm.log.warning( "SurvivalGame.sv_e_unloadBeacon in a world that doesn't exist" )
	end
end

function SurvivalGame.cl_e_overworldCreated( self, world )
	self.cl.overworld = world
end










































































































































































function SurvivalGame.sv_e_dungeonTransporterLoadFinished( self, params )
	if self.sv.transport then
		for playerId, transport in pairs( self.sv.transport ) do
			if params.world == transport.destinationWorld then
				local newCharacter = sm.character.createCharacter( transport.player, transport.destinationWorld, params.spawnPoint, 0, 0 )
				transport.player:setCharacter( newCharacter )
				self.sv.transport[playerId] = nil
			end
		end
	end
end

function SurvivalGame.sv_e_grantAdditionalRewards( self, rewardList )
	self.network:sendToClients( "cl_n_grantAdditionalRewards", rewardList )
end

function SurvivalGame.sv_e_grantAdditionalRewardsForPlayer( self, args  )
	self.network:sendToClient( args.player, "cl_n_grantAdditionalRewards", args.rewardList )
end

function SurvivalGame.cl_n_grantAdditionalRewards( self, rewardList )
	Cl_GrantAdditionalItems( rewardList )
end
