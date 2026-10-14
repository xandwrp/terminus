include("shared.lua")

language.Add("npc_terminus", "Terminus")
killicon.Add("npc_terminus", "terminus/killicon.png", color_white)

local SPRITE = Material("terminus/npc_terminus.png", "smooth mips")
local SIZE = 128
local CHASE_SHAKE = 1.5
local RAGE_SHAKE = 5
local RAGE_TINT = Color(255, 140, 140)
local RENDER_MIN, RENDER_MAX = Vector(-80, -80, 0), Vector(80, 80, 140)
local LIGHT_GAIN = 1.6
local LIGHT_FLOOR = 0.03
local FLASHLIGHT_RANGE = 1000
local FLASHLIGHT_COS = math.cos(math.rad(30))
local REPORT_EVERY = 0.2
local REPORT_CHANGE = 8
local POP_TIME = 0.35
local POP_SIZE = 0.3
local POP_SHAKE = 8
local FLICKER = 0.08
local FEED_DIP = 36
local CHEW_RATE, CHEW_DEPTH = 7, 6
local CHEW_SHAKE = 1

local tint = Color(255, 255, 255)

local function Lit(c)
	return math.Clamp(math.sqrt(math.max(c, 0)) * LIGHT_GAIN, LIGHT_FLOOR, 1)
end

-- How lit it looks where it stands, per channel. The world's lighting doesn't reach sprites on its own.
local function Lighting(pos)
	local light = render.GetLightColor(pos)
	return Lit(light.x), Lit(light.y), Lit(light.z)
end

local function Flashlit(pos)
	local me = LocalPlayer()
	if not me:FlashlightIsOn() then return 0 end
	local eye = me:EyePos()
	local to = pos - eye
	local dist = to:Length()
	if dist > FLASHLIGHT_RANGE or me:GetAimVector():Dot(to) < dist * FLASHLIGHT_COS then return 0 end
	if util.TraceLine({ start = eye, endpos = pos, mask = MASK_OPAQUE, filter = me }).Hit then return 0 end
	return 1 - dist / FLASHLIGHT_RANGE
end

function ENT:Initialize()
	self:SetRenderBounds(RENDER_MIN, RENDER_MAX)
end

function ENT:RenderOverride()
	local state = self:GetState()
	local pos, size, shake, color = self:SightPos(), SIZE, 0, tint
	if state == Terminus.STATE.chase and self:GetEnraged() then
		shake, color = RAGE_SHAKE, RAGE_TINT
	else
		local r, g, b = Lighting(pos)
		local f = Flashlit(pos)
		tint.r, tint.g, tint.b = Lerp(f, r, 1) * 255, Lerp(f, g, 1) * 255, Lerp(f, b, 1) * 255
		local leaving = state == Terminus.STATE.hide or state == Terminus.STATE.feint
		tint.a = (leaving and math.random() < FLICKER) and 0 or 255
		if state == Terminus.STATE.chase then shake = CHASE_SHAKE end
	end
	if state == Terminus.STATE.feed then
		pos = pos - vector_up * (FEED_DIP + CHEW_DEPTH * math.abs(math.sin(CurTime() * CHEW_RATE)))
		shake = shake + CHEW_SHAKE
	end
	local pop = 1 - (CurTime() - (self.SpottedAt or -math.huge)) / POP_TIME
	if pop > 0 then
		size = size * (1 + POP_SIZE * pop)
		shake = shake + POP_SHAKE * pop
	end
	if shake > 0 then pos = pos + VectorRand() * shake end
	render.SetMaterial(SPRITE)
	render.DrawSprite(pos, size, size, color)
end

-- Player models take their colour from whoever's wearing them, so a body of a player needs telling.
hook.Add("EntityNetworkedVarChanged", "TerminusBodyColor", function(ent, name, _, color)
	if name == Terminus.COLOR_VAR and color then ent.GetPlayerColor = function() return color end end
end)

hook.Add("Think", "TerminusSpotted", function()
	for _, ent in ipairs(ents.FindByClass("npc_terminus")) do
		local state = ent:GetState()
		if ent.LastState and Terminus.Spotted(ent.LastState, state) then ent.SpottedAt = CurTime() end
		ent.LastState = state
	end
end)

-- Tells the server how lit it is for whoever it's after, so it can hide in the dark.
local reportAt = 0
hook.Add("Think", "TerminusLight", function()
	local now = CurTime()
	if now < reportAt then return end
	reportAt = now + REPORT_EVERY
	local me = LocalPlayer()
	if not IsValid(me) then return end
	for _, ent in ipairs(ents.FindByClass("npc_terminus")) do
		if ent:GetTarget() == me then
			local light = math.floor(math.max(Lighting(ent:SightPos())) * 255 + 0.5)
			if ent.ReportedFor ~= me or math.abs(light - ent.Reported) >= REPORT_CHANGE then
				ent.Reported, ent.ReportedFor = light, me
				net.Start("TerminusLight")
				net.WriteEntity(ent)
				net.WriteUInt(light, 8)
				net.SendToServer()
			end
		else
			ent.ReportedFor = nil
		end
	end
end)
