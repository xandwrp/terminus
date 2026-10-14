Terminus = Terminus or {}

Terminus.STATES = { "idle", "relocate", "stalk", "chase", "hide", "ambush", "feint", "lure", "rest" }
Terminus.STATE = {}
for i, name in ipairs(Terminus.STATES) do Terminus.STATE[name] = i end

Terminus.EYE = Vector(0, 0, 64)

local SPOTTED_FROM = { stalk = true, ambush = true, lure = true }
local SPOTTED_TO = { chase = true, hide = true }

-- Whether going between these two states means someone just spotted it.
function Terminus.Spotted(from, to)
	return SPOTTED_FROM[Terminus.STATES[from]] and SPOTTED_TO[Terminus.STATES[to]] or false
end
