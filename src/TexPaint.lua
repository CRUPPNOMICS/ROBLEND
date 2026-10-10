--[[
	ROBLEND - Texture Paint: paint straight onto the model's picture (its texture), through its UVs.
	Works the way Blender's texture paint does (source/blender/editors/sculpt_paint/paint_image_proj.cc):
	the brush is a ball in 3D, so a stroke carries on across UV seams; paint bleeds a little past each UV
	island's edge so no seams show; only faces turned towards you get paint.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	A canvas is { w, h, buf }: RGBA bytes, row 0 = the top of the picture. UVs are Blender's way up (v = 0 at
	the bottom), the same as everywhere else in ROBLEND.
	TexPaint.canvas / fill / tris / dab / sample work on plain data (tested headless);
	TexPaint.new(C, PAINT) is the live mode (shares the colour with Vertex Paint).
]]
local TexPaint = {}
local V3 = Vector3.new

TexPaint.SIZE = 1024       -- a new picture's size (Roblox's biggest texture)
TexPaint.UNDO = 8          -- strokes Ctrl Z can take back

local function byte(x) return math.clamp(math.floor(x * 255 + 0.5), 0, 255) end
local function falloff(d, r)
	if d >= r then return 0 end
	local t = 1 - d / r
	return t * t * (3 - 2 * t)
end

-- a new picture, all one colour
function TexPaint.canvas(w, h, col)
	local cv = { w = w, h = h, buf = buffer.create(w * h * 4) }
	TexPaint.fill(cv, col or Color3.new(1, 1, 1))
	return cv
end
function TexPaint.fill(cv, col)
	local buf, n = cv.buf, cv.w * cv.h * 4
	buffer.writeu8(buf, 0, byte(col.R)) buffer.writeu8(buf, 1, byte(col.G)) buffer.writeu8(buf, 2, byte(col.B)) buffer.writeu8(buf, 3, 255)
	-- (doubling copies: a 1024 picture is filled in 20 steps)
	local done = 4
	while done < n do
		local k = math.min(done, n - done)
		buffer.copy(buf, done, buf, 0, k)
		done += k
	end
	return 0, 0, cv.w - 1, cv.h - 1
end
function TexPaint.get(cv, x, y)
	local o = (y * cv.w + x) * 4
	return Color3.fromRGB(buffer.readu8(cv.buf, o), buffer.readu8(cv.buf, o + 1), buffer.readu8(cv.buf, o + 2))
end
function TexPaint.copy(cv)
	local b = buffer.create(buffer.len(cv.buf))
	buffer.copy(b, 0, cv.buf)
	return b
end

-- the mesh as triangles with their UVs (faces without UVs are skipped). triangulate(verts, normal) -> {{i, j, k}}
function TexPaint.tris(bm, BMesh, triangulate)
	local out = {}
	for f in pairs(bm.faces) do
		if not f.hide then
			local ls = BMesh.faceLoops(f)
			local ok, vs = true, {}
			for i, l in ipairs(ls) do
				if not l.uv then ok = false break end
				vs[i] = l.v
			end
			if ok then
				for _, t in ipairs(triangulate(vs, f.no)) do
					local a, b, c = ls[t[1]], ls[t[2]], ls[t[3]]
					local p1, p2, p3 = a.v.co, b.v.co, c.v.co
					local ctr = (p1 + p2 + p3) / 3
					local rad = math.max((p1 - ctr).Magnitude, (p2 - ctr).Magnitude, (p3 - ctr).Magnitude)
					out[#out + 1] = { p1, p2, p3, a.uv, b.uv, c.uv, no = f.no, ctr = ctr, rad = rad }
				end
			end
		end
	end
	return out
end

-- one dab of the brush: a ball of radius r round c (the mesh's own space).
-- opts: { brush = "draw" | "blur" | "average", erase = Color3 (paint this instead of the colour), facing = Vector3 }
-- -> how many pixels changed, and the box they're in (x0, y0, x1, y1) or nil
function TexPaint.dab(cv, tris, c, r, color, strength, opts)
	opts = opts or {}
	strength = math.clamp(strength or 1, 0, 1)
	local W, H, buf = cv.w, cv.h, cv.buf
	local cx, cy, cz = c.X, c.Y, c.Z
	local r2 = r * r
	local seen, idxs, ws = {}, {}, {}
	local x0, y0, x1, y1 = W, H, -1, -1
	for _, t in ipairs(tris) do
		if (t.ctr - c).Magnitude <= r + t.rad and (not opts.facing or t.no:Dot(opts.facing) > -0.05) then
			local ax, ay = t[4].X * W, (1 - t[4].Y) * H
			local bx, by = t[5].X * W, (1 - t[5].Y) * H
			local qx, qy = t[6].X * W, (1 - t[6].Y) * H
			local area = (bx - ax) * (qy - ay) - (qx - ax) * (by - ay)
			if math.abs(area) > 1e-9 then
				-- bleed: let each corner's share go 1.5 pixels below zero, so paint runs just past the island's edge
				local aa = math.abs(area)
				local e1 = 1.5 * math.sqrt((qx - bx) ^ 2 + (qy - by) ^ 2) / aa
				local e2 = 1.5 * math.sqrt((qx - ax) ^ 2 + (qy - ay) ^ 2) / aa
				local e3 = 1.5 * math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / aa
				local mnx = math.max(0, math.floor(math.min(ax, bx, qx) - 2))
				local mxx = math.min(W - 1, math.ceil(math.max(ax, bx, qx) + 2))
				local mny = math.max(0, math.floor(math.min(ay, by, qy) - 2))
				local mxy = math.min(H - 1, math.ceil(math.max(ay, by, qy) + 2))
				local p1, p2, p3 = t[1], t[2], t[3]
				for py = mny, mxy do
					local sy = py + 0.5
					for px = mnx, mxx do
						local idx = py * W + px
						if not seen[idx] then
							local sx = px + 0.5
							local w2 = ((sx - ax) * (qy - ay) - (qx - ax) * (sy - ay)) / area
							local w3 = ((bx - ax) * (sy - ay) - (sx - ax) * (by - ay)) / area
							local w1 = 1 - w2 - w3
							if w1 >= -e1 and w2 >= -e2 and w3 >= -e3 then
								-- where this pixel sits on the surface (pulled onto the triangle at its edges)
								local k1, k2, k3 = math.max(w1, 0), math.max(w2, 0), math.max(w3, 0)
								local s = k1 + k2 + k3
								k1, k2, k3 = k1 / s, k2 / s, k3 / s
								local dx = p1.X * k1 + p2.X * k2 + p3.X * k3 - cx
								local dy = p1.Y * k1 + p2.Y * k2 + p3.Y * k3 - cy
								local dz = p1.Z * k1 + p2.Z * k2 + p3.Z * k3 - cz
								local d2 = dx * dx + dy * dy + dz * dz
								if d2 < r2 then
									seen[idx] = true
									idxs[#idxs + 1] = idx
									ws[#ws + 1] = falloff(math.sqrt(d2), r) * strength
									if px < x0 then x0 = px end
									if px > x1 then x1 = px end
									if py < y0 then y0 = py end
									if py > y1 then y1 = py end
								end
							end
						end
					end
				end
			end
		end
	end
	local n = #idxs
	if n == 0 then return 0, nil end
	local brush = opts.brush or "draw"
	local nr, ng, nb = {}, {}, {}
	if brush == "draw" then
		local tc = opts.erase or color
		local tr, tg, tb = tc.R * 255, tc.G * 255, tc.B * 255
		for i = 1, n do
			local o, w = idxs[i] * 4, ws[i]
			local r0, g0, b0 = buffer.readu8(buf, o), buffer.readu8(buf, o + 1), buffer.readu8(buf, o + 2)
			nr[i], ng[i], nb[i] = r0 + (tr - r0) * w, g0 + (tg - g0) * w, b0 + (tb - b0) * w
		end
	elseif brush == "average" then
		local sr, sg, sb, sw = 0, 0, 0, 0
		for i = 1, n do
			local o, w = idxs[i] * 4, ws[i] + 1e-6
			sr += buffer.readu8(buf, o) * w sg += buffer.readu8(buf, o + 1) * w sb += buffer.readu8(buf, o + 2) * w sw += w
		end
		sr, sg, sb = sr / sw, sg / sw, sb / sw
		for i = 1, n do
			local o, w = idxs[i] * 4, ws[i]
			local r0, g0, b0 = buffer.readu8(buf, o), buffer.readu8(buf, o + 1), buffer.readu8(buf, o + 2)
			nr[i], ng[i], nb[i] = r0 + (sr - r0) * w, g0 + (sg - g0) * w, b0 + (sb - b0) * w
		end
	else
		-- blur (Blender's Soften): each pixel towards the average of the 5 x 5 round it
		for i = 1, n do
			local idx, w = idxs[i], ws[i]
			local px, py = idx % W, idx // W
			local sr, sg, sb, k = 0, 0, 0, 0
			for yy = math.max(0, py - 2), math.min(H - 1, py + 2) do
				for xx = math.max(0, px - 2), math.min(W - 1, px + 2) do
					local o = (yy * W + xx) * 4
					sr += buffer.readu8(buf, o) sg += buffer.readu8(buf, o + 1) sb += buffer.readu8(buf, o + 2) k += 1
				end
			end
			local o = idx * 4
			local r0, g0, b0 = buffer.readu8(buf, o), buffer.readu8(buf, o + 1), buffer.readu8(buf, o + 2)
			nr[i], ng[i], nb[i] = r0 + (sr / k - r0) * w, g0 + (sg / k - g0) * w, b0 + (sb / k - b0) * w
		end
	end
	for i = 1, n do
		local o = idxs[i] * 4
		buffer.writeu8(buf, o, math.clamp(math.floor(nr[i] + 0.5), 0, 255))
		buffer.writeu8(buf, o + 1, math.clamp(math.floor(ng[i] + 0.5), 0, 255))
		buffer.writeu8(buf, o + 2, math.clamp(math.floor(nb[i] + 0.5), 0, 255))
		buffer.writeu8(buf, o + 3, 255)
	end
	return n, { x0, y0, x1, y1 }
end

-- the UV (Blender's way up) at a point on the surface, from the triangle it lies on
function TexPaint.uvAt(tris, c)
	local best, bd
	for _, t in ipairs(tris) do
		if (t.ctr - c).Magnitude <= t.rad + 1e-3 then
			local p1, p2, p3 = t[1], t[2], t[3]
			local v0, v1, v2 = p2 - p1, p3 - p1, c - p1
			local d00, d01, d11 = v0:Dot(v0), v0:Dot(v1), v1:Dot(v1)
			local d20, d21 = v2:Dot(v0), v2:Dot(v1)
			local den = d00 * d11 - d01 * d01
			if math.abs(den) > 1e-12 then
				local b = (d11 * d20 - d01 * d21) / den
				local g = (d00 * d21 - d01 * d20) / den
				local a = 1 - b - g
				if a >= -0.01 and b >= -0.01 and g >= -0.01 then
					local plane = math.abs(t.no:Dot(c - p1))
					if not bd or plane < bd then
						bd = plane
						best = t[4] * a + t[5] * b + t[6] * g
					end
				end
			end
		end
	end
	return best
end
-- S: the picture's colour under a point on the surface
function TexPaint.sample(cv, tris, c)
	local uv = TexPaint.uvAt(tris, c)
	if not uv then return nil end
	local x = math.clamp(math.floor(uv.X * cv.w), 0, cv.w - 1)
	local y = math.clamp(math.floor((1 - uv.Y) * cv.h), 0, cv.h - 1)
	return TexPaint.get(cv, x, y)
end

-- ===== the live mode =====
function TexPaint.new(C, PAINT)
	local P = { brush = "draw", radius = 40, strength = 1, symmetryX = false, images = {}, obj = nil, rec = nil, tris = nil }
	local BMesh = C.BMesh

	-- the picture on screen: copy the changed box into the EditableImage
	local function push(rec, rect)
		local cv = rec.cv
		local x0, y0, x1, y1 = rect[1], rect[2], rect[3], rect[4]
		local w, h = x1 - x0 + 1, y1 - y0 + 1
		if w <= 0 or h <= 0 then return end
		local sub
		if w == cv.w and h == cv.h then
			sub = cv.buf
		else
			sub = buffer.create(w * h * 4)
			for y = 0, h - 1 do buffer.copy(sub, y * w * 4, cv.buf, ((y0 + y) * cv.w + x0) * 4, w * 4) end
		end
		pcall(function() rec.img:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(w, h), sub) end)
	end
	local function pushAll(rec) push(rec, { 0, 0, rec.cv.w - 1, rec.cv.h - 1 }) end

	-- the picture for a part: the one it already has (if Roblox lets us read it), else a new one in the part's colour
	local function load(obj)
		local AS = C.AssetService
		local img, cv, note
		local tex = ""
		pcall(function() tex = obj.TextureID end)
		if tex ~= "" then
			local ok, im = pcall(function() return AS:CreateEditableImageAsync(Content.fromUri(tex)) end)
			if ok and im then
				local okR, sz, b = pcall(function()
					local s = im.Size
					return s, im:ReadPixelsBuffer(Vector2.zero, s)
				end)
				if okR and sz and b then img, cv = im, { w = sz.X, h = sz.Y, buf = b } end
			end
			if not img then note = "Its old texture couldn't be opened (only your own uploads can be), so this is a fresh picture." end
		end
		if not img then
			local N = TexPaint.SIZE
			local ok, im = pcall(function() return AS:CreateEditableImage({ Size = Vector2.new(N, N) }) end)
			if not ok or not im then return nil, "Texture Paint needs Game Settings > Security > Allow Mesh / Image APIs." end
			img, cv = im, TexPaint.canvas(N, N, obj.Color)
			pcall(function() img:WritePixelsBuffer(Vector2.zero, Vector2.new(N, N), cv.buf) end)
		end
		return { img = img, cv = cv, undo = {}, redo = {}, dirty = false }, note
	end
	function P.imageFor(p) local rec = P.images[p] return rec and rec.img or nil end

	-- into Texture Paint: UVs first (Smart UV Project if the mesh has none), then the picture
	function P.enter()
		local st = C.get()
		local obj, bm = st.obj, st.bm
		if not (obj and bm) then return false end
		local said
		if not C.Convert.hasUV(bm, BMesh) then
			C.UVTools.smartProject(bm, nil, { BMesh = BMesh, margin = 0.02 })
			obj:SetAttribute("RB_UVMode", "unwrap")
			C.dirtyMesh()
			C.commit("Smart UV Project")
			said = "It had no UVs, so Smart UV Project laid them out first (U > UV Editor to see them)."
		elseif obj:GetAttribute("RB_UVMode") ~= "unwrap" then
			obj:SetAttribute("RB_UVMode", "unwrap")
		end
		local rec = P.images[obj]
		local note
		if not rec then
			rec, note = load(obj)
			if not rec then C.setStatus(note) return false end
			P.images[obj] = rec
		end
		P.obj, P.rec = obj, rec
		P.tris = TexPaint.tris(bm, BMesh, C.Display.triangulate)
		pcall(function() obj.TextureContent = Content.fromObject(rec.img) end)
		C.dirtyMesh()
		C.setStatus("Texture Paint: paint onto the picture. " .. (said or note or "") ..
			" Shift = soften, Ctrl = white, S = pick a colour, Ctrl Z = undo a stroke. It's saved to Roblox when you leave.")
		return true
	end
	function P.ready() return P.rec ~= nil and P.tris ~= nil end

	function P.showRing(mp, visible)
		local st = C.get()
		if not (st.ui and st.ui.gui) then return end
		if not P.ring or not P.ring.Parent then
			local f = Instance.new("Frame")
			f.Name = "RB_TexBrush"
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
		if us then us.Color = PAINT.color end
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
	local function snapshot()
		local rec = P.rec
		table.insert(rec.undo, TexPaint.copy(rec.cv))
		if #rec.undo > TexPaint.UNDO then table.remove(rec.undo, 1) end
		rec.redo = {}
	end
	local function doDab()
		if not P.ready() then return false end
		local c, r, facing = hitAt()
		if not c then return false end
		local opts = { brush = C.shiftDown() and "blur" or P.brush, erase = C.ctrlDown() and Color3.new(1, 1, 1) or nil, facing = facing }
		local n, rect = TexPaint.dab(P.rec.cv, P.tris, c, r, PAINT.color, P.strength, opts)
		if P.symmetryX then
			opts.facing = nil
			local n2, r2 = TexPaint.dab(P.rec.cv, P.tris, V3(-c.X, c.Y, c.Z), r, PAINT.color, P.strength, opts)
			if r2 then
				rect = rect and { math.min(rect[1], r2[1]), math.min(rect[2], r2[2]), math.max(rect[3], r2[3]), math.max(rect[4], r2[4]) } or r2
				n += n2
			end
		end
		if rect then push(P.rec, rect) P.rec.dirty = true end
		return true
	end

	function P.press(mp)
		if P.adjust then P.finishAdjust(false) return true end
		if not P.ready() then C.setStatus("Texture Paint isn't ready: Q > Texture Paint again.") return true end
		local c = hitAt()
		if not c then C.setStatus("Paint: start on the mesh.") return true end
		snapshot()
		doDab()
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
		if s.moved >= math.max(2, P.radius * 0.15) then s.moved = 0 doDab() end
		return true
	end
	function P.release()
		if not P.stroke then return true end
		P.stroke = nil
		return true
	end

	-- Ctrl Z / Ctrl Y: whole strokes, kept with the picture
	function P.undo()
		local rec = P.rec
		if not rec or #rec.undo == 0 then C.setStatus("Nothing more to undo in this picture.") return true end
		table.insert(rec.redo, TexPaint.copy(rec.cv))
		local b = table.remove(rec.undo)
		buffer.copy(rec.cv.buf, 0, b)
		pushAll(rec)
		rec.dirty = true
		C.setStatus("Undo: paint stroke.")
		return true
	end
	function P.redo()
		local rec = P.rec
		if not rec or #rec.redo == 0 then return true end
		table.insert(rec.undo, TexPaint.copy(rec.cv))
		buffer.copy(rec.cv.buf, 0, table.remove(rec.redo))
		pushAll(rec)
		rec.dirty = true
		C.setStatus("Redo: paint stroke.")
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
		C.setStatus(("Texture Paint: radius %d px, strength %.2f."):format(P.radius, P.strength))
	end

	local NAMES = { draw = "Draw", blur = "Soften", average = "Average" }
	function P.setBrush(id)
		if not NAMES[id] then return end
		P.brush = id
		C.setStatus(("Texture brush: %s. Drag on the mesh. Ctrl = paint white, Shift = soften, S = pick a colour, F size, Shift F strength."):format(NAMES[id]))
	end
	-- Paint > Fill: the whole picture
	function P.fill()
		if not P.ready() then return end
		snapshot()
		TexPaint.fill(P.rec.cv, PAINT.color)
		pushAll(P.rec)
		P.rec.dirty = true
		C.setStatus("Filled the picture with #" .. C.Paint.hex(PAINT.color) .. ".")
	end

	function P.key(k, shift, ctrl, alt)
		local K = Enum.KeyCode
		if P.adjust then
			if k == K.Escape then P.finishAdjust(true) return true end
			if k == K.Return or k == K.KeypadEnter then P.finishAdjust(false) return true end
			return true
		end
		if ctrl and not alt and k == K.Z then if shift then P.redo() else P.undo() end return true end
		if ctrl and not alt and k == K.Y then P.redo() return true end
		if k == K.F and not ctrl and not alt then P.startAdjust(shift and "strength" or "radius", C.mousePos()) return true end
		if k == K.K and shift and not ctrl then P.fill() return true end
		if ctrl or alt or shift then return false end
		if k == K.S then
			local c = P.ready() and hitAt()
			if c then
				local col = TexPaint.sample(P.rec.cv, P.tris, c)
				if col then PAINT.setColor(col) end
			end
			return true
		end
		if k == K.LeftBracket then P.radius = math.max(4, P.radius * 0.9) return true end
		if k == K.RightBracket then P.radius = math.min(500, P.radius * 1.1) return true end
		return false
	end

	-- save the picture to Roblox (an Image asset) and put it on the part as its texture
	function P.save(obj, rec)
		if not (obj and rec and rec.dirty) then return end
		rec.dirty = false
		C.setStatus("Saving the texture to Roblox...")
		task.spawn(function()
			local ok, result, id = pcall(function()
				return C.AssetService:CreateAssetAsync(rec.img, Enum.AssetType.Image, { Name = (obj.Name .. " texture"):sub(1, 50), Description = "Painted in ROBLEND" })
			end)
			if ok and result == Enum.CreateAssetResult.Success and id then
				C.record("Texture", function() obj.TextureID = "rbxassetid://" .. tostring(id) end)
				rec.savedId = id
				C.setStatus(("Texture saved to Roblox (id %s) and put on %s."):format(tostring(id), obj.Name))
			else
				rec.dirty = true
				C.setStatus("Couldn't save the texture (" .. tostring(ok and result or result) .. "). It stays on screen; saving needs File > Beta Features > CreateAssetAsync Lua API. Open Texture Paint and leave again to retry.")
			end
		end)
	end
	function P.exit()
		P.stroke, P.adjust = nil, nil
		P.hideRing()
		if P.obj and P.rec then P.save(P.obj, P.rec) end
		P.obj, P.rec, P.tris = nil, nil, nil
	end
	return P
end

return TexPaint
