--[[
	ROBLENDER - the 3D view: a ViewportFrame with its own camera, Blender's grey background, grid,
	axis lines and a headlight, plus the edit cage (lines + dots drawn as depth-tested parts).
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27). Colours from Blender's default theme
	(release/datafiles/userdef/userdef_default_theme.c, GPL-2.0-or-later, Blender Authors).
	Navigation follows Blender's turntable orbit, pan, dolly and the numpad views.
]]

local View = {}
local V3 = Vector3.new

-- Blender default theme (space_view3d)
View.THEME = {
	back = Color3.fromRGB(0x3d, 0x3d, 0x3d),
	grid = Color3.fromRGB(0x54, 0x54, 0x54),
	xaxis = Color3.fromRGB(0xff, 0x33, 0x52),
	yaxis = Color3.fromRGB(0x8b, 0xdc, 0x00),
	zaxis = Color3.fromRGB(0x28, 0x90, 0xff),
	wire = Color3.fromRGB(0, 0, 0),
	vertex_select = Color3.fromRGB(0xff, 0x7a, 0x00),
	edge_select = Color3.fromRGB(0xff, 0x99, 0x00),
	edge_mode_select = Color3.fromRGB(0xff, 0xd8, 0x00),
	select = Color3.fromRGB(0xed, 0x57, 0x00),     -- selected object outline
	active = Color3.fromRGB(0xff, 0xa0, 0x28),     -- active object outline
}

local function lerpC(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end

View.__index = function(t, k)
	if k == "ViewportSize" then return t:size() end
	return View[k]
end

function View.new(parent)
	local vf = Instance.new("ViewportFrame")
	vf.Name = "RB_View3D"
	vf.BackgroundColor3 = View.THEME.back
	vf.BorderSizePixel = 0
	vf.Size = UDim2.fromScale(1, 1)
	vf.Ambient = Color3.fromRGB(105, 105, 105)
	vf.LightColor = Color3.fromRGB(200, 200, 200)
	vf.LightDirection = V3(-0.3, -1, -0.5)
	vf.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam
	local function folder(n) local f = Instance.new("Folder") f.Name = n f.Parent = vf return f end
	local self = setmetatable({
		frame = vf, cam = cam, FieldOfView = 40, baseFov = 40, ortho = false,
		focus = V3(0, 2, 0), dist = 30, yaw = math.rad(35), pitch = math.rad(26),
		gridFolder = folder("Grid"), sceneFolder = folder("Scene"), cageFolder = folder("Cage"),
		objects = {}, pools = {}, grid = { lines = {}, spacing = 0, cx = nil, cz = nil, thick = 0 },
		CFrame = CFrame.new(),
	}, View)
	self:update()
	return self
end

function View:size()
	local s = self.frame.AbsoluteSize
	if s and s.X > 0 and s.Y > 0 then return s end
	return Vector2.new(1200, 800)
end
function View:offset()
	return self.frame.AbsolutePosition or Vector2.new(0, 0)
end
local function focal(self) return (self:size().Y / 2) / math.tan(math.rad(self.FieldOfView) / 2) end

-- same maths as Camera:WorldToViewportPoint, but in screen pixels (the frame's offset added)
function View:WorldToViewportPoint(wp)
	local p = self.CFrame:PointToObjectSpace(wp)
	local z = -p.Z
	local size, off = self:size(), self:offset()
	if z <= 1e-6 then return V3(0, 0, z), false end
	local f = focal(self)
	local x = off.X + size.X / 2 + p.X / z * f
	local y = off.Y + size.Y / 2 - p.Y / z * f
	return V3(x, y, z), x >= off.X and y >= off.Y and x <= off.X + size.X and y <= off.Y + size.Y
end
-- the ray from the eye through a screen pixel
function View:ray(sp)
	local size, off = self:size(), self:offset()
	local f = focal(self)
	local d = V3((sp.X - off.X - size.X / 2) / f, -(sp.Y - off.Y - size.Y / 2) / f, -1)
	return { Origin = self.CFrame.Position, Direction = self.CFrame:VectorToWorldSpace(d).Unit }
end
function View:contains(sp)
	local size, off = self:size(), self:offset()
	return sp.X >= off.X and sp.Y >= off.Y and sp.X <= off.X + size.X and sp.Y <= off.Y + size.Y
end
-- world size of one pixel at a point (keeps lines and dots the same size on screen)
function View:pixel(wp)
	local depth = math.max(0.05, -(self.CFrame:PointToObjectSpace(wp)).Z)
	return depth * 2 * math.tan(math.rad(self.FieldOfView) / 2) / self:size().Y
end

-- ===== navigation (Blender turntable) =====
function View:update()
	local cp = math.cos(self.pitch)
	local dir = V3(cp * math.sin(self.yaw), math.sin(self.pitch), cp * math.cos(self.yaw))
	-- orthographic (Numpad 5): Roblox cameras are always perspective, so look from far away through a narrow lens;
	-- the same part of the scene fills the view
	local fov = self.ortho and 1 or self.baseFov
	self.FieldOfView = fov
	local eye = self.dist * math.tan(math.rad(self.baseFov) / 2) / math.tan(math.rad(fov) / 2)
	local pos = self.focus + dir * eye
	local up = V3(0, 1, 0)
	if math.abs(self.pitch) > math.rad(89) then
		-- looking straight down / up: keep "up" on screen pointing along the yaw
		up = V3(-math.sin(self.yaw), 0, -math.cos(self.yaw)) * (self.pitch > 0 and 1 or -1)
	end
	self.CFrame = CFrame.lookAt(pos, self.focus, up)
	self.cam.CFrame = self.CFrame
	self.cam.FieldOfView = self.FieldOfView
	-- headlight from up and to the left of the eye, like Blender's studio light
	local cf = self.CFrame
	self.frame.LightDirection = (cf.LookVector - cf.UpVector * 0.55 + cf.RightVector * 0.35).Unit
	self:updateGrid()
end
function View:orbit(dx, dy)
	-- Blender's Auto Perspective: orbiting away from a numpad view goes back to perspective
	if self.autoOrtho then self.ortho, self.autoOrtho = false, false end
	self.yaw -= dx * 0.008
	self.pitch = math.clamp(self.pitch + dy * 0.008, math.rad(-89.9), math.rad(89.9))
	self:update()
end
function View:pan(dx, dy)
	local u = 2 * self.dist * math.tan(math.rad(self.baseFov) / 2) / self:size().Y
	local cf = self.CFrame
	self.focus = self.focus - cf.RightVector * (dx * u) + cf.UpVector * (dy * u)
	self:update()
end
function View:zoom(steps)
	self.dist = math.clamp(self.dist * (0.85 ^ steps), 0.3, 20000)
	self:update()
end
local VIEWS = {
	front = { math.pi, 0 }, back = { 0, 0 }, right = { math.pi / 2, 0 }, left = { -math.pi / 2, 0 },
	top = { 0, math.rad(89.95) }, bottom = { 0, math.rad(-89.95) },
}
function View:viewAxis(name)
	local v = VIEWS[name]
	if not v then return end
	self.yaw, self.pitch = v[1], v[2]
	if not self.ortho then self.ortho, self.autoOrtho = true, true end
	self:update()
end
-- Numpad 5
function View:toggleOrtho() self.ortho, self.autoOrtho = not self.ortho, false self:update() end
-- Numpad 2 4 6 8 (15 degree steps), Numpad 9 (the other side)
function View:step(dyaw, dpitch)
	if self.autoOrtho then self.ortho, self.autoOrtho = false, false end
	self.yaw += dyaw
	self.pitch = math.clamp(self.pitch + dpitch, math.rad(-89.95), math.rad(89.95))
	self:update()
end
function View:frameBox(lo, hi)
	local r = math.max((hi - lo).Magnitude / 2, 0.5)
	self.focus = (lo + hi) / 2
	self.dist = r / math.sin(math.rad(self.baseFov) / 2) * 1.15
	self:update()
end

-- ===== grid (follows the view, spacing changes with zoom like Blender's) =====
function View:updateGrid()
	local g = self.grid
	local spacing = 2 ^ math.floor(math.log(math.max(self.dist, 1) / 10, 2) + 0.5)
	spacing = math.max(spacing, 0.25)
	local N = 40
	local cx = math.floor(self.focus.X / spacing + 0.5) * spacing
	local cz = math.floor(self.focus.Z / spacing + 0.5) * spacing
	local thick = math.clamp(self.dist * 0.0012, 0.004, 50)
	if spacing == g.spacing and cx == g.cx and cz == g.cz and math.abs(thick - g.thick) < thick * 0.15 then return end
	g.spacing, g.cx, g.cz, g.thick = spacing, cx, cz, thick
	local len = spacing * N * 2
	local th = View.THEME
	local i = 0
	local function put(pos, alongX, col, trans, w)
		i += 1
		local p = g.lines[i]
		if not p then
			p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CastShadow = true, false, false
			p.Material = Enum.Material.Neon
			p.Parent = self.gridFolder
			g.lines[i] = p
		end
		p.Size = alongX and V3(len, w, w) or V3(w, w, len)
		p.CFrame = CFrame.new(pos)
		p.Color = col
		p.Transparency = trans
	end
	for k = -N, N do
		local fade = 0.45 + 0.5 * (math.abs(k) / N)
		local z = cz + k * spacing
		local x = cx + k * spacing
		if math.abs(z) > spacing * 0.01 then put(V3(cx, 0, z), true, th.grid, fade, thick) end
		if math.abs(x) > spacing * 0.01 then put(V3(x, 0, cz), false, th.grid, fade, thick) end
	end
	-- the two floor axes (Roblox: X red, Z blue; Y is up)
	put(V3(cx, 0, 0), true, lerpC(th.grid, th.xaxis, 0.75), 0.1, thick * 1.6)
	put(V3(0, 0, cz), false, lerpC(th.grid, th.zaxis, 0.75), 0.1, thick * 1.6)
	for j = i + 1, #g.lines do g.lines[j].Transparency = 1 end
end

-- ===== objects shown in the view (display copies of the real parts) =====
-- display copies are ours: when one is replaced, free it (and its mesh) - set View.discard from outside
function View:drop(part)
	if not part then return end
	if self.discard then self.discard(part) else part.Parent = nil end
end
function View:setObject(key, part, cf, look)
	local old = self.objects[key]
	if old and old ~= part then self:drop(old) end
	part.Anchored = true
	part.CFrame = cf
	if look then
		part.Color = look.Color or part.Color
		part.Material = look.Material or part.Material
		part.Transparency = look.Transparency or 0
		if look.TextureID then pcall(function() part.TextureID = look.TextureID end) end
	end
	part.Parent = self.sceneFolder
	self.objects[key] = part
end
function View:moveObject(key, cf) local p = self.objects[key] if p then p.CFrame = cf end end
function View:styleObject(key, transparency) local p = self.objects[key] if p then p.Transparency = transparency end end
function View:removeObject(key)
	local p = self.objects[key]
	if p then self:drop(p) end
	self.objects[key] = nil
end

-- ===== cage: lines + dots as parts, so faces in front hide them (like Blender's edit overlay) =====
local function pool(self, kind)
	local p = self.pools[kind]
	if not p then p = { items = {}, n = 0 } self.pools[kind] = p end
	return p
end
local function get(self, kind)
	local p = pool(self, kind)
	p.n += 1
	local x = p.items[p.n]
	if not x then
		x = Instance.new("Part")
		x.Anchored, x.CanCollide, x.CastShadow = true, false, false
		x.Material = Enum.Material.Neon
		if kind == "dot" then x.Shape = Enum.PartType.Ball end
		p.items[p.n] = x
	end
	if x.Parent ~= self.cageFolder then x.Parent = self.cageFolder end
	return x
end
function View:beginCage() for _, p in pairs(self.pools) do p.n = 0 end end
function View:endCage()
	for _, p in pairs(self.pools) do
		for i = p.n + 1, #p.items do
			if p.items[i].Parent then p.items[i].Parent = nil end
		end
	end
end
-- px = width in pixels. Lines sit a hair toward the eye so they don't sink into the faces they edge.
function View:line(a, b, col, px)
	local d = b - a
	local len = d.Magnitude
	if len < 1e-5 then return end
	local mid = (a + b) / 2
	local eye = self.CFrame.Position
	local toEye = eye - mid
	local pix = self:pixel(mid)
	local lift = toEye.Magnitude > 1e-6 and toEye.Unit * (pix * 2.5) or V3()
	local x = get(self, "line")
	local w = pix * (px or 1.2)
	local up = math.abs(d.Unit.Y) > 0.99 and V3(1, 0, 0) or V3(0, 1, 0)
	x.Size = V3(w, w, len + w)
	x.CFrame = CFrame.lookAt(mid + lift, mid + lift + d, up)
	x.Color = col
	x.Transparency = 0
end
function View:dot(p, col, px)
	local eye = self.CFrame.Position
	local toEye = eye - p
	local pix = self:pixel(p)
	local lift = toEye.Magnitude > 1e-6 and toEye.Unit * (pix * 3) or V3()
	local x = get(self, "dot")
	local s = pix * (px or 6)
	x.Size = V3(s, s, s)
	x.CFrame = CFrame.new(p + lift)
	x.Color = col
	x.Transparency = 0
end

function View:destroy() self.frame.Parent = nil end

return View
