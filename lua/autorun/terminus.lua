AddCSLuaFile("terminus/sh_settings.lua")
AddCSLuaFile("terminus/cl_settings.lua")
include("terminus/sh_settings.lua")
if CLIENT then
	include("terminus/cl_settings.lua")
end
