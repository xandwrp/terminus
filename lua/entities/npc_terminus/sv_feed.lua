local COLOR_VAR = Terminus.COLOR_VAR

local FEED_TIME = 14
local FIRST_BITE = 1.2
local BITE_JITTER = { 0.6, 1.4 }
local TEAR_FORCE = 300
local DARKEN = { 150, 205, 205 }
local SPIT_DELAY = { 0.8, 1.6 }
local SPIT_SPEED = { 120, 280 }
local MAX_BONES = 60
local GLUE_REACH = 24
local GLUE_LOW = Vector(0, 0, 8)
local HEAD = "ValveBiped.Bip01_Head1"
local SKULL, RIB = "models/gibs/hgibs.mdl", "models/gibs/hgibs_rib.mdl"
local SCAPULA, SPINE = "models/gibs/hgibs_scapula.mdl", "models/gibs/hgibs_spine.mdl"
local LEFTOVERS = { SKULL, SCAPULA, SCAPULA, RIB, RIB, RIB, SPINE }

local TEAR_SOUNDS = {
	"physics/flesh/flesh_bloody_break.wav",
	"physics/flesh/flesh_squishy_impact_hard1.wav",
	"physics/flesh/flesh_squishy_impact_hard3.wav",
	"physics/flesh/flesh_squishy_impact_hard4.wav",
}
local CRUNCH_SOUNDS = { "npc/barnacle/barnacle_crunch2.wav", "npc/barnacle/barnacle_crunch3.wav" }
local GULP_SOUNDS = { "npc/barnacle/barnacle_gulp1.wav", "npc/barnacle/barnacle_gulp2.wav" }
local FINISH_SOUNDS = {
	"physics/body/body_medium_break2.wav",
	"physics/body/body_medium_break3.wav",
	"physics/body/body_medium_break4.wav",
}
local SPIT_SOUNDS = { "npc/barnacle/barnacle_bark1.wav", "npc/barnacle/barnacle_bark2.wav" }

local spat = {}

local function Pose(rag, ent)
	for i = 0, rag:GetPhysicsObjectCount() - 1 do
		local phys = rag:GetPhysicsObjectNum(i)
		local m = ent:GetBoneMatrix(rag:TranslatePhysBoneToBone(i))
		if IsValid(phys) and m then
			phys:SetPos(m:GetTranslation())
			phys:SetAngles(m:GetAngles())
			phys:Wake()
		end
	end
end

-- A ragdoll of ent, posed the way it's standing, for eating.
local function Body(ent)
	local model = ent:GetModel()
	if not model or not util.IsValidRagdoll(model) then return end
	local rag = ents.Create("prop_ragdoll")
	if not IsValid(rag) then return end
	rag:SetModel(model)
	rag:SetPos(ent:GetPos())
	rag:SetAngles(ent:GetAngles())
	rag:SetSkin(ent:GetSkin())
	for _, group in ipairs(ent:GetBodyGroups()) do
		rag:SetBodygroup(group.id, ent:GetBodygroup(group.id))
	end
	rag:Spawn()
	rag:Activate()

	local ok, err = pcall(Pose, rag, ent)
	if not ok or rag:GetPhysicsObjectCount() == 0 then
		if not ok then ErrorNoHalt("[terminus] couldn't pose body: " .. tostring(err) .. "\n") end
		rag:Remove()
		return
	end
	rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	if ent:IsPlayer() then rag:SetNW2Vector(COLOR_VAR, ent:GetPlayerColor()) end
	return rag
end

-- Kills victim and leaves a body to eat, if it can make one.
function ENT:Slay(victim)
	local body = Body(victim)
	if victim:IsPlayer() then
		if not body then
			local dmg = DamageInfo()
			dmg:SetDamage(1e6)
			dmg:SetAttacker(self)
			dmg:SetInflictor(self)
			victim:TakeDamageInfo(dmg)
			return
		end
		victim:KillSilent()
		victim:AddDeaths(1)
		hook.Run("PlayerDeath", victim, self, self)
		victim:Spectate(OBS_MODE_CHASE)
		victim:SpectateEntity(body)
		body.TerminusOwner = victim
	else
		victim.TerminusMeal = true
		hook.Run("OnNPCKilled", victim, self, self)
		victim:Remove()
	end
	return body
end

local function Depth(rag, bone)
	local n = 0
	bone = rag:GetBoneParent(bone)
	while bone and bone >= 0 do
		n = n + 1
		bone = rag:GetBoneParent(bone)
	end
	return n
end

-- Its physics bones in the order it eats them: the ends of the limbs first, the middle last.
local function Courses(body)
	local order, depth = {}, {}
	for i = 0, body:GetPhysicsObjectCount() - 1 do
		order[#order + 1] = i
		depth[i] = Depth(body, body:TranslatePhysBoneToBone(i))
	end
	table.sort(order, function(a, b) return depth[a] > depth[b] end)
	return order
end

local function Collapse(body, bone, physBones)
	body:ManipulateBoneScale(bone, vector_origin)
	for _, child in ipairs(body:GetChildBones(bone)) do
		if not physBones[child] then Collapse(body, child, physBones) end
	end
end

function ENT:Bite(body, index, eaten, total)
	local phys = body:GetPhysicsObjectNum(index)
	if not IsValid(phys) then return end
	local physBones = body.TerminusPhysBones
	if not physBones then
		physBones = {}
		for i = 0, body:GetPhysicsObjectCount() - 1 do physBones[body:TranslatePhysBoneToBone(i)] = true end
		body.TerminusPhysBones = physBones
	end
	Collapse(body, body:TranslatePhysBoneToBone(index), physBones)

	local p = phys:GetPos()
	local dir = (vector_up + VectorRand() * 0.5):GetNormalized()
	phys:ApplyForceCenter(dir * phys:GetMass() * TEAR_FORCE)

	local fx = EffectData()
	fx:SetOrigin(p)
	fx:SetNormal(dir)
	fx:SetScale(8)
	fx:SetColor(BLOOD_COLOR_RED)
	fx:SetFlags(3)
	util.Effect("bloodspray", fx)
	util.Effect("BloodImpact", fx)
	util.Decal("Blood", p, p - vector_up * 200 + VectorRand() * 60, body)
	sound.Play(TEAR_SOUNDS[math.random(#TEAR_SOUNDS)], p, 75, math.random(85, 110))
	if math.random() < 0.5 then sound.Play(CRUNCH_SOUNDS[math.random(#CRUNCH_SOUNDS)], p, 70, math.random(85, 110)) end
	timer.Simple(0.6, function()
		if IsValid(self) then sound.Play(GULP_SOUNDS[math.random(#GULP_SOUNDS)], self:GetPos(), 65, math.random(60, 80)) end
	end)

	local k = eaten / total
	body:SetColor(Color(255 - DARKEN[1] * k, 255 - DARKEN[2] * k, 255 - DARKEN[3] * k))
end

function ENT:Spit(models)
	timer.Simple(math.Rand(SPIT_DELAY[1], SPIT_DELAY[2]), function()
		if not IsValid(self) then return end
		local pos = self:GetPos() + vector_up * 24
		sound.Play(SPIT_SOUNDS[math.random(#SPIT_SOUNDS)], pos, 72, math.random(70, 90))
		for _, model in ipairs(models) do
			local bone = ents.Create("prop_physics")
			bone:SetModel(model)
			bone:SetPos(pos + VectorRand() * 4)
			bone:SetAngles(AngleRand())
			bone:Spawn()
			bone:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			local phys = bone:GetPhysicsObject()
			if IsValid(phys) then
				phys:SetVelocity((vector_up + VectorRand() * 0.6):GetNormalized() * math.Rand(SPIT_SPEED[1], SPIT_SPEED[2]))
				phys:AddAngleVelocity(VectorRand() * 600)
			end
			spat[#spat + 1] = bone
			if #spat > MAX_BONES then SafeRemoveEntity(table.remove(spat, 1)) end
		end
	end)
end

function ENT:Finish(body)
	local p = body:GetPos()
	for _ = 1, 3 do util.Decal("Blood", p, p - vector_up * 200 + VectorRand() * 80, body) end
	sound.Play(FINISH_SOUNDS[math.random(#FINISH_SOUNDS)], p, 80, math.random(85, 100))
	if body:LookupBone(HEAD) then self:Spit(LEFTOVERS) end
	local owner = body.TerminusOwner
	if IsValid(owner) and not owner:Alive() then owner:SpectateEntity(self) end
	body:Remove()
end

-- Keeps it over what it's eating, wherever that drifts or floats off to. Stands on the floor under it if
-- there's one close, otherwise hangs there with it.
function ENT:Glue(body)
	local pos = body:GetPos()
	local tr = util.TraceLine({ start = pos, endpos = pos - Vector(0, 0, GLUE_REACH), mask = MASK_PLAYERSOLID_BRUSHONLY })
	self:SetPos(tr.Hit and tr.HitPos or pos - GLUE_LOW)
	self.loco:SetVelocity(vector_origin)
end

-- Eats body one bite at a time. Runs in the behaviour coroutine.
function ENT:Eat(body)
	self.loco:SetGravity(0)
	local courses = Courses(body)
	local total = #courses
	local gap = FEED_TIME / math.max(total, 1)
	local nextBite = CurTime() + FIRST_BITE
	local eaten = 0
	while IsValid(body) do
		self:Glue(body)
		coroutine.yield()
		if not IsValid(body) then return end
		local now = CurTime()
		if now >= nextBite then
			local index = table.remove(courses, 1)
			if not index then
				self:Finish(body)
				return
			end
			eaten = eaten + 1
			self:Bite(body, index, eaten, total)
			nextBite = now + gap * math.Rand(BITE_JITTER[1], BITE_JITTER[2])
		end
	end
end
