AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.PrintName = "Terminus"
ENT.Category = "Terminus"
ENT.Spawnable = true

function ENT:Initialize()
    self:SetModel("models/terminus.mdl")
    self:SetSpawnEffect(false)
    self:SetCollisionBounds(Vector(-1, -1, 0), Vector(1, 1, 1))
    self:SetSolid(0)
    self:SetCollisionGroup(10)
    if SERVER then
        self:SetMaxHealth(999999999)
    end
    self:SetHealth(999999999)
    self.LoseTargetDist = 9999999
    self.SearchRadius = 9999999
    self.waiting = false
    self.walking = false
    self.stalking = true
    self.chasing = false
    self.ambushing = false
    self.enraged = false
    self.tired = false
    self.escapedchases = 0
 
    self.loaded_amb_sounds = {}
    self.loaded_amb_sounds[1] = CreateSound(game.GetWorld(), "chasing_ambience.wav")
    self.loaded_amb_sounds[2] = CreateSound(game.GetWorld(), "stalk_ambience_1.wav")
    self.loaded_amb_sounds[3] = CreateSound(game.GetWorld(), "stalk_ambience_2.wav")
    self.loaded_amb_sounds[4] = CreateSound(game.GetWorld(), "stalk_ambience_3.wav")
    self.loaded_amb_sounds[5] = CreateSound(game.GetWorld(), "stalk_ambience_4.wav")
    self.loaded_amb_sounds[6] = CreateSound(game.GetWorld(), "stalk_end.wav")
    self.loaded_amb_sounds[7] = CreateSound(self, "close_stalking_1.wav")
    self.loaded_amb_sounds[8] = CreateSound(self, "close_stalking_2.wav")

    self.loaded_sounds = {}
    self.loaded_sounds[1] = CreateSound(self, "chasing.wav")

    self.enrage_sounds = {}
    self.enrage_sounds[1] = CreateSound(game.GetWorld(), "enraged.wav")
end

local trace = {
	mask = MASK_SOLID_BRUSHONLY
}

--will set enemy variable
function ENT:SetEnemy(ent)
	self.Enemy = ent
end

--gets the currently set enemy
function ENT:GetEnemy()
	return self.Enemy
end

--checks if we have an enemy, if we don't, it will try to find a new one and return true or false if it found one or not. else, it will return true.
function ENT:HaveEnemy()
	if ( self:GetEnemy() and IsValid(self:GetEnemy()) ) then
		if ( self:GetRangeTo(self:GetEnemy():GetPos()) > self.LoseTargetDist ) then
			return self:FindEnemy()
		elseif ( self:GetEnemy():IsPlayer() and !self:GetEnemy():Alive() ) then
			return self:FindEnemy()
		end
		return true
	else
		return self:FindEnemy()
	end
end

--will return true and set enemy if one is found. searches in a sphere(but the search is limited by time rather than range)
function ENT:FindEnemy()
	local _ents = ents.FindInSphere( self:GetPos(), self.SearchRadius )
	for k,v in ipairs( _ents ) do
		if ( v:IsPlayer() ) then
			self:SetEnemy(v)
			return true
        end
	end
    print("couldn't find enemy")
	self:SetEnemy(nil)
	return false
end

--adding the run behavior
function ENT:RunBehaviour()

    if (self:HaveEnemy()) then
        self:TeleportToRandom()
    end

    while (true) do
        if (self:HaveEnemy() and !self.waiting) then
            --print("STARTED STALK");
            self:StalkEnemy()
        else
            --print("WAITING OR NO ENEMY");
        end

        coroutine.wait(2)
    end
end

-- if this function is called when the player is touching the enemy, they die and the enemy wanders off
function ENT:InstaGib()
    if (self:VectorDistance(self:GetEnemy():GetPos(), self:GetPos()) < 50 and self:GetEnemy():Alive()) then
        self:GetEnemy():Kill()
        self.stopchasing = true
        self:GoToRandomPoint()
    end
end

-- return the distance between two vectors
function ENT:VectorDistance(v1, v2)
    return math.sqrt((((v1.x)-(v2.x))*((v1.x)-(v2.x))) + (((v1.y)-(v2.y))*((v1.y)-(v2.y))) + (((v1.z)-(v2.z))*((v1.z)-(v2.z))))
end

function ENT:GetPlayerVisible()
    return self:GetEnemy():Visible(self)
end

function ENT:StalkEnemy( options )
    print("Stalking player")

    self.waiting = true
    self.stalking = true
    self.chasing = false
    self.walking = false

    --how long he waits before stalking
    self.pre_stalk_time = 15
    self.pre_stalk_timer = 0

    self.loco:SetAcceleration(200)
    self.loco:SetDesiredSpeed(300)

	local options = options or {}
	self.path = Path("Chase")
	self.path:SetMinLookAheadDistance( options.lookahead or 300 )
	self.path:SetGoalTolerance( options.tolerance or 20 )
	self.path:Compute(self, self:GetEnemy():GetPos())

    local stalking_timer = 0
    local stalking_time = 120

    -- if his path is invalid, return false out of the function
	if !self.path:IsValid() then
        print('Stalk failed')
        return "failed"
    end

    self.LastPathRecompute = 0

	while self.path:IsValid() and self:HaveEnemy() and self.stalking do
        self:InstaGib()
        self.pre_stalk_timer = self.pre_stalk_timer + FrameTime()

        if !self:GetPlayerVisible() then
            if (self.pre_stalk_timer > self.pre_stalk_time) then
                if ( self.path:GetAge() > 0.1 ) then
                    self.path:Compute(self, self:GetEnemy():GetPos())
                end
                self.path:Update( self )

                if (CurTime() - self.LastPathRecompute > 0.1) then
                    self.LastPathRecompute = CurTime()
                    self:RecomputeTargetPath(self:GetEnemy():GetPos())
                end

                if options.draw then self.path:Draw() end

                local stuckTimer = 0
                local stuckTime = 1
                stuckTimer = stuckTimer + FrameTime()

                if (stuckTimer > stuckTime) then
                    self:UnstickFromCeiling()
                    stuckTimer = 0
                end
                
                stalking_timer = stalking_timer + FrameTime()
                if (stalking_timer > stalking_time) then
                    stalking_timer = 0
                    self:TeleportToRandom()
                end
            end
        else
            print("STALK ENDED: SEEN BY PLAYER")
            self:RandBehaviour()
        end
        self:Sounds()
        coroutine.yield()
	end
	return "ok"
end

function ENT:ChasePlayer()
    local slowchoice = math.random(0, 3)
    print("Chasing player, if 1 then enemy will slow down when too close", slowchoice)
    print("Current escaped chase count:", self.escapedchases)
    print("ENRAGED BOOL:", self.enraged)

    self.waiting = true
    self.chasing = true
    self.stalking = false
    self.walking = false

    self.stopchasing = false

    if self.escapedchases >= 4 then
        print("ENRAGED")
        self.enraged = true
        self.escapedchases = 0
    end

    if !self.enraged and !self.tired then
        self.loco:SetAcceleration(375)
        self.loco:SetDesiredSpeed(1000)
    elseif self.enraged then
        self.loco:SetAcceleration(700)
        self.loco:SetDesiredSpeed(2000)
    elseif self.tired then
        self.loco:SetAcceleration(100)
        self.loco:SetDesiredSpeed(500)
    end

    local options = options or {}
	self.path = Path("Chase")
	self.path:SetMinLookAheadDistance( options.lookahead or 300 )
	self.path:SetGoalTolerance( options.tolerance or 20 )
	self.path:Compute(self, self:GetEnemy():GetPos())

	if !self.path:IsValid() then
        return "failed"
    end

    local chasing_time = 15
    local chasing_timer = 0

    self.LastPathRecompute = 0

	while (self.path:IsValid() and !self.stopchasing) do

        self:InstaGib()

        chasing_timer = chasing_timer + FrameTime()
        if ( self.path:GetAge() > 0.1 ) then
            self.path:Compute(self, self:GetEnemy():GetPos())
        end
        self.path:Update( self )

        if (CurTime() - self.LastPathRecompute > 0.1) then
            self.LastPathRecompute = CurTime()
            self:RecomputeTargetPath(self:GetEnemy():GetPos())
        end

        if ( options.draw ) then self.path:Draw() end

        /* rolls a dice as to whether or not the enemy will slow down 
        when too close to give the player some room during a chase */
        if self:VectorDistance(self:GetPos(), self:GetEnemy():GetPos()) < 150 and !self.enraged then
            if slowchoice == 1 then
                print("Slowing down to give player room")
                self.loco:SetDesiredSpeed(400)
            else
                self.loco:SetDesiredSpeed(1000)
            end
        end

        if (!self:GetPlayerVisible() and chasing_timer > chasing_time) then
            self.stopchasing = true
            self.enraged = false
            print("Chase stopped")
            print("Increasing escaped chases count, new:", self.escapedchases)
            self.escapedchases = self.escapedchases + 1
        end

        local stuckTimer = 0
        local stuckTime = 1
        stuckTimer = stuckTimer + FrameTime()

        if (stuckTimer > stuckTime) then
            self:UnstickFromCeiling()
            stuckTimer = 0
        end

        self:Sounds()
        coroutine.yield()
	end

    print("Chase stopped")
    print("Increasing escaped chases count, new:", self.escapedchases)
    self.escapedchases = self.escapedchases + 1
    self.enraged = false
    self:TeleportToRandom()
	return "ok"

end

local chase_sound_clock = 0
local chase_sound_time = 0
local amb_chase_sound_clock = 0
local amb_chase_sound_time = 0
local enraged_sound_clock = 0
local enraged_sound_time = 0

local stalk_close_sound_clock = 0
local stalk_close_sound_time = 0
local stalk_sound_clock = 0
local stalk_sound_time = 0

function ENT:Sounds()
    amb_chase_sound_clock = amb_chase_sound_clock + FrameTime()
    chase_sound_clock = chase_sound_clock + FrameTime()
    enraged_sound_clock = enraged_sound_clock + FrameTime()
    stalk_close_sound_clock = stalk_close_sound_clock + FrameTime()
    stalk_sound_clock = stalk_sound_clock + FrameTime()

    if (self.stalking or self.walking) then
        if (stalk_close_sound_clock > stalk_close_sound_time) then
            stalk_close_sound_clock = 0
            self.loaded_amb_sounds[7]:Stop()
            self.loaded_amb_sounds[8]:Stop()
            local random_sound = math.random(7,8)
            self.loaded_amb_sounds[random_sound]:SetSoundLevel(70)
            self.loaded_amb_sounds[random_sound]:Play()
            stalk_close_sound_time = SoundDuration("close_stalking_"..tostring(random_sound-6)..".wav")
            --print("played close stalk ambsound, set end time to "..stalk_close_sound_time)
        end
    end

    --if (self.walking or self.stalking) then
    if (false) then
        self.loaded_amb_sounds[1]:Stop()
        self:StopAllSelfSounds()
        if (stalk_sound_clock > stalk_sound_time) then
            stalk_sound_clock = 0
            self.loaded_amb_sounds[2]:Stop()
            self.loaded_amb_sounds[3]:Stop()
            self.loaded_amb_sounds[4]:Stop()
            self.loaded_amb_sounds[5]:Stop()
            local random_sound = math.random(2,5)
            self.loaded_amb_sounds[random_sound]:SetSoundLevel(0)
            self.loaded_amb_sounds[random_sound]:Play()
            stalk_sound_time = SoundDuration("stalk_ambience_"..tostring(random_sound-1)..".wav")
            --print("played stalk ambsound, set end time to "..stalk_sound_time)
        end
    end

    if (self.enraged) then
        if (enraged_sound_clock > enraged_sound_time) then
            self.enrage_sounds[1]:Stop()
            enraged_sound_clock = 0
            self.enrage_sounds[1]:SetSoundLevel(0)
            enraged_sound_time = SoundDuration("enraged.wav")
            self.enrage_sounds[1]:Play()
            print("Played ENRAGED audio")
        end
    end

    if (self.chasing) then
        if (amb_chase_sound_clock > amb_chase_sound_time) then
            self:StopAllAmbSounds()
            amb_chase_sound_clock = 0
            self.loaded_amb_sounds[1]:SetSoundLevel(0)
            amb_chase_sound_time = SoundDuration("chasing_ambience.wav")
            self.loaded_amb_sounds[1]:Play()
            print("Played chasing ambience")
        end
        if (chase_sound_clock > chase_sound_time) then
            self.loaded_sounds[1]:Stop()
            chase_sound_clock = 0
            self.loaded_sounds[1]:SetSoundLevel(70)
            chase_sound_time = SoundDuration("chasing.wav")
            self.loaded_sounds[1]:Play()
            print("Played chasing frontal")
        end
    end
end

function ENT:StopAllAmbSounds()
    for k,v in pairs(self.loaded_amb_sounds) do
        v:Stop()
    end
end

function ENT:StopAllAmbSoundsRange(min, max)
    for k,v in pairs(self.loaded_amb_sounds) do
        if (k <= min and k >= max) then
            v:Stop()
        end
    end
end

function ENT:StopAllSelfSounds()
    for k,v in pairs(self.loaded_sounds) do
        v:Stop()
    end
end

function ENT:GoToRandomPoint()

    self.waiting = true
    self.walking = true
    self.chasing = false
    self.stalking = false

    if !self.tired then
        self.loco:SetAcceleration(400)
        self.loco:SetDesiredSpeed(700)
    end
    
    local options = options or {}
	self.path = Path("Chase")
	self.path:SetMinLookAheadDistance( options.lookahead or 500 )
	self.path:SetGoalTolerance( options.tolerance or 10 )
    local spot_options = {pos = self:GetEnemy():GetPos(), radius = 10000, stepup = 5000, stepdown = 5000}
    local spot = self:FindSpot('random', spot_options)

    --print ("spot is at "..spot.x.." "..spot.y.." "..spot.z.." and player is at "..self:GetEnemy():GetPos().x.." "..self:GetEnemy():GetPos().y.." "..self:GetEnemy():GetPos().z)

	self.path:Compute(self, spot)

	if ( !self.path:IsValid() ) then
        --print('failed')
        return "failed"
    end

    local walking_time = 90
    local walking_timer = 0
    self.LastPathRecompute = 0
    local wait_to_tp = 0
    local wait_time = 15

	while ( self.path:IsValid() and self:HaveEnemy() and self.walking) do

        self:InstaGib()

        --print("WALKING AWAY")
            
        self.path:Update( self )

        if (CurTime() - self.LastPathRecompute > 0.1) then
            self.LastPathRecompute = CurTime()
            self:RecomputeTargetPath(spot)
        end

        if ( options.draw ) then self.path:Draw() end

        local stuckTimer = 0
        local stuckTime = 1
        stuckTimer = stuckTimer + FrameTime()

        if (stuckTimer > stuckTime) then
            self:UnstickFromCeiling()
            stuckTimer = 0
        end

        if ( self.loco:IsStuck() ) then
            --print("stuck")
            --return "stuck"
        end

        walking_timer = walking_timer + FrameTime()
        if (walking_timer > walking_time) then
            walking_timer = 0
            TeleportToRandom()
        end

        if (!self:GetEnemy():Visible(self)) then
            wait_to_tp = wait_to_tp + FrameTime()
            if (wait_to_tp > wait_time) then
                self:TeleportToRandom()
            end
        end

        self:Sounds()

        coroutine.yield()
	end

    self.walking = false
    self.waiting = false

	return "ok"
end

local VECTOR_HIGH = Vector(0, 0, 16384)
ENT.LastPathingInfraction = 0

function ENT:RecomputeTargetPath(path_target)
	if (CurTime() - self.LastPathingInfraction < 5) then
		return
	end

	local targetPos = path_target

	-- Run toward the position below the entity we're targetting, since we can't fly.
	trace.start = targetPos
	trace.endpos = targetPos - VECTOR_HIGH
	trace.filter = self:GetEnemy()
	local tr = util.TraceEntity(trace, self:GetEnemy())

	-- Of course, we sure that there IS a "below the target."
	if (tr.Hit and util.IsInWorld(tr.HitPos)) then
		targetPos = tr.HitPos
	end

	local rTime = SysTime()
	self.path:Compute(self, targetPos)

	if (SysTime() - rTime > 0.005) then
		self.LastPathingInfraction = CurTime()
	end
end

function ENT:RandBehaviour()
    self.waiting = true
    self.stalking = false
    local choice = math.random(-1, 2)

    if choice > 0 then
        self:Hide()
    else
        self:ChasePlayer()
    end

end

function ENT:Hide()
    print("Hiding")
    self:GoToRandomPoint()

    local choice = math.random(1, 2)

    -- roll a dice between going back to stalking or ambushing
    if choice == 2 then
        self:Ambush()
    end

end

function ENT:Ambush()
    print("Ambush at", self:GetPos())
    self.ambushing = true
    self.loco:SetDesiredSpeed(0)
    self:StopAllAmbSounds()
    self:StopAllSelfSounds()

    local ambushcounter = 0
    while self.ambushing do
        ambushcounter = ambushcounter + FrameTime()

        if ambushcounter > 25 then
            print("Ambush timer expired, now stalking")
            self:StalkEnemy()
        end

        if self:GetPlayerVisible() then
            self.ambushing = false
            self:ChasePlayer()
        end
        coroutine.yield()
    end

end

function ENT:TeleportToRandom()
    local spot_options = {pos = self:GetEnemy():GetPos(), radius = 10000, stepup = 5000, stepdown = 5000}
    local spot = nil
    local lookForSpot = true
    self.path = Path("Chase")
	self.path:SetMinLookAheadDistance(300)
	self.path:SetGoalTolerance(20)
    while (lookForSpot) do
        self.path:Compute(self, self:GetEnemy():GetPos())
        lookForSpot = false
        spot = self:FindSpot('random', spot_options)
        if (spot == nil) then lookForSpot = true end
        if (!self.path:IsValid()) then lookForSpot = true end
        coroutine.wait(0.1)
    end
    
    self:SetPos(spot)

    print("teleported to spot "..spot.x.." "..spot.y.." "..spot.z)

    self.waiting = false
    self.walking = false
    self.chasing = false
    self.stalking = false
end

function ENT:UnstickFromCeiling()
	if (self:IsOnGround()) then return end

	local myPos = self:GetPos()
	local myHullMin, myHullMax = self:GetCollisionBounds()
	local myHull = (myHullMax - myHullMin)
	local myHullTop = myPos + vector_up * myHull.z
	trace.start = myPos
	trace.endpos = myHullTop
	trace.filter = self
	local upTrace = util.TraceLine(trace, self)

	if (upTrace.Hit and upTrace.HitNormal ~= vector_origin and upTrace.Fraction > 0.5) then
		local unstuckPos = myPos + upTrace.HitNormal * (myHull.z * (1 - upTrace.Fraction))
		self:SetPos(unstuckPos)
	end
end

ENT.RenderGroup = RENDERGROUP_TRANSLUCENT
local terminusMaterial = Material("terminus/npc_terminus.png", "smooth mips")
local draw_offset = Vector(0, 0, 64)

function ENT:RenderOverride()
    self:SetRenderBounds(Vector(-80, -80, 0), Vector(80, 80, 80))
	render.SetMaterial(terminusMaterial)
	render.DrawSprite(self:GetPos() + draw_offset, 128, 128)
end

list.Set("NPC", "npc_terminus", {
    Name = "Terminus",
    Class = "npc_terminus",
    Category = "Terminus"
})
