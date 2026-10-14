local STATE = Terminus.STATE
local EYE = Terminus.EYE
local Setting = Terminus.Setting

local ai_ignoreplayers = GetConVar("ai_ignoreplayers")
local developer = GetConVar("developer")

local LOOKAHEAD = 300
local GOAL_TOLERANCE = 20
local REPATH_NEAR, REPATH_FAR, REPATH_RANGE = 0.1, 1, 4000
local GIVE_UP = 3
local STUCK_WARP = 1.5
local CATCH_RANGE = 48
local CATCH_HEIGHT = 72
local SIGHT_CLOSE = 160
local SIGHT_TOP = Vector(0, 0, 110)
local SPRITE_RADIUS = 48
local ASPECT = 16 / 9
local LEAD_MIN, LEAD_MAX = 250, 0.6
local PREDICT = 1.2
local SEARCH_TIME = 5
local SEARCH_REACHED = 80
local NAV_SNAP = 300
local STEP = Vector(0, 0, 18)
local HULL_MIN, HULL_MAX = Vector(-16, -16, 0), Vector(16, 16, 54)
local BREATHER_CHANCE = 0.25
local BREATHER_RANGE = 150
local BREATHER_SPEED = 400
local STALK_ACCEL = 200
local CHASE_ACCEL = 375
local RAGE_ACCEL = 700
local TIRED_PACE, TIRED_ACCEL = 0.5, 100
local WALK_SPEED, WALK_ACCEL = 700, 400
local HIDE_TIME = 90
local HIDE_UNSEEN = 15
local HIDE_RANGE = 5000
local HIDE_REACHED = 64
local AMBUSH_RANGE = 250
local SPAWN_NEAR = { 1500, 500 }
local SPAWN_FAR, SPAWN_WIDEN, SPAWN_MAX = 6000, 500, 20000
local SPAWN_CROWD = 600
local SPAWN_HIDDEN_TRIES = 10
local SPAWN_CLOSER_TRIES = 20
local SPOT_SAMPLES = 16
local CLIMB, DROP = 120, 4000
local IDLE_FORGET = 3
local EXPOSED_COST, BEHIND_COST = 4, 0.5
local EXPOSURE_MEMORY = 0.5
local EXPOSURE_TRACES = 400
local SIGHT_FAR = 3000
local FLANK, FLANK_RANGE = 300, 700
local HOLD_AHEAD = 120
local HOLD_MAX = 8
local DARK = 0.3
local DARK_CLOSE = 300
local FLASHLIGHT_RANGE = 1000
local FLASHLIGHT_COS = math.cos(math.rad(30))
local GROUND = Vector(0, 0, 16384)
local ARRIVE_SOUND = ")terminus/close_stalking_2.wav"
local ARRIVE_LEVEL, ARRIVE_PITCH = 80, 60
local CAMP_RADIUS = 120
local CAMP_TIME = 12
local ENCLOSED_REACH = 250
local ENCLOSED_HITS = 5
local ALONE_RANGE = 1000
local BAIT_RANGE = 900
local FEINT_REACH = 1400
local FEINT_TIME = 6
local LURK_SPOT = { 100, 400 }
local LURK_WAIT = 25
local LURE_TIME = 60
local WAIST = Vector(0, 0, 36)
local SNAP_ACCEL = 4000
local RAGE_GRIP, TIRED_GRIP = 0.5, 0.5
local DIRECT_RANGE, DIRECT_HEIGHT = 300, 48
local DIRECT_LEAD = 0.35
local STEER_TIGHT = 15
local PREFER_PLAYERS = 0.6
local REST_CHECK = 0.5
local REST_NEAR = 2000
local LINGER = 4
local SLINK_TIME = 10
local VANISH_BATCHES = 10
local VANISH_WAIT = 10
local AROUND = {}
for i = 0, 7 do
	local a = i * math.pi / 4
	AROUND[#AROUND + 1] = Vector(math.cos(a), math.sin(a), 0) * ENCLOSED_REACH
end

local function Huntable(ent)
	if not IsValid(ent) or ent:IsFlagSet(FL_NOTARGET) or ent.TerminusMeal then return false end
	if ent:IsPlayer() then
		return Setting("hunt_players") ~= 0 and ent:Alive()
			and not ai_ignoreplayers:GetBool()
			and not ent:HasGodMode()
			and ent:GetMoveType() ~= MOVETYPE_NOCLIP
			and ent:GetObserverMode() == OBS_MODE_NONE
	end
	if ent:IsNPC() then
		if Setting("hunt_npcs") == 0 or ent:GetMoveType() ~= MOVETYPE_STEP then return false end
	elseif ent:IsNextBot() then
		if Setting("hunt_nextbots") == 0 or ent:GetClass() == "npc_terminus" then return false end
	else
		return false
	end
	if ent.Dead or ent.IsDead and ent:IsDead() then return false end
	return ent:Health() > 0 or ent:IsNextBot() and ent:GetMaxHealth() <= 0
end

local function Facing(ent)
	return ent:IsPlayer() and ent:GetAimVector() or ent:EyeAngles():Forward()
end

local function Clear(from, to, filter)
	return not util.TraceLine({ start = from, endpos = to, mask = MASK_OPAQUE, filter = filter }).Hit
end

local function OnScreen(ply, point)
	local to = point - ply:EyePos()
	local ang = ply:EyeAngles()
	local depth = to:Dot(ang:Forward())
	if depth <= 0 then return false end
	local fov = ply:IsPlayer() and ply:GetFOV() or 0
	local tall = math.tan(math.rad(fov > 0 and fov or 75) / 2) * 0.75
	return math.abs(to:Dot(ang:Right())) < depth * tall * ASPECT + SPRITE_RADIUS
		and math.abs(to:Dot(ang:Up())) < depth * tall + SPRITE_RADIUS
end

-- Whether ply can see it standing at pos. Unless anyway is set, it has to be on their screen too.
local function Sees(ply, pos, anyway)
	local eye, center = ply:EyePos(), pos + EYE
	if not anyway and eye:DistToSqr(center) > SIGHT_CLOSE * SIGHT_CLOSE and not OnScreen(ply, center) then
		return false
	end
	local vehicle = ply:IsPlayer() and ply:GetVehicle()
	local filter = IsValid(vehicle) and { ply, vehicle } or ply
	return Clear(eye, center, filter) or Clear(eye, pos + SIGHT_TOP, filter)
end

-- Sees, plus the dark: ply has to have light on it, be close, or have it in their flashlight. Its target's
-- client says how lit it is.
function ENT:SeenBy(ply, pos)
	pos = pos or self:GetPos()
	if not Sees(ply, pos) then return false end
	if Setting("dark_hides") == 0 or self:GetEnraged() then return true end
	if self.LightFrom ~= ply or self.Light >= DARK then return true end
	local to = pos + EYE - ply:EyePos()
	local dist = to:Length()
	if dist < DARK_CLOSE then return true end
	return ply:IsPlayer() and ply:FlashlightIsOn() and dist < FLASHLIGHT_RANGE and Facing(ply):Dot(to) > dist * FLASHLIGHT_COS
end

local function Ground(ply)
	local pos = ply:GetPos()
	if ply:IsOnGround() then return pos end
	local tr = util.TraceLine({ start = pos, endpos = pos - GROUND, mask = MASK_PLAYERSOLID_BRUSHONLY })
	return tr.Hit and tr.HitPos or pos
end

-- Where someone at pos going at vel gets to in t seconds, stopping at walls and kept on the navmesh.
local function Ahead(pos, vel, t)
	local flat = Vector(vel.x, vel.y, 0) * t
	if flat:LengthSqr() < 1 then return pos end
	local from = pos + STEP
	local tr = util.TraceHull({ start = from, endpos = from + flat, mins = HULL_MIN, maxs = HULL_MAX, mask = MASK_PLAYERSOLID_BRUSHONLY })
	local spot = tr.HitPos - STEP
	local area = navmesh.GetNearestNavArea(spot, false, NAV_SNAP, true)
	return area and area:GetClosestPointOnArea(spot) or pos
end

-- Aims where they'll be by the time it gets there, so it cuts them off.
function ENT:Lead(pos, vel, speed)
	local dist = self:GetPos():Distance(pos)
	if dist < LEAD_MIN then return pos end
	return Ahead(pos, vel, math.min(dist / math.max(speed, 1), LEAD_MAX))
end

function ENT:Spots(ply)
	local eye = self:SightPos()
	local filter = { self, ply }
	return Clear(eye, ply:EyePos(), filter) or Clear(eye, ply:WorldSpaceCenter(), filter)
end

-- Whoever can see it at pos, if anyone.
function ENT:Watched(pos, anyway)
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and Sees(ply, pos, anyway) then return ply end
	end
end

function ENT:PickTarget()
	local current = self:GetTarget()
	if Huntable(current) then return current end

	local hunted = {}
	for _, bot in ipairs(ents.FindByClass(self:GetClass())) do
		local t = bot ~= self and bot:GetTarget()
		if IsValid(t) then hunted[t] = (hunted[t] or 0) + 1 end
	end

	-- The least hunted of each kind, leaning towards people when there's a choice.
	local function Least(list)
		local picks, fewest = {}, math.huge
		for _, ent in ipairs(list) do
			if Huntable(ent) then
				local n = hunted[ent] or 0
				if n < fewest then
					picks, fewest = { ent }, n
				elseif n == fewest then
					picks[#picks + 1] = ent
				end
			end
		end
		return picks[math.random(math.max(#picks, 1))]
	end

	local creatures = {}
	if Setting("hunt_npcs") ~= 0 or Setting("hunt_nextbots") ~= 0 then
		for _, ent in ipairs(ents.GetAll()) do
			if ent:IsNPC() or ent:IsNextBot() then creatures[#creatures + 1] = ent end
		end
	end
	local person, creature = Least(player.GetAll()), Least(creatures)
	if person and (not creature or math.random() < PREFER_PLAYERS) then return person end
	return creature
end

function ENT:Pace(speed, accel)
	self.loco:SetDesiredSpeed(speed)
	self.loco:SetAcceleration(accel)
	self.loco:SetDeceleration(self.BaseDecel)
end

-- Heads straight for aim, ignoring the path. The tighter its grip, the less it drifts.
function ENT:Steer(aim, speed, grip)
	local loco = self.loco
	loco:Approach(aim, 1)
	loco:FaceTowards(aim)
	if grip <= 0 then return end
	local vel = loco:GetVelocity()
	local want = aim - self:GetPos()
	want.z = 0
	want:Normalize()
	want:Mul(speed)
	want.z = vel.z
	loco:SetVelocity(LerpVector(1 - math.exp(-engine.TickInterval() * STEER_TIGHT * grip), vel, want))
end

-- How much worse ground is to cross for being where ply can see it. Remembered for a moment, since a path
-- search asks about the same areas over and over.
function ENT:Exposure(area, ply, now)
	local memo = self.Exposed
	if not memo or memo.ply ~= ply or now >= memo.expires then
		memo = { ply = ply, expires = now + EXPOSURE_MEMORY, eye = ply:EyePos(), traces = 0, areas = {} }
		self.Exposed = memo
	end
	local id = area:GetID()
	local cost = memo.areas[id]
	if cost then return cost end
	cost = 0
	local point = area:GetCenter() + EYE
	if memo.traces < EXPOSURE_TRACES and point:DistToSqr(memo.eye) < SIGHT_FAR * SIGHT_FAR then
		memo.traces = memo.traces + 1
		if Clear(memo.eye, point, ply) then cost = OnScreen(ply, point) and EXPOSED_COST or BEHIND_COST end
	end
	memo.areas[id] = cost
	return cost
end

-- A path cost that steers around ground ply can see.
function ENT:Sneaky(ply)
	local loco = self.loco
	return function(area, from, ladder, _, length)
		if not IsValid(from) then return 0 end
		if IsValid(ladder) or not loco:IsAreaTraversable(area) then return -1 end
		local rise = from:ComputeAdjacentConnectionHeightChange(area)
		if rise > loco:GetMaxJumpHeight() or rise < -loco:GetDeathDropHeight() then return -1 end
		local dist = length > 0 and length or area:GetCenter():Distance(from:GetCenter())
		local exposure = IsValid(ply) and self:Exposure(area, ply, CurTime()) or 0
		return from:GetCostSoFar() + dist * (1 + exposure)
	end
end

-- A spot behind ply, so it comes at their back.
local function Behind(ply)
	local back = -Facing(ply)
	back.z = 0
	back:Normalize()
	local spot = ply:GetPos() + back * FLANK
	local area = navmesh.GetNearestNavArea(spot, false, FLANK, true)
	return area and area:GetClosestPointOnArea(spot) or Ground(ply)
end

function ENT:PathAhead(dist)
	local path = self.Path
	if not path or not path:IsValid() then return end
	return path:GetPositionOnPath(path:GetCursorPosition() + dist)
end

-- Steps along a path to goal. Returns false once there's been no way there for a few seconds.
function ENT:Approach(goal, now, cost)
	if now >= self.RepathAt then
		local path = self.Path or Path("Follow")
		path:SetMinLookAheadDistance(LOOKAHEAD)
		path:SetGoalTolerance(GOAL_TOLERANCE)
		local reached = path:Compute(self, goal, cost)
		self.Path = path
		self.RepathAt = now + Lerp(math.min(self:GetPos():Distance(goal) / REPATH_RANGE, 1), REPATH_NEAR, REPATH_FAR)
		if reached then
			self.Stranded = nil
		else
			self.Stranded = self.Stranded or now
		end
	end
	if self.Path:IsValid() then self.Path:Update(self) end
	self:Unstick(now)
	return not self.Stranded or now - self.Stranded < GIVE_UP
end

-- Hops ahead along the path when it's been stuck a while and nobody's looking.
function ENT:Unstick(now)
	if not self.loco:IsStuck() then
		self.StuckSince = nil
		return
	end
	self.StuckSince = self.StuckSince or now
	if now - self.StuckSince < STUCK_WARP then return end
	local goal = self.Path:IsValid() and self.Path:GetCurrentGoal()
	if goal and not self:Watched(self:GetPos()) and not self:Watched(goal.pos) then self:SetPos(goal.pos) end
	self.loco:ClearStuck()
	self.StuckSince = nil
end

function ENT:Catch(victim)
	local to = victim:GetPos() - self:GetPos()
	if math.abs(to.z) > CATCH_HEIGHT or to:Length2DSqr() > CATCH_RANGE * CATCH_RANGE then return false end
	if not victim:IsPlayer() or Setting("kill_players") ~= 0 then self.Meal = self:Slay(victim) end
	self.FedUntil = CurTime() + Setting("sated_time")
	return true
end

function ENT:Fed()
	return CurTime() < self.FedUntil
end

local allAreas, allAreasCount
local function AllAreas()
	local n = navmesh.GetNavAreaCount()
	if n ~= allAreasCount then allAreas, allAreasCount = navmesh.GetAllNavAreas(), n end
	return allAreas
end

-- Anywhere on the map nobody's near or has line of sight to. On a map too open for that, the spot farthest
-- from everyone it came across.
function ENT:VanishSpot()
	local areas = AllAreas()
	if #areas == 0 then return end
	local best, bestGap = nil, -1
	for _ = 1, VANISH_BATCHES do
		for _ = 1, SPOT_SAMPLES do
			local area = areas[math.random(#areas)]
			if not area:IsUnderwater() then
				local spot = area:GetRandomPoint()
				local gap = math.huge
				for _, ply in ipairs(player.GetAll()) do
					if ply:Alive() then gap = math.min(gap, spot:Distance(ply:GetPos())) end
				end
				if gap >= REST_NEAR and self:Unseen(spot, true) then return spot end
				if gap > bestGap and not self:Watched(spot) then best, bestGap = spot, gap end
			end
		end
		coroutine.yield()
	end
	return best
end

-- Whether anyone within resting distance has line of sight to it.
function ENT:Exposed(pos)
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and ply:GetPos():DistToSqr(pos) < REST_NEAR * REST_NEAR and Sees(ply, pos, true) then return true end
	end
	return false
end

-- Walks off until whoever's looking at it can't see it any more.
function ENT:Slink(watcher)
	local spot = self:HideSpot(watcher:GetPos())
	if not spot then return end
	self:Pace(WALK_SPEED, WALK_ACCEL)
	self.Path, self.RepathAt, self.Stranded = nil, 0, nil
	local sneaky = self:Sneaky(watcher)
	local giveUp = CurTime() + SLINK_TIME
	while CurTime() < giveUp and self:Watched(self:GetPos()) do
		if not self:Approach(spot, CurTime(), sneaky) then break end
		coroutine.yield()
	end
	self.Path = nil
end

function ENT:SpawnSpot(origin, tries)
	local near = tries < SPAWN_CLOSER_TRIES and SPAWN_NEAR[1] or SPAWN_NEAR[2]
	local far = math.min(SPAWN_FAR + tries * SPAWN_WIDEN, SPAWN_MAX)
	local areas = navmesh.Find(origin, far, CLIMB, DROP)
	if #areas == 0 then return end
	local hidden = tries < SPAWN_HIDDEN_TRIES
	for _ = 1, SPOT_SAMPLES do
		local area = areas[math.random(#areas)]
		local spot = area:GetRandomPoint()
		if not area:IsUnderwater() and spot:DistToSqr(origin) > near * near and self:Unseen(spot, hidden) then
			return spot
		end
	end
end

function ENT:Unseen(spot, hidden)
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and (spot:DistToSqr(ply:GetPos()) < SPAWN_CROWD * SPAWN_CROWD or Sees(ply, spot, hidden)) then
			return false
		end
	end
	return true
end

function ENT:HideSpot(from, reach)
	local areas = navmesh.Find(self:GetPos(), reach or HIDE_RANGE, DROP, CLIMB)
	local best, farthest = nil, 0
	for _ = 1, math.min(#areas, SPOT_SAMPLES) do
		local spot = areas[math.random(#areas)]:GetRandomPoint()
		local d = spot:DistToSqr(from)
		if d > farthest then best, farthest = spot, d end
	end
	return best
end

-- The closest spot near ply that they've got no line of sight to.
function ENT:LurkSpot(ply)
	local origin = ply:GetPos()
	local areas = navmesh.Find(origin, LURK_SPOT[2], CLIMB, DROP)
	local best, nearest = nil, math.huge
	for _ = 1, math.min(#areas, SPOT_SAMPLES * 2) do
		local spot = areas[math.random(#areas)]:GetRandomPoint()
		local d = spot:DistToSqr(origin)
		if d > LURK_SPOT[1] * LURK_SPOT[1] and d < nearest and not Sees(ply, spot, true) then best, nearest = spot, d end
	end
	return best
end

local function Enclosed(ply)
	local from = ply:GetPos() + WAIST
	local hits = 0
	for _, dir in ipairs(AROUND) do
		if util.TraceLine({ start = from, endpos = from + dir, mask = MASK_SOLID, filter = ply }).Hit then hits = hits + 1 end
	end
	return hits >= ENCLOSED_HITS
end

local function Alone(ply)
	local pos = ply:GetPos()
	for _, other in ipairs(player.GetAll()) do
		if other ~= ply and other:Alive() and other:GetPos():DistToSqr(pos) < ALONE_RANGE * ALONE_RANGE then return false end
	end
	return true
end

-- Someone on their own, holed up somewhere tight and keeping still, who hasn't been baited out of this spot yet.
function ENT:Cornered(ply, now)
	return ply:IsPlayer() and now - self.CampSince >= CAMP_TIME and self.BaitedAt ~= self.CampSince
		and self:GetPos():DistToSqr(ply:GetPos()) < BAIT_RANGE * BAIT_RANGE
		and Alone(ply) and Enclosed(ply)
end

-- Waits a tick. Returns the target and the time if it's still worth hunting.
function ENT:Tick()
	coroutine.yield()
	local target = self:GetTarget()
	if not Huntable(target) then return end
	local now = CurTime()
	local pos = target:GetPos()
	if self.CampFor ~= target or pos:DistToSqr(self.CampPos) > CAMP_RADIUS * CAMP_RADIUS then
		self.CampFor, self.CampPos, self.CampSince = target, pos, now
	end
	return target, now
end

local BRAIN = {}

function BRAIN.idle(self)
	if self:Fed() then return "rest" end
	local last = self:GetTarget()
	local since = CurTime()
	self:SetTarget(NULL)
	while true do
		local target = self:PickTarget()
		if target then
			self:SetTarget(target)
			local resume = self.Placed and target == last and CurTime() - since < IDLE_FORGET
			return resume and "stalk" or "relocate"
		end
		coroutine.wait(1)
	end
end

function BRAIN.relocate(self)
	local wait = CurTime() + VANISH_WAIT
	while CurTime() < wait and self:Watched(self:GetPos()) do coroutine.wait(0.2) end
	for tries = 0, math.huge do
		local target = self:GetTarget()
		if not Huntable(target) then return "idle" end
		local spot = self:SpawnSpot(target:GetPos(), tries)
		if spot then
			self:SetPos(spot)
			self.Placed = true
			sound.Play(ARRIVE_SOUND, spot + EYE, ARRIVE_LEVEL, ARRIVE_PITCH)
			return "stalk"
		end
		coroutine.wait(0.2)
	end
end

function BRAIN.stalk(self, from)
	self:Pace(Setting("stalk_speed"), STALK_ACCEL)
	local lurk = CurTime() + (from == "relocate" and Setting("lurk_time") or 0)
	local giveUp = lurk + Setting("stalk_time")
	local sneaky = self:Sneaky(self:GetTarget())
	local held
	while true do
		local target, now = self:Tick()
		if not target then return "idle" end
		if self:SeenBy(target) then
			return math.random() < Setting("chase_chance") and "chase" or "hide"
		end
		if self:Catch(target) then return "feed" end
		if now >= giveUp then return "relocate" end
		if now >= lurk and self:Cornered(target, now) then
			self.BaitedAt = self.CampSince
			return "feint"
		end
		if now >= lurk then
			-- Waits at the corner while the next stretch is in view, and goes when they look away.
			local ahead = self:PathAhead(HOLD_AHEAD)
			if ahead and self:SeenBy(target, ahead) then held = held or now else held = nil end
			if not held or now - held >= HOLD_MAX then
				local close = self:GetPos():DistToSqr(target:GetPos()) < FLANK_RANGE * FLANK_RANGE
				if not self:Approach(close and Ground(target) or Behind(target), now, sneaky) then return "relocate" end
			end
		end
	end
end

function BRAIN.chase(self)
	local target = self:GetTarget()
	if not Huntable(target) then return "idle" end

	local start = CurTime()
	local enraged = (self.Escapes[target] or 0) >= Setting("rage_escapes")
	if enraged then self.Escapes[target] = 0 end
	local speed, accel = Setting("chase_speed"), CHASE_ACCEL
	if enraged then
		speed, accel = Setting("rage_speed"), RAGE_ACCEL
	elseif start < self.TiredUntil then
		speed, accel = speed * TIRED_PACE, TIRED_ACCEL
	end
	self:Pace(speed, accel)
	self:SetEnraged(enraged)
	local gripFrom = enraged and RAGE_GRIP or 0
	local gripMax = (not enraged and start < self.TiredUntil) and TIRED_GRIP or 1

	local breather = not enraged and math.random() < BREATHER_CHANCE
	local seen = start
	local lastPos, lastVel, guess

	local function Done(nextState, escaped)
		self:SetEnraged(false)
		if escaped then
			self.Escapes[target] = (self.Escapes[target] or 0) + 1
			if enraged then self.TiredUntil = CurTime() + Setting("tired_time") end
		end
		return nextState
	end

	while true do
		local t, now = self:Tick()
		if not t then return Done("idle") end
		if self:Catch(t) then return Done("feed") end
		local close = breather and self:GetPos():DistToSqr(t:GetPos()) < BREATHER_RANGE * BREATHER_RANGE
		local pace = close and math.min(BREATHER_SPEED, speed) or speed
		self.loco:SetDesiredSpeed(pace)
		-- Locks on as the chase goes, so it stops drifting past and starts turning on a dime.
		local grip = math.min(gripFrom + (now - start) / math.max(Setting("lock_on_time"), 0.1), gripMax)
		local snap = Lerp(grip, accel, SNAP_ACCEL)
		self.loco:SetAcceleration(snap)
		self.loco:SetDeceleration(snap)
		local spotted = self:Spots(t)
		-- Knows where you are for the first stretch. After that it has to keep you in sight, and when it
		-- loses you it heads where you were going.
		local free = now - start > Setting("chase_time")
		if not free or spotted then
			seen, lastPos, lastVel, guess = now, Ground(t), t:GetVelocity(), nil
		end
		local goal
		if seen == now then
			goal = self:Lead(lastPos, lastVel, speed)
		else
			guess = guess or Ahead(lastPos, lastVel, PREDICT)
			goal = guess
			if now - seen > SEARCH_TIME or self:GetPos():DistToSqr(guess) < SEARCH_REACHED * SEARCH_REACHED then
				return Done("relocate", true)
			end
		end
		local to = t:GetPos() - self:GetPos()
		if spotted and to:Length2DSqr() < DIRECT_RANGE * DIRECT_RANGE and math.abs(to.z) < DIRECT_HEIGHT then
			local vel = t:GetVelocity()
			self:Steer(t:GetPos() + Vector(vel.x, vel.y, 0) * (DIRECT_LEAD * grip), pace, grip)
			self.Stranded = nil
		elseif not self:Approach(goal, now) and free then
			return Done("relocate", true)
		end
	end
end

function BRAIN.hide(self)
	self:Pace(WALK_SPEED, WALK_ACCEL)
	local target = self:GetTarget()
	local spot = self:HideSpot(IsValid(target) and target:GetPos() or self:GetPos())
	if not spot then return "relocate" end

	local sneaky = self:Sneaky(target)
	local start = CurTime()
	local seen = start
	while true do
		coroutine.yield()
		local now = CurTime()
		target = self:GetTarget()
		if Huntable(target) then
			if self:SeenBy(target) then seen = now end
			if self:Catch(target) then return "feed" end
		end
		if now - start > HIDE_TIME or now - seen > HIDE_UNSEEN or self:GetPos():DistToSqr(spot) < HIDE_REACHED * HIDE_REACHED then
			break
		end
		if not self:Approach(spot, now, sneaky) then break end
	end

	if self:Fed() then return self.Meal and "feed" or "rest" end
	if Huntable(self:GetTarget()) and math.random() < Setting("ambush_chance") then return "ambush" end
	return "relocate"
end

-- Walks off where they can hear it go.
function BRAIN.feint(self)
	self:Pace(Setting("stalk_speed"), STALK_ACCEL)
	local target = self:GetTarget()
	local spot = self:HideSpot(target:GetPos(), FEINT_REACH)
	if not spot then return "lure" end
	local sneaky = self:Sneaky(target)
	local start = CurTime()
	while true do
		local t, now = self:Tick()
		if not t then return "idle" end
		if now - start > FEINT_TIME or self:GetPos():DistToSqr(spot) < HIDE_REACHED * HIDE_REACHED then return "lure" end
		if not self:Approach(spot, now, sneaky) then return "lure" end
	end
end

-- Comes back without a sound and waits just out of sight of their hiding spot. Goes for them the moment
-- they come out, or walks in when it's done waiting.
function BRAIN.lure(self)
	self:Pace(Setting("stalk_speed"), STALK_ACCEL)
	local target = self:GetTarget()
	local camp = self.CampPos
	local spot = self:LurkSpot(target)
	local sneaky = self:Sneaky(target)
	local start = CurTime()
	local waiting
	while true do
		local t, now = self:Tick()
		if not t then return "idle" end
		if self:SeenBy(t) or t:GetPos():DistToSqr(camp) > CAMP_RADIUS * CAMP_RADIUS then return "chase" end
		if self:Catch(t) then return "feed" end
		if now - start > LURE_TIME then return "stalk" end
		if spot and not waiting then
			if self:GetPos():DistToSqr(spot) < HIDE_REACHED * HIDE_REACHED then
				waiting = now
			elseif not self:Approach(spot, now, sneaky) then
				spot = nil
			end
		elseif not waiting or now - waiting >= LURK_WAIT then
			self:Approach(Ground(t), now)
		end
	end
end

-- Eats what it just killed, right where it fell.
function BRAIN.feed(self)
	local body = self.Meal
	self.Meal = nil
	self:SetTarget(NULL)
	self:SetEnraged(false)
	if IsValid(body) then self:Eat(body) end
	return "rest"
end

-- Fed. Lingers over the meal, then keeps out of everyone's sight until it's hungry again.
function BRAIN.rest(self)
	self:SetTarget(NULL)
	self:SetEnraged(false)
	local linger = CurTime() + LINGER
	while self:Fed() do
		local watcher = self:Watched(self:GetPos())
		if watcher then
			self:Slink(watcher)
		elseif CurTime() >= linger and self:Exposed(self:GetPos()) then
			local spot = self:VanishSpot()
			if spot and not self:Watched(self:GetPos()) then self:SetPos(spot) end
		end
		coroutine.wait(REST_CHECK)
	end
	return "idle"
end

function BRAIN.ambush(self)
	local giveUp = CurTime() + Setting("ambush_time")
	while true do
		local target, now = self:Tick()
		if not target then return "idle" end
		if self:SeenBy(target) then return "chase" end
		if self:GetPos():DistToSqr(target:GetPos()) < AMBUSH_RANGE * AMBUSH_RANGE and self:Spots(target) then
			return "chase"
		end
		if now >= giveUp then return "stalk" end
	end
end

function ENT:RunBehaviour()
	local state = "idle"
	while true do
		local from = self:StateName()
		if developer:GetBool() then print(self, from, "->", state) end
		self:SetState(STATE[state])
		self.Path = nil
		self.RepathAt = 0
		self.Stranded = nil
		self.StuckSince = nil
		state = BRAIN[state](self, from) or "idle"
	end
end

function ENT:Think()
	if not developer:GetBool() then return end
	debugoverlay.Text(self:SightPos() + Vector(0, 0, 72), self:StateName(), 0.1, false)
	if self.Path and self.Path:IsValid() then self.Path:Draw() end
end
