local STATE = Terminus.STATE
local Setting = Terminus.Setting

local RANGE = 1500
local CHASE_FLOOR = 0.4
local STALK_MAX = 0.3
local RISE, FALL = 3, 0.6
local DRAIN = 0.7
local CONTRAST = 0.15
local DARKEN = 0.03
local RAGE_RED = 0.08

local dread, rage = 0, 0
local mod = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 1,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
}

hook.Add("RenderScreenspaceEffects", "TerminusDread", function()
	local me = LocalPlayer()
	if not IsValid(me) then return end

	local goal, angry = 0, 0
	if Setting("dread") ~= 0 and me:Alive() then
		for _, ent in ipairs(ents.FindByClass("npc_terminus")) do
			if ent:GetTarget() == me then
				local state = ent:GetState()
				local near = 1 - math.min(ent:GetPos():Distance(me:GetPos()) / RANGE, 1)
				local d = 0
				if Terminus.CHASING[state] then
					d = CHASE_FLOOR + (1 - CHASE_FLOOR) * near
					if ent:GetEnraged() then angry = 1 end
				elseif state == STATE.stalk or state == STATE.ambush then
					d = STALK_MAX * near
				end
				goal = math.max(goal, d)
			end
		end
	end

	local dt = FrameTime()
	dread = math.Approach(dread, goal, dt * (goal > dread and RISE or FALL))
	rage = math.Approach(rage, angry, dt * (angry > rage and RISE or FALL))
	if dread <= 0 and rage <= 0 then return end

	mod["$pp_colour_colour"] = 1 - DRAIN * dread
	mod["$pp_colour_contrast"] = 1 + CONTRAST * dread
	mod["$pp_colour_brightness"] = -DARKEN * dread
	mod["$pp_colour_addr"] = RAGE_RED * rage
	DrawColorModify(mod)
end)
