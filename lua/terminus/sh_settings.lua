Terminus = Terminus or {}

Terminus.SETTINGS = {
	{ name = "kill_players", default = 1, min = 0, max = 1, label = "Kills players",
		help = "Catching a player kills them. At 0 it just walks off" },
	{ name = "dark_hides", default = 1, min = 0, max = 1, label = "Hides in the dark",
		help = "It can't be spotted in the dark unless it's close or in your flashlight" },
	{ name = "lurk_time", default = 15, min = 0, max = 120, decimals = 0, label = "Lurk time",
		help = "Seconds it stands still after showing up before it creeps in" },
	{ name = "stalk_time", default = 120, min = 10, max = 600, decimals = 0, label = "Stalk time",
		help = "Seconds it stalks without being seen before it shows up somewhere else" },
	{ name = "chase_chance", default = 0.5, min = 0, max = 1, decimals = 2, label = "Chase chance",
		help = "Chance it chases when you spot it. Otherwise it walks off" },
	{ name = "chase_time", default = 15, min = 1, max = 120, decimals = 0, label = "Chase time",
		help = "Seconds a chase lasts at least. After that, breaking line of sight loses it" },
	{ name = "ambush_chance", default = 0.5, min = 0, max = 1, decimals = 2, label = "Ambush chance",
		help = "Chance it waits in ambush after walking off" },
	{ name = "ambush_time", default = 25, min = 1, max = 300, decimals = 0, label = "Ambush time",
		help = "Seconds it waits in ambush" },
	{ name = "rage_escapes", default = 4, min = 1, max = 20, decimals = 0, label = "Escapes before rage",
		help = "Chases a player gets away from before the next one is enraged" },
	{ name = "tired_time", default = 60, min = 0, max = 600, decimals = 0, label = "Tired time",
		help = "Seconds its chases stay slow after a rage. At 0 it never tires" },
	{ name = "stalk_speed", default = 300, min = 50, max = 3000, decimals = 0, label = "Stalk speed",
		help = "Top speed while stalking" },
	{ name = "chase_speed", default = 1000, min = 50, max = 3000, decimals = 0, label = "Chase speed",
		help = "Top speed while chasing" },
	{ name = "rage_speed", default = 2000, min = 50, max = 5000, decimals = 0, label = "Rage speed",
		help = "Top speed while enraged" },
}

Terminus.CLIENT_SETTINGS = {
	{ name = "music", default = 1, min = 0, max = 1, decimals = 2, label = "Music volume",
		help = "Music when it's after you" },
	{ name = "stalk_ambience", default = 1, min = 0, max = 1, label = "Stalk ambience",
		help = "Noises while it's stalking you" },
	{ name = "dread", default = 1, min = 0, max = 1, label = "Screen effects",
		help = "Drains the color while it's close" },
}

local convars, byConVar = {}, {}
for _, s in ipairs(Terminus.SETTINGS) do
	s.convar = "terminus_" .. s.name
	convars[s.name] = CreateConVar(s.convar, tostring(s.default), bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), s.help, s.min, s.max)
	byConVar[s.convar] = s
end

function Terminus.Setting(name)
	return convars[name]:GetFloat()
end

if CLIENT then
	for _, s in ipairs(Terminus.CLIENT_SETTINGS) do
		s.convar = "terminus_cl_" .. s.name
		convars[s.name] = CreateClientConVar(s.convar, tostring(s.default), true, false, s.help, s.min, s.max)
	end
	return
end

util.AddNetworkString("TerminusSetting")

net.Receive("TerminusSetting", function(_, ply)
	local s = byConVar[net.ReadString()]
	local value = tonumber(net.ReadString())
	if not s or not value or not IsValid(ply) or not ply:IsSuperAdmin() then return end
	RunConsoleCommand(s.convar, tostring(math.Clamp(value, s.min, s.max)))
end)
