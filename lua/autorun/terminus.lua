AddCSLuaFile("terminus/sh_settings.lua")
AddCSLuaFile("terminus/sh_states.lua")
AddCSLuaFile("terminus/cl_settings.lua")
AddCSLuaFile("terminus/cl_audio.lua")
AddCSLuaFile("terminus/cl_dread.lua")
include("terminus/sh_settings.lua")
include("terminus/sh_states.lua")
if CLIENT then
	include("terminus/cl_settings.lua")
	include("terminus/cl_audio.lua")
	include("terminus/cl_dread.lua")
end
