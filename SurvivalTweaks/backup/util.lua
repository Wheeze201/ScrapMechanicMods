--util.lua
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_constants.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

dofile( "$SURVIVAL_DATA/Scripts/terrain/underground/chunk_raster.lua" )

function printf( s, ... )
	return print( s:format( ... ) )
end

function PrintTable( t )
	for k,v in pairs( t ) do
		print( tostring( k ).." ("..type( v )..")"..tostring( v ) )
	end
end

function clamp( value, min, max )
	if value < min then return min elseif value > max then return max else return value end
end

function saturate( value )
	return clamp( value, 0, 1 )
end

function normalize( x, xMin, xMax )
	return clamp( ( x - xMin ) / ( xMax - xMin ), 0, 1 )
end

function ClampVector( vector, maxValue )
	return vector:safeNormalize( sm.vec3.zero() ) * math.min( vector:length(), maxValue )
end

function HorizontalDistance( vec1, vec2 )
	local dx = vec2.x - vec1.x
	local dy = vec2.y - vec1.y
	return math.sqrt( dx * dx + dy * dy )
end

function IsPositionInBox( position, centerPos, halfExtents )
	return position.x >= centerPos.x - halfExtents.x and position.x <= centerPos.x + halfExtents.x and
			position.y >= centerPos.y - halfExtents.y and position.y <= centerPos.y + halfExtents.y and
			position.z >= centerPos.z - halfExtents.z and position.z <= centerPos.z + halfExtents.z
end

function Distance2ToAabb( point, aabbMin, aabbMax )
	local dx = 0
	if point.x < aabbMin.x then
		dx = aabbMin.x - point.x
	elseif point.x > aabbMax.x then
		dx = point.x - aabbMax.x
	end

	local dy = 0
	if point.y < aabbMin.y then
		dy = aabbMin.y - point.y
	elseif point.y > aabbMax.y then
		dy = point.y - aabbMax.y
	end

	local dz = 0
	if point.z < aabbMin.z then
		dz = aabbMin.z - point.z
	elseif point.z > aabbMax.z then
		dz = point.z - aabbMax.z
	end

	return dx * dx + dy * dy + dz * dz
end

function round( value )
	return math.floor( value + 0.5 )
end

function max( a, b )
	return a > b and a or b
end

function min( a, b )
	return a < b and a or b
end

function sign( value )
	return value >= DBL_EPSILON and 1 or ( value <= -DBL_EPSILON and -1 or 0 )
end

function fuzzyZero( value )
	return value > -FLT_EPSILON and value < FLT_EPSILON
end

function finite( value )
	return  value > -math.huge and value < math.huge
end

function RadToDeg( rad )
	return rad * 57.295779513082320876798154814105
end

function DegToRad( deg )
	return deg * 0.01745329251994329576923690768489
end

function orthogonal( vec )
	assert( type( vec ) == "Vec3" )
	local x = math.abs( vec.x )
	local y = math.abs( vec.y )
	local z = math.abs( vec.z )

	local other = sm.vec3.new( 0, 0, 1 )
	if x < y and x < z then
		sm.vec3.new( 1, 0, 0 )
	elseif y < x and y < z then
		sm.vec3.new( 0, 1, 0 )
	end
	return vec:cross( other )
end

function lerp( a, b, p )
	return clamp( a + (b - a) * p, min(a, b), max(a, b) )
end

function smoothstep( edge0, edge1, p )
    p = math.max( 0, math.min( 1, ( p - edge0 ) / ( edge1 - edge0 ) ) )
    return p * p * ( 3 - 2 * p )
end

function easeIn( a, b, dt, speed )
	local p = 1 - math.pow( clamp( speed, 0.0, 1.0 ), dt * 60 )
	return lerp( a, b, p )
end

function unclampedLerp( a, b, p )
	return a + (b - a) * p
end

function inverseLerp( a, b, p )
	if b - a == 0 then
		return a
	end
	return ( p - a ) / ( b - a )
end

function isAnyOf( is, of )
	for _, v in pairs( of ) do
		if is == v then
			return true
		end
	end
	return false
end

function valueExists( array, value )
	for _, v in ipairs( array ) do
		if v == value then
			return true
		end
	end
	return false
end

function valueIndex( array, value )
	for index, v in ipairs( array ) do
		if v == value then
			return index
		end
	end
	return nil
end

function indexOf( array, predicate )
	for index, v in ipairs( array ) do
		if predicate( v ) == true then
			return index
		end
	end
end

function concat( a, b )
	for _, v in ipairs( b ) do
		a[#a+1] = v
	end
end

function concatArrays( ... )
    local result = {}
    local args = { ... }
    for _, tbl in ipairs( args ) do
        for _, value in ipairs( tbl ) do
            table.insert( result, value )
        end
    end
    return result
end

function append( a, b )
	for k, v in pairs( b ) do
		a[k] = v
	end
end

function intersection( a, b )
	local out = {}
	for _, a in pairs( a ) do
		for _, b in pairs(b) do
			if a == b then
				table.insert( out, a )
			end
		end
	end
	return out
end

function clearTable( t )
	for k, _ in pairs( t ) do
		t[k] = nil
	end
end

function tableCount( t )
	local count = 0
	for _ in pairs( t ) do
		count = count + 1
	end
	return count
end

--http://lua-users.org/wiki/SwitchStatement
function switch( table )
	table.case = function ( self, caseVariable )
		local caseFunction = self[caseVariable] or self.default
		if caseFunction then
			if type( caseFunction ) == "function" then
				caseFunction( caseVariable, self )
			else
				error( "case " .. tostring( caseVariable ).." not a function" )
			end
		end
	end
	return table
end

function SafeGetExist( t, key )
	if type( t ) == "table" and t[key] then
		return sm.exists( t[key] )
	end
	return false
end

function SafeGet( t, key )
    if type( t ) ~= "table" then
        return nil
    end
    return t[key]
end

function SafeSet( t, key, value )
    if t == nil then
        t = {}
    end
	if type( t ) == "table" then
		t[key] = value
	end
    return t
end

function SafeSetKVPs( t, keyValuePairs )
    if t == nil then
        t = {}
    end
	if type( t ) == "table" then
		for key, value in pairs( keyValuePairs ) do
			t[key] = value
		end
	end
    return t
end

function InitializeNestedTables(baseTable, ... )
    local current = baseTable
    
    for _, key in ipairs({...}) do
        if current[key] == nil then
            current[key] = {}
        end
        current = current[key]
    end
    
    return current
end

function SafeNestedAccess(baseTable, ...)
    local current = baseTable
    
    for _, key in ipairs({...}) do
		-- Checks if type is table or an engine userdata
		local et = enumType(current)
		if et ~= LUA_TYPE.table and et <= LUA_TYPE.thread then
			return nil
		end
        current = current[key]
        if current == nil then
            return nil
        end
    end
    
    return current
end

function addToArrayIfNotExists( array, value )
	local n = #array
	for i = 1, n do
		if array[i] == value then
			return
		end
	end
	array[n + 1] = value
end


function removeFromArray( array, fnShouldRemove )
	local n = #array
	local j = 1
	for i = 1, n do
		if fnShouldRemove( array[i] ) then
			array[i] = nil
		else
			if i ~= j then
				array[j] = array[i]
				array[i] = nil
			end
			j = j + 1
		end
	end
	return array
end

function ModuloIndex( index, limit )
	return ( ( index - 1 ) % limit ) + 1
end

function CellKey( x, y )
	return ( y + 1024 ) * 2048 + x + 1024
end

function isHarvest( shapeUuid )
	sm.log.error( "isHarvest util is deprecated, will return false" )
	return false
end

function getCell( x, y )
	return math.floor( x / 64 ), math.floor( y / 64 )
end

-- Allows to iterate a table of form [key, value, key, value, key, value]
function kvpairs(t)
	local i = 1
	local n = #t
	return function ()
		if i < n then
			local a = t[i]
			local b = t[i + 1]
			i = i + 2
			return a, b
		end
	end
end

function reverse_ipairs( a )
	function iter( a, i )
		i = i - 1
		local v = a[i]
		if v then
			return i, v
		end
	end
	return iter, a, #a + 1
end

function shuffle( array, first, last )
	first = first or 1
	last = last or #array
	for i = last, 1 + first, -1 do
		local j = math.random( first, i )
		array[i], array[j] = array[j], array[i]
	end
	return array
end

function reverse( array )
	local i, j = 1, #array
	while i < j do
		array[i], array[j] = array[j], array[i]
		i = i + 1
		j = j - 1
	end
end

function shallowcopy( orig )
	local orig_type = type( orig )
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in pairs( orig ) do
			copy[orig_key] = orig_value
		end
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

function CapsuleDistance( capA, capB, pos )
	local dir = capB - capA
	if ( pos - capB ):dot( dir ) >= 0 then
		return ( pos - capB ):length()
	elseif ( pos - capA ):dot( dir ) <= 0 then
		return ( pos - capA ):length()
	end
	local t = ( pos - capA ):dot( dir ) / dir:length2()
	local linePos = capA + dir * t
	return ( pos - linePos ):length()
end

function closestPointOnLineSegment( line0, line1, point )
	local vec = line1 - line0
	local len = vec:length()
	if len >= FLT_EPSILON then
		local dist = ( vec / len ):dot( point - line0 )
		local t = sm.util.clamp( dist / len, 0, 1 )
		return line0 + vec * t, t, len
	end
	return line1, 0, 1
end

function closestPointInLines( linePoints, point )
	local closest
	if #linePoints > 1 then
		local closestDistance2 = math.huge
		for i = 1, #linePoints - 1 do
			local pt, t, len = closestPointOnLineSegment( linePoints[i], linePoints[i + 1], point )
			local distance2 = ( pt - point ):length2()
			if distance2 < closestDistance2 then
				closest = { i = i, pt = pt, t = t, len = len }
				closestDistance2 = distance2
			end
		end
	elseif #linePoints == 1 then
		closest = { i = 1, pt = linePoints[1], t = 0, len = 1 }
	end
	return closest
end

function closestPointInLinesSkipFirst( linePoints, point )
	local closest
	if #linePoints > 1 then
		local closestDistance2 = math.huge
		for i = 2, #linePoints - 1 do
			local pt, t, len = closestPointOnLineSegment( linePoints[i], linePoints[i + 1], point )
			local distance2 = ( pt - point ):length2()
			if distance2 < closestDistance2 then
				closest = { i = i, pt = pt, t = t, len = len }
				closestDistance2 = distance2
			end
		end
	elseif #linePoints == 1 then
		closest = { i = 1, pt = linePoints[1], t = 0, len = 1 }
	end
	return closest
end


function lengthOfLines( linePoints )
	local lines = {}
	local totalLength = 0
	if #linePoints > 1 then
		for i = 1, #linePoints - 1 do
			lines[i] = {}
			lines[i].p0 = linePoints[i]
			lines[i].p1 = linePoints[i+1]
			lines[i].length = ( lines[i].p1 - lines[i].p0 ):length()
			totalLength = totalLength + lines[i].length
			lines[i].totalLength = totalLength
		end
	end
	return totalLength, lines
end

function closestFractionInLines( linePoints, point )
	if #linePoints > 1 then
		local closest = closestPointInLines( linePoints, point )
		local totalLength, lines = lengthOfLines( linePoints )
		local distance = lines[closest.i].totalLength - lines[closest.i].length + closest.t * closest.len
		return totalLength >= FLT_EPSILON and clamp( distance / totalLength, 0.0, 1.0 ) or 1.0
	elseif #linePoints == 1 then
		return 1.0
	end
end

function pointInLines( linePoints, fraction )
	local totalLength, lines = lengthOfLines( linePoints )

	if totalLength == 0 then
		return linePoints[1]
	end

	local point
	for i = 1, #lines do
		lines[i].minFraction = 0.0
		lines[i].maxFraction = lines[i].length / totalLength
		if lines[i-1] then
			lines[i].minFraction = lines[i].minFraction + lines[i-1].maxFraction
			lines[i].maxFraction = lines[i].maxFraction + lines[i-1].maxFraction
		end
		if i == #lines then
			lines[i].maxFraction = 1.0
		end

		if fraction >= lines[i].minFraction and fraction <= lines[i].maxFraction then
			local f = ( fraction - lines[i].minFraction ) / ( lines[i].maxFraction - lines[i].minFraction )
			point = sm.vec3.lerp( lines[i].p0, lines[i].p1, f )
			break
		end
	end

	return point
end

-- p = progress from first point (1) to last point (#points)
function spline( points, p, distances )
	assert( #points > 1, "Must have at least 2 points" )
	local i0 = math.floor( p )
	if i0 < 1 then
		i0 = 1
		p = 1
	elseif i0 >= #points then
		i0 = #points - 1
		p = #points
	end

	local u
	local ui
	if distances then
		assert( #distances == #points, "Distances must have the same length as points" )
		local invDistance = 1 / distances[#distances]
		u = ( ( p - i0 ) * ( distances[i0 + 1] - distances[i0] ) + distances[i0] ) * invDistance
		ui = function( o )
			local i = i0 + o
			if i < 1 then i = 1 end
			if i > #distances then i = #distances end
			return distances[i] * invDistance
		end
	else
		u = p
		ui = function( o ) return i0 + o end
	end

	local pt1_0 = points[math.max( i0 - 1, 1 )]
	local pt2_0 = points[i0]
	local pt3_0 = points[i0 + 1]
	local pt4_0 = points[math.min( i0 + 2, #points )]

	local t = ( u - ui(-2 ) ) / ( ui( 1 ) - ui(-2 ) )
	local pt1_1 = sm.vec3.lerp( pt1_0, pt2_0, finite( t ) and t or 0.0 )
	t = ( u - ui(-1 ) ) / ( ui( 2 ) - ui(-1 ) )
	local pt2_1 = sm.vec3.lerp( pt2_0, pt3_0, finite( t ) and t or 0.0 )
	t = ( u - ui( 0 ) ) / ( ui( 3 ) - ui( 0 ) )
	local pt3_1 = sm.vec3.lerp( pt3_0, pt4_0, finite( t ) and t or 0.0 )

	t = ( u - ui(-1 ) ) / ( ui( 1 ) - ui(-1 ) )
	local pt1_2 = sm.vec3.lerp( pt1_1, pt2_1, finite( t ) and t or 0.0 )
	t = ( u - ui( 0 ) ) / ( ui( 2 ) - ui( 0 ) )
	local pt2_2 = sm.vec3.lerp( pt2_1, pt3_1, finite( t ) and t or 0.0 )

	t = ( u - ui( 0 ) ) / ( ui( 1 ) - ui( 0 ) )
	local pt1_3 = sm.vec3.lerp( pt1_2, pt2_2, finite( t ) and t or 0.0 )

	return pt1_3, pt1_2, pt2_2, pt1_1, pt2_1, pt3_1
end

function getClosestShape( body, position )
	local closestShape = nil
	local closestDistance = math.huge
	local shapes = body:getShapes()
	for _, shape in ipairs( shapes ) do
		local distance = ( shape.worldPosition - position ):length()
		if closestShape then
			if distance < closestDistance then
				closestShape = shape
				closestDistance = distance
			end
		else
			closestShape = shape
			closestDistance = distance
		end
	end

	return closestShape
end

function EstimateBezierLength( points, samples )
	samples = samples and samples or 32
	samples = math.min( samples, 64 )
	if #points == 0 or samples < 2 then
		return 0
	end

	local step = 1.0 / ( samples - 1 )
	local latestPosition = points[1]
	local length = 0.0
	for i = 2, samples do
		local position = BezierPosition( points, step * i )
		length = length + ( latestPosition - position ):length()
		latestPosition = position
	end

	return length
end

local function bezierPositionRecursive( points, p, startIndex, endIndex )
	if startIndex == endIndex then
		return points[startIndex]
	end

	local p1 = bezierPositionRecursive( points, p, startIndex, endIndex - 1 )
	local p2 = bezierPositionRecursive( points, p, startIndex + 1, endIndex )
	return sm.vec3.lerp( p1, p2, p )
end

function BezierPosition( points, p )
	if #points == 0 then
		return sm.vec3.zero()
	elseif #points == 1 then
		return points[#points]
	end
	
	local p1 = bezierPositionRecursive( points, p, 1, #points - 1 )
	local p2 = bezierPositionRecursive( points, p, 2, #points )

	return sm.vec3.lerp( p1, p2, p )
end

local function bezierRotationRecursive( rotations, p, startIndex, endIndex )
	if startIndex == endIndex then
		return rotations[startIndex]
	end

	local q1 = bezierRotationRecursive( rotations, p, startIndex, endIndex - 1 )
	local q2 = bezierRotationRecursive( rotations, p, startIndex + 1, endIndex )
	return sm.quat.slerp( q1, q2, p )
end

function BezierRotation( rotations, p )
	if #rotations == 0 then
		return sm.quat.identity()
	elseif #rotations == 1 then
		return rotations[#rotations]
	end

	local q1 = bezierRotationRecursive( rotations, p, 1, #rotations - 1 )
	local q2 = bezierRotationRecursive( rotations, p, 2, #rotations )
	return sm.quat.slerp( q1, q2, p )
end

function lerpDirection( fromDirection, toDirection, p )
	local cameraHeading = math.atan2( -fromDirection.x, fromDirection.y )
	local cameraPitch = math.asin( fromDirection.z )

	local cameraDesiredHeading = math.atan2( -toDirection.x, toDirection.y )
	local cameraDesiredPitch = math.asin( toDirection.z )

	local shortestAngle = ( ( ( cameraDesiredHeading - cameraHeading ) % ( 2 * math.pi ) + 3 * math.pi ) % ( 2 * math.pi ) ) - math.pi
	cameraDesiredHeading = cameraHeading + shortestAngle

	cameraHeading = sm.util.lerp( cameraHeading, cameraDesiredHeading, p )
	cameraPitch = sm.util.lerp( cameraPitch, cameraDesiredPitch, p )

	local newCameraDirection = sm.vec3.new( 0, 1, 0 )
	newCameraDirection = newCameraDirection:rotateX( cameraPitch )
	newCameraDirection = newCameraDirection:rotateZ( cameraHeading )

	return newCameraDirection
end

function magicDirectionInterpolation( currentDirection, desiredDirection, dt, speed )
	-- Smooth heading and pitch movement
	local speed = speed or ( 1.0 / 6.0 )
	local blend = 1 - math.pow( 1 - speed, dt * 60 )
	return lerpDirection( currentDirection, desiredDirection, blend )
end

function magicPositionInterpolation( currentPosition, desiredPosition, dt, speed )
	local speed = speed or ( 1.0 / 6.0 )
	local blend = 1 - math.pow( 1 - speed, dt * 60 )
	return sm.vec3.lerp( currentPosition, desiredPosition, blend )
end

function magicRotationInterpolation( currentRotation, desiredRotation, dt, speed )
	local speed = speed or ( 1.0 / 6.0 )
	local blend = 1 - math.pow( 1 - speed, dt * 60 )
	return sm.quat.slerp( currentRotation, desiredRotation, blend )
end

function magicInterpolation( currentValue, desiredValue, dt, speed )
	local speed = speed or ( 1.0 / 6.0 )
	local blend = 1 - math.pow( 1 - speed, dt * 60 )
	return sm.util.lerp( currentValue, desiredValue, blend )
end

function ScaleAndVibrate( time, duration, min, max, speed )
	local p = math.min( time / duration, 1.0 )
	local vp = ( math.sin( p * speed ) + 1 ) * 0.5
	local vibration = lerp( min, max, vp )
	local scaleAndVibration = p + vibration
	return scaleAndVibration > 1 and p - math.fmod( scaleAndVibration, 1 ) or scaleAndVibration
end

function TriangleCurve( p )
	local res = math.max( math.min( p, 1.0 ), 0.0 )
	return 1.0 - math.abs( res * 2 - 1.0 )
end

function PredictRotation( rotation, angularVelocity, dt )
	local angle2 = angularVelocity:length2()
	if angle2 < 0.000001 then
		return rotation
	end
	local angle = math.sqrt( angle2 )
	local axis = angularVelocity * ( math.sin( 0.5 * angle * dt ) / angle )
	local deltaRotation = sm.quat.new( axis.x, axis.y, axis.z, math.cos( angle * dt * 0.5 ) )
	deltaRotation:safeNormalize( sm.quat.identity() )
	return deltaRotation * rotation
end

function isDangerousCollisionShape( shapeUuid ) --TODO: Remove, this is not fun
	return isAnyOf( shapeUuid, g_dangerousObjects )
end

function isSafeCollisionShape( shapeUuid )
	return isAnyOf( shapeUuid, { obj_scrap_smallwheel, obj_vehicle_smallwheel, obj_vehicle_bigwheel, obj_spaceship_cranewheel } )
end

function isTrapProjectile( projectileUuid )
	local TrapProjectiles = { projectile_tape, projectile_explosivetape }
	return isAnyOf( projectileUuid, TrapProjectiles )
end

function isGoopProjectile( projectileUuid )
	local GoopProjectiles = { projectile_colorblob }
	return isAnyOf( projectileUuid, GoopProjectiles )
end

function isIgnoreCollisionShape( shapeUuid )
	return isAnyOf( shapeUuid, {
		obj_harvest_metal,

		obj_robotparts_tapebothead01,
		obj_robotparts_tapebottorso01,
		obj_robotparts_tapebotleftarm01,
		obj_robotparts_tapebotshooter,

		obj_robotparts_haybothead,
		obj_robotparts_haybotbody,
		obj_robotparts_haybotfork,

		obj_robotpart_totebotbody,
		obj_robotpart_totebotleg,

		obj_robotparts_farmbotpart_head,
		obj_robotparts_farmbotpart_cannonarm,
		obj_robotparts_farmbotpart_drill,
		obj_robotparts_farmbotpart_scytharm
	} )
end

function isIgnoreAttackShape( shape )
	local ignore = isAnyOf( shape.uuid, {
		obj_robotparts_tapebothead01,
		obj_robotparts_tapebottorso01,
		obj_robotparts_tapebotleftarm01,
		obj_robotparts_tapebotshooter,

		obj_robotparts_haybothead,
		obj_robotparts_haybotbody,
		obj_robotparts_haybotfork,

		obj_robotpart_totebotbody,
		obj_robotpart_totebotleg,

		obj_robotparts_farmbotpart_head,
		obj_robotparts_farmbotpart_cannonarm,
		obj_robotparts_farmbotpart_drill,
		obj_robotparts_farmbotpart_scytharm
	} )

	if not ignore then
		if isAnyOf( shape.uuid, {
			obj_harvest_metal,
			obj_interactive_robotbasshead,
			obj_interactive_robotdrumhead,
			obj_interactive_robotsynthhead,
			obj_interactive_robotbliphead01,
		} ) and not shape.body:isStatic() then
			ignore = true
		end
	end
	return ignore
end

function getTimeOfDayString()
	local timeOfDay = sm.game.getTimeOfDay()
	local hour = ( timeOfDay * 24 ) % 24
	local minute = ( hour % 1 ) * 60
	local hour1 = math.floor( hour / 10 )
	local hour2 = math.floor( hour - hour1 * 10 )
	local minute1 = math.floor( minute / 10 )
	local minute2 = math.floor( minute - minute1 * 10 )

	return hour1..hour2..":"..minute1..minute2
end

function GetTimeOfDayHoursMinutes()
	local timeOfDay = sm.game.getTimeOfDay()
	local hour = ( timeOfDay * 24 ) % 24
	local minute = math.floor( ( hour % 1 ) * 60 )

	hour = math.floor( hour )

	return hour, minute
end

function formatCountdown( seconds )
	local time = seconds / DAYCYCLE_TIME
	local days = math.floor(( time * 24 ) / 24)
	local hour = ( time * 24 ) % 24
	local minute = ( hour % 1 ) * 60
	local hour1 = math.floor( hour / 10 )
	local hour2 = math.floor( hour - hour1 * 10 )
	local minute1 = math.floor( minute / 10 )
	local minute2 = math.floor( minute - minute1 * 10 )

	return days.."d "..hour1..hour2.."h "..minute1..minute2.."m"
end

-- Formats a vault value with dot thousand separators, capped at 999.999.999.
-- When pad is true, zero-pads to the full "000.000.000" width.
function FormatVaultNumber( n, pad )
	n = clamp( math.floor( n ), 0, 999999999 )
	if pad then
		local digits = string.format( "%09d", n )
		return digits:sub( 1, 3 ).."."..digits:sub( 4, 6 ).."."..digits:sub( 7, 9 )
	end
	return FormatThousandSeparator( n )
end

function FormatThousandSeparator( n )
	n = math.floor( n )
	local formatted = tostring( n )
	local k
	repeat
		formatted, k = formatted:gsub( "^(%d+)(%d%d%d)", "%1.%2" )
	until k == 0
	return formatted
end

function getDayCycleFraction()

	local time = sm.game.getTimeOfDay()

	local index = 1
	while index < #DAYCYCLE_SOUND_TIMES and time >= DAYCYCLE_SOUND_TIMES[index + 1] do
		index = index + 1
	end
	assert( index <= #DAYCYCLE_SOUND_TIMES )

	local night = 0.0
	if index < #DAYCYCLE_SOUND_TIMES then
		local p = ( time - DAYCYCLE_SOUND_TIMES[index] ) / ( DAYCYCLE_SOUND_TIMES[index + 1] - DAYCYCLE_SOUND_TIMES[index] )
		night = sm.util.lerp( DAYCYCLE_SOUND_VALUES[index], DAYCYCLE_SOUND_VALUES[index + 1], p )
	else
		night = DAYCYCLE_SOUND_VALUES[index]
	end

	return 1.0 - night
end

function getTicksUntilDayCycleFraction( dayCycleFraction )
	local time = sm.game.getTimeOfDay()
	local timeDiff = ( time > dayCycleFraction ) and ( dayCycleFraction - time ) + 1.0 or ( dayCycleFraction - time )
	return math.floor( timeDiff * DAYCYCLE_TIME * 40 + 0.5 )
end

-- Brute force testing of a function for randomizing integer ranges
function TestRandomFunction( functionName, p1, p2, p3 )
	print( "Testing function '"..tostring( functionName ).."' with parameters "..tostring( p1 )..", "..tostring( p2 )..", "..tostring( p3 ) )
	local fn = _G[functionName]
	if not fn then
		print( "Function not found" )
		return
	end

	local a = {}
	local sum = 0
	for i = 1,1000000 do
		local n = fn( p1, p2, p3 )
		a[n] = a[n] and a[n] + 1 or 1
		sum = sum + n
	end

	for n,v in pairs( a ) do
		print( n, "=", (v / 10000).."%" )
	end
	print( "avg =", sum / 1000000 )
end

function randomStackAmount( min, mean, max )
	return clamp( round( sm.noise.randomNormalDistribution( mean, ( max - min + 1 ) * 0.25 ) ), min, max )
end

function PlantSeedDropAmount( seedUuid )
	if seedUuid == ITEMS.obj_seed_potato then
		return randomStackAmount( 1, 1, 2 )
	elseif seedUuid == ITEMS.obj_seed_cotton or seedUuid == ITEMS.obj_seed_pigmentflower then
		return 1
	end
	return randomStackAmount( 0, 0.5, 1 )
end

function randomStackAmount2()
	return randomStackAmount( 1, 1, 2 )
end

function randomStackAmountAvg2()
	return randomStackAmount( 1, 2, 3 )
end

function randomStackAmountAvg3()
	return randomStackAmount( 2, 3, 4 )
end

function randomStackAmount5()
	return randomStackAmount( 2, 3.5, 5 )
end

function randomStackAmountAvg5()
	return randomStackAmount( 3, 5, 7 )
end

function randomStackAmount10()
	return randomStackAmount( 5, 7.5, 10 )
end

function randomStackAmountAvg10()
	return randomStackAmount( 5, 10, 15 )
end

function randomStackAmount20()
	return randomStackAmount( 10, 15, 20 )
end

function GetOwnerPosition( tool )
	local playerPosition = sm.vec3.new( 0, 0, 0 )
	local player = tool:getOwner()
	if player and player.character and sm.exists( player.character ) then
		playerPosition = player.character.worldPosition
	end
	return playerPosition
end

function CharacterCollision( self, other, vCollisionPosition, vPointVelocitySelf, vPointVelocityOther, vCollisionNormal, maxhp, velDiffThreshold, velocityBuffer, velocityBufferIndex, fallDamageMultiplier )
	assert( type( self ) == "Character" )
	
	if type( other ) == "Character" then
		return 0, 0, sm.vec3.zero(), sm.vec3.zero()
	end

	if type( other ) == "Shape" and not sm.exists( other ) then
		return 0, 0, sm.vec3.zero(), sm.vec3.zero()
	end

	if type( other ) == "Harvestable" and not sm.exists( other ) then
		return 0, 0, sm.vec3.zero(), sm.vec3.zero()
	end

	if type( other ) == "Shape" then
		if isIgnoreCollisionShape( other:getShapeUuid() ) then
			return 0, 0, sm.vec3.zero(), sm.vec3.zero()
		end
	end

	-- local landSebugSamples = {}
	local landVelocity = sm.vec3.zero()
	if velocityBuffer and velocityBufferIndex then
		local samples = 0
		local idx = velocityBufferIndex
		-- go back 2 ticks to ignore the landing corrected velocity's
		for i = 1, 2 do
			idx = idx - 1
			if idx < 1 then
				idx = #velocityBuffer
			end
		end
		local started = false
		for i = 1, #velocityBuffer - 2 do
			if idx < 1 then
				idx = #velocityBuffer
			end
			local vel = velocityBuffer[idx]
			if vel ~= nil and vel.z < 0 then
				landVelocity = landVelocity + vel
				samples = samples + 1
				-- landSebugSamples[#landSebugSamples+1] = vel
				started = true
			else
				if started then
					break
				end
			end
			idx = idx - 1
		end
		if samples > 0 then
			landVelocity = landVelocity / samples
		end
	end

	--print( "------ COLLISION", type( other ), "------" )

	local vVelImpact = ( vPointVelocitySelf - vPointVelocityOther )
	local vDirImpact = vVelImpact:safeNormalize( sm.vec3.zero() )
	local fCosImpactAngle = vDirImpact:dot( -vCollisionNormal )

	local vTumbleVelocity = sm.vec3.zero()
	local vImpactReaction = sm.vec3.zero()

	local fallDamage = 0
	local collisionDamage = 0
	local specialCollisionDamage = 0
	local fallTumbleTicks = 0
	local collisionTumbleTicks = 0
	local specialCollision = false

	-- Fall damage
	-- Jumping on on ground ~= 5
	-- Falling from max lift hight ~= 13 
	-- Free falling at max speed falling ~= 55 

	local fFallMinVelocity = 18 / ( fallDamageMultiplier or 1 )
	local fFallMaxVelocity = 35 / ( fallDamageMultiplier or 1 )
	-- local fFallImpact = math.min( -vVelImpact.z, -vPointVelocitySelf.z ) * fCosImpactAngle
	local fFallImpact = math.abs( landVelocity.z )
	local fFallDamageFraction = clamp( ( fFallImpact - fFallMinVelocity ) / ( fFallMaxVelocity - fFallMinVelocity ), 0.0, 1.0 )
	if fFallImpact > 0 then
		-- print( "fFallImpact", fFallImpact, "fFallDamageFraction", fFallDamageFraction )
		-- for i = 1, #landSebugSamples do
		-- 	print( "landSebugSamples", landSebugSamples[i].z )
		-- end
		for i = 1, #velocityBuffer do
			velocityBuffer[i] = sm.vec3.zero()
		end
		velocityBufferIndex = 1
	end
	if fFallDamageFraction > 0.25 then
		fallTumbleTicks = MEDIUM_TUMBLE_TICK_TIME
	end

	fallDamage = fFallDamageFraction * ( maxhp or 100 )


	local isSafeShape = false
	if type( other ) == "Shape" then

		-- Special damage
		if isDangerousCollisionShape( other:getShapeUuid() ) then
			if other.body.angularVelocity:length() > SPINNER_ANGULAR_THRESHOLD then
				specialCollisionDamage = 10
				specialCollision = true
			end
		end

		isSafeShape = isSafeCollisionShape( other:getShapeUuid() )
	end

	-- Collision damage
	local fRestitution = 0.3
	local fFriction = 0.3
	local velOther = sm.vec3.zero()
	if not isSafeShape then
		local massSelf = self.mass
		local massOther = 0
		if type( other ) == "Shape" and other.body:isDynamic() then
			massOther = other.body.mass
			velOther = other.body.velocity
		elseif type( other ) == "Harvestable" and sm.exists( other ) then
			velOther = other.velocity
		end

		if fCosImpactAngle > 0.5 then -- At least 30 degree impact angle
			local fVel0Self = vPointVelocitySelf:dot( vDirImpact )
			local fVel0Other = vPointVelocityOther:dot( vDirImpact )

			local fVel1Self
			local fVel1Other
			
			if massOther > 0 then
				fVel1Self = ( fRestitution * massOther * ( fVel0Other - fVel0Self ) + massSelf * fVel0Self + massOther * fVel0Other ) / ( massSelf + massOther )
				fVel1Other = ( fRestitution * massSelf * ( fVel0Self - fVel0Other ) + massSelf * fVel0Self + massOther * fVel0Other ) / ( massSelf + massOther )
			else
				-- Simplified with massSelf as 0, massOther as 1
				fVel1Self = fRestitution * ( fVel0Other - fVel0Self ) + fVel0Other
				fVel1Other = fVel0Other
			end

			-- Damage is based on the change in velocity from collision
			local fVelDiffSelf = ( fVel1Self - fVel0Self )
			local fVelDiffOther = ( fVel1Other - fVel0Other )

			if fVelDiffSelf <= -( velDiffThreshold or TUMBLE_VELOCITY_THRESHOLD ) then
				collisionDamage = round( 0.1885715 * ( -fVelDiffSelf )^1.464069 )

				local tumbleFraction = ( fVelDiffSelf + TUMBLE_VELOCITY_THRESHOLD ) / ( -TUMBLE_VELOCITY_MAX_IMPACT + TUMBLE_VELOCITY_THRESHOLD )
				tumbleFraction = clamp( tumbleFraction, 0.0, 1.0 )
				collisionTumbleTicks = lerp( TUMBLE_MIN_TICK_TIME, TUMBLE_MAX_TICK_TIME, tumbleFraction )

				-- Tumble body created with zero velocity
				if vDirImpact:dot( vCollisionNormal ) > -0.99802673 then -- 4 degrees
					local vTangent = vDirImpact:cross( vCollisionNormal )
					vTangent = ( vTangent:cross( vCollisionNormal ) ):normalize()
					vTumbleVelocity = ( vCollisionNormal * vDirImpact:dot( vCollisionNormal ) - vTangent * vDirImpact:dot( vTangent ) * fFriction ) * fVel1Self
					--sm.debugDraw.addArrow( "vTangent", vCollisionPosition, vCollisionPosition + vTangent, BLUE )
				else
					vTumbleVelocity = vDirImpact * fVel1Self
					--sm.debugDraw.removeArrow( "vTangent" )
				end

				-- Value to slow down whatever hit the character
				vImpactReaction = vDirImpact * fVelDiffOther

				--sm.debugDraw.addArrow( "vCollisionNormal", vCollisionPosition, vCollisionPosition + vCollisionNormal, GREEN )
				--sm.debugDraw.addArrow( "vDirImpact", vCollisionPosition, vCollisionPosition + vDirImpact, RED )
				
				--sm.debugDraw.addArrow( "vVelImpact", vCollisionPosition - vVelImpact, vCollisionPosition, WHITE )
				--sm.debugDraw.addArrow( "vTumbleVelocity", vCollisionPosition, vCollisionPosition + vTumbleVelocity, CYAN )
				--sm.debugDraw.addArrow( "vImpactReaction", vCollisionPosition, vCollisionPosition + vImpactReaction, MAGENTA )
			end
		end
	end

	-- if landing on non moving object allways override the collision output  
	if fFallImpact > 2.5 and math.abs( velOther.z ) < 0.01 then 
		local reflectionDir = landVelocity - (vCollisionNormal * 2 * landVelocity:dot(vCollisionNormal))
		reflectionDir = reflectionDir:safeNormalize( sm.vec3.new(0,0,1) )

		vImpactReaction = reflectionDir * landVelocity:length() * fRestitution
		vTumbleVelocity = reflectionDir * landVelocity:length() * fRestitution
		collisionTumbleTicks = 0
	end

	local damage = fallDamage > 0 and fallDamage or math.max( collisionDamage, specialCollisionDamage )
	local tumbleTicks = specialCollision and 0 or math.max( fallTumbleTicks, collisionTumbleTicks )

	return damage, tumbleTicks, vTumbleVelocity, vImpactReaction
end

function ApplyCharacterImpulse( targetCharacter, direction, power, offset, tumbleModifier )
	local impulseDirection = direction:safeNormalize( sm.vec3.zero() )
	if impulseDirection:length2() >= FLT_EPSILON * FLT_EPSILON then
		local massImpulse = power / ( 5000.0 / 10.0 )
		local massImpulseSqrt = power / ( 5000.0 / 12.0 )
		local impulse = math.min( targetCharacter.mass * massImpulse + math.sqrt( targetCharacter.mass ) * massImpulseSqrt, power )
		impulse = math.min( impulse, MAX_CHARACTER_KNOCKBACK_VELOCITY * targetCharacter.mass )

		if targetCharacter:isTumbling() then
			targetCharacter:applyTumblingImpulse( impulseDirection * impulse * ( tumbleModifier or 1.0 ), offset )
		else
			sm.physics.applyImpulse( targetCharacter, impulseDirection * impulse )
		end
	end
end

function ApplyKnockback( targetCharacter, direction, power, offset )

	local impulseDirection = sm.vec3.new( direction.x, direction.y, 0 ):safeNormalize( sm.vec3.zero() )
	if impulseDirection:length2() >= FLT_EPSILON * FLT_EPSILON then
		local rightVector =  impulseDirection:cross( sm.vec3.new( 0, 0, 1 ) )
		impulseDirection = impulseDirection:rotate( 0.523598776, rightVector ) -- 30 degrees
	end

	ApplyCharacterImpulse( targetCharacter, impulseDirection, power, offset )
end

function GetClosestPlayer( worldPosition, maxDistance, world )
	local closestPlayer = nil
	local closestDd = maxDistance and ( maxDistance * maxDistance ) or math.huge
	local players = sm.player.getAllPlayers()
	for _, player in ipairs( players ) do
		if player.character and player.character:getWorld() == world then
			local dd = ( player.character.worldPosition - worldPosition ):length2()
			if dd <= closestDd then
				closestPlayer = player
				closestDd = dd
			end
		end
	end
	return closestPlayer
end

function GetClosestPlayerCharacterAlongAxis( worldPosition, axis, maxDistance, world )
	local closestCharacter = nil
	local closestProjectedPosition = nil
	local closestDd = maxDistance and ( maxDistance * maxDistance ) or math.huge
	local players = sm.player.getAllPlayers()
	for _, player in ipairs( players ) do
		local playerCharacter = sm.exists( player.character ) and player.character or nil
		if playerCharacter and playerCharacter:getWorld() == world then
			local relativePosition = playerCharacter.worldPosition - worldPosition
			local relativeProjectedPosition = relativePosition - ( axis * axis:dot( relativePosition ) )
			local projectedPosition = worldPosition + relativeProjectedPosition

			local dd = relativeProjectedPosition:length2()
			if dd <= closestDd then
				closestCharacter = playerCharacter
				closestProjectedPosition = projectedPosition
				closestDd = dd
			end
		end
	end
	return closestCharacter, closestProjectedPosition
end

local ToolItems = {
	[tostring( tool_connect )] = obj_tool_connect,
	[tostring( tool_paint )] = obj_tool_paint,
	[tostring( tool_weld )] = obj_tool_weld,
	[tostring( tool_spudgun )] = obj_tool_spudgun,
	[tostring( tool_shotgun )] = obj_tool_frier,
	[tostring( tool_gatling )] = obj_tool_spudling,
	[tostring( tool_handbook )] = obj_tool_handbook,
	[tostring( tool_scrap_spudgun )] = obj_tool_scrap_spudgun,
	[tostring( tool_launcher )] = obj_tool_launcher,
	["ed185725-ea12-43fc-9cd7-4295d0dbf88b"] = obj_tool_sledgehammer, --Creative sledgehammer
}
function GetToolProxyItem( toolUuid )
	return ToolItems[tostring( toolUuid )]
end

function FindFirstInteractable( uuid )
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs( bodies ) do
		for _, shape in ipairs( body:getShapes() ) do
			if tostring( shape:getShapeUuid() ) == uuid then
				return shape:getInteractable()
			end
		end
	end	
end

function FindFirstInteractableWithinCell( uuid, x, y )
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs( bodies ) do
		for _, shape in ipairs( body:getShapes() ) do
			if tostring( shape:getShapeUuid() ) == uuid then
				local ix, iy = getCell( shape:getWorldPosition().x, shape:getWorldPosition().y )
				if ix == x and iy == y then
					return shape:getInteractable()
				end
			end
		end
	end	
end

function FindInteractablesWithinCell( uuid, x, y )
	local tbl = {}
	local bodies = sm.body.getAllBodies()
	for _, body in ipairs( bodies ) do
		for _, shape in ipairs( body:getShapes() ) do
			if tostring( shape:getShapeUuid() ) == uuid then
				local ix, iy = getCell( shape:getWorldPosition().x, shape:getWorldPosition().y )
				if ix == x and iy == y then
					table.insert( tbl, shape:getInteractable() )
				end
			end
		end
	end
	return tbl	
end

function ConstructionRayCast( constructionFilters )
	local valid, result = sm.localPlayer.getLatestRaycast()
	if valid then
		for _, filter in ipairs( constructionFilters ) do
			if result.type == filter then

				local groundPointOffset = -( sm.construction.constants.subdivideRatio_2 - 0.04 + sm.construction.constants.shapeSpacing + 0.005 )
				local pointLocal = result.pointLocal + result.normalLocal * groundPointOffset

				-- Compute grid pos
				local size = sm.vec3.new( 3, 3, 1 )
				local size_2 = sm.vec3.new( 1, 1, 0 )
				local a = pointLocal * sm.construction.constants.subdivisions
				local gridPos = sm.vec3.new( math.floor( a.x ), math.floor( a.y ), a.z ) - size_2

				-- Compute world pos
				local worldPos = gridPos * sm.construction.constants.subdivideRatio + ( size * sm.construction.constants.subdivideRatio ) * 0.5

				return valid, worldPos, result.normalWorld
			end
		end
	end
	return false, nil, nil
end

function UpdateForceBuildText()
	local valid = ConstructionRayCast( { "terrainSurface", "terrainAsset", "body", "joint", "voxelTerrain" } )
	if valid then
		local keyBindingText = sm.gui.getKeyBinding( "ForceBuild", true )
		sm.gui.setInteractionText( "", keyBindingText, "#{INTERACTION_FORCE_BUILD}" )
	end
end

function GetWorld( userdataObject )
	local userdataType = enumType( userdataObject )
	if userdataObject and isAnyOf( userdataType, { LUA_TYPE.character, LUA_TYPE.body, LUA_TYPE.harvestable, LUA_TYPE.player, LUA_TYPE.unit, LUA_TYPE.shape, LUA_TYPE.interactable, LUA_TYPE.joint, LUA_TYPE.world } ) then
		if sm.exists( userdataObject ) then
			if userdataType == LUA_TYPE.character or userdataType == LUA_TYPE.body or userdataType == LUA_TYPE.harvestable then
				return userdataObject:getWorld()
			elseif userdataType == LUA_TYPE.player or userdataType == LUA_TYPE.unit then
				if userdataObject.character then
					return userdataObject.character:getWorld()
				end
			elseif userdataType == LUA_TYPE.shape or userdataType == LUA_TYPE.interactable then
				if userdataObject.body then
					return userdataObject.body:getWorld()
				end
			elseif userdataType == LUA_TYPE.joint then
				local hostShape = userdataObject:getShapeA()
				if hostShape and hostShape.body then
					return hostShape.body:getWorld()
				end
			elseif userdataType == LUA_TYPE.world then
				return userdataObject
			end
			return nil
		else
			return nil
		end
	end
	sm.log.warning( "Tried to get world for an unsupported type: "..type( userdataObject ) )
	return nil
end

function InSameWorld( userdataObjectA, userdataObjectB )
	local worldA = GetWorld( userdataObjectA )
	local worldB = GetWorld( userdataObjectB )

	local result = ( worldA ~= nil and worldB ~= nil and worldA == worldB )
	return result
end

function FindAttackableShape( worldPosition, radius, attackLevel )
	local nearbyShapes = sm.shape.shapesInSphere( worldPosition, radius )
	local destructableNearbyShapes = {}
	for _, shape in ipairs( nearbyShapes )do
		local canAttack = true
		if isIgnoreAttackShape( shape ) then
			local shapes = shape.body:getShapes()
			if shapes and #shapes == 1 then
				canAttack = false
			end
		end
		if canAttack then
			local shapeQualityLevel = sm.item.getQualityLevel( shape.shapeUuid )
			if shape.destructable and attackLevel >= shapeQualityLevel and shapeQualityLevel > 0 then
				destructableNearbyShapes[#destructableNearbyShapes+1] = shape
			end
		end
	end
	if #destructableNearbyShapes > 0 then
		local targetShape = destructableNearbyShapes[math.random( 1, #destructableNearbyShapes )]
		local targetPosition = targetShape.worldPosition
		if sm.item.isBlock( targetShape.shapeUuid ) then
			local targetLocalPosition = targetShape:getClosestBlockLocalPosition( worldPosition )
			targetPosition = targetShape.body:transformPoint( ( targetLocalPosition + sm.vec3.new( 0.5, 0.5, 0.5 ) ) * 0.25 )
		end
		return targetShape, targetPosition
	end
	return nil, nil
end

function BinarySearchInterval( array, targetValue )
	local lowerBound = 1
	local upperBound = #array
	if targetValue < array[lowerBound] then
		return lowerBound -- Clamp to lower index
	elseif targetValue > array[upperBound] then
		return upperBound -- Clamp to upper index
	end
	
	while lowerBound <= upperBound do
		local middleIndex = math.floor( ( lowerBound + upperBound ) * 0.5 )
		if array[middleIndex] < targetValue then
			lowerBound = middleIndex + 1
		elseif array[middleIndex] > targetValue then
			upperBound = middleIndex - 1
		else
			return middleIndex -- Found exact value
		end
	end
	return upperBound -- No exact value, return the interval index
end

function RotateAxis( vector, xAxis, zAxis, inverse )
	local yAxis = zAxis:cross( xAxis )
	if inverse then
		-- Transpose rotation matrix
		return sm.vec3.new(
			vector.x * xAxis.x + vector.y * xAxis.y + vector.z * xAxis.z,
			vector.x * yAxis.x + vector.y * yAxis.y + vector.z * yAxis.z,
			vector.x * zAxis.x + vector.y * zAxis.y + vector.z * zAxis.z
		)
	end
	return sm.vec3.new(
		vector.x * xAxis.x + vector.y * yAxis.x + vector.z * zAxis.x,
		vector.x * xAxis.y + vector.y * yAxis.y + vector.z * zAxis.y,
		vector.x * xAxis.z + vector.y * yAxis.z + vector.z * zAxis.z
	)
end

function RotateSticky( minSticky, maxSticky, xAxis, zAxis, inverse )
	local minFlags = RotateAxis( minSticky, xAxis, zAxis, inverse )
	local maxFlags = RotateAxis( maxSticky, xAxis, zAxis, inverse )

	local NX = ( minFlags.x > 0 or maxFlags.x < 0 ) and 1 or 0
	local NY = ( minFlags.y > 0 or maxFlags.y < 0 ) and 1 or 0
	local NZ = ( minFlags.z > 0 or maxFlags.z < 0 ) and 1 or 0
	local PX = ( maxFlags.x > 0 or minFlags.x < 0 ) and 1 or 0
	local PY = ( maxFlags.y > 0 or minFlags.y < 0 ) and 1 or 0
	local PZ = ( maxFlags.z > 0 or minFlags.z < 0 ) and 1 or 0

	local rotatedMinSticky = sm.vec3.new( NX, NY, NZ )
	local rotatedMaxSticky = sm.vec3.new( PX, PY, PZ )
	return rotatedMinSticky, rotatedMaxSticky
end

local EasyDifficultySettings =
{
	playerTakeDamageMultiplier = 0.5
}
local NormalDifficultySettings =
{
	playerTakeDamageMultiplier = 1.0
}
function GetDifficultySettings()
	local difficulties = { EasyDifficultySettings, NormalDifficultySettings }
	local difficultyIndex = sm.game.getDifficulty()
	if difficultyIndex < 0 then
		difficultyIndex = 2 -- Default to Normal difficulty
	else
		difficultyIndex = difficultyIndex + 1 -- Lua index
	end
	return difficulties[difficultyIndex]
end

function SpawnDebris( character, bone, debrisEffect, offsetPos, offsetRot )
	local bonePos = character:getTpBonePos( bone )
	local boneRot = character:getTpBoneRot( bone )

	if bonePos == nil or boneRot == nil then
		sm.log.error( "SpawnDebris failed to fetch position for bone named: '",bone,"' for character:", character:getCharacterType() )
		return
	end

	local position = offsetPos and bonePos + boneRot * offsetPos or bonePos
	local rotation = offsetRot and boneRot * offsetRot or boneRot

	local relPos = position - character.worldPosition

	local velocity = relPos:safeNormalize( sm.vec3.new( 0, 0, 1 ) ) * ( math.random() + 1 ) * 2 + sm.vec3.new( 0, 0, math.random() + 2 ) + character.velocity
	local color = character:getColor()

	sm.effect.playEffect( debrisEffect, position, velocity, rotation, nil, { Color = color, startVelocity = velocity } )
end

function FindWidget( widget, name, throw )
	if widget == nil then 
		return nil
	end
	if widget.Name == name then
		return widget
	end
	if widget.Childs then
		for _, child in ipairs( widget.Childs ) do
			local find = FindWidget( child, name )
			if find then
				return find
			end
		end
	end

	if throw then
		assert( false, "Could not find widget named '"..name.."'" )
	end

	return nil
end

function IndexWidgets( widget, table )
	table = table or {}
	if widget.Name then
		if table[widget.Name] then
			sm.log.error( "Duplicate widget name", widget.Name )
		end
		table[widget.Name] = widget
	end
	if widget.Childs then
		for _, child in ipairs( widget.Childs ) do
			IndexWidgets( child, table )
		end
	end
	return table
end

function DeepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = DeepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

function ReplaceSubLayouts( widget )
	if widget.Childs then
		for index, child in ipairs( widget.Childs ) do
			if child.Type == "SubLayout" then
				local x = child.x
				local y = child.y
				local sublayout = sm.json.open( child.SubLayoutPath )
				widget.Childs[index] = sublayout
				widget.Childs[index].x = x
				widget.Childs[index].y = y
			end
			ReplaceSubLayouts( child )
		end
	end
end

function SendEvent( object, callbackName, params )
	local t = type( object )
	if t == "World" then
		sm.event.sendToWorld( object, callbackName, params )
	elseif t == "Unit" then
		sm.event.sendToUnit( object, callbackName, params )
	elseif t == "Player" then
		sm.event.sendToPlayer( object, callbackName, params )
	elseif t == "Character" then
		sm.event.sendToCharacter( object, callbackName, params )
	elseif t == "Harvestable" then
		sm.event.sendToHarvestable( object, callbackName, params )
	elseif t == "Interactable" then
		sm.event.sendToInteractable( object, callbackName, params )
	elseif t == "ScriptableObject" then
		sm.event.sendToScriptableObject( object, callbackName, params )
	elseif t == "Tool" then
		sm.event.sendToTool( object, callbackName, params )
	else
		sm.log.error( "Tried to send event to non-supported type", t )
	end
end

function IsEmptyTable( table )
	return next( table ) == nil
end

function GetHighestValue( t, field )
    local highest = nil
	local highestKey = nil
    for key, value in pairs( t ) do
        if highest == nil or value[field] > highest then
			highest = value[field]
			highestKey = key
        end
    end
    return highestKey,highest
end

function GetCellDataStorage( worldId )
	if g_cellDataStorage == nil then
		g_cellDataStorage = {}
	end
	if g_cellDataStorage[worldId] == nil then
		g_cellDataStorage[worldId] = sm.storage.load( "cds_"..worldId )
		if g_cellDataStorage[worldId] == nil then
			sm.log.warning( "Failed to load cell data for world", worldId )
		end
	end
	return g_cellDataStorage[worldId]
end

function GetTerrainData( worldId )
	if g_TerrainData == nil then
		g_TerrainData = {}
	end
	if g_TerrainData[worldId] == nil then
		g_TerrainData[worldId] = sm.storage.loadTerrainData( worldId )
		if g_TerrainData[worldId] == nil then
			sm.log.warning( "Failed to load terrain data for world", worldId )
		end
	end
	return g_TerrainData[worldId]
end

function CalculateTileStorageKey( worldId, cellX, cellY )
	local terrainData
	if g_cellData ~= nil then
		-- called in terrain script
		terrainData = g_cellData
	else
		-- called in game
		terrainData = GetTerrainData( worldId )
		if terrainData == nil then
			return nil
		end
		if not ( terrainData.xOffset and terrainData.yOffset and terrainData.rotation ) then
			terrainData = terrainData[2] -- terrain_custom
		end
	end

	if terrainData == nil then
		return nil
	end

	-- No tile at this cell (e.g. underground cave/pocket cells have no base tile)
	if terrainData.uid then
		local uid = terrainData.uid[cellY] and terrainData.uid[cellY][cellX]
		if uid == nil or uid:isNil() then
			return nil
		end
	end

	local rotation = terrainData.rotation[cellY][cellX]
	local xOffset = terrainData.xOffset[cellY][cellX]
	local yOffset = terrainData.yOffset[cellY][cellX]

	local rx, ry
	if rotation == 1 then
		rx = -yOffset
		ry = xOffset
	elseif rotation == 2 then
		rx = -xOffset
		ry = -yOffset
	elseif rotation == 3 then
		rx = yOffset
		ry = -xOffset
	else
		rx = xOffset
		ry = yOffset
	end

	local tx = cellX - rx
	local ty = cellY - ry

	return "ts_"..worldId..":("..tx..","..ty..")"
end

function CalculateIndoorTileStorageKey( worldId ) -- Warehouse
	return "ts_"..worldId..":(0,0)"
end

	local function UnrotateOffset( rotation, srcOffX, srcOffY )
	if rotation == 1 then     return -srcOffY, srcOffX
	elseif rotation == 2 then return -srcOffX, -srcOffY
	elseif rotation == 3 then return srcOffY, -srcOffX
	else                      return srcOffX, srcOffY
	end
end

function CalculateCaveTileStorageKey( worldId, cellX, cellY, rotation, srcOffset, dstOffset )
	local rx, ry = UnrotateOffset( rotation, srcOffset.x, srcOffset.y )
	local originX = cellX - rx
	local originY = cellY - ry
	return "ts_"..worldId..":cave("..originX..","..originY..","..dstOffset.z..")"
end

function FindPocketAtPosition( pockets, localChunkX, localChunkY, chunkZ )
	for i = 1, #pockets do
		local rotation, srcOffset, dstOffset, srcSize = DecodePocketTransform( pockets[i] )
		local dstSizeX = rotation % 2 == 1 and srcSize.y or srcSize.x
		local dstSizeY = rotation % 2 == 1 and srcSize.x or srcSize.y
		if localChunkX >= dstOffset.x and localChunkX < dstOffset.x + dstSizeX
			and localChunkY >= dstOffset.y and localChunkY < dstOffset.y + dstSizeY
			and chunkZ >= dstOffset.z and chunkZ < dstOffset.z + srcSize.z then
			return i, rotation, srcOffset, dstOffset, srcSize
		end
	end
	return nil
end

function CalculatePocketOriginChunk( cellX, cellY, rotation, srcOffset, dstOffset, srcSize )
	local absChunkX = cellX * 4 + dstOffset.x
	local absChunkY = cellY * 4 + dstOffset.y
	local originX, originY
	if rotation == 1 then
		originX = absChunkX + ( srcSize.y - 1 ) + srcOffset.y
		originY = absChunkY - srcOffset.x
	elseif rotation == 2 then
		originX = absChunkX + ( srcSize.x - 1 ) + srcOffset.x
		originY = absChunkY + ( srcSize.y - 1 ) + srcOffset.y
	elseif rotation == 3 then
		originX = absChunkX - srcOffset.y
		originY = absChunkY + ( srcSize.x - 1 ) + srcOffset.x
	else
		originX = absChunkX - srcOffset.x
		originY = absChunkY - srcOffset.y
	end
	return originX, originY
end

function CalculatePocketTileStorageKey( worldId, cellX, cellY, rotation, srcOffset, dstOffset, srcSize )
	local originX, originY = CalculatePocketOriginChunk( cellX, cellY, rotation, srcOffset, dstOffset, srcSize )
	






	return "ts_"..worldId..":pocket("..originX..","..originY..","..dstOffset.z..")"
end

function CalculateCavePocketKey( worldId, position )
	local terrainData
	if g_cellData ~= nil then
		terrainData = g_cellData
	else
		terrainData = GetTerrainData( worldId )
	end

	if terrainData == nil then
		return nil
	end

	local cellX = math.floor( position.x / 64 )
	local cellY = math.floor( position.y / 64 )
	local chunkZ = math.floor( position.z / 16 ) -- CHUNK_SIZE = 16

	-- Check pockets (sub-cell positioned, variable xyz)
	local pocketsRow = terrainData.pockets and terrainData.pockets[cellY]
	local pockets = pocketsRow and pocketsRow[cellX]
	if pockets then
		local localChunkX = math.floor( position.x / 16 ) % 4
		local localChunkY = math.floor( position.y / 16 ) % 4
		local pocketIdx, rotation, srcOffset, dstOffset, srcSize = FindPocketAtPosition( pockets, localChunkX, localChunkY, chunkZ )
		if pocketIdx then
			return CalculatePocketTileStorageKey( worldId, cellX, cellY, rotation, srcOffset, dstOffset, srcSize )
		end
	end

	-- Check caves (cell-aligned in x,y, variable z)
	local cavesRow = terrainData.caves and terrainData.caves[cellY]
	local caves = cavesRow and cavesRow[cellX]
	if caves then
		for i = 1, #caves do
			local rotation, srcOffset, dstOffset, srcSize = DecodeCaveTransform( caves[i] )
			if chunkZ >= dstOffset.z and chunkZ < dstOffset.z + srcSize.z then
				return CalculateCaveTileStorageKey( worldId, cellX, cellY, rotation, srcOffset, dstOffset )
			end
		end
	end

	return nil
end

function GetCavePocketTilePath( worldId, position )
	local terrainData
	if g_cellData ~= nil then
		terrainData = g_cellData
	else
		terrainData = GetTerrainData( worldId )
	end

	if terrainData == nil then
		return nil
	end

	local tileList = terrainData.tileList
	if tileList == nil then
		return nil
	end

	local tileData = GetTileData( worldId )
	if tileData == nil then
		return nil
	end

	local cellX = math.floor( position.x / 64 )
	local cellY = math.floor( position.y / 64 )
	local chunkZ = math.floor( position.z / 16 )

	-- Check pockets
	local pocketsRow = terrainData.pockets and terrainData.pockets[cellY]
	local pockets = pocketsRow and pocketsRow[cellX]
	if pockets then
		local localChunkX = math.floor( position.x / 16 ) % 4
		local localChunkY = math.floor( position.y / 16 ) % 4
		local pocketIdx = FindPocketAtPosition( pockets, localChunkX, localChunkY, chunkZ )
		if pocketIdx then
			local tileUid = tileList[bit.band( pockets[pocketIdx], 0xff )]
			if tileUid then
				local entry = tileData[tostring( tileUid )]
				if entry then
					return entry.path, tileUid
				end
			end
			return nil
		end
	end

	-- Check caves
	local cavesRow = terrainData.caves and terrainData.caves[cellY]
	local caves = cavesRow and cavesRow[cellX]
	if caves then
		for i = 1, #caves do
			local rotation, srcOffset, dstOffset, srcSize = DecodeCaveTransform( caves[i] )
			if chunkZ >= dstOffset.z and chunkZ < dstOffset.z + srcSize.z then
				local tileUid = tileList[bit.band( caves[i], 0xff )]
				if tileUid then
					local entry = tileData[tostring( tileUid )]
					if entry then
						return entry.path, tileUid
					end
				end
				return nil
			end
		end
	end

	return nil
end

function GetTileData( worldId )
	if g_TileData == nil then
		g_TileData = {}
	end
	if g_TileData[worldId] == nil then
		g_TileData[worldId] = sm.storage.load( "tileData"..worldId )
	end
	return g_TileData[worldId]
end

function GetTileRangesFromCell( cellX, cellY, worldId )
	local terrainData = GetTerrainData( worldId )
	local tileData = GetTileData( worldId )

    if terrainData == nil or tileData == nil then
       return nil,nil,nil,nil
    end

    local tileUuid = terrainData.uid and terrainData.uid[cellY] and terrainData.uid[cellY][cellX]
    if tileUuid and not tileUuid:isNil() then
        local tileRange = tileData[tostring( tileUuid )].size - 1

        local xOffset =  terrainData.xOffset[cellY][cellX]
        local yOffset =  terrainData.yOffset[cellY][cellX]
        local rotation = terrainData.rotation[cellY][cellX]

        local xMin, yMin
        if rotation == 0 then
            xMin = cellX - xOffset
            yMin = cellY - yOffset
        elseif rotation == 1 then
            xMin = cellX - ( tileRange - yOffset )
            yMin = cellY - xOffset
        elseif rotation == 2 then
            xMin = cellX - ( tileRange - xOffset )
            yMin = cellY - ( tileRange - yOffset )
        elseif rotation == 3 then
            xMin = cellX - yOffset
            yMin = cellY - ( tileRange - xOffset )
        end

        local xMax = xMin + tileRange
        local yMax = yMin + tileRange

        return xMin,xMax,yMin,yMax
    end

    -- Cave/pocket cells cannot be resolved from cell coordinates alone. Use GetTileRanges with a world position instead.
    local cavesRow = terrainData.caves and terrainData.caves[cellY]
    local caves = cavesRow and cavesRow[cellX]
    if caves and #caves > 0 then
        sm.log.error( "GetTileRangesFromCell was called for a cave cell. Use GetTileRanges with a world position instead." )
        return nil, nil, nil, nil
    end

    local pocketsRow = terrainData.pockets and terrainData.pockets[cellY]
    local pockets = pocketsRow and pocketsRow[cellX]
    if pockets and #pockets > 0 then
        sm.log.error( "GetTileRangesFromCell was called for a pocket cell. Use GetTileRanges with a world position instead." )
        return nil, nil, nil, nil
    end

    return nil,nil,nil,nil
end

function GetTileRanges( worldPosition, worldId )
    local cellX = math.floor( worldPosition.x / 64 )
    local cellY = math.floor( worldPosition.y / 64 )

    local terrainData = GetTerrainData( worldId )
    if terrainData == nil then
        return nil, nil, nil, nil
    end

    -- Surface tile: delegate to cell-based resolution
    local tileUuid = terrainData.uid and terrainData.uid[cellY] and terrainData.uid[cellY][cellX]
    if tileUuid and not tileUuid:isNil() then
        return GetTileRangesFromCell( cellX, cellY, worldId )
    end

    local tileData = GetTileData( worldId )
    local tileList = terrainData.tileList

    -- Check caves (cell-aligned in x,y, variable z — requires position to disambiguate stacked caves)
    local cavesRow = terrainData.caves and terrainData.caves[cellY]
    local caves = cavesRow and cavesRow[cellX]
    if caves and #caves > 0 and tileData and tileList then
        local chunkZ = math.floor( worldPosition.z / 16 )
        for i = 1, #caves do
            local value = caves[i]
            local rotation, srcOffset, dstOffset, srcSize = DecodeCaveTransform( value )
            if chunkZ >= dstOffset.z and chunkZ < dstOffset.z + srcSize.z then
                local tileUid = tileList[bit.band( value, 0xff )]
                if tileUid then
                    local entry = tileData[tostring( tileUid )]
                    if entry and entry.chunkSize then
                        local caveSizeX = math.ceil( entry.chunkSize.x / 4 )
                        local caveSizeY = math.ceil( entry.chunkSize.y / 4 )
                        local worldSizeX = rotation % 2 == 1 and caveSizeY or caveSizeX
                        local worldSizeY = rotation % 2 == 1 and caveSizeX or caveSizeY

                        local wx, wy
                        if rotation == 0 then
                            wx = srcOffset.x
                            wy = srcOffset.y
                        elseif rotation == 1 then
                            wx = ( worldSizeX - 1 ) - srcOffset.y
                            wy = srcOffset.x
                        elseif rotation == 2 then
                            wx = ( worldSizeX - 1 ) - srcOffset.x
                            wy = ( worldSizeY - 1 ) - srcOffset.y
                        elseif rotation == 3 then
                            wx = srcOffset.y
                            wy = ( worldSizeY - 1 ) - srcOffset.x
                        end

                        local xMin = cellX - wx
                        local yMin = cellY - wy
                        local xMax = xMin + worldSizeX - 1
                        local yMax = yMin + worldSizeY - 1
                        return xMin, xMax, yMin, yMax
                    end
                end
            end
        end
    end

    -- Check pockets (sub-cell positioned, variable xyz)
    local pocketsRow = terrainData.pockets and terrainData.pockets[cellY]
    local pockets = pocketsRow and pocketsRow[cellX]
    if pockets and tileData and tileList then
        local localChunkX = math.floor( worldPosition.x / 16 ) % 4
        local localChunkY = math.floor( worldPosition.y / 16 ) % 4
        local chunkZ = math.floor( worldPosition.z / 16 )
        local pocketIdx, rotation, srcOffset, dstOffset, srcSize = FindPocketAtPosition( pockets, localChunkX, localChunkY, chunkZ )
        if pocketIdx then
            local tileUid = tileList[bit.band( pockets[pocketIdx], 0xff )]
            if tileUid then
                local entry = tileData[tostring( tileUid )]
                if entry and entry.chunkSize then
                    local tileSizeX = entry.chunkSize.x
                    local tileSizeY = entry.chunkSize.y
                    local worldSizeX = rotation % 2 == 1 and tileSizeY or tileSizeX
                    local worldSizeY = rotation % 2 == 1 and tileSizeX or tileSizeY
                    local originX, originY = CalculatePocketOriginChunk( cellX, cellY, rotation, srcOffset, dstOffset, srcSize )
                    -- Origin is the world chunk of source (0,0), ranges are calculated from that and then rotated according to pocket rotation to find the world chunk ranges that the pocket occupies.
                    local chunkMinX, chunkMaxX, chunkMinY, chunkMaxY
                    if rotation == 0 then
                        chunkMinX = originX
                        chunkMaxX = originX + worldSizeX - 1
                        chunkMinY = originY
                        chunkMaxY = originY + worldSizeY - 1
                    elseif rotation == 1 then
                        chunkMinX = originX - worldSizeX + 1
                        chunkMaxX = originX
                        chunkMinY = originY
                        chunkMaxY = originY + worldSizeY - 1
                    elseif rotation == 2 then
                        chunkMinX = originX - worldSizeX + 1
                        chunkMaxX = originX
                        chunkMinY = originY - worldSizeY + 1
                        chunkMaxY = originY
                    elseif rotation == 3 then
                        chunkMinX = originX
                        chunkMaxX = originX + worldSizeX - 1
                        chunkMinY = originY - worldSizeY + 1
                        chunkMaxY = originY
                    end
                    local xMin = math.floor( chunkMinX / 4 )
                    local yMin = math.floor( chunkMinY / 4 )
                    local xMax = math.floor( chunkMaxX / 4 )
                    local yMax = math.floor( chunkMaxY / 4 )
                    return xMin, xMax, yMin, yMax
                end
            end
        end
    end

    return nil, nil, nil, nil
end

function GetTileZeroCell( cellX, cellY, worldId )
	local terrainData = GetTerrainData( worldId )

    if terrainData == nil then
       return nil,nil
    end

	local xOffset =  terrainData.xOffset[cellY][cellX]
    local yOffset =  terrainData.yOffset[cellY][cellX]
    local rotation = terrainData.rotation[cellY][cellX]

	local x0, y0
    if rotation == 0 then
        x0 = cellX - xOffset
        y0 = cellY - yOffset
    elseif rotation == 1 then
        x0 = cellX + yOffset
        y0 = cellY - xOffset
    elseif rotation == 2 then
        x0 = cellX + xOffset
        y0 = cellY + yOffset
    elseif rotation == 3 then
        x0 = cellX - yOffset
        y0 = cellY + xOffset
    end
	return x0, y0
end

function SetTileStorageFlag( tileStorageKey, flag )
	TileStorageManager.Sv_SyncedSetValueInSubTable( tileStorageKey, TILESTORAGE_FLAGS_TABLE, flag, true )
	TileStorageManager.Sv_Save()
end

function UnsetTileStorageFlag( tileStorageKey, flag )
	TileStorageManager.Sv_SyncedSetValueInSubTable( tileStorageKey, TILESTORAGE_FLAGS_TABLE, flag, nil )
	TileStorageManager.Sv_Save()
end

function SetTileStorageFlagAtPosition( world, position, flag )
	local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )
	if tileStorageKey then
		SetTileStorageFlag( tileStorageKey, flag )
	end
end

function UnsetTileStorageFlagAtPosition( world, position, flag )
	local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )
	if tileStorageKey then
		UnsetTileStorageFlag( tileStorageKey, flag )
	end
end

function GetTileTagKey( tileStorageKey, groupTag )
	return tileStorageKey.."|"..groupTag
end

function SetLimitedLootTileLimit( world, position, limitedLoot, limit )
	local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )
	if tileStorageKey == nil then return end
	g_limitedLootLimits = g_limitedLootLimits or {}
	local value = g_limitedLootLimits[tileStorageKey] or {}
	if value[limitedLoot] == nil then
		value[limitedLoot] = { limit = limit, quantity = 0 }
	else
		value[limitedLoot].limit = limit
	end
	g_limitedLootLimits[tileStorageKey] = value
end

function CanDropLimitedLoot( world, position, limitedLoot )
	local tileStorageKey = TileStorageManager.Sv_GetTileStorageKeyFromPosition( world, position )
	if tileStorageKey == nil then return true end
	g_limitedLootLimits = g_limitedLootLimits or {}
	local value = g_limitedLootLimits[tileStorageKey] or nil
	if value == nil or value[limitedLoot] == nil then
		return true
	end
	return value[limitedLoot].quantity < value[limitedLoot].limit
end

function TriggerResultContainsLocalPlayer( results )
	if results == nil then return false end
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			if result:isPlayer() and result == sm.localPlayer.getPlayer().character then
				return true
			end
		end
	end
	return false
end

function TriggerResultContainsAnyPlayer( results )
	if results == nil then return false end
	for _,result in ipairs( results ) do
		if sm.exists( result ) then
			if result:isPlayer() then
				return true
			end
		end
	end
	return false
end

function TriggerContentsContainsLocalPlayer( contents )
	for _,content in ipairs( contents ) do
        if content == sm.localPlayer.getPlayer().character then
            return true
        end
    end
    return false
end

function TriggerContentsContainsAnyPlayer( contents )
	if contents == nil then return false end
	for _,content in ipairs( contents ) do
        if type( content ) == "Character" and content:isPlayer() then
            return true
        end
    end
    return false
end

function FireTriggerEventForPlayers( results, eventName )
    for _, result in ipairs( results ) do
        if result and sm.exists( result ) and result:isPlayer() then
            local player = result:getPlayer()
            if player then
                sm.event.sendToPlayer( player, eventName )
            end
        end
    end
end

function GetPlayersInRange( position, range, world )
	local players = sm.player.getAllPlayers()
	local playersInRange = {}
	for _, player in ipairs( players ) do
		if player.character and player.character:getWorld() == world then
			local distanceSqr = ( player.character.worldPosition - position ):length2()
			if distanceSqr <= range * range then
				playersInRange[#playersInRange+1] = player
			end
		end
	end
	return playersInRange
end

function GetPlayersInWorld( world )
	local players = sm.player.getAllPlayers()
	local playersInWorld = {}
	for _, player in ipairs( players ) do
		if player.character and player.character:getWorld() == world then
			playersInWorld[#playersInWorld+1] = player
		end
	end
	return playersInWorld
end

function Vec3IfArray( arr )
	if type( arr ) == "Vec3" then
		return arr
	end
	return sm.vec3.new( arr[1], arr[2], arr[3] )
end

function ColorFromGuiColor( colorString )
	local tokens = {}
	for token in string.gmatch(colorString, "%S+") do
		table.insert(tokens, token)
	end
	return sm.color.new( tonumber( tokens[1] ), tonumber( tokens[2] ), tonumber( tokens[3] ), tonumber( tokens[4] ) )
end

function HSVtoRGB( h, s, v )
    if s <= 0 then return v, v, v end

    local i = math.floor( h * 6 )
    local f = h * 6 - i
    local p = v * ( 1 - s )
    local q = v * ( 1 - s * f )
    local t = v * ( 1 - s * ( 1 - f ) )

    local r, g, b
    local case = i % 6
    if case == 0 then
        r, g, b = v, t, p
    elseif case == 1 then
        r, g, b = q, v, p
    elseif case == 2 then
        r, g, b = p, v, t
    elseif case == 3 then
        r, g, b = p, q, v
    elseif case == 4 then
        r, g, b = t, p, v
    else
        r, g, b = v, p, q
    end
    return r, g, b
end

function IsArray( table )
	if type( table ) ~= "table" or IsEmptyTable( table ) then
		return false
	end
	local i = 0
    for _,_ in pairs( table ) do
        i = i + 1
        if table[i] == nil then
            return false
        end
    end

    return true
end

--Marsaglia method for random vector
function RandomUnitVector()
	local z = math.random() * 2 - 1
	local theta = math.random() * 2 * math.pi
	local r = math.sqrt( 1 - z*z )
	local x = r * math.cos( theta )
	local y = r * math.sin( theta )
	return sm.vec3.new( x, y, z )
end

function GetInteractionKeybinding()
	return sm.gui.getKeyBinding( sm.localPlayer.secondaryInteractBusy() and "Use" or "Attack", true )
end

function SetKeyLockCounterValue( tileStorageKey, keyTag, keyCount )
	TileStorageManager.Sv_SetValueInSubTable( tileStorageKey, KEY_LOCK_COUNTER_TABLE, keyTag, keyCount )
	KinematicManager.Sv_KeyLockCounterSet( tileStorageKey, keyTag, keyCount )
end

function EvaluateWaypointTrack( waypointTrackParamData, worldPosition, worldRotation, scale, world )
	-- Translate track nodes into world space
	local waypointTrackParam = waypointTrackParamData.waypointTrack or waypointTrackParamData.actorTrack
	local track = waypointTrackParam.waypointTrack or waypointTrackParam.actorTrack
	if track.actorTrack then
		track = track.actorTrack
	end
	local worldWaypointTrack = {}
	for _, waypointTrackNode in ipairs( track ) do
		local worldWaypointTrackNode = DeepCopy( waypointTrackNode )
		worldWaypointTrackNode.position = worldPosition + worldRotation * ( waypointTrackNode.position * scale )
		worldWaypointTrackNode.rotation = worldRotation * sm.quat.fromEuler( waypointTrackNode.rotation )
		worldWaypointTrackNode.world = world

		worldWaypointTrack[#worldWaypointTrack+1] = worldWaypointTrackNode
	end

	return worldWaypointTrack
end

function SetNeedResourceInteractionText( text1, binding1, text2, resourceString )
	sm.gui.setInteractionText( text1, binding1, text2.." #FFFFC0"..resourceString )
end

function FindFirstNearbyNode( position, tags )
	local cellX = math.floor( position.x / 64 )
    local cellY = math.floor( position.y / 64 )
	for y = cellY - 1, cellY + 1 do
		for x = cellX - 1, cellX + 1 do
            local nodes = sm.cell.getNodesByTags( x, y, tags )
            if nodes[1] then
                return nodes[1]
            end
        end
    end
	return nil
end

function FindClosestMatchingNode( position, tags, maximumDistance )
	local closestNode = nil
	local closestDistanceSqr = math.huge
	local cellX = math.floor( position.x / 64 )
	local cellY = math.floor( position.y / 64 )
	for y = cellY - 1, cellY + 1 do
		for x = cellX - 1, cellX + 1 do
			local nodes = sm.cell.getNodesByTags( x, y, tags )
			for _, node in ipairs( nodes ) do
				local distanceSqr = ( node.position - position ):length2()
				if distanceSqr < closestDistanceSqr
				and ( maximumDistance == nil or distanceSqr <= maximumDistance * maximumDistance ) then
					closestNode = node
					closestDistanceSqr = distanceSqr
				end
			end
		end
	end
	return closestNode
end

PowerConsumeType = {
	resource = 2,
	failure = 3
}

function TryConsumePowerResource( interactable, targetResource, connectionType, resourceAmount )
	resourceAmount = resourceAmount or 1
	local parents = interactable:getParents()
	local matchingParents = {}
	for _,parent in ipairs( parents ) do
		if parent:hasOutputType( connectionType ) then
			matchingParents[#matchingParents+1] = parent
		end
	end
	local consumeAmount = resourceAmount
	sm.container.beginTransaction()
	for _,parent in ipairs( matchingParents ) do
		consumeAmount = TrySpendFromConnectedContainer( parent, targetResource, consumeAmount )
		if consumeAmount <= 0 then
			break
		end
	end
	if consumeAmount > 0 then
		local selfContainer = interactable:getContainer( 0 )
		if selfContainer then
			consumeAmount = consumeAmount - sm.container.spend( selfContainer, targetResource, consumeAmount, false )
		end
	end
	if consumeAmount ~= 0 then
		sm.container.abortTransaction()
		return PowerConsumeType.failure
	end
	if sm.container.endTransaction() then
		return PowerConsumeType.resource, resourceAmount - consumeAmount
	end
	return PowerConsumeType.failure
end

function GetPipeGraphObjectContainer( pipegraphObject )
	local containerIndex = pipegraphObject:getShapeOutputContainerIndex()
	if containerIndex == -1 then
		containerIndex = 0
	end
	local container = pipegraphObject:getInteractable():getContainer( containerIndex )
	return container
end

function TrySpendFromConnectedContainer( connectedInteractable, resource, amount )
	if connectedInteractable == nil then
		return amount
	end
	local containers = sm.pipeGraph.getMatchingPipedContainers( connectedInteractable )
	local remainingAmount = amount
	for _, container in ipairs( containers ) do
		remainingAmount = remainingAmount - sm.container.spend( container, resource, remainingAmount, false )
		if remainingAmount <= 0 then
			return remainingAmount
		end
	end

	return remainingAmount
end

function CanSpendFromConnectedContainer( connectedInteractable, resource, amount )
	if connectedInteractable == nil then
		return false
	end
	local containers = sm.pipeGraph.getMatchingPipedContainers( connectedInteractable )
	local totalAvailable = 0
	for _, container in ipairs( containers ) do
		totalAvailable = totalAvailable + sm.container.totalQuantity( container, resource )
		if totalAvailable >= amount then
			return true
		end
	end

	return false
end

function PopBaseItem( itemContentPanel )
	if itemContentPanel then
		local baseItem = table.remove( itemContentPanel.Childs )
		assert( baseItem )
		return baseItem
	end
	assert( false )
end

function FormatGuiNumberCount( number1, number2, starOverThousand )
	local color = "#99ff53"
	if number1 < number2 then
		color = "#ff5353"
	end
	
	local number1String = starOverThousand and number1 >= 1000 and "*" or number1
	return color..number1String.."#a9a9a9/"..number2
end

function GetAllFilterFlags( tags )
	local filterFlags = {}
	for _, objectTag in pairs( tags ) do
		local tokens = {}
		for s in string.gmatch( objectTag, "([^:]+)" ) do
			table.insert( tokens, s )
		end
		local tokenCount = #tokens
		if tokenCount >= 3 then
			if tokens[1] == "ts" then
				if tokens[2] ~= nil and tokens[3] ~= nil then
					local flagName = tokens[3]
					if tokenCount > 3 then
						for j = 4, tokenCount, 1 do
							flagName = flagName..":"..tokens[j]
						end
					end
					filterFlags[flagName] = true
				end
			end
		end
	end
	return filterFlags
end


function ShouldShow( tags, tileStorageFlags )
	for _, objectTag in pairs( tags ) do
		local tokens = {}
		for s in string.gmatch( objectTag, "([^:]+)" ) do
			table.insert( tokens, s )
		end
		local tokenCount = #tokens
		if tokenCount >= 3 then
			if tokens[1] == "ts" then
				if tokens[2] ~= nil and tokens[3] ~= nil then
					local flagName = tokens[3]
					if tokenCount > 3 then
						for j = 4, tokenCount, 1 do
							flagName = flagName..":"..tokens[j]
						end
					end
					if tileStorageFlags[flagName] == nil and tokens[2] == "show" then
						return false
					elseif tileStorageFlags[flagName] == true and tokens[2] == "hide" then
						return false
					end
				end
			end
		end
	end
	return true
end