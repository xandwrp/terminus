Terminus = Terminus or {}

Terminus.STATES = { "idle", "relocate", "stalk", "chase", "hide", "ambush", "feint", "lure", "rest", "feed", "fly" }
Terminus.STATE = {}
for i, name in ipairs(Terminus.STATES) do Terminus.STATE[name] = i end

Terminus.EYE = Vector(0, 0, 64)
Terminus.COLOR_VAR = "TerminusColor"

local SPOTTED_FROM = { stalk = true, ambush = true, lure = true }
local SPOTTED_TO = { chase = true, hide = true }

-- Whether going between these two states means someone just spotted it.
function Terminus.Spotted(from, to)
	return SPOTTED_FROM[Terminus.STATES[from]] and SPOTTED_TO[Terminus.STATES[to]] or false
end

-- Whether going between these two states should hit like being spotted: that, or taking off.
function Terminus.Jolted(from, to)
	return Terminus.Spotted(from, to) or to == Terminus.STATE.fly and from ~= to
end

Terminus.CHASING = { [Terminus.STATE.chase] = true, [Terminus.STATE.fly] = true }

if CLIENT then
	-- Whose eyes you're looking through: your own, or whoever you're spectating.
	function Terminus.Viewer()
		local me = LocalPlayer()
		if not IsValid(me) then return end
		local mode = me:GetObserverMode()
		if mode == OBS_MODE_IN_EYE or mode == OBS_MODE_CHASE then
			local them = me:GetObserverTarget()
			if IsValid(them) and them:IsPlayer() then return them end
		end
		return me
	end
end
