--[[
	ROBLEND - Vertex Paint: paint colours onto the mesh's points (the colour blends across each face).
	Converted to Luau (and cut down) from Blender's vertex paint:
	  source/blender/editors/sculpt_paint/paint_vertex.cc (draw / blur / fill / sample, brush falloff, front faces only)
	SPDX-License-Identifier: GPL-2.0-or-later
	Original: Copyright (C) Blender Authors. Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27).

	Colours live on each vert as v.col (a Color3; nil = white) and are saved in RB_Data as "vc".
	Paint.dab / fill / sample work on the mesh alone (tested headless); Paint.new(C) is the live mode.
]]
local Paint = {}
local V3 = Vector3.new

Paint.BRUSHES = {
	{ id = "draw", name = "Draw", key = "", short = "Dr", tip = "Paint the colour on (Ctrl = paint white back)" },
	{ id = "blur", name = "Blur", key = "", short = "Bl", tip = "Blend neighbouring colours together" },
	{ id = "average", name = "Average", key = "", short = "Av", tip = "Pull the colours under the brush towards their average" },
}
Paint.BY_ID = {}
for _, b in ipairs(Paint.BRUSHES) do Paint.BY_ID[b.id] = b end
Paint.PALETTE = { 0xffffff, 0x1e1e1e, 0x7a7a7a, 0xc42b2b, 0xe8822e, 0xf2cd37, 0x5ba84a, 0x2b86c4, 0x6a4bc4, 0xd96ab8, 0x8a5a36, 0xffd60a }

local function rgb(c) return c and c.R or 1, c and c.G or 1, c and c.B or 1 end
local function mix(a, b, t)
	local ar, ag, ab = rgb(a)
	local br, bg, bb = rgb(b)
	return Color3.new(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end
Paint.mix = mix
function Paint.hex(c) local r, g, b = rgb(c) return string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)) end
function Paint.fromHex(s)
	s = tostring(s or ""):gsub("#", ""):gsub("%s", "")
	if not s:match("^%x%x%x%x%x%x$") then return nil end
	return Color3.fromRGB(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16))
end
function Paint.fromInt(n) return Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end

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

-- one dab. opts: { BMesh, brush = "draw" | "blur" | "average", erase = bool, facing = Vector3 (only paint
-- points whose normal faces this way, i.e. towards the camera; nil = all) } -> how many points changed
function Paint.dab(bm, c, r, color, strength, opts)
	opts = opts or {}
	local BMesh = opts.BMesh
	local brush = opts.brush or "draw"
	strength = math.clamp(strength or 1, 0, 1)
	local hits = {}
	for v in pairs(bm.verts) do
		if not v.hide then
			local d = (v.co - c).Magnitude
			if d < r and (not opts.facing or vertNormal(BMesh, v):Dot(opts.facing) > -0.05) then
				hits[#hits + 1] = { v = v, w = falloff(d, r) }
			end
		end
	end
	local new = {}
	if brush == "draw" then
		local target = opts.erase and Color3.new(1, 1, 1) or color
		for _, h in ipairs(hits) do new[h.v] = mix(h.v.col, target, strength * h.w) end
	elseif brush == "blur" then
		for _, h in ipairs(hits) do
			local sr, sg, sb, k = 0, 0, 0, 0
			for _, e in ipairs(BMesh.vertEdges(h.v)) do
				local cr, cg, cb = rgb(BMesh.otherVert(e, h.v).col)
				sr += cr sg += cg sb += cb k += 1
			end
			if k > 0 then new[h.v] = mix(h.v.col, Color3.new(sr / k, sg / k, sb / k), strength * h.w) end
		end
	elseif brush == "average" then
		local sr, sg, sb, k = 0, 0, 0, 0
		for _, h in ipairs(hits) do local cr, cg, cb = rgb(h.v.col) sr += cr * h.w sg += cg * h.w sb += cb * h.w k += h.w end
		if k > 0 then
			local avg = Color3.new(sr / k, sg / k, sb / k)
			for _, h in ipairs(hits) do new[h.v] = mix(h.v.col, avg, strength * h.w) end
		end
	end
	local n = 0
	for v, col in pairs(new) do v.col = col n += 1 end
	return n
end

-- Paint > Fill: the colour on every point (or just the ones in `verts`)
function Paint.fill(bm, color, verts)
	local n = 0
	for v in pairs(verts or bm.verts) do v.col = color n += 1 end
	return n
end

-- S (sample): the colour of the point nearest `c`
function Paint.sample(bm, c)
	local best, bd = nil, math.huge
	for v in pairs(bm.verts) do
		local d = (v.co - c).Magnitude
		if d < bd then best, bd = v, d end
	end
	return best and (best.col or Color3.new(1, 1, 1)) or nil
end

-- ===== the live mode =====
function Paint.new(C)
	local P = { brush = "draw", radius = 40, strength = 1, color = Paint.fromInt(0xc42b2b), symmetryX = false, stroke = nil, adjust = nil, ring = nil }
	local BMesh = C.BMesh

	function P.showRing(mp, visible)
		local st = C.get()
		if not (st.ui and st.ui.gui) then return end
		if not P.ring or not P.ring.Parent then
			local f = Instance.new("Frame")
			f.Name = "RB_PaintBrush"
			f.BackgroundTransparency = 1
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.ZIndex = 50
			local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0.5, 0) uc.Parent = f
			local us = Instance.new("UIStroke") us.Thickness = 2 us.Parent = f
			f.Parent = st.ui.gui
			P.ring = f
		end
		P.ring.Visible = visible ~= false
		P.ring.Position = UDim2.fromOffset(mp.X, mp.Y)
		P.ring.Size = UDim2.fromOffset(P.radius * 2, P.radius * 2)
		local us = P.ring:FindFirstChildOfClass("UIStroke")
		if us then us.Color = P.color end
	end
	function P.hideRing() if P.ring then P.ring.Visible = false end end

	local function hitAt()
		local st = C.get()
		local ray = C.getRay()
		local t = C.rayMesh(ray.Origin, ray.Direction)
		if not t then return nil end
		local wp = ray.Origin + ray.Direction * t
		local cam = C.camera()
		local depth = (cam.CFrame.Position - wp).Magnitude
		local wpp = 2 * depth * math.tan(math.rad(cam.FieldOfView) / 2) / math.max(1, cam.ViewportSize.Y)
		return st.origin:PointToObjectSpace(wp), P.radius * wpp, st.origin:VectorToObjectSpace(-cam.CFrame.LookVector)
	end
	local function doDab()
		local c, r, facing = hitAt()
		if not c then return false end
		local st = C.get()
		local opts = { BMesh = BMesh, brush = C.shiftDown() and "blur" or P.brush, erase = C.ctrlDown(), facing = facing }
		Paint.dab(st.bm, c, r, P.color, P.strength, opts)
		if P.symmetryX then
			opts.facing = nil
			Paint.dab(st.bm, V3(-c.X, c.Y, c.Z), r, P.color, P.strength, opts)
		end
		C.dirtyMesh()
		return true
	end

	function P.press(mp)
		if P.adjust then P.finishAdjust(false) return true end
		if P.sampleNext then
			P.sampleNext = nil
			local c = hitAt()
			if c then P.setColor(Paint.sample(C.get().bm, c)) end
			return true
		end
		if not doDab() then C.setStatus("Paint: start on the mesh.") return true end
		P.stroke = { last = mp, moved = 0 }
		return true
	end
	function P.move(mp)
		if P.adjust then P.updateAdjust(mp) return true end
		P.showRing(mp, true)
		local s = P.stroke
		if not s then return true end
		s.moved += (mp - s.last).Magnitude
		s.last = mp
		if s.moved >= math.max(3, P.radius * 0.2) then s.moved = 0 doDab() end
		return true
	end
	function P.release()
		if not P.stroke then return true end
		P.stroke = nil
		C.commit("Paint " .. Paint.BY_ID[P.brush].name)
		return true
	end

	function P.startAdjust(kind, mp)
		P.adjust = { kind = kind, m0 = mp, r0 = P.radius, s0 = P.strength }
		C.setStatus(kind == "radius" and "Brush size: move the mouse, click to set (Esc = cancel)." or "Brush strength: move the mouse, click to set (Esc = cancel).")
	end
	function P.updateAdjust(mp)
		local A = P.adjust
		local dx = mp.X - A.m0.X
		if A.kind == "radius" then P.radius = math.clamp(A.r0 + dx, 4, 500) C.setStatus(("Radius %d px"):format(P.radius))
		else P.strength = math.clamp(A.s0 + dx / 300, 0.01, 1) C.setStatus(("Strength %.2f"):format(P.strength)) end
		P.showRing(A.m0, true)
	end
	function P.finishAdjust(cancel)
		local A = P.adjust
		if not A then return end
		if cancel then P.radius, P.strength = A.r0, A.s0 end
		P.adjust = nil
		C.setStatus(("Paint: %s, radius %d px, strength %.2f, colour #%s."):format(Paint.BY_ID[P.brush].name, P.radius, P.strength, Paint.hex(P.color)))
	end

	function P.setBrush(id)
		if not Paint.BY_ID[id] then return end
		P.brush = id
		C.setStatus(("Paint brush: %s. Drag on the mesh. Ctrl = paint white, Shift = blur, S = pick a colour from the mesh, F size, Shift F strength.")
			:format(Paint.BY_ID[id].name))
	end
	function P.setColor(c)
		if not c then return end
		P.color = c
		C.setStatus("Colour #" .. Paint.hex(c) .. ".")
	end
	-- Paint > Fill (Shift K in Blender): the whole mesh
	function P.fill()
		local st = C.get()
		Paint.fill(st.bm, P.color)
		C.dirtyMesh()
		C.commit("Fill Colour")
		C.setStatus("Filled with #" .. Paint.hex(P.color) .. ".")
	end

	function P.key(k, shift, ctrl, alt)
		local K = Enum.KeyCode
		if P.adjust then
			if k == K.Escape then P.finishAdjust(true) return true end
			if k == K.Return or k == K.KeypadEnter then P.finishAdjust(false) return true end
			return true
		end
		if k == K.F and not ctrl and not alt then P.startAdjust(shift and "strength" or "radius", C.mousePos()) return true end
		if k == K.K and shift and not ctrl then P.fill() return true end
		if ctrl or alt or shift then return false end
		if k == K.S then
			-- sample: the colour under the mouse right now
			local st = C.get()
			local ray = C.getRay()
			local t = C.rayMesh(ray.Origin, ray.Direction)
			if t then P.setColor(Paint.sample(st.bm, st.origin:PointToObjectSpace(ray.Origin + ray.Direction * t))) end
			return true
		end
		if k == K.LeftBracket then P.radius = math.max(4, P.radius * 0.9) return true end
		if k == K.RightBracket then P.radius = math.min(500, P.radius * 1.1) return true end
		return false
	end
	function P.exit()
		P.stroke, P.adjust, P.sampleNext = nil, nil, nil
		P.hideRing()
	end
	return P
end

return Paint
