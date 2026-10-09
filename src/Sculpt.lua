--[[
	ROBLEND - Sculpt Mode: brushes that push the surface around like clay.
	Converted to Luau (and cut down) from Blender's sculpt brushes:
	  source/blender/editors/sculpt_paint/brushes/draw.cc, clay_strips.cc, inflate.cc, grab.cc, smooth.cc,
	  flatten.cc, pinch.cc, crease.cc  +  sculpt.cc (area normal / centre, falloff, X symmetry)
	SPDX-License-Identifier: GPL-2.0-or-later
	Original: Copyright (C) Blender Authors. Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27).

	Sculpt.dab(bm, brush, centre, radius, strength, opts) works on the mesh alone (tested headless).
	Sculpt.new(C) is the live mode: mouse strokes, the brush ring, F / Shift F, brush keys.
]]
local Sculpt = {}
local V3 = Vector3.new

-- Blender's default sculpt keys (2.8+ keymap: X draw, C clay strips, I inflate, G grab, S smooth, T flatten,
-- P pinch, Shift C crease)
Sculpt.BRUSHES = {
	{ id = "draw", name = "Draw", key = "X", short = "Dr", tip = "Push the surface out (Ctrl = in)" },
	{ id = "clay", name = "Clay Strips", key = "C", short = "Cl", tip = "Build up flat layers like strips of clay (Ctrl = carve)" },
	{ id = "inflate", name = "Inflate", key = "I", short = "In", tip = "Blow the surface up along its own normals (Ctrl = deflate)" },
	{ id = "grab", name = "Grab", key = "G", short = "Gr", tip = "Drag a chunk of the surface around with the mouse" },
	{ id = "smooth", name = "Smooth", key = "S", short = "Sm", tip = "Relax bumps away (hold Shift with any brush)" },
	{ id = "flatten", name = "Flatten", key = "T", short = "Fl", tip = "Press the surface flat (Ctrl = push it out from the flat)" },
	{ id = "pinch", name = "Pinch", key = "P", short = "Pi", tip = "Pull the surface towards the middle of the brush (Ctrl = push away)" },
	{ id = "crease", name = "Crease", key = "Shift C", short = "Cr", tip = "Cut a sharp groove (Ctrl = a sharp ridge)" },
}
Sculpt.BY_ID = {}
for _, b in ipairs(Sculpt.BRUSHES) do Sculpt.BY_ID[b.id] = b end

-- smooth falloff from the middle (1) to the edge (0) of the brush
local function falloff(d, r)
	if d >= r then return 0 end
	local t = 1 - d / r
	return t * t * (3 - 2 * t)
end

local function vertNormal(BMesh, v)
	local n = V3()
	for _, f in ipairs(BMesh.vertFaces(v)) do n += f.no end
	return n.Magnitude > 1e-9 and n.Unit or V3(0, 1, 0)
end

-- the verts under the brush with their weights, plus the area normal and centre (Blender's sculpt "area")
function Sculpt.gather(BMesh, bm, c, r)
	local hits, an, ac, wsum = {}, V3(), V3(), 0
	for v in pairs(bm.verts) do
		if not v.hide then
			local d = (v.co - c).Magnitude
			if d < r then
				local w = falloff(d, r)
				if w > 0 then
					hits[#hits + 1] = { v = v, w = w }
					an += vertNormal(BMesh, v) * w
					ac += v.co * w
					wsum += w
				end
			end
		end
	end
	if wsum > 0 then ac /= wsum end
	return hits, (an.Magnitude > 1e-9 and an.Unit or V3(0, 1, 0)), ac
end

-- one brush dab. opts: { BMesh = BMesh, invert = bool, grabDelta = Vector3 (grab only, with opts.grab = captured hits) }
-- returns how many verts moved
function Sculpt.dab(bm, brush, c, r, strength, opts)
	opts = opts or {}
	local BMesh = opts.BMesh
	strength = math.clamp(strength or 0.5, 0, 1)
	local sign = opts.invert and -1 or 1
	if brush == "grab" then
		-- grab moves the verts captured at the start of the stroke by the mouse's movement
		for _, h in ipairs(opts.grab or {}) do h.v.co = h.orig + (opts.grabDelta or V3()) * h.w end
		bm:normalsUpdate()
		return #(opts.grab or {})
	end
	local hits, n, ac = Sculpt.gather(BMesh, bm, c, r)
	if #hits == 0 then return 0 end
	local moves = {}
	if brush == "draw" then
		local h = r * 0.12 * strength * sign
		for _, x in ipairs(hits) do moves[x.v] = x.v.co + n * (h * x.w) end
	elseif brush == "clay" then
		-- a plane just above the surface: everything under it rises towards it (layers of clay)
		local plane = ac + n * (r * 0.1 * strength * sign)
		for _, x in ipairs(hits) do
			local below = (plane - x.v.co):Dot(n) * sign
			if below > 0 then moves[x.v] = x.v.co + n * ((plane - x.v.co):Dot(n) * math.min(1, x.w * strength * 1.5)) end
		end
	elseif brush == "inflate" then
		local h = r * 0.1 * strength * sign
		for _, x in ipairs(hits) do moves[x.v] = x.v.co + vertNormal(BMesh, x.v) * (h * x.w) end
	elseif brush == "smooth" then
		for _, x in ipairs(hits) do
			local s, k = V3(), 0
			for _, e in ipairs(BMesh.vertEdges(x.v)) do s += BMesh.otherVert(e, x.v).co k += 1 end
			if k > 0 then moves[x.v] = x.v.co:Lerp(s / k, math.clamp(strength * x.w, 0, 1)) end
		end
	elseif brush == "flatten" then
		for _, x in ipairs(hits) do
			local d = (x.v.co - ac):Dot(n)
			moves[x.v] = x.v.co - n * (d * strength * x.w * sign)
		end
	elseif brush == "pinch" then
		for _, x in ipairs(hits) do
			local to = c - x.v.co
			to -= n * to:Dot(n) -- stay on the surface
			moves[x.v] = x.v.co + to * (0.3 * strength * x.w * sign)
		end
	elseif brush == "crease" then
		-- pinch in + push down = a sharp groove (Ctrl: ridge)
		local h = -r * 0.08 * strength * sign
		for _, x in ipairs(hits) do
			local to = c - x.v.co
			to -= n * to:Dot(n)
			moves[x.v] = x.v.co + to * (0.25 * strength * x.w) + n * (h * x.w)
		end
	end
	local k = 0
	for v, p in pairs(moves) do
		if p.X == p.X and p.Y == p.Y and p.Z == p.Z then v.co = p k += 1 end
	end
	bm:normalsUpdate()
	return k
end

-- grab: remember the verts under the brush at the start of the stroke
function Sculpt.capture(BMesh, bm, c, r)
	local hits = Sculpt.gather(BMesh, bm, c, r)
	for _, h in ipairs(hits) do h.orig = h.v.co end
	return hits
end

-- ===== the live mode =====
function Sculpt.new(C)
	local S = {
		brush = "draw", radius = 50, strength = 0.5, symmetryX = true,
		stroke = nil, adjust = nil, ring = nil,
	}
	local BMesh = C.BMesh

	local function ringFrame()
		local st = C.get()
		if not (st.ui and st.ui.gui) then return nil end
		if not S.ring or not S.ring.Parent then
			local f = Instance.new("Frame")
			f.Name = "RB_Brush"
			f.BackgroundTransparency = 1
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.ZIndex = 50
			local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0.5, 0) uc.Parent = f
			local us = Instance.new("UIStroke") us.Color = Color3.fromRGB(255, 255, 255) us.Thickness = 1 us.Parent = f
			f.Parent = st.ui.gui
			S.ring = f
		end
		return S.ring
	end
	function S.showRing(mp, visible)
		local f = ringFrame()
		if not f then return end
		f.Visible = visible ~= false
		f.Position = UDim2.fromOffset(mp.X, mp.Y)
		f.Size = UDim2.fromOffset(S.radius * 2, S.radius * 2)
		local us = f:FindFirstChildOfClass("UIStroke")
		if us then us.Transparency = 1 - (0.35 + 0.65 * S.strength) end
	end
	function S.hideRing() if S.ring then S.ring.Visible = false end end

	-- where the mouse hits the mesh (mesh space) + how big the brush is there (mesh space)
	local function hitAt(mp)
		local st = C.get()
		local ray = C.getRay()
		local t = C.rayMesh(ray.Origin, ray.Direction)
		if not t then return nil end
		local wp = ray.Origin + ray.Direction * t
		local cam = C.camera()
		local depth = (cam.CFrame.Position - wp).Magnitude
		local wpp = 2 * depth * math.tan(math.rad(cam.FieldOfView) / 2) / math.max(1, cam.ViewportSize.Y)
		return st.origin:PointToObjectSpace(wp), S.radius * wpp, wp, depth
	end

	local function doDab(c, r)
		local st = C.get()
		local bm = st.bm
		local brush = (C.shiftDown() and S.brush ~= "grab") and "smooth" or S.brush
		local invert = C.ctrlDown()
		Sculpt.dab(bm, brush, c, r, S.strength, { BMesh = BMesh, invert = invert })
		if S.symmetryX and math.abs(c.X) > r * 0.05 then
			Sculpt.dab(bm, brush, V3(-c.X, c.Y, c.Z), r, S.strength, { BMesh = BMesh, invert = invert })
		end
		C.dirtyMeshFast("pos")
	end

	function S.press(mp)
		if S.adjust then S.finishAdjust(false) return true end
		local c, r, wp, depth = hitAt(mp)
		if not c then C.setStatus("Sculpt: start the stroke on the mesh.") return true end
		S.stroke = { last = mp, moved = 0, dabs = 0, depth = depth }
		if S.brush == "grab" and not C.shiftDown() then
			local st = C.get()
			S.stroke.grab = Sculpt.capture(BMesh, st.bm, c, r)
			if S.symmetryX and math.abs(c.X) > r * 0.05 then
				for _, h in ipairs(Sculpt.capture(BMesh, st.bm, V3(-c.X, c.Y, c.Z), r)) do h.mirror = true table.insert(S.stroke.grab, h) end
			end
			S.stroke.plane0 = wp
		else
			doDab(c, r)
			S.stroke.dabs += 1
		end
		return true
	end
	function S.move(mp)
		if S.adjust then S.updateAdjust(mp) return true end
		S.showRing(mp, true)
		local stroke = S.stroke
		if not stroke then return true end
		if stroke.grab then
			local st = C.get()
			local cam = C.camera()
			local ray = C.getRay()
			local hitW = C.planeHit(ray, stroke.plane0, cam.CFrame.LookVector)
			if hitW then
				local d = st.origin:VectorToObjectSpace(hitW - stroke.plane0)
				for _, h in ipairs(stroke.grab) do
					local dd = h.mirror and V3(-d.X, d.Y, d.Z) or d
					h.v.co = h.orig + dd * h.w
				end
				st.bm:normalsUpdate()
				C.dirtyMeshFast("pos")
			end
			return true
		end
		-- space the dabs: one every ~15% of the brush size along the stroke
		local step = math.max(3, S.radius * 0.15)
		stroke.moved += (mp - stroke.last).Magnitude
		stroke.last = mp
		if stroke.moved >= step then
			stroke.moved = 0
			local c, r = hitAt(mp)
			if c then doDab(c, r) stroke.dabs += 1 end
		end
		return true
	end
	function S.release()
		if not S.stroke then return true end
		S.stroke = nil
		C.commit("Sculpt " .. Sculpt.BY_ID[S.brush].name)
		return true
	end

	-- F = brush size, Shift F = strength (move the mouse, click / Enter = keep, Esc / right click = put back)
	function S.startAdjust(kind, mp)
		S.adjust = { kind = kind, m0 = mp, r0 = S.radius, s0 = S.strength }
		C.setStatus(kind == "radius" and "Brush size: move the mouse, click to set (Esc = cancel)." or "Brush strength: move the mouse, click to set (Esc = cancel).")
	end
	function S.updateAdjust(mp)
		local A = S.adjust
		local dx = mp.X - A.m0.X
		if A.kind == "radius" then
			S.radius = math.clamp(A.r0 + dx, 4, 500)
			C.setStatus(("Radius %d px"):format(S.radius))
		else
			S.strength = math.clamp(A.s0 + dx / 300, 0.01, 1)
			C.setStatus(("Strength %.2f"):format(S.strength))
		end
		S.showRing(A.m0, true)
	end
	function S.finishAdjust(cancel)
		local A = S.adjust
		if not A then return end
		if cancel then S.radius, S.strength = A.r0, A.s0 end
		S.adjust = nil
		C.setStatus(("Brush: %s, radius %d px, strength %.2f."):format(Sculpt.BY_ID[S.brush].name, S.radius, S.strength))
	end

	function S.setBrush(id)
		if not Sculpt.BY_ID[id] then return end
		S.brush = id
		C.setStatus(("Brush: %s. Drag on the mesh. F = size, Shift F = strength, Ctrl = invert, Shift = smooth, X symmetry %s.")
			:format(Sculpt.BY_ID[id].name, S.symmetryX and "on" or "off"))
	end

	-- keys while sculpting; returns true when used
	function S.key(k, shift, ctrl, alt)
		local K = Enum.KeyCode
		if S.adjust then
			if k == K.Escape then S.finishAdjust(true) return true end
			if k == K.Return or k == K.KeypadEnter then S.finishAdjust(false) return true end
			return true
		end
		if k == K.F and not ctrl and not alt then S.startAdjust(shift and "strength" or "radius", C.mousePos()) return true end
		if ctrl or alt then return false end
		if k == K.C and shift then S.setBrush("crease") return true end
		if shift then return false end
		local map = { X = "draw", C = "clay", I = "inflate", G = "grab", S = "smooth", T = "flatten", P = "pinch" }
		local id = map[k.Name]
		if id then S.setBrush(id) return true end
		if k == K.LeftBracket then S.radius = math.max(4, S.radius * 0.9) C.setStatus(("Radius %d px"):format(S.radius)) return true end
		if k == K.RightBracket then S.radius = math.min(500, S.radius * 1.1) C.setStatus(("Radius %d px"):format(S.radius)) return true end
		return false
	end

	function S.exit()
		S.stroke, S.adjust = nil, nil
		S.hideRing()
	end
	return S
end

return Sculpt
