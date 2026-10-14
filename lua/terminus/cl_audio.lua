local STATE = Terminus.STATE
local Setting = Terminus.Setting

local CLOSE = { ")terminus/close_stalking_1.wav", ")terminus/close_stalking_2.wav" }
local CLOSE_LEVEL = 70
local CHASE = ")terminus/chasing.wav"
local CHASE_LEVEL = 75
local CHASE_FADE = 0.5
local CHASE_MUSIC = "terminus/chasing_ambience.wav"
local RAGE_MUSIC = "terminus/enraged.wav"
local MUSIC_FADE = 2
local STING = "terminus/stalk_end.wav"
local AMBIENCE = {
	"terminus/stalk_ambience_1.wav", "terminus/stalk_ambience_2.wav",
	"terminus/stalk_ambience_3.wav", "terminus/stalk_ambience_4.wav",
}
local AMBIENCE_GAP = { 6, 18 }
local AMBIENCE_VOLUME = 0.6
local CREEPING = { [STATE.stalk] = true, [STATE.hide] = true }
local HEART = "player/heartbeat1.wav"
local HEART_RANGE = 1200
local HEART_PITCH = { 85, 140 }
local HEART_VOLUME = { 0.2, 1 }
local HEARTBEAT = { [STATE.stalk] = true, [STATE.hide] = true }

local function Length(path)
	return math.max(SoundDuration((path:gsub("^%)", ""))), 0.1)
end

-- A sound kept going by restarting it when it runs out, since the wavs have no loop points.
local Loop = {}
Loop.__index = Loop

local function NewLoop(ent, path, level, fade)
	return setmetatable({ patch = CreateSound(ent, path), length = Length(path), level = level, fade = fade, ends = 0 }, Loop)
end

function Loop:Hold(on, volume, now)
	if on and volume > 0 then
		if not self.on or now >= self.ends then
			self.patch:Stop()
			self.patch:SetSoundLevel(self.level)
			self.patch:PlayEx(volume, 100)
			self.ends = now + self.length
			self.on = true
		elseif volume ~= self.volume then
			self.patch:ChangeVolume(volume, 0.1)
		end
		self.volume = volume
	elseif self.on then
		self.patch:FadeOut(self.fade)
		self.on = false
	end
end

local bots = {}

local function Voice(ent)
	local v = bots[ent]
	if v then return v end
	v = { chase = NewLoop(ent, CHASE, CHASE_LEVEL, CHASE_FADE), close = {}, closeEnds = 0, state = ent:GetState() }
	for i, path in ipairs(CLOSE) do
		v.close[i] = { patch = CreateSound(ent, path), length = Length(path) }
	end
	bots[ent] = v
	return v
end

local function Creep(v, on, now)
	if on and now >= v.closeEnds then
		local c = v.close[math.random(#v.close)]
		c.patch:Stop()
		c.patch:SetSoundLevel(CLOSE_LEVEL)
		c.patch:Play()
		v.closeEnds = now + c.length
	elseif not on and v.closeEnds > 0 then
		for _, c in ipairs(v.close) do c.patch:Stop() end
		v.closeEnds = 0
	end
end

local function Silence(v)
	v.chase.patch:Stop()
	for _, c in ipairs(v.close) do c.patch:Stop() end
end

local music
local nextAmbience = 0
local nextBeat = 0

hook.Add("Think", "TerminusAudio", function()
	local me = LocalPlayer()
	if not IsValid(me) then return end
	local now = CurTime()
	local chased, enraged, stalked = false, false, false
	local near = 0

	for _, ent in ipairs(ents.FindByClass("npc_terminus")) do
		local v = Voice(ent)
		local state = ent:GetState()
		v.chase:Hold(state == STATE.chase, 1, now)
		Creep(v, CREEPING[state], now)
		if ent:GetTarget() == me then
			chased = chased or state == STATE.chase
			enraged = enraged or (state == STATE.chase and ent:GetEnraged())
			stalked = stalked or state == STATE.stalk
			if HEARTBEAT[state] then near = math.max(near, 1 - ent:GetPos():Distance(me:GetPos()) / HEART_RANGE) end
			if Terminus.Spotted(v.state, state) then me:EmitSound(STING, 0, 100, 1, CHAN_STATIC) end
		end
		v.state = state
		v.heard = now
	end

	for ent, v in pairs(bots) do
		if not IsValid(ent) or v.heard ~= now then
			Silence(v)
			bots[ent] = nil
		end
	end

	if not music or music.owner ~= me then
		music = {
			owner = me,
			chase = NewLoop(me, CHASE_MUSIC, 0, MUSIC_FADE),
			rage = NewLoop(me, RAGE_MUSIC, 0, MUSIC_FADE),
		}
	end
	local volume = Setting("music")
	music.chase:Hold(chased, volume, now)
	music.rage:Hold(enraged, volume, now)

	if stalked and Setting("stalk_ambience") ~= 0 then
		if now >= nextAmbience then
			if nextAmbience > 0 then me:EmitSound(AMBIENCE[math.random(#AMBIENCE)], 0, 100, AMBIENCE_VOLUME, CHAN_STATIC) end
			nextAmbience = now + math.Rand(AMBIENCE_GAP[1], AMBIENCE_GAP[2])
		end
	else
		nextAmbience = 0
	end

	if near > 0 and me:Alive() and Setting("stalk_ambience") ~= 0 and now >= nextBeat then
		local pitch = Lerp(near, HEART_PITCH[1], HEART_PITCH[2])
		me:EmitSound(HEART, 0, pitch, Lerp(near, HEART_VOLUME[1], HEART_VOLUME[2]), CHAN_STATIC)
		nextBeat = now + Length(HEART) * 100 / pitch
	end
end)
