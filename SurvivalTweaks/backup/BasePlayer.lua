dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_items.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/util/Timer.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/managers/QuestManager.lua" )
dofile( "$SURVIVAL_DATA/Scripts/camera_util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/SurvivalPlayer.lua" )

---@class BasePlayer : PlayerClass
---@field sv table
---@field cl table
BasePlayer = class( nil )

local FireDamage = 10
local FireDamageCooldown = 40
local PoisonDamage = 10
local PoisonDamageCooldown = 40
local RadiationDamage = 1
local RadiationDamageCooldown = 20

local VelocityBufferCount = 8

-- Tumble recovery
local StopTumbleSpeedThreshold = 2.5 -- Tumble will start to recover at or below this speed threshold
local StopTumbleTimerTickThreshold = 40 -- Time to recover from tumble while the speed is below the threshold, acts as default tumble
local StopTumbleSuspendedTickThreshold = 3.0 * 40 -- Tumble will recover while not touching anything, after this amount of time
-- Tumble resist
local MaxTumbleTimerTickThreshold = 8.0 * 40 -- Maximum time to keep tumble active before forcing recovery
local TumbleResistTickTime = 3.0 * 40 -- Time that the player will resist tumbling after timing out
local MaxRecentTumbles = 10 -- Ignore tumbles when this amount of tumbles already happened recently
local RecentTumblesTickTimeInterval = 30.0 * 40 -- Time frame to count amount of tumbles that has happened recently

local MaxTumbleImpulseSpeed = 35 -- Max allowed tumble speed inherited from a collision

local ProjectileToEdibleShape = {
	[tostring(projectile_banana)] = ITEMS.obj_plantables_banana,
	[tostring(projectile_blueberry)] = ITEMS.obj_plantables_blueberry,
	[tostring(projectile_orange)] = ITEMS.obj_plantables_orange,
	[tostring(projectile_pineapple)] = ITEMS.obj_plantables_pineapple,
	[tostring(projectile_carrot)] = ITEMS.obj_plantables_carrot,
	[tostring(projectile_redbeet)] = ITEMS.obj_plantables_redbeet,
	[tostring(projectile_tomato)] = ITEMS.obj_plantables_tomato,
	[tostring(projectile_broccoli)] = ITEMS.obj_plantables_broccoli,
}

function BasePlayer.server_onCreate( self )
	self.sv = {}
	self.sv.saved = self.storage:load()
	if self.sv.saved == nil then
		self.sv.saved = {}
		self.sv.saved.inChemical = false
		self.sv.saved.inOil = false
		self.storage:save( self.sv.saved )
	end
	self:sv_init()
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.server_onRefresh( self )
	self:sv_init()
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_init( self )
	if self.player.publicData == nil then
		self.player.publicData = {}
	end

	self.sv.damageCooldown = Timer()
	self.sv.damageCooldown:start( 3.0 * 40 )

	self.sv.impactCooldown = Timer()
	self.sv.impactCooldown:start( 3.0 * 40 )

	self.sv.fireDamageCooldown = Timer()
	self.sv.fireDamageCooldown:start()

	self.sv.poisonDamageCooldown = Timer()
	self.sv.poisonDamageCooldown:start()

	self.sv.radiationDamageCooldown = Timer()
	self.sv.radiationDamageCooldown:start()

	self.sv.tumbleReset = Timer()
	self.sv.tumbleReset:start( StopTumbleTimerTickThreshold )

	self.sv.collisionTumbleImmunity = Timer()
	self.sv.collisionTumbleImmunity:start()

	self.sv.tumbleSuspendedReset = Timer()
	self.sv.tumbleSuspendedReset:start( StopTumbleSuspendedTickThreshold )

	self.sv.maxTumbleTimer = Timer()
	self.sv.maxTumbleTimer:start( MaxTumbleTimerTickThreshold )

	self.sv.resistTumbleTimer = Timer()
	self.sv.resistTumbleTimer:start( TumbleResistTickTime )
	self.sv.resistTumbleTimer.count = TumbleResistTickTime

	self.sv.velocityBuffer = {}
	self.sv.velocityBufferIndex = 1

	self.sv.recentTumbles = {}
end

function BasePlayer.client_onCreate( self )
	self.cl = {}
	self:cl_init()
	self.cl.cameraState = CameraState.DEFAULT
	self.player.clientPublicData = {}
end

function BasePlayer.client_onRefresh( self )
	self:cl_init()
	sm.gui.hideGui( false )
	sm.camera.setCameraState( sm.camera.state.default )
	sm.localPlayer.setLockedControls( false )
end

function BasePlayer.cl_init( self ) end

function BasePlayer.cl_n_onEvent( self, data )

	local function getCharParam()
		if self.player:isMale() then
			return 1
		else
			return 2
		end
	end

	local function playSingleHurtSound( effect, pos, damage )
		local params = {
			["char"] = getCharParam(),
			["damage"] = damage
		}
		sm.effect.playEffect( effect, pos, sm.vec3.zero(), sm.quat.identity(), sm.vec3.one(), params )
	end

	if data.event == "drown" then
		playSingleHurtSound( "Mechanic - HurtDrown", data.pos, data.damage )
	elseif data.event == "fatigue" then
		playSingleHurtSound( "Mechanic - Hurthunger", data.pos, data.damage)
	elseif data.event == "shock" then
		playSingleHurtSound( "Mechanic - Hurtshock", data.pos, data.damage )
	elseif data.event == "impact" then
		playSingleHurtSound( "Mechanic - Hurt", data.pos, data.damage )
	elseif data.event == "scannerbot" then
		playSingleHurtSound( "Mechanic - Hurt", data.pos, data.damage )
	elseif data.event == "fire" then
		playSingleHurtSound( "Mechanic - HurtFire", data.pos, data.damage )
	elseif data.event == "poison" then
		playSingleHurtSound( "Mechanic - Hurtpoision", data.pos, data.damage )
	elseif data.event == "radiation" then
		playSingleHurtSound( "Mechanic - HurtRadiation", data.pos, data.damage )
	end
end

function BasePlayer.client_onClientDataUpdate( self, data )
	if sm.localPlayer.getPlayer() == self.player then
		self.cl.inChemical = data.inChemical
		self.cl.inOil = data.inOil
	end
end

function BasePlayer.client_onUpdate( self, dt )
	if self.player == sm.localPlayer.getPlayer() then
		self:cl_localPlayerUpdate( dt )
	end
end

function BasePlayer.cl_localPlayerUpdate( self, dt )
	local character = self.player:getCharacter()

	local alwaysUpdate = false
	local wantedCameraState = CameraState.DEFAULT
	local wantedCameraData = {
		hideGui = false,
		cameraState = sm.camera.state.default,
		lockedControls = false
	}

	if self.player.clientPublicData.cutsceneCameraData and self.player.clientPublicData.cutsceneCameraData.distance < MAX_CINEMATIC_DISTANCE then
		wantedCameraState = CameraState.CUTSCENE
		wantedCameraData = self.player.clientPublicData.cutsceneCameraData
		alwaysUpdate = true
	elseif self.player.clientPublicData.interactableCameraData then
		wantedCameraState = CameraState.INTERACTABLE
		wantedCameraData = self.player.clientPublicData.interactableCameraData
		alwaysUpdate = true
	elseif self.player.clientPublicData.customCameraData then
		wantedCameraState = CameraState.CUSTOM
		wantedCameraData = self.player.clientPublicData.customCameraData
		alwaysUpdate = true
		self.player.clientPublicData.customCameraData = nil
	elseif self.player.clientPublicData.seatLockedCameraData then
		wantedCameraState = CameraState.SEAT_LOCKED_CAMERA
		wantedCameraData = self.player.clientPublicData.seatLockedCameraData
		alwaysUpdate = true
	elseif character and character:isTumbling() then
		wantedCameraState = CameraState.TUMBLING
		wantedCameraData.cameraState = sm.camera.state.forcedTP
	end

	if self.cl.cameraState ~= wantedCameraState or alwaysUpdate then
		self.cl.cameraState = wantedCameraState
		SetWantedCameraData( wantedCameraData )
	end

	if character and character:isSwimming() and not self.cl.inChemical and not self.cl.inOil then
		self:cl_n_fillWater()
	end
end

function BasePlayer.client_onInteract( self, character, state )
end

function BasePlayer.server_onFixedUpdate( self, dt )
	local character = self.player:getCharacter()
	if character then
		self:sv_updateTumbling()

		self.sv.velocityBufferIndex = self.sv.velocityBufferIndex + 1
		if self.sv.velocityBufferIndex > VelocityBufferCount then
			self.sv.velocityBufferIndex = 1
		end
		self.sv.velocityBuffer[self.sv.velocityBufferIndex] = character:getVelocity()
	end

	self.sv.damageCooldown:tick()
	self.sv.impactCooldown:tick()
	self.sv.fireDamageCooldown:tick()
	self.sv.poisonDamageCooldown:tick()
	self.sv.collisionTumbleImmunity:tick()
	self.sv.radiationDamageCooldown:tick()
end

function BasePlayer.client_onFixedUpdate( self, dt )
	local character = self.player:getCharacter()
	if character then
		self:cl_updateTumbling()
	end
end

function BasePlayer.cl_updateTumbling( self )
	if self.player.character:isTumbling() then
		-- Remember the tumbling velocity
		self.cl.lastTumblingVelocity = self.player.character:getTumblingLinearVelocity()
	elseif self.cl.lastTumblingVelocity then
		-- Apply the tumbling velocity to the recovered character
		local tumbleDirection = self.cl.lastTumblingVelocity:safeNormalize( sm.vec3.new( 0, 0, 1 ) )
		local tumbleImpulse = self.cl.lastTumblingVelocity:length() * self.player.character.mass
		sm.physics.applyImpulse( self.player.character, tumbleDirection * tumbleImpulse )
		self.cl.lastTumblingVelocity = nil
	end
end

function BasePlayer.server_onProjectile( self, hitPos, hitTime, hitVelocity, _, attacker, damage, userData, hitNormal, projectileUuid )
	if type( attacker ) == "Unit" or ( type( attacker ) == "Shape" and isTrapProjectile( projectileUuid ) ) or ( userData and userData.damagePlayer ) then
		local source = "shock"
		if projectileUuid == projectile_tape or projectileUuid == projectile_bubblewrap then
			source = "tapebotprojectile"
		end
		self:sv_takeDamage( damage, source, projectileUuid )
	end
	if self.player.character:isTumbling() then
		ApplyKnockback( self.player.character, hitVelocity:normalize(), 2000 )
	end

	if projectileUuid == projectile_water  then
		self.network:sendToClient( self.player, "cl_n_fillWater" )
	end

	if isGoopProjectile( projectileUuid ) then
		sm.event.sendToCharacter( self.player.character, "sv_e_addStatusEffect", { status = "goop", strength = 1 } )
	end

	local edibleShape = ProjectileToEdibleShape[tostring( projectileUuid )]
	if edibleShape then
		local edible = sm.item.getEdible( edibleShape )
		if edible then
			self:sv_e_eat( edible )
		end
	end
end

function BasePlayer.cl_n_fillWater( self )
	if self.player == sm.localPlayer.getPlayer() then
		if sm.localPlayer.getActiveItem() == ITEMS.obj_tool_bucket_empty then
			local params = {}
			if sm.game.getLimitedInventory() then
				params.playerInventory = sm.localPlayer.getInventory()
			else
				params.playerInventory = sm.localPlayer.getHotbar()
			end
			params.slotIndex = sm.localPlayer.getSelectedHotbarSlot()
			params.previousUid = ITEMS.obj_tool_bucket_empty
			params.nextUid = ITEMS.obj_tool_bucket_water
			params.previousQuantity = 1
			params.nextQuantity = 1
			self.network:sendToServer( "sv_n_exchangeItem", params )
		end
	end
end

function BasePlayer.server_onMelee( self, hitPos, attacker, damage, power, hitDirection )
	if not sm.exists( attacker ) then
		return
	end

	if type( attacker ) == "Unit" then
		self:sv_takeDamage( damage, "impact" )
	else
		local playerCharacter = self.player.character
		if sm.exists( playerCharacter ) then
			self.network:sendToClients( "cl_n_onEvent", { event = "impact", pos = playerCharacter.worldPosition, damage = damage * 0.01 } )
		end
	end

	-- Melee impulse
	if attacker then
		ApplyKnockback( self.player.character, hitDirection, power )
	end

end

function BasePlayer.server_onExplosion( self, center, _, _, damage, src, srcTypeUid )
	local source = "impact"
	if srcTypeUid == unit_minerbot or srcTypeUid == ITEMS.obj_robotparts_minerbot_thruster then
		source = "minerbotexplosion"
	end
	self:sv_takeDamage( damage, source )
	if self.player.character:isTumbling() then
		local knockbackDirection = ( self.player.character.worldPosition - center ):safeNormalize( sm.vec3.new( 0, 0, 1 ) )
		ApplyKnockback( self.player.character, knockbackDirection, 5000 )
	end
end

function BasePlayer.sv_startTumble( self, tumbleTickTime )
	if not self.player.character:isDowned() and self.sv.resistTumbleTimer:done() then
		local currentTick = sm.game.getCurrentTick()
		self.sv.recentTumbles[#self.sv.recentTumbles+1] = currentTick
		local recentTumbles = {}
		for _, tumbleTickTimestamp in ipairs( self.sv.recentTumbles ) do
			if tumbleTickTimestamp >= currentTick - RecentTumblesTickTimeInterval then
				recentTumbles[#recentTumbles+1] = tumbleTickTimestamp
			end
		end
		self.sv.recentTumbles = recentTumbles
		if #self.sv.recentTumbles > MaxRecentTumbles then
			-- Too many tumbles in quick succession, gain temporary tumble immunity
			self.player.character:setTumbling( false )
			self.sv.maxTumbleTimer:reset()
			self.sv.tumbleReset:reset()
			self.sv.tumbleSuspendedReset:reset()
			self.sv.resistTumbleTimer:reset()
		else
			self.player.character:setTumbling( true )
			if tumbleTickTime then
				self.sv.tumbleReset:start( tumbleTickTime )
			else
				self.sv.tumbleReset:start( StopTumbleTimerTickThreshold )
			end
			self.sv.tumbleSuspendedReset:reset()
			return true
		end
	end
	return false
end

function BasePlayer.sv_updateTumbling( self )
	if not self.sv.resistTumbleTimer:done() then
		self.sv.resistTumbleTimer:tick()
	end

	if not self.player.character:isDowned() then
		if self.player.character:isTumbling() then
			self.sv.maxTumbleTimer:tick()
			if self.sv.maxTumbleTimer:done() then
				-- Stuck in the tumble state for too long, gain temporary tumble immunity
				self.player.character:setTumbling( false )
				self.sv.maxTumbleTimer:reset()
				self.sv.tumbleReset:reset()
				self.sv.tumbleSuspendedReset:reset()
				self.sv.resistTumbleTimer:reset()
			else
				local shouldRecover = false
				-- Check if player should recover normally
				self.sv.tumbleReset:tick()
				if self.player.character:getTumblingLinearVelocity():length() <= StopTumbleSpeedThreshold then
					if self.sv.tumbleReset:done() then
						shouldRecover = true
					end
				end

				-- Check if player should recover because of being suspended
				self.sv.tumbleSuspendedReset:tick() -- Resets with each server_onCollision
				if self.sv.tumbleSuspendedReset:done() then
					shouldRecover = true
				end

				if shouldRecover then
					self.player.character:setTumbling( false )
					self.sv.tumbleReset:reset()
					self.sv.tumbleSuspendedReset:reset()
					self.sv.maxTumbleTimer:reset()
				end
			end
		end
	end
end

function BasePlayer.sv_n_exchangeItem( self, params )
	if sm.container.beginTransaction() then
		sm.container.spendFromSlot( params.playerInventory, params.slotIndex, params.previousUid, params.previousQuantity, true )
		sm.container.collectToSlot( params.playerInventory, params.slotIndex, params.nextUid, params.nextQuantity, true )
		sm.container.endTransaction()
	end
end

function BasePlayer.server_onCollision( self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal  )
	if not self.player.character or not sm.exists( self.player.character ) then
		return
	end

	self.sv.tumbleSuspendedReset:reset() -- Suspended tumble recovery resets with each collision

	if not self.sv.impactCooldown:done() then
		return
	end

	local collisionDamageMultiplier = 0.25
	
	local maxHp = 100
	local fallDamageMultiplier = 1.0
	if self.sv.saved.stats then
		if self.sv.saved.stats.maxhp then
			maxHp = self.sv.saved.stats.maxhp
		end
	
		if self.sv.saved.stats.perks and self.sv.saved.stats.perks[SurvivalPlayer.Perks.FallProtection] then
			fallDamageMultiplier = fallDamageMultiplier * SurvivalPlayer.BuffFallProtectionMult
		end
	end

	local damage, tumbleTicks, tumbleVelocity, impactReaction = CharacterCollision( self.player.character, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal, maxHp / collisionDamageMultiplier, 24, self.sv.velocityBuffer, self.sv.velocityBufferIndex, fallDamageMultiplier )
	damage = damage * collisionDamageMultiplier
	if damage > 0 or tumbleTicks > 0 then
		self.sv.impactCooldown:start( 0.25 * 40 )
	end
	if damage > 0 then
		self:sv_takeDamage( damage, "shock" )
	end
	if g_enableCollisionTumble then
		if tumbleTicks > 0 and self.sv.collisionTumbleImmunity:done() then
			if self:sv_startTumble( tumbleTicks ) then
				-- Limit tumble velocity
				if tumbleVelocity:length2() > MaxTumbleImpulseSpeed * MaxTumbleImpulseSpeed then
					tumbleVelocity = tumbleVelocity:normalize() * MaxTumbleImpulseSpeed
				end
				self.player.character:applyTumblingImpulse( tumbleVelocity * self.player.character.mass )
				if type( other ) == "Shape" and sm.exists( other ) and other.body:isDynamic() then
					sm.physics.applyImpulse( other.body, impactReaction * other.body.mass, true, collisionPosition - other.body.worldPosition )
				end
			end
		end
	end
end

function BasePlayer.sv_e_grantTumbleImmunity( self, duration )
	self.sv.collisionTumbleImmunity:start( duration )
end

function BasePlayer.sv_e_receiveDamage( self, damageData )
	self:sv_takeDamage( damageData.damage, damageData.source )
end

function BasePlayer.sv_takeDamage( self, damage, source, typeUuid ) end

function BasePlayer.sv_e_respawn( self ) end

function BasePlayer.sv_startFadeToBlack( self, param )
	self.network:sendToClient( self.player, "cl_n_startFadeToBlack", { duration = param.duration, timeout = param.timeout } )
end

function BasePlayer.sv_startFadeToBlackWaitForWorld( self, param )
	self.network:sendToClient( self.player, "cl_n_startFadeToBlackWaitForWorld", { duration = param.duration, timeout = param.timeout } )
end

function BasePlayer.sv_endFadeToBlack( self, param )
	self.network:sendToClient( self.player, "cl_n_endFadeToBlack", { duration = param.duration, force = param.force } )
end

function BasePlayer.cl_e_startCinematicFadeToBlack( self, param )
	if self.cl.cameraState == CameraState.CUTSCENE then
		sm.gui.startFadeToBlack( param.duration, param.timeout )
	end
end

function BasePlayer.cl_e_endCinematicFadeToBlack( self, param )
	if self.cl.cameraState == CameraState.CUTSCENE then
		sm.gui.endFadeToBlack( param.duration )
	end
end

function BasePlayer.cl_e_endFadeToBlack( self, param )
	sm.gui.endFadeToBlack( param.duration )
end

function BasePlayer.cl_n_startFadeToBlack( self, param )
	sm.gui.startFadeToBlack( param.duration, param.timeout )
end

function BasePlayer.cl_n_startFadeToBlackWaitForWorld( self, param )
	sm.gui.startFadeToBlackWaitForWorld( param.duration, param.timeout )
end

function BasePlayer.cl_n_endFadeToBlack( self, param )
	sm.gui.endFadeToBlack( param.duration, param.force )
end

function BasePlayer.sv_e_onSpawnCharacter( self ) end

function BasePlayer.sv_e_debug( self, params ) end

function BasePlayer.sv_e_eat( self, edibleParams ) end

function BasePlayer.sv_e_feed( self, params ) end

function BasePlayer.sv_e_setRefiningState( self, state )
	if state == true then
		self.player:sendCharacterEvent( "refineStart" )
	else
		self.player:sendCharacterEvent( "refineEnd" )
	end
end

function BasePlayer.sv_e_onLoot( self, params )
	self.network:sendToClient( self.player, "cl_n_onLoot", params )
end

function BasePlayer.cl_n_onLoot( self, params )
	local color
	if params.uuid then
		color = sm.shape.getShapeTypeColor( params.uuid )
	end
	local effectName = params.effectName or "Loot - Pickup"
	sm.effect.playEffect( effectName, params.pos, sm.vec3.zero(), params.rot or sm.quat.identity(), sm.vec3.one(), { ["Color"] = color } )
end

function BasePlayer.sv_e_onMsg( self, msg )
	self.network:sendToClient( self.player, "cl_n_onMsg", msg )
end

function BasePlayer.cl_n_onMsg( self, msg )
	NotificationManager.Cl_AddGenericNotification( msg )
end

function BasePlayer.cl_n_onEffect( self, params )
	if params.host then
		sm.effect.playHostedEffect( params.name, params.host, params.boneName, params.parameters )
	else
		sm.effect.playEffect( params.name, params.position, params.velocity, params.rotation, params.scale, params.parameters )
	end
end

function BasePlayer.sv_e_onStayPesticide( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
end

function BasePlayer.sv_e_onEnterFire( self )
	if self.sv.fireDamageCooldown:done() then
		self:sv_takeDamage( FireDamage, "fire" )
		self.sv.fireDamageCooldown:start( FireDamageCooldown )
	end
end

function BasePlayer.sv_e_onStayFire( self )
	if self.sv.fireDamageCooldown:done() then
		self:sv_takeDamage( FireDamage, "fire" )
		self.sv.fireDamageCooldown:start( FireDamageCooldown )
	end
end

function BasePlayer.sv_e_onEnterChemical( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
	self.sv.saved.inChemical = true
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_e_onStayChemical( self )
	if self.sv.poisonDamageCooldown:done() then
		self:sv_takeDamage( PoisonDamage, "poison" )
		self.sv.poisonDamageCooldown:start( PoisonDamageCooldown )
	end
end

function BasePlayer.sv_e_onExitChemical( self )
	self.sv.saved.inChemical = false
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_e_onEnterRadiation( self )
	if self.sv.radiationDamageCooldown:done() then
		self:sv_takeDamage( RadiationDamage, "radiation" )
		self.sv.radiationDamageCooldown:start( RadiationDamageCooldown )
	end
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_e_onStayRadiation( self )
	if self.sv.radiationDamageCooldown:done() then
		self:sv_takeDamage( RadiationDamage, "radiation" )
		self.sv.radiationDamageCooldown:start( RadiationDamageCooldown )
	end
end

function BasePlayer.sv_e_onEnterOil( self )
	self.sv.saved.inOil = true
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.sv_e_onExitOil( self )
	self.sv.saved.inOil = false
	self.network:setClientData( self.sv.saved )
end

function BasePlayer.client_onCancel( self )
	local myPlayer = sm.localPlayer.getPlayer()
	local myCharacter = myPlayer and myPlayer.character or nil
	if sm.exists( myCharacter ) then
		sm.event.sendToCharacter( myCharacter, "cl_e_onCancel" )
	end
end

function BasePlayer.cl_n_onMessage( self, params )
	local message = params.message or ""
	local displayTime = params.displayTime or 2
	NotificationManager.Cl_AddGenericNotification( message, displayTime )
end

function ItemPickupFilter( fistUuid, transactionChanges, compareUuids  )
	if isAnyOf( fistUuid, compareUuids ) then
		for _, otherItem in ipairs( transactionChanges ) do
			if isAnyOf( fistUuid, compareUuids ) and otherItem.uuid ~= fistUuid then
				return false
			end
		end
	end
	return true
end

function BasePlayer.sv_e_startPushbackSound( self )
	self.network:sendToClient( self.player, "cl_n_startPushbackSound" )
end

function BasePlayer.sv_e_stopPushbackSound( self )
	self.network:sendToClient( self.player, "cl_n_stopPushbackSound" )
end

function BasePlayer.cl_n_startPushbackSound( self )
	if not self.cl.pushbackSound then
		self.cl.pushbackSound = sm.effect.createEffect2D( "audio:event:/char/npc/bots/enemies/trashbot/pushback_wind" )
	end
	if not self.cl.pushbackSound:isPlaying() then
		self.cl.pushbackSound:start()
	end
end

function BasePlayer.cl_n_stopPushbackSound( self )
	if self.cl.pushbackSound and self.cl.pushbackSound:isPlaying() then
		self.cl.pushbackSound:stop()
	end
end