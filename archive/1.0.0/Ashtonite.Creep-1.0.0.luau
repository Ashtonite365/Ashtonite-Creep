-- @name Ashtonite.Creep
-- @author Ashtonite365
-- @credits to Grok for some help
metadata = {
	name = "Ashtonite.Creep",
	description = "Perch / 3rd-person creep camera",
	author = "Ashtonite365",
	defaultKeybind = "",
}

local function cfg(k, d)
	if config[k] == nil then return d end
	return config[k]
end

local mode = "Idle"
local creeping = false
local freecamOverride = false
local targetRef = nil
local targetName = ""
local searchFilter = ""
local lastSearch = -1
local lastYaw = nil
local orbitAngle = 0
local followRadius = 250
local prioritizeWalls = false
local perchFollow = cfg("perchFollow", true)
local onlyThird = cfg("onlyThird", false)
local useExclusions = cfg("useExclusions", true)
local lastFind = "none"
local maxRange = cfg("maxRange", 800)
local orbitMul = cfg("orbitMul", 2)
local safeCone = cfg("safeCone", 0.35)
local minFollow = cfg("minFollow", 280)
local backScale = cfg("backScale", 0.08)
local backLead = cfg("backLead", 0.12)
local mouseSens = cfg("mouseSens", 2.4)
local invertMouseX = cfg("invertMouseX", true)
local invertMouseY = cfg("invertMouseY", true)
local moveSpeed = cfg("moveSpeed", 1600)
local vertSpeed = cfg("vertSpeed", 1200)
local alignGravity = cfg("alignGravity", true)
local fov = cfg("fieldOfView", 90)
local showTags = cfg("showNameTags", true)
local HITBOX = 28
local CAGE_DEPTH = 36
local CAGE_RADIUS = 32
local EXTRA_ROOM = 8
local EXTRA_BACK = 7

local EXCLUSIONS = {
	{ name = "Plaza East A", enabled = true, min = Vec3.new(-6239.4, 17443.5, -29132.0), max = Vec3.new(-2647.6, 19674.3, -28965.6) },
	{ name = "Plaza East B", enabled = true, min = Vec3.new(-4782.1, 16598.3, -29552.2), max = Vec3.new(-4038.0, 20386.7, -29285.6) },
	{ name = "Plaza West A", enabled = true, min = Vec3.new(2642.0, 17459.9, -29151.7), max = Vec3.new(6201.8, 19666.5, -29015.1) },
	{ name = "Plaza West B", enabled = true, min = Vec3.new(4042.1, 16734.9, -29525.0), max = Vec3.new(4831.2, 20382.3, -29338.3) },
	{ name = "Stadium Prime A", enabled = true, min = Vec3.new(-1093.5, 25441.1, -27588.7), max = Vec3.new(1078.7, 29065.3, -27372.1) },
	{ name = "Stadium Prime B", enabled = true, min = Vec3.new(-1823.0, 26832.0, -27908.7), max = Vec3.new(1873.7, 27659.1, -27748.7) },
	{ name = "Bunker A", enabled = true, min = Vec3.new(-1215.2, 23169.3, -31053.4), max = Vec3.new(1047.4, 26741.5, -30905.7) },
	{ name = "Bunker B", enabled = true, min = Vec3.new(-1965.7, 24602.6, -31375.3), max = Vec3.new(1753.5, 25334.3, -31262.1) },
	{ name = "Fieldhouse East A", enabled = true, min = Vec3.new(-6301.9, 26023.6, -29351.3), max = Vec3.new(-2714.0, 28218.1, -29217.9) },
	{ name = "Fieldhouse East B", enabled = true, min = Vec3.new(-4890.2, 25304.3, -29712.2), max = Vec3.new(-4053.1, 28905.4, -29552.2) },
	{ name = "Fieldhouse West A", enabled = true, min = Vec3.new(2720.2, 26019.6, -29369.6), max = Vec3.new(6281.0, 28168.0, -29229.8) },
	{ name = "Fieldhouse West B", enabled = true, min = Vec3.new(4115.5, 25295.1, -29716.2), max = Vec3.new(4880.3, 28874.6, -29556.2) },
}
local freeEuler = nil
local audioFlip = 0
local perchPos = nil
local hopFrom = nil
local hopTo = nil
local hopPhase = 3
local hopWait = 0
local hopBelow = true

camera.positionSmoothing = 0
camera.rotationSmoothing = 0
camera.fieldOfView = fov
camera.hideNearestHead = false
camera.showNameTags = showTags

local DIRS = {}
do
	local n = 0
	for x = -1, 1 do
		for y = -1, 1 do
			for z = -1, 1 do
				if not (x == 0 and y == 0 and z == 0) then
					n += 1
					local v = Vec3.new(x, y, z)
					local m = v:length()
					DIRS[n] = v / m
				end
			end
		end
	end
end

local function getAllPlayers()
	local list = {}
	local frames = getAllGameData()
	if frames == nil then return list end
	for i = 1, #frames do
		local ps = frames[i].players
		if ps then
			for j = 1, #ps do
				list[#list + 1] = { playerId = ps[j].playerId, frameIndex = i, name = ps[j].playerName }
			end
		end
	end
	return list
end

local function resolvePlayer(ref)
	if ref == nil then return nil end
	local frames = getAllGameData()
	if frames == nil or ref.frameIndex > #frames then return nil end
	return frames[ref.frameIndex]:getPlayerById(ref.playerId)
end

local function upVec()
	if gravity and gravity.strength and gravity.strength ~= 0 then
		return gravity.upDirection
	end
	return Vec3.upVector
end

local function flatten(v, up)
	local d = v - up * v:dot(up)
	local m = d:length()
	if m < 0.0001 then return Vec3.zeroVector end
	return d / m
end

local function yawOf(fwd, up)
	local f = flatten(fwd, up)
	if f:length() < 0.0001 then return 0 end
	local r = flatten(Vec3.rightVector, up)
	if r:length() < 0.0001 then r = Vec3.rightVector end
	return math.atan2(f:dot(up:cross(r)), f:dot(r))
end

local function nameMatch(n, f)
	if f == nil or f == "" then return true end
	if n == nil then return false end
	return string.find(string.lower(n), string.lower(f), 1, true) ~= nil
end

local function isVerticalDir(dir, up)
	return math.abs(dir:dot(up)) >= 0.82
end

local function isFloorDown(dir, up)
	return dir:dot(up) <= -0.82
end

local function axis3(v)
	return v.x or v.X or 0, v.y or v.Y or 0, v.z or v.Z or 0
end

local function inExclusion(pos)
	if (not useExclusions) or pos == nil then return false end
	local x, y, z = axis3(pos)
	for i = 1, #EXCLUSIONS do
		local e = EXCLUSIONS[i]
		if e.enabled and e.min and e.max then
			local x1, y1, z1 = axis3(e.min)
			local x2, y2, z2 = axis3(e.max)
			local loX, hiX = math.min(x1, x2), math.max(x1, x2)
			local loY, hiY = math.min(y1, y2), math.max(y1, y2)
			local loZ, hiZ = math.min(z1, z2), math.max(z1, z2)
			if x >= loX and x <= hiX and y >= loY and y <= hiY and z >= loZ and z <= hiZ then
				return true
			end
		end
	end
	return false
end

local function seeThrough(hitPos, dir)
	local n = dir:getSafeNormal()
	local justBehind = hitPos + n * 2
	local past = hitPos - n * 2
	local probe = camera:castRay(justBehind, past)
	return not probe.successful
end

local function enclosed(center, intoDir, up)
	local n = intoDir:getSafeNormal()
	local r = n:cross(up)
	if r:length() < 0.001 then r = n:cross(Vec3.rightVector) end
	r = r:getSafeNormal()
	local u = n:cross(r)
	if u:length() < 0.001 then u = up:getSafeNormal() else u = u:getSafeNormal() end
	local radius = CAGE_RADIUS
	local c1 = (r + u + n):getSafeNormal()
	local c2 = (r + u - n):getSafeNormal()
	local c3 = (r - u + n):getSafeNormal()
	local c4 = (r - u - n):getSafeNormal()
	local c5 = (-r + u + n):getSafeNormal()
	local c6 = (-r + u - n):getSafeNormal()
	local c7 = (-r - u + n):getSafeNormal()
	local c8 = (-r - u - n):getSafeNormal()
	local starts = {
		center + r * radius,
		center - r * radius,
		center + u * radius,
		center - u * radius,
		center + n * radius,
		center - n * radius,
		center + c1 * radius,
		center + c2 * radius,
		center + c3 * radius,
		center + c4 * radius,
		center + c5 * radius,
		center + c6 * radius,
		center + c7 * radius,
		center + c8 * radius,
	}
	local faceHits, otherHits = 0, 0
	for i = 1, #starts do
		local s = starts[i]
		local to = center - s
		local len = to:length()
		if len < 4 then return 0 end
		local hit = camera:castRay(s, s + (to / len) * (len - 3))
		if hit.successful then
			if (s - center):dot(n) < -0.15 then
				faceHits += 1
			else
				otherHits += 1
			end
		end
	end
	if otherHits > 0 then return 0 end
	if faceHits > 0 then return 2 end
	return 1
end

local function roomBehind(center, n)
	local start = center + n * EXTRA_BACK
	local hit = camera:castRay(start, center)
	return not hit.successful
end

local function slabWide(hitPos, dir, up)
	local n = dir:getSafeNormal()
	local t = n:cross(up)
	if t:length() < 0.001 then t = n:cross(Vec3.rightVector) end
	t = t:getSafeNormal()
	local b = n:cross(t):getSafeNormal()
	local origin = hitPos - n * 4
	local need = CAGE_RADIUS * 2
	local span = need + 120
	local function width(axis)
		local h1 = camera:castRay(origin, origin + axis * span)
		local h2 = camera:castRay(origin, origin - axis * span)
		local d1 = h1.successful and (h1.position - origin):length() or span
		local d2 = h2.successful and (h2.position - origin):length() or span
		return d1 + d2
	end
	return math.min(width(t), width(b)) >= need
end

local function tryHide(hitPos, dir, up, floorMode)
	local n = dir:getSafeNormal()
	if not seeThrough(hitPos, n) then return nil end
	if floorMode and not slabWide(hitPos, n, up) then return nil end
	local hide = hitPos + n * CAGE_DEPTH
	if inExclusion(hide) then return nil end
	if not roomBehind(hide, n) then return nil end
	local result = enclosed(hide, n, up)
	if result == 1 then return hide end
	if result ~= 2 then return nil end
	local room = camera:castRay(hide, hide + n * (EXTRA_ROOM + 2))
	local slide = EXTRA_ROOM
	if room.successful then
		local d = (room.position - hide):length()
		if d < 3 then return nil end
		slide = math.min(EXTRA_ROOM, d - 2)
		if slide < 2 then return nil end
	end
	local deeper = hide + n * slide
	if inExclusion(deeper) then return nil end
	if not roomBehind(deeper, n) then return nil end
	if enclosed(deeper, n, up) == 1 then return deeper end
	return nil
end

local function scoreHit(h, up)
	local dir = h.dir:getSafeNormal()
	local alongUp = dir:dot(up)
	local downC = -alongUp
	local upC = alongUp
	local across = 1 - math.abs(alongUp)
	local rank
	if downC >= 0.65 then
		rank = downC * 3 + across * 2 + math.max(upC, 0)
	elseif upC >= 0.65 then
		rank = upC * 3 + across * 2 + math.max(downC, 0)
	else
		rank = across * 3 + math.abs(alongUp) * 2
	end
	if prioritizeWalls then
		if math.abs(alongUp) < 0.65 then rank += 1.5 end
	else
		if math.abs(alongUp) >= 0.65 then rank += 1.5 end
	end
	return -h.dist * 10 + rank
end

local function axisParts(dir)
	local parts = {}
	local x, y, z = dir.x or dir.X, dir.y or dir.Y, dir.z or dir.Z
	if math.abs(x) > 0.05 then parts[#parts + 1] = Vec3.new(x > 0 and 1 or -1, 0, 0) end
	if math.abs(y) > 0.05 then parts[#parts + 1] = Vec3.new(0, y > 0 and 1 or -1, 0) end
	if math.abs(z) > 0.05 then parts[#parts + 1] = Vec3.new(0, 0, z > 0 and 1 or -1) end
	return parts
end

local function rayLen()
	return maxRange * 3
end

local function tryAddHit(hits, origin, dir)
	local reach = rayLen()
	local hit = camera:castRay(origin, origin + dir * reach)
	if not hit.successful then return end
	local dist = (hit.position - origin):length()
	if dist <= reach * 0.75 then
		hits[#hits + 1] = { pos = hit.position, dir = dir, dist = dist }
	end
end

local function searchPocket(headPos, up)
	local hits = {}
	for i = 1, #DIRS do
		local dir = DIRS[i]
		local before = #hits
		tryAddHit(hits, headPos, dir)
		if #hits > before then
			local parts = axisParts(dir)
			for p = 1, #parts do
				tryAddHit(hits, headPos, parts[p])
			end
		end
	end
	if #hits == 0 then
		lastFind = "no ray hits"
		return nil, 0, 0
	end
	table.sort(hits, function(a, b) return a.dist < b.dist end)
	local n = math.min(20, #hits)
	local bestWall, wallScore = nil, -1e9
	local bestFlat, flatScore = nil, -1e9
	local walls, flats = 0, 0
	for i = 1, n do
		local h = hits[i]
		local down = isFloorDown(h.dir, up)
		local mid = tryHide(h.pos, h.dir, up, down)
		if mid then
			local s = scoreHit(h, up)
			if down then
				flats += 1
				if s > flatScore then
					flatScore = s
					bestFlat = mid
				end
			else
				walls += 1
				if s > wallScore then
					wallScore = s
					bestWall = mid
				end
			end
		end
	end
	local best
	if prioritizeWalls then
		best = bestWall or bestFlat
	else
		best = bestFlat or bestWall
	end
	if best == nil then
		lastFind = "hits " .. tostring(#hits) .. " none valid (walls " .. tostring(walls) .. " floors " .. tostring(flats) .. ")"
	elseif best == bestWall and bestWall ~= nil and (prioritizeWalls or bestFlat == nil) then
		lastFind = "wall"
	else
		lastFind = "floor/roof"
	end
	return best, n, #hits
end

local function perchBlocked(head)
	local origin = perchPos or camera.position
	local to = head - origin
	local dist = to:length()
	if dist < 8 then return false end
	local dir = to / dist
	local hit = camera:castRay(origin + dir * 2, head)
	return hit.successful
end

local function axisOf(v)
	return v.x or v.X or 0, v.y or v.Y or 0, v.z or v.Z or 0
end

local function startHop(dest, head)
	hopFrom = camera.position
	hopTo = dest
	hopPhase = 0
	hopWait = 0
	perchPos = dest
	local up = upVec()
	hopBelow = dest:dot(up) < head:dot(up)
end

local function hopPos(dt)
	if hopTo == nil then return perchPos end
	if hopPhase >= 3 then return hopTo or perchPos end
	local up = upVec()
	local fromH = hopFrom:dot(up)
	local toH = hopTo:dot(up)
	local fromFlat = hopFrom - up * fromH
	local toFlat = hopTo - up * toH
	local dH = toH - fromH
	local goingDown = dH < -2
	local goingUp = dH > 2
	local vertFirst
	if hopBelow then
		vertFirst = goingDown
	else
		vertFirst = goingUp
	end
	if (not goingDown) and (not goingUp) then
		hopWait += dt
		local t = math.min(hopWait / 0.28, 1)
		local pos = fromFlat * (1 - t) + toFlat * t + up * toH
		if t >= 1 then hopPhase = 3 end
		return pos
	end
	hopWait += dt
	local t = math.min(hopWait / 0.28, 1)
	local pos
	if hopPhase == 0 then
		if vertFirst then
			pos = fromFlat + up * (fromH + dH * t)
		else
			pos = fromFlat * (1 - t) + toFlat * t + up * fromH
		end
		if t >= 1 then
			hopPhase = 1
			hopWait = 0
		end
	else
		if vertFirst then
			pos = fromFlat * (1 - t) + toFlat * t + up * toH
		else
			pos = toFlat + up * (fromH + dH * t)
		end
		if t >= 1 then hopPhase = 3 end
	end
	return pos
end

local function applyMouseLook(dt, up)
	if freeEuler == nil then
		freeEuler = camera.rotation:euler()
	end
	local mouse = Input.getMouseDelta and Input.getMouseDelta() or nil
	local mx, my = 0, 0
	if mouse then
		mx = (mouse.x or 0) * mouseSens
		my = (mouse.y or 0) * mouseSens
	end
	mx += Input.getAnalog(Input.Gamepad.RightX) * mouseSens * 40 * dt
	my += Input.getAnalog(Input.Gamepad.RightY) * mouseSens * 40 * dt
	if invertMouseX then mx = -mx end
	if invertMouseY then my = -my end
	freeEuler.z -= mx
	freeEuler.y -= my
	if freeEuler.y > 89.9 then freeEuler.y = 89.9 end
	if freeEuler.y < -89.9 then freeEuler.y = -89.9 end
	if alignGravity then
		freeEuler.x = 0
		local base = Quat.fromEuler(0, freeEuler.y, freeEuler.z)
		if gravity and gravity.upRotation then
			camera.rotation = gravity.upRotation * base
		else
			camera.rotation = base
		end
	else
		camera.rotation = Quat.fromEuler(freeEuler.x, freeEuler.y, freeEuler.z)
	end
end

local function applyLook(pos, targetPos, up, dt)
	if perchFollow then
		freeEuler = nil
		camera:lookAt(targetPos, up)
	else
		applyMouseLook(dt or 0, up)
	end
	audioFlip = 1 - audioFlip
	camera.rotation = camera.rotation
	camera.position = pos + camera.rotation:getForwardVector() * (audioFlip * 0.02)
	if hopPhase >= 3 then
		perchPos = hopTo or pos
	end
end

local function tickFreecam(dt, up)
	mode = "Freecam"
	local sprint = Input.getKey(Input.Key.LeftShift) and 3 or 1
	local slow = Input.getKey(Input.Key.LeftControl) and 0.25 or 1
	local spd = moveSpeed * sprint * slow
	local fwd = camera.rotation:getForwardVector()
	local right = camera.rotation:getRightVector()
	if alignGravity then
		fwd = flatten(fwd, up)
		right = flatten(right, up)
	end
	local move = Vec3.zeroVector
	if Input.getKey(Input.Key.W) then move += fwd end
	if Input.getKey(Input.Key.S) then move -= fwd end
	if Input.getKey(Input.Key.D) then move += right end
	if Input.getKey(Input.Key.A) then move -= right end
	if move:length() > 0.001 then
		camera.position += move:getSafeNormal() * spd * dt
	end
	local vert = 0
	if Input.getKey(Input.Key.E) then vert += 1 end
	if Input.getKey(Input.Key.Q) then vert -= 1 end
	if vert ~= 0 then
		camera.position += up * vert * vertSpeed * sprint * slow * dt
	end
	applyMouseLook(dt, up)
end

local function tickThird(dt, player, up)
	mode = "3rd person"
	local head = player.head.position
	local hfwd = player.head.rotation:getForwardVector()
	local yaw = yawOf(hfwd, up)
	if lastYaw == nil then
		lastYaw = yaw
		orbitAngle = yaw + math.pi
	end
	local dyaw = yaw - lastYaw
	while dyaw > math.pi do dyaw -= math.pi * 2 end
	while dyaw < -math.pi do dyaw += math.pi * 2 end
	local behind = flatten(-hfwd, up)
	local lookingAtCam = 0
	local toCam = camera.position - head
	if toCam:length() > 0.01 then
		lookingAtCam = flatten(hfwd, up):dot(toCam:getSafeNormal())
	end
	if dyaw < 0 and math.abs(dyaw) > 0.04 then
		orbitAngle = yaw + math.pi
	elseif lookingAtCam < safeCone then
		orbitAngle += dyaw * 0.25
	else
		orbitAngle += dyaw * orbitMul
	end
	lastYaw = yaw
	local vel = player.velocity or Vec3.zeroVector
	local back = vel:dot(-hfwd)
	local thirdDist = minFollow * 2
	if back > 50 then
		followRadius += back * backScale * dt
	else
		followRadius -= (followRadius - thirdDist) * math.min(dt * 2.2, 1)
	end
	if followRadius < thirdDist then followRadius = thirdDist end
	local behindDir = flatten(-hfwd, up)
	if behindDir:length() < 0.01 then behindDir = flatten(Vec3.forwardVector, up) end
	if behindDir:length() < 0.01 then behindDir = Vec3.forwardVector end
	behindDir = behindDir:getSafeNormal()
	local dest = head + behindDir * followRadius + up * (thirdDist * 0.12)
	applyLook(dest, head, up, dt)
end

function tick(dt)
	camera.positionSmoothing = 0
	camera.rotationSmoothing = 0
	camera.fieldOfView = fov
	camera.hideNearestHead = false
	camera.showNameTags = showTags

	local up = upVec()
	if freecamOverride or not creeping then
		tickFreecam(dt, up)
		return
	end
	freeEuler = nil

	local player = resolvePlayer(targetRef)
	if player == nil or player.head == nil then
		mode = "Idle"
		return
	end

	local head = player.head.position
	local dist = (camera.position - head):length()
	local now = os.clock and os.clock() or 0

	if onlyThird then
		tickThird(dt, player, up)
		return
	end

	if mode == "Perch" and perchBlocked(head) then
		mode = "Searching"
		lastSearch = -1
		lastFind = "blocked LOS"
	end

	if mode == "Perch" and dist <= maxRange * 2 then
		applyLook(hopPos(dt) or perchPos or camera.position, head, up, dt)
		return
	end

	local needSearch = mode == "Idle" or mode == "Searching" or mode == "3rd person" or dist > maxRange * 2
	if needSearch then
		local due = lastSearch < 0 or (now - lastSearch) >= 0.5
		if due then
			lastSearch = now
			mode = "Searching"
			local pocket, kept, rawHits = searchPocket(head, up)
			if pocket then
				local cur = perchPos or camera.position
				local sameHome = perchPos ~= nil and (pocket - cur):length() < 220
					and math.abs(pocket:dot(up) - cur:dot(up)) < 80
				if sameHome then
					mode = "Perch"
					applyLook(hopPos(dt) or perchPos or cur, head, up, dt)
					return
				end
				mode = "Perch"
				if (pocket - cur):length() > 8 then
					startHop(pocket, head)
				else
					perchPos = pocket
					hopPhase = 3
					hopTo = pocket
				end
				applyLook(hopPos(dt) or pocket, head, up, dt)
				return
			end
			tickThird(dt, player, up)
			return
		elseif mode == "3rd person" then
			tickThird(dt, player, up)
			return
		end
	end

	if mode == "Perch" then
		applyLook(hopPos(dt) or perchPos or camera.position, head, up, dt)
	elseif mode == "3rd person" then
		tickThird(dt, player, up)
	end
end

function onGui()
	Gui.text("Mode: " .. mode .. (onlyThird and " (only 3rd on)" or ""))
	Gui.text("Target: " .. (targetName ~= "" and targetName or "None"))
	Gui.text("Last perch search: " .. lastFind)
	local p = camera.position
	local px = p.x or p.X or 0
	local py = p.y or p.Y or 0
	local pz = p.z or p.Z or 0
	local e = camera.rotation:euler()
	local ex = e.x or e.X or 0
	local ey = e.y or e.Y or 0
	local ez = e.z or e.Z or 0
	Gui.text(string.format("Pos  %.1f  %.1f  %.1f", px, py, pz))
	Gui.text(string.format("Rot  %.1f  %.1f  %.1f", ex, ey, ez))
	Gui.separator()
	if Gui.beginTabBar("CreepTabs") then
		if Gui.beginTabItem("Target") then
			searchFilter = Gui.inputText("Search", searchFilter)
			local players = getAllPlayers()
			for i = 1, #players do
				local p = players[i]
				local n = p.name or "?"
				if nameMatch(n, searchFilter) then
					local mark = (targetRef and targetRef.playerId == p.playerId) and " [sel]" or ""
					if Gui.selectable(n .. mark, targetRef ~= nil and targetRef.playerId == p.playerId) then
						targetRef = p
						targetName = n
					end
				end
			end
			if Gui.button("Begin creep") then
				if targetRef then
					creeping = true
					freecamOverride = false
					mode = "Idle"
					lastSearch = -1
					lastYaw = nil
					followRadius = minFollow * 2
				end
			end
			Gui.sameLine()
			if Gui.button("Stop creep") then
				creeping = false
				mode = "Idle"
			end
			Gui.endTabItem()
		end
		if Gui.beginTabItem("Perch") then
			perchFollow = Gui.checkbox("Follow tracked player", perchFollow)
			if prioritizeWalls then
				if Gui.button("Prioritize walls") then prioritizeWalls = false end
			else
				if Gui.button("Prioritize floor or ceiling") then prioritizeWalls = true end
			end
			maxRange = Gui.sliderFloat("Max range", maxRange, 100, 3000)
			Gui.separator()
			useExclusions = Gui.checkbox("Use exclusions", useExclusions)
			Gui.text("Driftball see-through exclusions")
			for i = 1, #EXCLUSIONS do
				local e = EXCLUSIONS[i]
				e.enabled = Gui.checkbox(e.name, e.enabled)
			end
			Gui.endTabItem()
		end
		if Gui.beginTabItem("3rd person") then
			onlyThird = Gui.checkbox("Only 3rd person", onlyThird)
			orbitMul = Gui.sliderFloat("Orbit rate (x head yaw)", orbitMul, 0.5, 4)
			safeCone = Gui.sliderFloat("Safe cone", safeCone, 0, 1)
			minFollow = Gui.sliderFloat("Min follow distance", minFollow, 60, 800)
			backScale = Gui.sliderFloat("Back-away scale", backScale, 0, 0.4)
			backLead = Gui.sliderFloat("Back-away lead", backLead, 0, 0.5)
			Gui.endTabItem()
		end
		if Gui.beginTabItem("Freecam") then
			freecamOverride = Gui.checkbox("Freecam override", freecamOverride)
			alignGravity = Gui.checkbox("Align to gravity", alignGravity)
			mouseSens = Gui.sliderFloat("Mouse sensitivity", mouseSens, 0.2, 8)
			invertMouseX = Gui.checkbox("Invert mouse X", invertMouseX)
			invertMouseY = Gui.checkbox("Invert mouse Y", invertMouseY)
			moveSpeed = Gui.sliderFloat("Move speed", moveSpeed, 200, 8000)
			vertSpeed = Gui.sliderFloat("Q/E speed", vertSpeed, 200, 8000)
			Gui.text("WASD move  |  Q/E up down  |  Shift sprint  |  Ctrl slow")
			Gui.endTabItem()
		end
		if Gui.beginTabItem("Camera") then
			fov = Gui.sliderFloat("Field of view", fov, 40, 150)
			showTags = Gui.checkbox("Show nametags", showTags)
			Gui.endTabItem()
		end
		Gui.endTabBar()
	end
end

function main()
	camera.fieldOfView = fov
	camera.positionSmoothing = 0
	camera.rotationSmoothing = 0
end
