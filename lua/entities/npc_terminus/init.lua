AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")
include("sv_brain.lua")
include("sv_feed.lua")

local ai_disabled = GetConVar("ai_disabled")

local RESTART_DELAY = 1

util.AddNetworkString("TerminusLight")
util.AddNetworkString("TerminusStatic")

net.Receive("TerminusLight", function(_, ply)
	local ent = net.ReadEntity()
	local light = net.ReadUInt(8) / 255
	if not IsValid(ent) or ent:GetClass() ~= "npc_terminus" or ent:GetTarget() ~= ply then return end
	ent.Light = light
	ent.LightFrom = ply
end)

function ENT:Initialize()
	self:SetModel("models/terminus.mdl")
	self:SetSpawnEffect(false)
	self:SetCollisionBounds(Vector(-1, -1, 0), Vector(1, 1, 1))
	self:SetSolid(SOLID_NONE)
	self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
	self:AddFlags(FL_NOTARGET)

	self.loco:SetDeathDropHeight(4000)
	self.loco:SetJumpHeight(120)
	self.BaseDecel = self.loco:GetDeceleration()

	self.Escapes = {}
	self.TiredUntil = 0
	self.FedUntil = 0
	self.Light = 1

	timer.Simple(0, function()
		if not IsValid(self) or navmesh.GetNavAreaCount() > 0 then return end
		local ply = self:GetCreator()
		local msg = "Terminus can't move on this map without a navmesh. Run nav_generate to make one."
		if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
	end)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_ALWAYS
end

function ENT:OnTakeDamage()
	return 0
end

-- The base version gives up for good when the behaviour errors. This picks it back up a second later.
function ENT:BehaveUpdate()
	if ai_disabled:GetBool() then return end
	if not self.BehaveThread or coroutine.status(self.BehaveThread) == "dead" then
		if CurTime() < (self.RestartAt or 0) then return end
		self.BehaveThread = coroutine.create(function() self:RunBehaviour() end)
	end
	local ok, err = coroutine.resume(self.BehaveThread)
	if not ok then
		self.BehaveThread = nil
		self.RestartAt = CurTime() + RESTART_DELAY
		ErrorNoHalt(self, " Error: ", err, "\n")
	end
end
