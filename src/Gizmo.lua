--[[
	ROBLEND - the transform gizmo (Blender's Viewport Gizmos for the Move / Rotate / Scale / Transform tools):
	coloured arrows, rings and boxes drawn over the 3D view at the selection's middle. Drag one = that tool, locked to
	that axis (or plane); it's the same move / rotate / scale as G R S with X Y Z, so typing a number, Ctrl to snap and
	Esc to cancel all still work. Drawn flat on top of the view (2D frames), so it's never hidden behind the mesh.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27). Layout and colours follow Blender's transform gizmos
	(axis colours from the default theme, GPL-2.0-or-later, Blender Authors).
]]

local Gizmo = {}
Gizmo.__index = Gizmo

local V2, V3 = Vector2.new, Vector3.new
local AX = { X = V3(1, 0, 0), Y = V3(0, 1, 0), Z = V3(0, 0, 1) }
local COL = {
	X = Color3.fromRGB(0xff, 0x33, 0x52),
	Y = Color3.fromRGB(0x8b, 0xdc, 0x00),
	Z = Color3.fromRGB(0x28, 0x90, 0xff),
	W = Color3.fromRGB(235, 235, 235),
}
-- sizes in screen pixels
Gizmo.ARROW = 80      -- move / scale axis length
Gizmo.RING = 70       -- rotate rings
Gizmo.VIEW = 92       -- the white outer ring (rotate / scale around the view)
Gizmo.PLANE = 26      -- plane squares sit this far along both axes
Gizmo.HIT = 8         -- how close the mouse has to be

local function lerpC(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
local function others(a) if a == "X" then return "Y", "Z" elseif a == "Y" then return "X", "Z" end return "X", "Y" end

-- ===== layout (pure: no instances) =====
-- kind = "move" | "rotate" | "scale" | "transform"; c = the middle (world); look = the camera's CFrame;
-- project(wp) -> Vector2, inFront; pixel(wp) -> studs per pixel there. Returns the handles, nearest-first order
-- doesn't matter (Gizmo.hit picks the closest).
function Gizmo.layout(kind, c, look, project, pixel)
	local hs = {}
	local cs, ok = project(c)
	if not ok then return hs, nil end
	local px = pixel(c)
	local eyeDir = (look.Position - c)
	eyeDir = eyeDir.Magnitude > 1e-9 and eyeDir.Unit or -look.LookVector
	local move = kind == "move" or kind == "transform"
	local scale = kind == "scale"
	local rot = kind == "rotate" or kind == "transform"
	-- axis lines (move = arrow tips, scale = box tips)
	if move or scale then
		for _, a in ipairs({ "X", "Y", "Z" }) do
			local tip, tok = project(c + AX[a] * (Gizmo.ARROW * px))
			local d = tip - cs
			-- pointing (nearly) straight at the camera: too short to grab, left out (like Blender)
			if tok and d.Magnitude > Gizmo.ARROW * 0.22 then
				local u = d.Unit
				hs[#hs + 1] = { id = (scale and "s" or "g") .. a, op = scale and "S" or "G", axis = a, col = COL[a], shape = "line",
					a = cs + u * 14, b = tip, tip = scale and "box" or "arrow" }
			end
		end
		-- plane squares (drag = move / scale flat on that plane; coloured by the axis it leaves out, like Blender)
		for _, a in ipairs({ "X", "Y", "Z" }) do
			if math.abs(AX[a]:Dot(eyeDir)) > 0.2 then
				local p, q = others(a)
				local sp, sok = project(c + (AX[p] + AX[q]) * (Gizmo.PLANE * px))
				if sok then
					hs[#hs + 1] = { id = (scale and "sp" or "gp") .. a, op = scale and "S" or "G", plane = a, col = COL[a], shape = "square", c = sp, r = 6 }
				end
			end
		end
	end
	if move and kind == "move" then
		-- the little white ring in the middle: free move (on the screen)
		hs[#hs + 1] = { id = "g", op = "G", col = COL.W, shape = "circle", c = cs, r = 9 }
	end
	if rot then
		-- rings round each axis; only the half facing you (the back half would be grabbed through the front)
		local R = Gizmo.RING * px * (kind == "transform" and 0.82 or 1)
		local N = 48
		for _, a in ipairs({ "X", "Y", "Z" }) do
			local p, q = others(a)
			local u, v = AX[p], AX[q]
			local pts, runs = {}, {}
			local cur
			for i = 0, N do
				local t = i / N * math.pi * 2
				local wp = c + (u * math.cos(t) + v * math.sin(t)) * R
				local front = (wp - c):Dot(eyeDir) >= -R * 0.04
				local sp, sok = project(wp)
				if front and sok then
					if not cur then cur = {} runs[#runs + 1] = cur end
					cur[#cur + 1] = sp
				else
					cur = nil
				end
			end
			for _, run in ipairs(runs) do
				if #run >= 2 then
					hs[#hs + 1] = { id = "r" .. a .. #pts, op = "R", axis = a, col = COL[a], shape = "poly", pts = run }
					pts[#pts + 1] = run
				end
			end
		end
	end
	if kind == "rotate" then
		hs[#hs + 1] = { id = "r", op = "R", col = COL.W, shape = "circle", c = cs, r = Gizmo.VIEW }
	elseif scale then
		hs[#hs + 1] = { id = "s", op = "S", col = COL.W, shape = "circle", c = cs, r = Gizmo.VIEW }
	end
	return hs, cs
end

-- ===== hit test (screen pixels) =====
local function segDist(p, a, b)
	local ab = b - a
	local l2 = ab.X * ab.X + ab.Y * ab.Y
	local t = l2 > 1e-9 and math.clamp(((p - a).X * ab.X + (p - a).Y * ab.Y) / l2, 0, 1) or 0
	return (p - (a + ab * t)).Magnitude
end
Gizmo.segDist = segDist
function Gizmo.distTo(h, mp)
	if h.shape == "line" then
		local d = segDist(mp, h.a, h.b)
		return math.min(d, (mp - h.b).Magnitude - 3)   -- (the tip is a bit easier to grab)
	elseif h.shape == "square" then
		local d = mp - h.c
		return math.max(math.abs(d.X), math.abs(d.Y)) - h.r
	elseif h.shape == "circle" then
		return math.abs((mp - h.c).Magnitude - h.r)
	elseif h.shape == "poly" then
		local best = math.huge
		for i = 1, #h.pts - 1 do best = math.min(best, segDist(mp, h.pts[i], h.pts[i + 1])) end
		return best
	end
	return math.huge
end
-- the handle under the mouse (or nil). Squares and arrow tips win over a ring that happens to pass under them.
function Gizmo.hit(hs, mp)
	local best, bd = nil, Gizmo.HIT
	for _, h in ipairs(hs or {}) do
		local d = Gizmo.distTo(h, mp)
		if h.shape == "square" then d -= 2 end
		if d < bd then best, bd = h, d end
	end
	return best
end
-- two handles are "the same" for hover (rings are split into runs: any run of that ring lights it)
function Gizmo.same(h1, h2)
	if not h1 or not h2 then return false end
	return h1.op == h2.op and h1.axis == h2.axis and h1.plane == h2.plane and h1.shape == h2.shape
end

-- ===== drawing (2D frames on top of the 3D view) =====
function Gizmo.new(parent)
	local f = Instance.new("Frame")
	f.Name = "RB_Gizmo"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 2
	f.Active = false
	f.Visible = false
	f.Parent = parent
	return setmetatable({ frame = f, pools = {}, cache = setmetatable({}, { __mode = "k" }) }, Gizmo)
end
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
		x = Instance.new("Frame")
		x.Name = "G_" .. kind
		x.BorderSizePixel = 0
		x.ZIndex = 2
		x.AnchorPoint = V2(0.5, 0.5)
		x.Active = false
		if kind == "ring" then
			x.BackgroundTransparency = 1
			local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0.5, 0) c.Parent = x
			local s = Instance.new("UIStroke") s.Name = "S" s.Thickness = 2 s.Parent = x
		end
		x.Parent = self.frame
		p.items[p.n] = x
	end
	x.Visible = true
	return x
end
-- only write what changed (each property write costs)
local function set(self, x, pos, size, rotn, col, thick)
	local c = self.cache[x]
	if not c then c = {} self.cache[x] = c end
	if c.p ~= pos then x.Position = pos c.p = pos end
	if c.s ~= size then x.Size = size c.s = size end
	if c.r ~= rotn then x.Rotation = rotn c.r = rotn end
	if c.c ~= col then
		c.c = col
		local st = x:FindFirstChild("S")
		if st then st.Color = col else x.BackgroundColor3 = col end
	end
	if thick and c.t ~= thick then
		c.t = thick
		local st = x:FindFirstChild("S")
		if st then st.Thickness = thick end
	end
end
function Gizmo:seg(a, b, col, w)
	local d = b - a
	local len = d.Magnitude
	if len < 0.5 then return end
	local mid = (a + b) / 2 - self.origin
	local x = get(self, "line")
	set(self, x, UDim2.fromOffset(math.floor(mid.X * 2 + 0.5) / 2, math.floor(mid.Y * 2 + 0.5) / 2), UDim2.fromOffset(len + 1, w),
		math.floor(math.deg(math.atan2(d.Y, d.X)) * 10 + 0.5) / 10, col)
end
function Gizmo:box(p, r, col, rotn)
	local x = get(self, "box")
	local q = p - self.origin
	set(self, x, UDim2.fromOffset(q.X, q.Y), UDim2.fromOffset(r * 2, r * 2), rotn or 0, col)
end
function Gizmo:ring(p, r, col, w)
	local x = get(self, "ring")
	local q = p - self.origin
	set(self, x, UDim2.fromOffset(q.X, q.Y), UDim2.fromOffset(r * 2, r * 2), 0, col, w)
end
function Gizmo:draw(hs, hover)
	for _, p in pairs(self.pools) do p.n = 0 end
	self.origin = self.frame.AbsolutePosition or V2(0, 0)
	for _, h in ipairs(hs or {}) do
		local hot = Gizmo.same(h, hover)
		local col = hot and lerpC(h.col, Color3.new(1, 1, 1), 0.45) or h.col
		local w = hot and 3.5 or 2
		if h.shape == "line" then
			self:seg(h.a, h.b, col, w)
			local d = h.b - h.a
			local u = d.Magnitude > 1e-6 and d.Unit or V2(1, 0)
			if h.tip == "arrow" then
				local n = V2(-u.Y, u.X)
				self:seg(h.b, h.b - u * 11 + n * 6, col, w)
				self:seg(h.b, h.b - u * 11 - n * 6, col, w)
			else
				self:box(h.b, hot and 6 or 5, col, math.deg(math.atan2(u.Y, u.X)))
			end
		elseif h.shape == "square" then
			self:box(h.c, hot and h.r + 1 or h.r, col, 0)
		elseif h.shape == "circle" then
			self:ring(h.c, h.r, col, hot and 3 or (h.r > 20 and 1.5 or 2))
		elseif h.shape == "poly" then
			for i = 1, #h.pts - 1 do self:seg(h.pts[i], h.pts[i + 1], col, w) end
		end
	end
	for _, p in pairs(self.pools) do
		for i = p.n + 1, #p.items do if p.items[i].Visible then p.items[i].Visible = false end end
	end
	self.frame.Visible = true
end
function Gizmo:hide()
	if self.frame.Visible then self.frame.Visible = false end
end

return Gizmo
