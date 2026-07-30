-- [SurvivalTweaks] Vanilla 1.0 CreativeGame.lua patched with Survival Tweaks
-- (adds /export and /import so blueprints can be shared with survival)
dofile( "$GAME_DATA/Scripts/game/managers/EffectManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/UnitManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/KinematicManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/TileStorageManager.lua" )
dofile( "$GAME_DATA/Scripts/game/managers/WeatherManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/recipes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_meleeattacks.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/WorldManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/scriptableObjects/GlowstickManager.lua" )




-- [SurvivalTweaks] blueprint lookup - same rules as survival's SurvivalGame.lua:
-- a creation saved on a lift wins, an /export file is the fallback. See the longer
-- explanation there; in short, $CONTENT_<localId> is the alias the engine gives every
-- saved blueprint, and _userblueprints.json maps names to those ids because script
-- cannot list a directory.
local USER_BLUEPRINT_INDEX = "$SURVIVAL_DATA/LocalBlueprints/_userblueprints.json"
local EXPORT_DIR = "$SURVIVAL_DATA/LocalBlueprints/Exported/"

local function blueprintKey( name )
	return ( tostring( name ):lower():gsub( "[^%w]", "" ) )
end

local function fileExists( path )
	local ok, exists = pcall( sm.json.fileExists, path )
	if ok then return exists == true end
	-- fallback if sm.json.fileExists is not callable from here; see SurvivalGame.lua
	local opened, data = pcall( sm.json.open, path )
	return opened and type( data ) == "table"
end

local function resolveBlueprint( name )
	if name == nil or name == "" then return nil end
	name = tostring( name )
	local wanted = blueprintKey( name )
	if wanted == "" then return nil end

	local ok, index = pcall( sm.json.open, USER_BLUEPRINT_INDEX )
	if ok and type( index ) == "table" and type( index.blueprints ) == "table" then
		for _, entry in ipairs( index.blueprints ) do
			if type( entry ) == "table" and entry.id and blueprintKey( entry.key or entry.name or "" ) == wanted then
				local path = "$CONTENT_" .. tostring( entry.id ) .. "/blueprint.json"
				if fileExists( path ) then return path, tostring( entry.name or name ) end
			end
		end
	end

	if string.find( name, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$" ) then
		local path = "$CONTENT_" .. name .. "/blueprint.json"
		if fileExists( path ) then return path, name end
	end

	local exported = EXPORT_DIR .. name .. ".blueprint"
	if fileExists( exported ) then return exported, name, "export" end

	local legacy = "$SURVIVAL_DATA/LocalBlueprints/" .. name .. ".blueprint"
	if fileExists( legacy ) then return legacy, name, "asset" end

	return nil
end

-- [SurvivalTweaks] body "type" 0 is dynamic, 1 is static; a lift-saved blueprint omits
-- the field and the engine then treats it as static, so the creation imports frozen.
-- See the longer explanation in SurvivalGame.lua.
local function forceDynamicBodies( data, source )
	for _, body in ipairs( data.bodies or {} ) do
		if source == "asset" then
			if body.type == nil then body.type = 0 end
		elseif body.type ~= 0 then
			body.type = 0
		end
	end
end

CreativeGame = class( nil )
CreativeGame.enableLimitedInventory = false
CreativeGame.enableRestrictions = true
CreativeGame.enableFuelConsumption = false
CreativeGame.enableAmmoConsumption = false
CreativeGame.enableUpgrade = true
CreativeGame.enableRecipes = false

local TimeSyncInterval = 400
local WeatherConditions = {
	rain = "Rain",
	thunder = "ThunderRain",
	clear = "Clear",
	cloudy = "Clouds01",
	drizzle = "Drizzle",
}

function CreativeGame.server_onCreate( self )
	self.sv = {}

	g_kinematicManager = KinematicManager()
	g_kinematicManager:sv_onCreate()

	g_unitManager = UnitManager()
	g_unitManager:sv_onCreate( nil, { aggroCreations = true } )

	g_beaconManager = BeaconManager()
	g_beaconManager:sv_onCreate()

	WorldManager.Sv_OnCreate()

	self.sv.weatherManager = sm.scriptableObject.createScriptableObject( sm.uuid.new( "46e23051-c20b-4929-9df1-7f4f838a3802" ), { permanentForecast = "CloudyDay", resetForecast = true } )

	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		local legacyCreativeWorld = sm.world.getLegacyCreativeWorld()
		if legacyCreativeWorld then
			self.sv.saved = {}
			self.sv.saved.data = self.data
			self.sv.saved.world = legacyCreativeWorld
			self.storage:save( self.sv.saved )
		else
			self.sv.saved = {}
			self.sv.saved.data = self.data
			self.sv.saved.world = sm.world.createWorld( self.worldScriptFilename, self.worldScriptClass, { worldFile = self.data.worldFile }, self.data.seed )
			self.storage:save( self.sv.saved )
		end
	end

	if not sm.exists( self.sv.saved.world ) then
		sm.world.loadWorld( self.sv.saved.world )
	end

	self.sv.time = sm.storage.load( STORAGE_CHANNEL_TIME )
	if self.sv.time then
		print( "Loaded timeData:" )
		print( self.sv.time )
	else
		self.sv.time = { timeOfDay = 0.5, timeProgress = false }
	end
	self.sv.time.timeProgress = self.sv.time.timeProgress or false
	self.sv.timeSyncTick = 0
	sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )

	self.network:setClientData( { time = self.sv.time } )

	self:loadCraftingRecipes()
	g_godMode = true
	g_disableScrapHarvest = true
end

function CreativeGame.loadCraftingRecipes( self )
	local recipeSets = sm.json.open( "$SURVIVAL_DATA/CraftingRecipes/craftbot/craftbot.json" )
	recipeSets.sawtable = "$SURVIVAL_DATA/CraftingRecipes/sawtable.json"
	recipeSets.portablecrafter = "$SURVIVAL_DATA/CraftingRecipes/portablecrafter.json"
	LoadCraftingRecipes( recipeSets )
end

function CreativeGame.server_onFixedUpdate( self, timeStep )
	if self.sv.time.timeProgress then
		self.sv.time.timeOfDay = self.sv.time.timeOfDay + ( timeStep / DAYCYCLE_TIME )
	end

	WeatherManager.Sv_SetTimeOfDay( self.sv.time.timeOfDay )

	self.sv.timeSyncTick = self.sv.timeSyncTick + 1
	if self.sv.timeSyncTick >= TimeSyncInterval then
		self.sv.timeSyncTick = 0
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
		self.network:setClientData( { time = self.sv.time } )
	end

	g_unitManager:sv_onFixedUpdate()
end

function CreativeGame.server_onPlayerJoined( self, player, newPlayer )
	WeatherManager.Sv_PlayerJoined( player )
	if newPlayer then
		self.sv.saved.world:loadCell( 0, 0, player, "sv_createNewPlayer" )
	end
end

function CreativeGame.sv_createNewPlayer( self, world, x, y, player )
	local params = { player = player, x = 16, y = 16 }
	sm.event.sendToWorld( self.sv.saved.world, "sv_e_spawnNewCharacter", params )
end

function CreativeGame.client_onCreate( self )
	if not sm.isHost then
		self:loadCraftingRecipes()
	end

	self.cl = { time = { timeOfDay = 0.5, timeProgress = false } }

	WorldManager.Cl_OnCreate()
	self.cl.renderManager = sm.clientScriptableObject.createScriptableObject( sm.uuid.new( "54563daa-dd25-4f43-9e49-7e58bd59f66a" ) )
	
	g_radioTransmitter = sm.effect.createEffect( "Radio - Transmitter" )
	g_radioTransmitter:setWorldAny()
	g_boomboxTransmitter = sm.effect.createEffect( "Boombox - Transmitter" )
	g_boomboxTransmitter:setWorldAny()

	sm.game.bindChatCommand( "/noaggro", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles the player as a target" )
	sm.game.bindChatCommand( "/noaggrocreations", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles whether the Tapebots will shoot at creations" )
	sm.game.bindChatCommand( "/aggroall", {}, "cl_onChatCommand", "All hostile units will be made aware of the player's position" )
	sm.game.bindChatCommand( "/popcapsules", { { "string", "filter", true } }, "cl_onChatCommand", "Opens all capsules. An optional filter controls which type of capsules to open: 'bot', 'animal'" )
	sm.game.bindChatCommand( "/killall", {}, "cl_onChatCommand", "Kills all spawned units" )
	sm.game.bindChatCommand( "/dropscrap", {}, "cl_onChatCommand", "Toggles the scrap loot from Haybots" )
	sm.game.bindChatCommand( "/place", { { "string", "harvestable", false } }, "cl_onChatCommand", "Places a harvestable at the aimed position. Must be placed on the ground. The harvestable parameter controls which harvestable to place: 'stone', 'tree', 'birch', 'leafy', 'spruce', 'pine'" )
	sm.game.bindChatCommand( "/restrictions", { { "bool", "enable", true } }, "cl_onChatCommand", "Toggles restrictions on creations" )
	sm.game.bindChatCommand( "/timeofday", { { "number", "timeOfDay", true } }, "cl_onChatCommand", "Sets the time of the day as a fraction (0.5=mid day)" )
	sm.game.bindChatCommand( "/timeprogress", { { "bool", "enabled", true } }, "cl_onChatCommand", "Enables or disables time progress" )
	sm.game.bindChatCommand( "/weather", { { "string", "condition", false, { "rain", "thunder", "clear", "cloudy", "drizzle" } } }, "cl_onChatCommand", "Sets the weather condition" )
	sm.game.bindChatCommand( "/day", {}, "cl_onChatCommand", "Sets time of day to day" )
	sm.game.bindChatCommand( "/night", {}, "cl_onChatCommand", "Sets time of day to night" )

	-- [SurvivalTweaks] blueprint exchange with survival
	-- pcall-protected: a name collision is logged and falls back to /bp* instead of
	-- aborting all remaining bindings.
	local function bindModCommand( names, args, help )
		for _, name in ipairs( names ) do
			local ok, err = pcall( sm.game.bindChatCommand, name, args, "cl_onChatCommand", help )
			if ok then
				sm.log.info( "[SurvivalTweaks] bound " .. name )
				return name
			end
			sm.log.warning( "[SurvivalTweaks] could not bind " .. name .. ": " .. tostring( err ) )
		end
		return nil
	end
	-- the extra optional words let a blueprint saved as "Car mk1" be typed as-is
	bindModCommand( { "/export", "/bpexport" }, { { "string", "name", false } }, "Exports aimed creation to $SURVIVAL_DATA/LocalBlueprints/Exported/<name>.blueprint" )
	bindModCommand( { "/import", "/bpimport" }, { { "string", "name", false }, { "string", "...", true }, { "string", "...", true }, { "string", "...", true } }, "Places <name> - one of your saved blueprints, or an /export" )











	if sm.isHost then
		self.clearEnabled = false
		sm.game.bindChatCommand( "/allowclear", { { "bool", "enable", true } }, "cl_onChatCommand", "Enabled/Disables the /clear command" )
		sm.game.bindChatCommand( "/clear", {}, "cl_onChatCommand", "Remove all shapes in the world. It must first be enabled with /allowclear" )
	end

	if g_unitManager == nil then
		assert( not sm.isHost )
		g_unitManager = UnitManager()
	end

	if g_beaconManager == nil then
		assert( not sm.isHost )
		g_beaconManager = BeaconManager()
	end
	g_beaconManager:cl_onCreate()

	-- Compass HUD
	self.cl.compassEnabled = sm.game.getSettingBoolean( "CompassHud" )
	g_compassHud = sm.gui.createCompassHudGui()
	assert(g_compassHud)
	self:cl_compassHudEnable( self.cl.compassEnabled )
end

function CreativeGame.client_onFixedUpdate( self, dt )
	local compassSetting = sm.game.getSettingBoolean( "CompassHud" )
	if self.cl.compassEnabled ~= compassSetting then
		self.cl.compassEnabled = compassSetting
		self:cl_compassHudEnable( self.cl.compassEnabled )
	end
end

function CreativeGame.cl_compassHudEnable( self, enable )
	if enable == true then
		g_compassHud:open()
	else
		g_compassHud:close()
	end
end

function CreativeGame.client_onClientDataUpdate( self, clientData )
	self.cl.time = clientData.time
	self:cl_updateTimeOfDay()
end

function CreativeGame.client_onUpdate( self, dt )
	if self.cl.time.timeProgress then
		self.cl.time.timeOfDay = self.cl.time.timeOfDay + ( dt / DAYCYCLE_TIME )
	end
	self:cl_updateTimeOfDay()
end

function CreativeGame.cl_updateTimeOfDay( self )
	local timeOfDay = math.fmod( self.cl.time.timeOfDay, 1 )
	sm.game.setTimeOfDay( timeOfDay )

	local index = 1
	while index < #DAYCYCLE_LIGHTING_TIMES and timeOfDay >= DAYCYCLE_LIGHTING_TIMES[index + 1] do
		index = index + 1
	end

	local light = DAYCYCLE_LIGHTING_VALUES[index]
	if index < #DAYCYCLE_LIGHTING_TIMES then
		local fraction = ( timeOfDay - DAYCYCLE_LIGHTING_TIMES[index] ) / ( DAYCYCLE_LIGHTING_TIMES[index + 1] - DAYCYCLE_LIGHTING_TIMES[index] )
		light = sm.util.lerp( DAYCYCLE_LIGHTING_VALUES[index], DAYCYCLE_LIGHTING_VALUES[index + 1], fraction )
	end
	sm.render.setOutdoorLighting( light )

	if WeatherManager.Get() then
		WeatherManager.Get():cl_setTimeOfDay( self.cl.time.timeOfDay )
	end
end

function CreativeGame.client_showMessage( self, params )
	sm.gui.chatMessage( params )
end

function CreativeGame.client_onLoadingScreenLifted( self )
	EffectManager.Cl_OnLoadingScreenLifted()
end

function CreativeGame.client_onUnstuck( self )
	sm.event.sendToPlayer( sm.localPlayer.getPlayer(), "cl_e_unstuck" )
end

function CreativeGame.cl_onClearConfirmButtonClick( self, name )
	if name == "Yes" then
		self.cl.confirmClearGui:close()
		self.network:sendToServer( "sv_clear" )
	elseif name == "No" then
		self.cl.confirmClearGui:close()
	end
	self.cl.confirmClearGui = nil
end

function CreativeGame.sv_clear( self, _, player )
	if player.character and sm.exists( player.character ) then
		sm.event.sendToWorld( player.character:getWorld(), "sv_e_clear" )
	end
end

function CreativeGame.cl_onChatCommand( self, params )
	if params[1] == "/place" then
		local range = 7.5
		local success, result = sm.localPlayer.getRaycast( range )
		if success then
			params.aimPosition = result.pointWorld
		else
			params.aimPosition = sm.localPlayer.getRaycastStart() + sm.localPlayer.getDirection() * range
		end
		self.network:sendToServer( "sv_n_onChatCommand", params )
	elseif params[1] == "/allowclear" then
		local clearEnabled = not self.clearEnabled
		if type( params[2] ) == "boolean" then
			clearEnabled = params[2]
		end
		self.clearEnabled = clearEnabled
		sm.gui.chatMessage( "/clear is " .. ( self.clearEnabled and "Enabled" or "Disabled" ) )
	elseif params[1] == "/clear" then
		if self.clearEnabled then
			self.clearEnabled = false
			self.cl.confirmClearGui = sm.gui.createGuiFromLayout( "$GAME_DATA/Gui/Layouts/PopUp/PopUp_YN.layout" )
			self.cl.confirmClearGui:setButtonCallback( "Yes", "cl_onClearConfirmButtonClick" )
			self.cl.confirmClearGui:setButtonCallback( "No", "cl_onClearConfirmButtonClick" )
			self.cl.confirmClearGui:setText( "Title", "#{MENU_YN_TITLE_ARE_YOU_SURE}" )
			self.cl.confirmClearGui:setText( "Message", "#{MENU_YN_MESSAGE_CLEAR_MENU}" )
			self.cl.confirmClearGui:open()
		else
			sm.gui.chatMessage( "/clear is disabled. It must first be enabled with /allowclear" )
		end
	-- [SurvivalTweaks] blueprint export/import
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
	elseif params[1] == "/import" or params[1] == "/bpimport" then
		-- the name arrives split across arguments when it contains spaces
		local nameParts = {}
		for i = 2, #params do
			if type( params[i] ) == "string" and params[i] ~= "" then
				nameParts[#nameParts + 1] = params[i]
			end
		end

		local rayCastValid, rayCastResult = sm.localPlayer.getRaycast( 100 )
		if rayCastValid then
			self.network:sendToServer( "sv_importCreation", {
				world = sm.localPlayer.getPlayer().character:getWorld(),
				name = table.concat( nameParts, " " ),
				position = rayCastResult.pointWorld
			} )
		else
			sm.gui.chatMessage( "#ff0000Aim at the ground where the creation should be placed" )
		end



























	else
		self.network:sendToServer( "sv_n_onChatCommand", params )
	end
end







function CreativeGame.sv_n_onChatCommand( self, params, player )
	if params[1] == "/noaggro" then
		local aggro = not sm.game.getEnableAggro()
		if type( params[2] ) == "boolean" then
			aggro = not params[2]
		end
		sm.game.setEnableAggro( aggro )
		self.network:sendToClients( "client_showMessage", "AGGRO: " .. ( aggro and "On" or "Off" ) )
	elseif params[1] == "/noaggrocreations" then
		local aggroCreations = not g_unitManager:sv_getHostSettings().aggroCreations
		if type( params[2] ) == "boolean" then
			aggroCreations = not params[2]
		end
		g_unitManager:sv_setHostSettings( { aggroCreations = aggroCreations } )
		self.network:sendToClients( "client_showMessage", "AGGRO CREATIONS: " .. ( aggroCreations and "On" or "Off" ) )
	elseif params[1] == "/popcapsules" then
		g_unitManager:sv_openCapsules( params[2] )
	elseif params[1] == "/dropscrap" then
		local disableScrapHarvest = not g_disableScrapHarvest
		if type( params[2] ) == "boolean" then
			disableScrapHarvest = not params[2]
		end
		g_disableScrapHarvest = disableScrapHarvest
		self.network:sendToClients( "client_showMessage", "SCRAP LOOT: " .. ( g_disableScrapHarvest and "Off" or "On" ) )
	elseif params[1] == "/restrictions" then
		local restrictions = not sm.game.getEnableRestrictions()
		if type( params[2] ) == "boolean" then
			restrictions = params[2]
		end
		sm.game.setEnableRestrictions( restrictions )
		self.network:sendToClients( "client_showMessage", "RESTRICTIONS: " .. ( restrictions and "On" or "Off" ) )
	elseif params[1] == "/timeofday" then
		self:sv_setTimeOfDay( params[2] )
	elseif params[1] == "/timeprogress" then
		self:sv_setTimeProgress( params[2] )
	elseif params[1] == "/weather" then
		local condition = WeatherConditions[string.lower( params[2] )]
		if condition then
			WeatherManager.Sv_StartCondition( condition )
			self.network:sendToClients( "client_showMessage", "Weather: " .. params[2] )
		end
	elseif params[1] == "/day" then
		self:sv_setTimeOfDay( 0.5 )
	elseif params[1] == "/night" then
		self:sv_setTimeOfDay( 0.0 )
	else
		if sm.exists( player.character ) then
			params.player = player
			sm.event.sendToWorld( player.character:getWorld(), "sv_e_onChatCommand", params )
		end
	end
end

function CreativeGame.sv_setTimeOfDay( self, timeOfDay )
	if timeOfDay ~= nil then
		self.sv.time.timeOfDay = math.floor( self.sv.time.timeOfDay ) + sm.util.clamp( timeOfDay, 0.0, 0.9999 )
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
		self.network:setClientData( { time = self.sv.time } )
	end
	self.network:sendToClients( "client_showMessage", "Time of day set to " .. self.sv.time.timeOfDay )
end

function CreativeGame.sv_setTimeProgress( self, timeProgress )
	if timeProgress ~= nil then
		self.sv.time.timeProgress = timeProgress
		sm.storage.save( STORAGE_CHANNEL_TIME, self.sv.time )
		self.network:setClientData( { time = self.sv.time } )
	end
	self.network:sendToClients( "client_showMessage", "Time progress: " .. ( self.sv.time.timeProgress and "On" or "Off" ) )
end

-- [SurvivalTweaks] blueprint export/import server side
function CreativeGame.sv_exportCreation( self, params )
	local target = EXPORT_DIR..params.name..".blueprint"

	local success, existing = pcall( sm.json.open, target )
	if success and existing then
		sm.json.save( existing, EXPORT_DIR..params.name.."_backup.blueprint" )
		self.network:sendToClients( "client_showMessage", "A blueprint named '"..params.name.."' already existed and was backed up as '"..params.name.."_backup'" )
	end
	local obj = sm.json.parseJsonString( sm.creation.exportToString( params.body ) )
	sm.json.save( obj, target )
	self.network:sendToClients( "client_showMessage", "Exported #00ff00"..params.name )
end

function CreativeGame.sv_importCreation( self, params )
	local path, displayName, source = resolveBlueprint( params.name )
	if not path then
		return self.network:sendToClients( "client_showMessage", "#ff0000No blueprint or export named '"..tostring( params.name ).."'" )
	end
	local opened, data = pcall( sm.json.open, path )
	if not opened or type( data ) ~= "table" or not data.bodies then
		self.network:sendToClients( "client_showMessage", "#ff0000Blueprint '"..tostring( displayName ).."' could not be read!" )
		return
	end
	forceDynamicBodies( data, source )

	-- import from the parsed table, so the corrected body types reach the engine
	local status, bodies = pcall( sm.creation.importFromString, params.world, sm.json.writeJsonString( data ), params.position, sm.quat.identity() )
	if status == false then
		self.network:sendToClients( "client_showMessage", "#ff0000Could not import '"..tostring( displayName ).."' (it may contain parts this mode does not have)" )
		return
	end
	for _, body in ipairs( bodies or {} ) do
		pcall( body.setConvertibleToDynamic, body, true )
	end
end

-- Beacons
function CreativeGame.sv_e_createBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_createBeacon", params )
	else
		sm.log.warning( "CreativeGame.sv_e_createBeacon in a world that doesn't exist" )
	end
end

function CreativeGame.sv_e_destroyBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_destroyBeacon", params )
	else
		sm.log.warning( "CreativeGame.sv_e_destroyBeacon in a world that doesn't exist" )
	end
end

function CreativeGame.sv_e_unloadBeacon( self, params )
	if sm.exists( params.beacon.world ) then
		sm.event.sendToWorld( params.beacon.world, "sv_e_unloadBeacon", params )
	else
		sm.log.warning( "CreativeGame.sv_e_unloadBeacon in a world that doesn't exist" )
	end
end

CreativeFlatGame = class( CreativeGame )
CreativeFlatGame.worldScriptFilename = "$GAME_DATA/Scripts/game/worlds/CreativeFlatWorld.lua";
CreativeFlatGame.worldScriptClass = "CreativeFlatWorld";

ClassicCreativeGame = class( CreativeGame )
ClassicCreativeGame.worldScriptFilename = "$GAME_DATA/Scripts/game/worlds/ClassicCreativeTerrainWorld.lua";
ClassicCreativeGame.worldScriptClass = "ClassicCreativeTerrainWorld";

CreativeCustomGame = class( CreativeGame )
CreativeCustomGame.worldScriptFilename = "$GAME_DATA/Scripts/game/worlds/CreativeCustomWorld.lua";
CreativeCustomGame.worldScriptClass = "CreativeCustomWorld";

CreativeTerrainGame = class( CreativeGame )
CreativeTerrainGame.worldScriptFilename = "$GAME_DATA/Scripts/game/worlds/CreativeTerrainWorld.lua";
CreativeTerrainGame.worldScriptClass = "CreativeTerrainWorld";