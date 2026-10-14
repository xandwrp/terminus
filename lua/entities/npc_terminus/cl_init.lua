include("shared.lua")

language.Add("npc_terminus", "Terminus")
killicon.Add("npc_terminus", "terminus/killicon.png", color_white)

local SPRITE = Material("terminus/npc_terminus.png", "smooth mips")
local SIZE = 128
local CHASE_SHAKE = 1.5
local RAGE_SHAKE = 5
local RAGE_TINT = Color(255, 140, 140)
local RENDER_MIN, RENDER_MAX = Vector(-80, -80, 0), Vector(80, 80, 140)

function ENT:Initialize()
	self:SetRenderBounds(RENDER_MIN, RENDER_MAX)
end

function ENT:RenderOverride()
	local pos, color = self:SightPos(), color_white
	if self:GetState() == Terminus.STATE.chase then
		local rage = self:GetEnraged()
		pos = pos + VectorRand() * (rage and RAGE_SHAKE or CHASE_SHAKE)
		if rage then color = RAGE_TINT end
	end
	render.SetMaterial(SPRITE)
	render.DrawSprite(pos, SIZE, SIZE, color)
end
