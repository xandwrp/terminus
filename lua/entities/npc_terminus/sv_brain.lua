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
local CATCH_FORCE = 5000
local SIGHT_CLOSE = 160
local SIGHT_TOP = Vector(0, 0, 110)
local SPRITE_RADIUS = 48
local ASPECT = 16 / 9
local LOSE_SIGHT = 2
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
local GROUND = Vector(0, 0, 16384)

local function Huntable(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:Alive()
		and not ai_ignoreplayers:GetBool()
		and not ply:IsFlagSet(FL_NOTARGET)
		and ply:GetMoveType() ~= MOVETYPE_NOCLIP
		and ply:GetObserverMode() == OBS_MODE_NONE
end

local function Clear(from, to, filter)
	return not util.TraceLine({ start = from, endpos = to, mask = MASK_OPAQUE, filter = filter }).Hit
end

local function OnScreen(ply, point)
	local to = point - ply:EyePos()
	local ang = ply:EyeAngles()
	local depth = to:Dot(ang:Forward())
	if depth <= 0 then return false end
	local fov = ply:GetFOV()
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
	local vehicle = ply:GetVehicle()
	local filter = IsValid(vehicle) and { ply, vehicle } or ply
	return Clear(eye, center, filter) or Clear(eye, pos + SIGHT_TOP, filter)
end

local function Ground(ply)
	local pos = ply:GetPos()
	if ply:IsOnGround() then return pos end
	local tr = util.TraceLine({ start = pos, endpos = pos - GROUND, mask = MASK_PLAYERSOLID_BRUSHONLY })
	return tr.Hit and tr.HitPos or pos
end

function ENT:Spots(ply)
	local eye = self:SightPos()
	local filter = { self, ply }
	return Clear(eye, ply:EyePos(), filter) or Clear(eye, ply:WorldSpaceCenter(), filter)
end

function ENT:Watched(pos, anyway)
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and Sees(ply, pos, anyway) then return true end
	end
	return false
end

function ENT:PickTarget()
	local current = self:GetTarget()
	if Huntable(current) then return current end

	local hunted = {}
	for _, bot in ipairs(ents.FindByClass(self:GetClass())) do
		local t = bot ~= self and bot:GetTarget()
		if IsValid(t) then hunted[t] = (hunted[t] or 0) + 1 end
	end

	local picks, fewest = {}, math.huge
	for _, ply in ipairs(player.GetAll()) do
		if Huntable(ply) then
			local n = hunted[ply] or 0
			if n < fewest then
				picks, fewest = { ply }, n
			elseif n == fewest then
				picks[#picks + 1] = ply
			end
		end
	end
	return picks[math.random(math.max(#picks, 1))]
end

function ENT:Pace(speed, accel)
	self.loco:SetDesiredSpeed(speed)
	self.loco:SetAcceleration(accel)
end

-- Steps along a path to goal. Returns false once there's been no way there for a few seconds.
function ENT:Approach(goal, now)
	if now >= self.RepathAt then
		local path = self.Path or Path("Follow")
		path:SetMinLookAheadDistance(LOOKAHEAD)
		path:SetGoalTolerance(GOAL_TOLERANCE)
		local reached = path:Compute(self, goal)
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

function ENT:Catch(ply)
	local to = ply:GetPos() - self:GetPos()
	if math.abs(to.z) > CATCH_HEIGHT or to:Length2DSqr() > CATCH_RANGE * CATCH_RANGE then return false end
	if Setting("kill_players") ~= 0 then
		local dmg = DamageInfo()
		dmg:SetDamage(1e6)
		dmg:SetDamageType(DMG_GENERIC)
		dmg:SetAttacker(self)
		dmg:SetInflictor(self)
		dmg:SetDamageForce(to:GetNormalized() * CATCH_FORCE)
		ply:TakeDamageInfo(dmg)
	end
	return true
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

function ENT:HideSpot(from)
	local areas = navmesh.Find(self:GetPos(), HIDE_RANGE, DROP, CLIMB)
	local best, farthest = nil, 0
	for _ = 1, math.min(#areas, SPOT_SAMPLES) do
		local spot = areas[math.random(#areas)]:GetRandomPoint()
		local d = spot:DistToSqr(from)
		if d > farthest then best, farthest = spot, d end
	end
	return best
end

-- Waits a tick. Returns the target and the time if it's still worth hunting.
function ENT:Tick()
	coroutine.yield()
	local target = self:GetTarget()
	if Huntable(target) then return target, CurTime() end
end

local BRAIN = {}

function BRAIN.idle(self)
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
	for tries = 0, math.huge do
		local target = self:GetTarget()
		if not Huntable(target) then return "idle" end
		local spot = self:SpawnSpot(target:GetPos(), tries)
		if spot then
			self:SetPos(spot)
			self.Placed = true
			return "stalk"
		end
		coroutine.wait(0.2)
	end
end

function BRAIN.stalk(self, from)
	self:Pace(Setting("stalk_speed"), STALK_ACCEL)
	local lurk = CurTime() + (from == "relocate" and Setting("lurk_time") or 0)
	local giveUp = lurk + Setting("stalk_time")
	while true do
		local target, now = self:Tick()
		if not target then return "idle" end
		if Sees(target, self:GetPos()) then
			return math.random() < Setting("chase_chance") and "chase" or "hide"
		end
		if self:Catch(target) then return "hide" end
		if now >= giveUp then return "relocate" end
		if now >= lurk and not self:Approach(Ground(target), now) then return "relocate" end
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

	local breather = not enraged and math.random() < BREATHER_CHANCE
	local seen = start

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
		if self:Catch(t) then return Done("hide") end
		local close = breather and self:GetPos():DistToSqr(t:GetPos()) < BREATHER_RANGE * BREATHER_RANGE
		self.loco:SetDesiredSpeed(close and math.min(BREATHER_SPEED, speed) or speed)
		if self:Spots(t) then seen = now end
		local reachable = self:Approach(Ground(t), now)
		if now - start > Setting("chase_time") and (now - seen > LOSE_SIGHT or not reachable) then
			return Done("relocate", true)
		end
	end
end

function BRAIN.hide(self)
	self:Pace(WALK_SPEED, WALK_ACCEL)
	local target = self:GetTarget()
	local spot = self:HideSpot(IsValid(target) and target:GetPos() or self:GetPos())
	if not spot then return "relocate" end

	local start = CurTime()
	local seen = start
	while true do
		coroutine.yield()
		local now = CurTime()
		target = self:GetTarget()
		if Huntable(target) then
			if Sees(target, self:GetPos()) then seen = now end
			self:Catch(target)
		end
		if now - start > HIDE_TIME or now - seen > HIDE_UNSEEN or self:GetPos():DistToSqr(spot) < HIDE_REACHED * HIDE_REACHED then
			break
		end
		if not self:Approach(spot, now) then break end
	end

	if Huntable(self:GetTarget()) and math.random() < Setting("ambush_chance") then return "ambush" end
	return "relocate"
end

function BRAIN.ambush(self)
	local giveUp = CurTime() + Setting("ambush_time")
	while true do
		local target, now = self:Tick()
		if not target then return "idle" end
		if Sees(target, self:GetPos()) then return "chase" end
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
