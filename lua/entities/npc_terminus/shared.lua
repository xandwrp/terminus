Terminus.STATES = { "idle", "relocate", "stalk", "chase", "hide", "ambush" }
Terminus.STATE = {}
for i, name in ipairs(Terminus.STATES) do Terminus.STATE[name] = i end

Terminus.EYE = Vector(0, 0, 64)

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "Terminus"
ENT.Category = "Terminus"
ENT.Spawnable = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
	self:NetworkVar("Int", 0, "State")
	self:NetworkVar("Entity", 0, "Target")
	self:NetworkVar("Bool", 0, "Enraged")
end

function ENT:StateName()
	return Terminus.STATES[self:GetState()] or "idle"
end

function ENT:SightPos()
	return self:GetPos() + Terminus.EYE
end

list.Set("NPC", "npc_terminus", {
	Name = "Terminus",
	Class = "npc_terminus",
	Category = "Terminus"
})
