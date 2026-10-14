Terminus = Terminus or {}

Terminus.STATES = { "idle", "relocate", "stalk", "chase", "hide", "ambush" }
Terminus.STATE = {}
for i, name in ipairs(Terminus.STATES) do Terminus.STATE[name] = i end

Terminus.EYE = Vector(0, 0, 64)
