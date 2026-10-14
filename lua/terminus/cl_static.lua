local SIZE = 128
local GRAIN = 270
local RATE = 1 / 40
local IN, HOLD, OUT = 0.08, 0.5, 1.2
local ROLL_SPEED, ROLL_HEIGHT, ROLL_DARK = 0.7, 0.12, 110
local SOUND = "terminus/static.wav"
local POINT_SAMPLE, NO_MIP, NO_LOD = 1, 256, 512

local rt, mat
local dirty = false
local started = -math.huge
local u, v, shuffleAt = 0, 0, 0

local function Level(t)
	if t < IN then return t / IN end
	if t < IN + HOLD then return 1 end
	return 1 - (t - IN - HOLD) / OUT
end

-- Fresh noise for every burst, since a render target can lose what was drawn on it.
local function Fill()
	if not rt then
		rt = GetRenderTargetEx("terminus_static", SIZE, SIZE, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE,
			bit.bor(POINT_SAMPLE, NO_MIP, NO_LOD), 0, IMAGE_FORMAT_RGB888)
		mat = CreateMaterial("terminus_static", "UnlitGeneric", {
			["$basetexture"] = rt:GetName(), ["$vertexcolor"] = 1, ["$vertexalpha"] = 1,
		})
	end
	render.PushRenderTarget(rt)
	cam.Start2D()
	for y = 0, SIZE - 1 do
		for x = 0, SIZE - 1 do
			local c = math.random() ^ 1.5 * 255
			surface.SetDrawColor(c, c, c)
			surface.DrawRect(x, y, 1, 1)
		end
	end
	cam.End2D()
	render.PopRenderTarget()
end

-- Covers the screen while it jumps somewhere else. A burst on top of one already going carries on from
-- however thick it is.
net.Receive("TerminusStatic", function()
	local now = CurTime()
	started = now - IN * math.max(Level(now - started), 0)
	dirty = true
	surface.PlaySound(SOUND)
end)

hook.Add("PreRender", "TerminusStatic", function()
	if not dirty then return end
	dirty = false
	Fill()
end)

hook.Add("DrawOverlay", "TerminusStatic", function()
	local now = CurTime()
	local level = Level(now - started)
	if level <= 0 or not mat then return end
	if now >= shuffleAt or now < shuffleAt - RATE then u, v, shuffleAt = math.random(), math.random(), now + RATE end
	local w, h = ScrW(), ScrH()
	local tiles = GRAIN / SIZE
	surface.SetMaterial(mat)
	surface.SetDrawColor(255, 255, 255, level * 255)
	surface.DrawTexturedRectUV(0, 0, w, h, u, v, u + tiles * w / h, v + tiles)
	local band = h * ROLL_HEIGHT
	surface.SetDrawColor(0, 0, 0, ROLL_DARK * level)
	surface.DrawRect(0, (now * ROLL_SPEED % 1) * (h + band) - band, w, band)
end)
