--[[
	ROBLEND - modifiers: a non-destructive stack on each mesh (Blender's Properties > Modifiers)
	SPDX-License-Identifier: GPL-2.0-or-later

	Converted to Luau (and cut down) from Blender's modifiers:
	  source/blender/modifiers/intern/MOD_mirror.cc     + blenkernel mesh_mirror.cc   (Mirror, merge on the plane)
	  source/blender/modifiers/intern/MOD_subsurf.cc    + OpenSubdiv's Catmull-Clark rules (Subdivision Surface)
	  source/blender/modifiers/intern/MOD_solidify.cc   (Solidify, simple mode)
	  source/blender/modifiers/intern/MOD_array.cc      (Array, relative offset)
	  source/blender/modifiers/intern/MOD_bevel.cc      (Bevel, angle limit)
	  source/blender/modifiers/intern/MOD_smooth.cc     (Smooth)
	  source/blender/modifiers/intern/MOD_weld.cc       (Weld, by distance)
	  source/blender/modifiers/intern/MOD_screw.cc      (Screw: spin the edges round an axis)
	  source/blender/modifiers/intern/MOD_triangulate.cc (Triangulate)
	  source/blender/modifiers/intern/MOD_decimate.cc   (Decimate, planar mode = limited dissolve)
	  source/blender/modifiers/intern/MOD_simpledeform.cc (Simple Deform: twist, bend, taper, stretch)
	  source/blender/modifiers/intern/MOD_cast.cc       (Cast, sphere)
	  source/blender/modifiers/intern/MOD_wave.cc       (Wave)
	  source/blender/modifiers/intern/MOD_displace.cc   (Displace, with Roblox's math.noise as the texture)
	  source/blender/modifiers/intern/MOD_wireframe.cc  + bmesh/operators/bmo_wireframe.cc (Wireframe, simplified)
	  source/blender/blenkernel/intern/curve_bevel.cc + displist.cc (Tube: a curve's round bevel, on line paths)
	Original: Copyright (C) Blender Authors (GPL-2.0-or-later)
	Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27) - GPL-2.0-or-later.

	The base mesh is never changed: evaluate() works on a copy. The list is stored on the part as JSON
	(StringValue RB_Mods): { {type = "mirror", on = true, ...settings}, ... }
]]

local BMesh = require(script.Parent.BMesh)
local Ops = require(script.Parent.Ops)
local MT = require(script.Parent.MeshTools)
local Mods = {}
local V3 = Vector3.new

-- types, Blender's names, default settings (in Blender's Add Modifier menu order)
Mods.TYPES = {
	{ id = "array", name = "Array", group = "Generate", defaults = { count = 3, axis = "X", relative = 1, constant = 0, merge = false } },
	{ id = "bevel", name = "Bevel", group = "Generate", defaults = { amount = 0.2, segments = 2, angle = 30 } },
	{ id = "boolean", name = "Boolean", group = "Generate", defaults = { target = "", operation = "Difference" } },
	{ id = "mirror", name = "Mirror", group = "Generate", defaults = { x = true, y = false, z = false, merge = true, mergeDist = 0.001, bisect = false } },
	{ id = "solidify", name = "Solidify", group = "Generate", defaults = { thickness = 0.2, offset = -1 } },
	{ id = "decimate", name = "Decimate", group = "Generate", defaults = { mode = "Collapse", ratio = 0.5, angle = 5 } },
	{ id = "edgesplit", name = "Edge Split", group = "Generate", defaults = { angle = 30, useAngle = true, sharp = true } },
	{ id = "screw", name = "Screw", group = "Generate", defaults = { angle = 360, steps = 16, screw = 0, axis = "Y" } },
	{ id = "subsurf", name = "Subdivision Surface", group = "Generate", defaults = { levels = 1 } },
	{ id = "triangulate", name = "Triangulate", group = "Generate", defaults = {} },
	{ id = "tube", name = "Tube (Curve Bevel)", group = "Generate", defaults = { radius = 0.25, sides = 8, resolution = 4, caps = true } },
	{ id = "weld", name = "Weld", group = "Generate", defaults = { distance = 0.01 } },
	{ id = "wireframe", name = "Wireframe", group = "Generate", defaults = { thickness = 0.1 } },
	{ id = "cast", name = "Cast", group = "Deform", defaults = { factor = 0.5 } },
	{ id = "displace", name = "Displace", group = "Deform", defaults = { strength = 0.3, size = 1, seed = 0 } },
	{ id = "shrinkwrap", name = "Shrinkwrap", group = "Deform", defaults = { target = "", mode = "Nearest Surface Point", offset = 0 } },
	{ id = "simpledeform", name = "Simple Deform", group = "Deform", defaults = { method = "Twist", angle = 45, factor = 0.5, axis = "Y" } },
	{ id = "smooth", name = "Smooth", group = "Deform", defaults = { factor = 0.5, ["repeat"] = 1 } },
	{ id = "wave", name = "Wave", group = "Deform", defaults = { height = 0.5, width = 1.5, offset = 0, radial = true } },
}
Mods.BY_ID = {}
for _, t in ipairs(Mods.TYPES) do Mods.BY_ID[t.id] = t end

function Mods.new(id)
	local t = Mods.BY_ID[id]
	if not t then return nil end
	local m = { type = id, on = true }
	for k, v in pairs(t.defaults) do m[k] = v end
	return m
end

-- copy keeping selection + smooth flags (so the edit view can still tint selected faces)
local function copy(bm) return (MT.fromSpec(MT.toSpec(bm))) end

-- ===== Mirror (MOD_mirror.cc): copy across the object's own X / Y / Z plane, weld the seam =====
local function mirrorAxis(bm, axis, merge, dist, bisect)
	if bisect then
		-- Bisect: cut on the mirror plane and drop the half on the negative side first
		bm = copy(bm)
		MT.bisect(bm, V3(), axis)
		local gone = {}
		for v in pairs(bm.verts) do if v.co:Dot(axis) < -1e-4 then gone[v] = true end end
		if next(gone) then Ops.deleteVerts(bm, gone) end
	end
	local spec = MT.toSpec(bm)
	local n = #spec.verts
	local twin = {}
	for i = 1, n do
		local sv = spec.verts[i]
		local d = sv.co:Dot(axis)
		if merge and math.abs(d) <= dist then
			sv.co = sv.co - axis * d -- snap onto the plane so both halves share it
			twin[i] = i
		else
			twin[i] = MT.addVert(spec, sv.co - axis * (2 * d), sv.sel)
		end
	end
	local nf = #spec.faces
	for i = 1, nf do
		local f = spec.faces[i]
		local r = {}
		for j = #f.v, 1, -1 do r[#r + 1] = twin[f.v[j]] end
		spec.faces[#spec.faces + 1] = { v = r, sel = f.sel, smooth = f.smooth }
	end
	local ne = #spec.edges
	for i = 1, ne do
		local e = spec.edges[i]
		spec.edges[#spec.edges + 1] = { twin[e[1]], twin[e[2]], sel = e.sel }
	end
	return (MT.fromSpec(spec))
end
function Mods.mirror(bm, m)
	local out = bm
	for _, a in ipairs({ { "x", V3(1, 0, 0) }, { "y", V3(0, 1, 0) }, { "z", V3(0, 0, 1) } }) do
		if m[a[1]] then out = mirrorAxis(out, a[2], m.merge ~= false, math.max(m.mergeDist or 0.001, 1e-5), m.bisect == true) end
	end
	return out
end

-- ===== Subdivision Surface: Catmull-Clark, one level at a time =====
-- face point = centre; edge point = (ends + both face points) / 4 (border: the middle);
-- vert = (F + 2R + (n - 3) V) / n inside, (b1 + b2 + 6 V) / 8 on a border
local function catmullClark(bm)
	local spec = { verts = {}, faces = {}, edges = {}, eflags = {}, vi = {} }
	local fp, ep, vp = {}, {}, {}
	local function add(co, sel) spec.verts[#spec.verts + 1] = { co = co, sel = sel } return #spec.verts end
	for f in pairs(bm.faces) do fp[f] = add(BMesh.faceCenter(f), f.sel) end
	for e in pairs(bm.edges) do
		local fs = BMesh.edgeFaces(e)
		local co
		if #fs == 2 and not e.crease then co = (e.v1.co + e.v2.co + spec.verts[fp[fs[1]]].co + spec.verts[fp[fs[2]]].co) / 4
		else co = (e.v1.co + e.v2.co) / 2 end
		ep[e] = add(co, e.sel)
	end
	for v in pairs(bm.verts) do
		local edges = BMesh.vertEdges(v)
		-- open edges and creased edges (Shift E) both use the sharp rules
		local border, open = {}, 0
		for _, e in ipairs(edges) do
			local fc = BMesh.edgeFaceCount(e)
			if fc < 2 then open += 1 end
			if fc < 2 or e.crease then border[#border + 1] = e end
		end
		local co
		if #border == 2 then
			local b1, b2 = BMesh.otherVert(border[1], v).co, BMesh.otherVert(border[2], v).co
			co = (b1 + b2 + v.co * 6) / 8
		elseif #border >= 3 or open == 1 or #edges < 3 then
			co = v.co
		else
			local faces = BMesh.vertFaces(v)
			local F, R = V3(), V3()
			for _, f in ipairs(faces) do F += spec.verts[fp[f]].co end
			F /= #faces
			for _, e in ipairs(edges) do R += (e.v1.co + e.v2.co) / 2 end
			local n = #edges
			R /= n
			co = (F + R * 2 + v.co * (n - 3)) / n
		end
		vp[v] = add(co, v.sel)
	end
	-- a creased edge's two halves stay creased for the next level
	for e in pairs(bm.edges) do
		if e.crease or e.sharp or e.seam then
			for _, v in ipairs({ e.v1, e.v2 }) do
				local a, b = vp[v], ep[e]
				spec.eflags[math.min(a, b) .. ":" .. math.max(a, b)] = { crease = e.crease, sharp = e.sharp, seam = e.seam }
			end
		end
	end
	for f in pairs(bm.faces) do
		for _, l in ipairs(BMesh.faceLoops(f)) do
			-- corner quad: v, middle of the edge out, face centre, middle of the edge in
			spec.faces[#spec.faces + 1] = { v = { vp[l.v], ep[l.e], fp[f], ep[l.prev.e] }, sel = f.sel, smooth = f.smooth }
		end
	end
	return (MT.fromSpec(spec))
end
function Mods.subsurf(bm, m)
	local out = bm
	local levels = math.clamp(math.floor(m.levels or 1), 0, 4)
	for _ = 1, levels do
		-- stop before Roblox's 20,000-triangle limit
		local quads = 0
		for f in pairs(out.faces) do quads += f.len end
		if quads * 2 > 20000 then break end
		out = catmullClark(out)
	end
	return out
end

-- ===== Solidify (simple): a shell `thickness` thick; offset -1 = inward, 1 = outward, 0 = centred =====
function Mods.solidify(bm, m)
	local out = copy(bm)
	local t = m.thickness or 0.2
	local off = math.clamp(m.offset or -1, -1, 1)
	local fs = {}
	for f in pairs(out.faces) do fs[f] = true end
	if not next(fs) then return out end
	-- shift the original so the shell sits where offset says, then build the inner (flipped) layer
	local shift = (off + 1) / 2 * t
	if math.abs(shift) > 1e-9 then
		for v in pairs(out.verts) do v.co += MT.vertNormal(v) * shift end
		out:normalsUpdate()
	end
	MT.solidify(out, fs, t)
	return out
end

-- ===== Array (relative offset): count copies, each shifted by the mesh's size along the axis * relative =====
function Mods.array(bm, m)
	local count = math.clamp(math.floor(m.count or 2), 1, 64)
	if count <= 1 then return bm end
	local axis = ({ X = V3(1, 0, 0), Y = V3(0, 1, 0), Z = V3(0, 0, 1) })[m.axis or "X"] or V3(1, 0, 0)
	local lo, hi
	for v in pairs(bm.verts) do
		lo = lo and V3(math.min(lo.X, v.co.X), math.min(lo.Y, v.co.Y), math.min(lo.Z, v.co.Z)) or v.co
		hi = hi and V3(math.max(hi.X, v.co.X), math.max(hi.Y, v.co.Y), math.max(hi.Z, v.co.Z)) or v.co
	end
	if not lo then return bm end
	-- relative offset (times the mesh's size) + constant offset (studs), like Blender's two offset options
	local step = axis * ((hi - lo):Dot(axis) * (m.relative or 1) + (m.constant or 0))
	local spec = MT.toSpec(bm)
	local nv, nf, ne = #spec.verts, #spec.faces, #spec.edges
	for c = 1, count - 1 do
		local base = #spec.verts
		for i = 1, nv do
			local sv = spec.verts[i]
			spec.verts[#spec.verts + 1] = { co = sv.co + step * c, sel = sv.sel, loose = sv.loose }
		end
		for i = 1, nf do
			local f = spec.faces[i]
			local r = {}
			for j, k in ipairs(f.v) do r[j] = k + base end
			spec.faces[#spec.faces + 1] = { v = r, sel = f.sel, smooth = f.smooth }
		end
		for i = 1, ne do
			local e = spec.edges[i]
			spec.edges[#spec.edges + 1] = { e[1] + base, e[2] + base, sel = e.sel }
		end
	end
	local out = MT.fromSpec(spec)
	if m.merge then out = Mods.mergeDoubles(out, 0.01) end
	return out
end

-- ===== Bevel (angle limit): round every edge sharper than `angle` degrees =====
function Mods.bevel(bm, m)
	local out = copy(bm)
	local lim = math.cos(math.rad(m.angle or 30))
	for e in pairs(out.edges) do e.sel = false end
	local any = false
	for e in pairs(out.edges) do
		if BMesh.edgeFaceCount(e) == 2 then
			local f = BMesh.edgeFaces(e)
			if f[1].no:Dot(f[2].no) < lim then e.sel = true any = true end
		end
	end
	if not any or (m.amount or 0) <= 1e-4 then return bm end
	local nb = MT.bevel(out, m.amount, false, m.segments or 1)
	if not nb then return bm end
	for f in pairs(nb.faces) do f.sel = false end
	return nb
end

-- ===== Smooth =====
function Mods.smooth(bm, m)
	local out = copy(bm)
	MT.smooth(out, out.verts, math.clamp(m.factor or 0.5, -2, 2), math.clamp(math.floor(m["repeat"] or 1), 0, 50))
	return out
end

local AXES = { X = V3(1, 0, 0), Y = V3(0, 1, 0), Z = V3(0, 0, 1) }
-- the other two axes for an axis, in Blender's cyclic order (X -> Y, Z; Y -> Z, X; Z -> X, Y)
local PERP = { X = { V3(0, 1, 0), V3(0, 0, 1) }, Y = { V3(0, 0, 1), V3(1, 0, 0) }, Z = { V3(1, 0, 0), V3(0, 1, 0) } }
local function bounds(bm)
	local lo, hi
	for v in pairs(bm.verts) do
		lo = lo and lo:Min(v.co) or v.co
		hi = hi and hi:Max(v.co) or v.co
	end
	return lo, hi
end

-- ===== Weld (MOD_weld.cc, "All" mode): merge verts closer than distance =====
function Mods.weld(bm, m)
	local nb = Mods.mergeDoubles(bm, math.max(m.distance or 0.01, 1e-5))
	return nb
end

-- ===== Wireframe: every face becomes a frame round its edges, then gets thickness =====
-- turns faces `fs` into frames (an inset ring each, middle removed); returns the frame faces
function Mods.wireframeFaces(bm, fs, t)
	local before = {}
	for f in pairs(bm.faces) do before[f] = true end
	local _, inner = Ops.insetIndividual(bm, fs, t, 0)
	local kill = {}
	for f in pairs(inner or {}) do kill[f] = true end
	Ops.deleteFaces(bm, kill)
	local frame = {}
	for f in pairs(bm.faces) do if not before[f] then frame[f] = true end end
	bm:normalsUpdate()
	return frame
end
function Mods.wireframe(bm, m)
	local out = copy(bm)
	local t = math.max(m.thickness or 0.1, 1e-3)
	local fs = {}
	for f in pairs(out.faces) do fs[f] = true end
	if not next(fs) then return bm end
	Mods.wireframeFaces(out, fs, t)
	local all = {}
	for f in pairs(out.faces) do all[f] = true end
	MT.solidify(out, all, t)
	for f in pairs(out.faces) do f.sel = false end
	return out
end

-- ===== Tube: every line path (edges with no faces) becomes a smooth round pipe =====
-- (Blender: a curve with Bevel Depth / Resolution; here the "curve" is the mesh's loose edge chains,
-- smoothed Catmull-Rom style, then a ring of `sides` points swept along with rotation-minimising frames)
local function wireChains(bm)
	local wire, deg = {}, {}
	for e in pairs(bm.edges) do
		if not e.l then
			wire[e] = true
			deg[e.v1] = (deg[e.v1] or 0) + 1
			deg[e.v2] = (deg[e.v2] or 0) + 1
		end
	end
	local used, chains = {}, {}
	local function walk(v, e)
		local pts = { v }
		while e and not used[e] do
			used[e] = true
			local o = (e.v1 == v) and e.v2 or e.v1
			pts[#pts + 1] = o
			v = o
			if deg[v] ~= 2 then break end
			local nxt
			for _, e2 in ipairs(BMesh.vertEdges(v)) do if wire[e2] and not used[e2] then nxt = e2 break end end
			e = nxt
		end
		return pts
	end
	-- open chains start at ends / junctions
	for v, d in pairs(deg) do
		if d ~= 2 then
			for _, e in ipairs(BMesh.vertEdges(v)) do
				if wire[e] and not used[e] then chains[#chains + 1] = { pts = walk(v, e), closed = false } end
			end
		end
	end
	-- whatever is left are closed loops
	for e in pairs(wire) do
		if not used[e] then
			local pts = walk(e.v1, e)
			if pts[#pts] == pts[1] then table.remove(pts) end
			chains[#chains + 1] = { pts = pts, closed = true }
		end
	end
	return chains, wire
end
local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end
function Mods.smoothPath(pts, closed, res)
	local n = #pts
	if n < 2 or res <= 1 then
		local out = {}
		for i, p in ipairs(pts) do out[i] = p end
		return out
	end
	local function at(i)
		if closed then return pts[(i - 1) % n + 1] end
		if i < 1 then return pts[1] * 2 - pts[2] end
		if i > n then return pts[n] * 2 - pts[n - 1] end
		return pts[i]
	end
	local out = {}
	local segs = closed and n or n - 1
	for i = 1, segs do
		for s = 0, res - 1 do out[#out + 1] = catmull(at(i - 1), at(i), at(i + 1), at(i + 2), s / res) end
	end
	if not closed then out[#out + 1] = pts[n] end
	return out
end
function Mods.tube(bm, m)
	local chains, wire = wireChains(bm)
	if #chains == 0 then return bm end
	local r = math.max(m.radius or 0.25, 1e-3)
	local sides = math.clamp(math.floor(m.sides or 8), 3, 64)
	local res = math.clamp(math.floor(m.resolution or 4), 1, 32)
	local spec = MT.toSpec(bm)
	-- the line paths themselves don't stay (they'd only show as stray edges)
	local keep = {}
	for _, e in ipairs(spec.edges) do keep[#keep + 1] = e end
	spec.edges = {}
	for _, ch in ipairs(chains) do
		local raw = {}
		for i, v in ipairs(ch.pts) do raw[i] = v.co end
		local P = Mods.smoothPath(raw, ch.closed, res)
		local n = #P
		if n >= 2 then
			-- tangents + rotation-minimising frames (parallel transport)
			local T = {}
			for i = 1, n do
				local a = ch.closed and P[(i - 2) % n + 1] or P[math.max(1, i - 1)]
				local b = ch.closed and P[i % n + 1] or P[math.min(n, i + 1)]
				local d = b - a
				T[i] = d.Magnitude > 1e-9 and d.Unit or V3(1, 0, 0)
			end
			local up = math.abs(T[1].Y) < 0.9 and V3(0, 1, 0) or V3(1, 0, 0)
			local N = { (up - T[1] * up:Dot(T[1])).Unit }
			for i = 2, n do
				local prev = N[i - 1]
				local q = prev - T[i] * prev:Dot(T[i])
				N[i] = q.Magnitude > 1e-9 and q.Unit or prev
			end
			local rings = {}
			for i = 1, n do
				local B = T[i]:Cross(N[i])
				rings[i] = {}
				for s = 0, sides - 1 do
					local a = 2 * math.pi * s / sides
					rings[i][s + 1] = MT.addVert(spec, P[i] + (N[i] * math.cos(a) + B * math.sin(a)) * r, false)
				end
			end
			local last = ch.closed and n or n - 1
			for i = 1, last do
				local A, Bq = rings[i], rings[i % n + 1]
				for s = 1, sides do
					local s2 = s % sides + 1
					-- winding so the face points out of the tube
					spec.faces[#spec.faces + 1] = { v = { A[s], A[s2], Bq[s2], Bq[s] }, sel = false, smooth = true }
				end
			end
			if not ch.closed and m.caps ~= false then
				local c1, c2 = {}, {}
				for s = sides, 1, -1 do c1[#c1 + 1] = rings[1][s] end
				for s = 1, sides do c2[#c2 + 1] = rings[n][s] end
				spec.faces[#spec.faces + 1] = { v = c1, sel = false }
				spec.faces[#spec.faces + 1] = { v = c2, sel = false }
			end
		end
	end
	local out = MT.fromSpec(spec)
	-- sharp rims where the caps meet the pipe, smooth along it
	for e in pairs(out.edges) do
		local fs = BMesh.edgeFaces(e)
		if #fs == 2 and (fs[1].smooth == nil) ~= (fs[2].smooth == nil) then e.sharp = true end
	end
	pcall(MT.recalcNormals, out)
	return out
end

-- ===== Triangulate =====
function Mods.triangulate(bm, m)
	local out = copy(bm)
	local fs = {}
	for f in pairs(out.faces) do if f.len > 3 then fs[f] = true end end
	if not next(fs) then return bm end
	MT.triangulate(out, fs)
	return out
end

-- ===== Decimate, Planar (MOD_decimate.cc -> limited dissolve): join faces that are flatter than `angle` =====
function Mods.decimate(bm, m)
	-- (older saves have no mode: they were Planar)
	if m.mode == "Collapse" then return Mods.collapse(bm, m.ratio) end
	local out = copy(bm)
	local ang = math.rad(math.clamp(m.angle or 5, 0, 180))
	local lim = math.cos(ang)
	local any = false
	-- dissolving can leave two faces sharing two edges (which can't join yet): straighten, then go again
	for _ = 1, 32 do
		local es = {}
		for e in pairs(out.edges) do
			if BMesh.edgeFaceCount(e) == 2 then
				local f = BMesh.edgeFaces(e)
				if f[1] ~= f[2] and f[1].no:Dot(f[2].no) >= lim then es[e] = true end
			end
		end
		local n = next(es) and MT.dissolveEdges(out, es) or 0
		-- the verts left in the middle of straight edges
		local vs = {}
		for v in pairs(out.verts) do
			local ed = BMesh.vertEdges(v)
			if #ed == 2 then
				local a = BMesh.otherVert(ed[1], v).co - v.co
				local b = BMesh.otherVert(ed[2], v).co - v.co
				if a.Magnitude > 1e-9 and b.Magnitude > 1e-9 and a.Unit:Dot(b.Unit) < -lim then vs[v] = true end
				-- or both its edges lie between the same two faces (a corner inside a region that is being joined)
				local f1, f2 = BMesh.edgeFaces(ed[1]), BMesh.edgeFaces(ed[2])
				if #f1 == 2 and #f2 == 2 and ((f1[1] == f2[1] and f1[2] == f2[2]) or (f1[1] == f2[2] and f1[2] == f2[1]))
					and f1[1].no:Dot(f1[2].no) >= lim then vs[v] = true end
			end
		end
		local d = false
		if next(vs) then
			local ok, nb = MT.dissolveDeg2(out, vs)
			if ok and nb then out, d = nb, true end
		end
		if n == 0 and not d then break end
		any = true
		out:normalsUpdate()
	end
	if not any then return bm end
	return out
end

-- ===== Screw (MOD_screw.cc): sweep the mesh's open edges round an axis through the origin =====
function Mods.screw(bm, m)
	local axis = AXES[m.axis or "Y"] or AXES.Y
	local steps = math.clamp(math.floor(m.steps or 16), 1, 256)
	local ang = math.rad(m.angle or 360)
	local screw = m.screw or 0
	local spec = MT.toSpec(bm)
	local profile = {}
	for e in pairs(bm.edges) do
		if BMesh.edgeFaceCount(e) < 2 then profile[#profile + 1] = { spec.vi[e.v1], spec.vi[e.v2] } end
	end
	if #profile == 0 then return bm end
	local closed = math.abs(math.abs(ang) - 2 * math.pi) < 1e-4 and math.abs(screw) < 1e-6
	local rings = steps + (closed and 0 or 1)
	local ring = { [0] = {} }
	local used = {}
	for _, pe in ipairs(profile) do used[pe[1]] = true used[pe[2]] = true end
	for k in pairs(used) do ring[0][k] = k end
	for s = 1, rings - 1 do
		ring[s] = {}
		local cf = CFrame.fromAxisAngle(axis, ang * s / steps)
		for k in pairs(used) do
			local co = spec.verts[k].co
			local d = co:Dot(axis)
			if (co - axis * d).Magnitude < 1e-6 and math.abs(screw) < 1e-6 then
				ring[s][k] = k -- on the axis: one shared vert
			else
				ring[s][k] = MT.addVert(spec, cf * co + axis * (screw * s / steps), false)
			end
		end
	end
	for s = 0, steps - 1 do
		local a, b = ring[s], ring[(s + 1) % rings]
		for _, pe in ipairs(profile) do
			spec.faces[#spec.faces + 1] = { v = { a[pe[1]], a[pe[2]], b[pe[2]], b[pe[1]] }, sel = false }
		end
	end
	local out = MT.fromSpec(spec)
	-- make the new surface face outwards
	pcall(MT.recalcNormals, out)
	return out
end

-- ===== Simple Deform (MOD_simpledeform.cc): Twist / Bend round the axis, Taper / Stretch along it =====
function Mods.simpledeform(bm, m)
	local name = m.axis or "Y"
	local a = AXES[name] or AXES.Y
	local u, w = PERP[name][1], PERP[name][2]
	local lo, hi = bounds(bm)
	if not lo then return bm end
	local c = (lo + hi) / 2
	local method = m.method or "Twist"
	local out = copy(bm)
	local ext = hi - lo
	if method == "Twist" then
		local f = math.rad(m.angle or 45) / math.max(ext:Dot(a), 1e-6)
		for v in pairs(out.verts) do
			local p = v.co - c
			local x, y, z = p:Dot(u), p:Dot(w), p:Dot(a)
			local th = z * f
			local ct, st = math.cos(th), math.sin(th)
			v.co = c + u * (x * ct - y * st) + w * (x * st + y * ct) + a * z
		end
	elseif method == "Bend" then
		local f = math.rad(m.angle or 45) / math.max(ext:Dot(u), 1e-6)
		if math.abs(f) < 1e-7 then return bm end
		for v in pairs(out.verts) do
			local p = v.co - c
			local x, y, z = p:Dot(u), p:Dot(w), p:Dot(a)
			local th = x * f
			local ct, st = math.cos(th), math.sin(th)
			v.co = c + u * (-(y - 1 / f) * st) + w * ((y - 1 / f) * ct + 1 / f) + a * z
		end
	else
		local half = math.max(ext:Dot(a) / 2, 1e-6)
		local fac = m.factor or 0.5
		for v in pairs(out.verts) do
			local p = v.co - c
			local x, y, z = p:Dot(u), p:Dot(w), p:Dot(a)
			local zn = z / half -- -1 .. 1 along the axis
			if method == "Taper" then
				local s = 1 + zn * fac
				v.co = c + u * (x * s) + w * (y * s) + a * z
			else -- Stretch: longer along the axis, thinner in the middle (keeps the volume roughly)
				local s = zn * zn * fac - fac + 1
				v.co = c + u * (x * s) + w * (y * s) + a * (z * (1 + fac))
			end
		end
	end
	return out
end

-- ===== Cast (MOD_cast.cc, sphere): pull every vert towards a sphere round the middle =====
function Mods.cast(bm, m)
	local lo, hi = bounds(bm)
	if not lo then return bm end
	local c = (lo + hi) / 2
	local out = copy(bm)
	local r, n = 0, 0
	for v in pairs(out.verts) do r += (v.co - c).Magnitude n += 1 end
	r /= n
	local fac = m.factor or 0.5
	for v in pairs(out.verts) do
		local d = v.co - c
		if d.Magnitude > 1e-9 then v.co = c + d:Lerp(d.Unit * r, fac) end
	end
	return out
end

-- ===== Wave (MOD_wave.cc): ripples up the object's Y, out from the middle (radial) or along X =====
function Mods.wave(bm, m)
	local lo, hi = bounds(bm)
	if not lo then return bm end
	local c = (lo + hi) / 2
	local out = copy(bm)
	local h, wl, off = m.height or 0.5, math.max(m.width or 1.5, 1e-3), m.offset or 0
	for v in pairs(out.verts) do
		local d = v.co - c
		local dist = m.radial ~= false and math.sqrt(d.X * d.X + d.Z * d.Z) or d.X
		v.co += V3(0, h * math.sin((dist - off) / wl * 2 * math.pi), 0)
	end
	return out
end

-- ===== Displace (MOD_displace.cc): push each vert along its normal by a noise texture =====
function Mods.displace(bm, m)
	local out = copy(bm)
	local size = math.max(m.size or 1, 1e-3)
	local seed = (m.seed or 0) * 7.31 + 0.5
	local moves = {}
	for v in pairs(out.verts) do
		local p = v.co / size
		local n = math.noise(p.X + seed, p.Y + seed * 0.37, p.Z - seed * 0.71)
		moves[v] = MT.vertNormal(v) * (n * 2 * (m.strength or 0.3))
	end
	for v, d in pairs(moves) do v.co += d end
	return out
end

-- run the whole stack (on = false ones are skipped); returns a new mesh, or `bm` itself when nothing ran
-- env (from the plugin): what modifiers that use another part can see -
--   env.target(name) -> that part's mesh in this mesh's space (or nil), env.Boolean, env.triangulate
function Mods.evaluate(bm, list, env)
	if not list or #list == 0 then return bm end
	local out = bm
	for _, m in ipairs(list) do
		if m.on ~= false and Mods[m.type] then
			local ok, res = pcall(Mods[m.type], out, m, env)
			if ok and res then out = res end
		end
	end
	if out ~= bm then out:normalsUpdate() end
	return out
end
-- ===== Boolean (MOD_boolean.cc): cut by / join with / trim to another part, kept live =====
function Mods.boolean(bm, m, env)
	if not (env and env.target and env.Boolean) then return nil end
	local t = env.target(m.target)
	if not t then return nil end
	local op = tostring(m.operation or "Difference"):lower()
	return (env.Boolean.run(bm, t, op, { BMesh = BMesh, triangulate = env.triangulate }))
end
-- ===== Decimate > Collapse (bmesh_decimate_collapse.cc): quadric error edge collapse, cut down.
-- Every point remembers the planes of the triangles round it (a quadric); the edge whose collapse moves
-- the surface least goes first, until only `ratio` of the triangles are left. Open edges are held in place.
function Mods.collapse(bm, ratio)
	ratio = math.clamp(ratio or 0.5, 0.01, 1)
	local pos, col, vid = {}, {}, {}
	for v in pairs(bm.verts) do
		if v.e then pos[#pos + 1] = v.co col[#pos] = v.col vid[v] = #pos end
	end
	local tris, smoothOf = {}, {}
	for f in pairs(bm.faces) do
		local vs = BMesh.faceVerts(f)
		for i = 2, #vs - 1 do
			tris[#tris + 1] = { vid[vs[1]], vid[vs[i]], vid[vs[i + 1]] }
			smoothOf[#tris] = f.smooth
		end
	end
	local nT = #tris
	local target = math.max(4, math.floor(nT * ratio + 0.5))
	if nT <= target then return nil end
	local Q, vt, stamp, dead = {}, {}, {}, {}
	for i = 1, #pos do Q[i] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } vt[i] = {} stamp[i] = 0 end
	local function addPlane(q, a, b, c, d, w)
		q[1] += w * a * a q[2] += w * a * b q[3] += w * a * c q[4] += w * a * d
		q[5] += w * b * b q[6] += w * b * c q[7] += w * b * d
		q[8] += w * c * c q[9] += w * c * d q[10] += w * d * d
	end
	local function ek(a, b) if a < b then return a .. ":" .. b end return b .. ":" .. a end
	local edgeCount = {}
	for t, tr in ipairs(tris) do
		local p1, p2, p3 = pos[tr[1]], pos[tr[2]], pos[tr[3]]
		local n = (p2 - p1):Cross(p3 - p1)
		local area = n.Magnitude
		if area > 1e-12 then
			n = n / area
			for _, k in ipairs(tr) do addPlane(Q[k], n.X, n.Y, n.Z, -n:Dot(p1), area) end
		end
		for _, k in ipairs(tr) do vt[k][t] = true end
		for j = 1, 3 do local key = ek(tr[j], tr[j % 3 + 1]) edgeCount[key] = (edgeCount[key] or 0) + 1 end
	end
	-- open edges: a steep plane through each keeps the outline where it is
	for _, tr in ipairs(tris) do
		local p1, p2, p3 = pos[tr[1]], pos[tr[2]], pos[tr[3]]
		local fn = (p2 - p1):Cross(p3 - p1)
		for j = 1, 3 do
			local a, b = tr[j], tr[j % 3 + 1]
			if edgeCount[ek(a, b)] == 1 then
				local e = pos[b] - pos[a]
				local n = e:Cross(fn)
				if n.Magnitude > 1e-12 then
					n = n.Unit
					local w = e:Dot(e) * 1000
					addPlane(Q[a], n.X, n.Y, n.Z, -n:Dot(pos[a]), w)
					addPlane(Q[b], n.X, n.Y, n.Z, -n:Dot(pos[a]), w)
				end
			end
		end
	end
	local function err(q, p)
		local x, y, z = p.X, p.Y, p.Z
		return q[1] * x * x + 2 * q[2] * x * y + 2 * q[3] * x * z + 2 * q[4] * x + q[5] * y * y + 2 * q[6] * y * z + 2 * q[7] * y + q[8] * z * z + 2 * q[9] * z + q[10]
	end
	local function sumQ(a, b) local s = {} for i = 1, 10 do s[i] = a[i] + b[i] end return s end
	-- the best place for the merged point: the quadric's minimum (if it's well defined and near), else an end or the middle
	local function place(q, pa, pb)
		local a, b, c, d, e, f = q[1], q[2], q[3], q[5], q[6], q[8]
		local A11, A12, A13 = d * f - e * e, c * e - b * f, b * e - d * c
		local A22, A23, A33 = a * f - c * c, b * c - a * e, a * d - b * b
		local det = a * A11 + b * A12 + c * A13
		if math.abs(det) > 1e-9 then
			local r1, r2, r3 = -q[4], -q[7], -q[9]
			local p = V3((A11 * r1 + A12 * r2 + A13 * r3) / det, (A12 * r1 + A22 * r2 + A23 * r3) / det, (A13 * r1 + A23 * r2 + A33 * r3) / det)
			if (p - (pa + pb) / 2).Magnitude <= (pb - pa).Magnitude * 1.5 + 1e-6 then return p, err(q, p) end
		end
		local best, be = pa, err(q, pa)
		for _, cand in ipairs({ pb, (pa + pb) / 2 }) do local ee = err(q, cand) if ee < be then best, be = cand, ee end end
		return best, be
	end
	-- a small binary heap of { cost, a, b, stampA, stampB }
	local heap = {}
	local function push(x)
		heap[#heap + 1] = x
		local i = #heap
		while i > 1 do
			local p = i // 2
			if heap[p][1] <= heap[i][1] then break end
			heap[p], heap[i] = heap[i], heap[p]
			i = p
		end
	end
	local function pop()
		local top = heap[1]
		local last = table.remove(heap)
		if #heap > 0 then
			heap[1] = last
			local i = 1
			while true do
				local l, r, m = 2 * i, 2 * i + 1, i
				if l <= #heap and heap[l][1] < heap[m][1] then m = l end
				if r <= #heap and heap[r][1] < heap[m][1] then m = r end
				if m == i then break end
				heap[m], heap[i] = heap[i], heap[m]
				i = m
			end
		end
		return top
	end
	local function pushEdge(a, b)
		local _, cost = place(sumQ(Q[a], Q[b]), pos[a], pos[b])
		push({ cost, a, b, stamp[a], stamp[b] })
	end
	for key in pairs(edgeCount) do
		local a, b = key:match("(%d+):(%d+)")
		pushEdge(tonumber(a), tonumber(b))
	end
	local live = nT
	local deadTri = {}
	local function neighbours(v)
		local s = {}
		for t in pairs(vt[v]) do for _, k in ipairs(tris[t]) do if k ~= v then s[k] = true end end end
		return s
	end
	while live > target and #heap > 0 do
		local it = pop()
		local a, b = it[2], it[3]
		if not dead[a] and not dead[b] and it[4] == stamp[a] and it[5] == stamp[b] then
			local q = sumQ(Q[a], Q[b])
			local p = place(q, pos[a], pos[b])
			-- link condition: the two ends may only share the points across their shared triangles
			local na, nb = neighbours(a), neighbours(b)
			local shared, both = 0, 0
			for k in pairs(na) do if nb[k] then shared += 1 end end
			for t in pairs(vt[a]) do if vt[b][t] then both += 1 end end
			local ok = shared <= both
			-- no triangle may flip over
			if ok then
				for _, v in ipairs({ a, b }) do
					for t in pairs(vt[v]) do
						if not (vt[a][t] and vt[b][t]) then
							local tr = tris[t]
							local p1, p2, p3 = pos[tr[1]], pos[tr[2]], pos[tr[3]]
							local n0 = (p2 - p1):Cross(p3 - p1)
							local q1 = (tr[1] == a or tr[1] == b) and p or p1
							local q2 = (tr[2] == a or tr[2] == b) and p or p2
							local q3 = (tr[3] == a or tr[3] == b) and p or p3
							local n1 = (q2 - q1):Cross(q3 - q1)
							if n1.Magnitude < 1e-12 or n0:Dot(n1) < 0.2 * n0.Magnitude * n1.Magnitude then ok = false break end
						end
					end
					if not ok then break end
				end
			end
			if ok then
				pos[a], Q[a] = p, q
				for t in pairs(vt[b]) do
					local tr = tris[t]
					if vt[a][t] then
						deadTri[t] = true
						live -= 1
						for _, k in ipairs(tr) do vt[k][t] = nil end
					else
						for j = 1, 3 do if tr[j] == b then tr[j] = a end end
						vt[a][t] = true
					end
				end
				vt[b] = {}
				dead[b] = true
				stamp[a] += 1
				for k in pairs(neighbours(a)) do pushEdge(a, k) end
			end
		end
	end
	local out = BMesh.new()
	local nvs = {}
	local function nv(k)
		if not nvs[k] then nvs[k] = out:vertCreate(pos[k]) nvs[k].col = col[k] end
		return nvs[k]
	end
	for t, tr in ipairs(tris) do
		if not deadTri[t] then
			local f = out:faceCreate({ nv(tr[1]), nv(tr[2]), nv(tr[3]) })
			if f and smoothOf[t] then f.smooth = true end
		end
	end
	out:normalsUpdate()
	return out
end

-- ===== Edge Split (MOD_edgesplit.cc): faces come apart along sharp edges (by angle and / or marked Sharp)
function Mods.edgesplit(bm, m)
	local lim = math.cos(math.rad(math.clamp(m.angle or 30, 0, 180)))
	local useAngle, useSharp = m.useAngle ~= false, m.sharp ~= false
	local split = {}
	local any = false
	for e in pairs(bm.edges) do
		local fs = BMesh.edgeFaces(e)
		if #fs > 2 or (#fs == 2 and ((useSharp and e.sharp) or (useAngle and fs[1].no:Dot(fs[2].no) < lim))) then split[e] = true any = true end
	end
	if not any then return nil end
	local out = BMesh.new()
	local newOf = {}
	for v in pairs(bm.verts) do
		local fs = BMesh.vertFaces(v)
		local map = {}
		newOf[v] = map
		if #fs == 0 then
			map.loose = out:vertCreate(v.co)
			map.loose.col = v.col
		else
			local parent = {}
			local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]] x = parent[x] end return x end
			for _, f in ipairs(fs) do parent[f] = f end
			for _, e in ipairs(BMesh.vertEdges(v)) do
				if not split[e] then
					local ef = BMesh.edgeFaces(e)
					if #ef == 2 then local a, b = find(ef[1]), find(ef[2]) if a ~= b then parent[a] = b end end
				end
			end
			local made = {}
			for _, f in ipairs(fs) do
				local r = find(f)
				if not made[r] then made[r] = out:vertCreate(v.co) made[r].col = v.col end
				map[f] = made[r]
			end
		end
	end
	for f in pairs(bm.faces) do
		local ls = BMesh.faceLoops(f)
		local list = {}
		for i, l in ipairs(ls) do list[i] = newOf[l.v][f] end
		local nf = out:faceCreate(list)
		if nf then
			nf.smooth, nf.sel = f.smooth, f.sel
			local nls = BMesh.faceLoops(nf)
			for i, l in ipairs(ls) do if l.uv and nls[i] then nls[i].uv = l.uv end end
		end
	end
	for e in pairs(bm.edges) do
		if not e.l then
			local a = newOf[e.v1].loose or select(2, next(newOf[e.v1]))
			local b = newOf[e.v2].loose or select(2, next(newOf[e.v2]))
			if a and b and a ~= b then out:edgeCreate(a, b, true) end
		end
	end
	out:normalsUpdate()
	return out
end

-- ===== Shrinkwrap (MOD_shrinkwrap.cc, cut down): the mesh's points move onto another part's surface
-- modes: "Nearest Surface Point", "Nearest Vertex", "Project" (along each point's normal, both ways)
local function closestOnTri(p, a, b, c)
	-- Ericson, Real-Time Collision Detection 5.1.5
	local ab, ac, ap = b - a, c - a, p - a
	local d1, d2 = ab:Dot(ap), ac:Dot(ap)
	if d1 <= 0 and d2 <= 0 then return a end
	local bp = p - b
	local d3, d4 = ab:Dot(bp), ac:Dot(bp)
	if d3 >= 0 and d4 <= d3 then return b end
	local vc = d1 * d4 - d3 * d2
	if vc <= 0 and d1 >= 0 and d3 <= 0 then return a + ab * (d1 / (d1 - d3)) end
	local cp = p - c
	local d5, d6 = ab:Dot(cp), ac:Dot(cp)
	if d6 >= 0 and d5 <= d6 then return c end
	local vb = d5 * d2 - d1 * d6
	if vb <= 0 and d2 >= 0 and d6 <= 0 then return a + ac * (d2 / (d2 - d6)) end
	local va = d3 * d6 - d5 * d4
	if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0 then return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))) end
	local denom = 1 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)
end
Mods.closestOnTri = closestOnTri
function Mods.shrinkwrap(bm, m, env)
	if not (env and env.target) then return nil end
	local t = env.target(m.target)
	if not t then return nil end
	local tris = {}
	for f in pairs(t.faces) do
		local vs = BMesh.faceVerts(f)
		for i = 2, #vs - 1 do tris[#tris + 1] = { vs[1].co, vs[i].co, vs[i + 1].co, f.no } end
	end
	if #tris == 0 then return nil end
	local out = copy(bm)
	local mode = m.mode or "Nearest Surface Point"
	local offset = m.offset or 0
	if mode == "Nearest Vertex" then
		local pts = {}
		for v in pairs(t.verts) do pts[#pts + 1] = v.co end
		for v in pairs(out.verts) do
			local best, bd = nil, math.huge
			for _, q in ipairs(pts) do local d = (q - v.co).Magnitude if d < bd then best, bd = q, d end end
			if best then
				local dir = v.co - best
				v.co = best + (dir.Magnitude > 1e-9 and dir.Unit * offset or V3())
			end
		end
	elseif mode == "Project" then
		local normals = {}
		for v in pairs(out.verts) do normals[v] = MT.vertNormal(v) end
		for v in pairs(out.verts) do
			local n = normals[v]
			local best, bt = nil, math.huge
			for _, tr in ipairs(tris) do
				-- Moller-Trumbore, both directions along the normal
				local e1, e2 = tr[2] - tr[1], tr[3] - tr[1]
				local h = n:Cross(e2)
				local a = e1:Dot(h)
				if math.abs(a) > 1e-12 then
					local f = 1 / a
					local s = v.co - tr[1]
					local u = f * s:Dot(h)
					if u >= 0 and u <= 1 then
						local q = s:Cross(e1)
						local w = f * n:Dot(q)
						if w >= 0 and u + w <= 1 then
							local tt = f * e2:Dot(q)
							if math.abs(tt) < math.abs(bt) then best, bt = tr, tt end
						end
					end
				end
			end
			if best then v.co = v.co + n * bt + best[4] * offset end
		end
	else
		-- nearest point on the surface, with a grid of the target's triangles so it stays quick
		local lo, hi = tris[1][1], tris[1][1]
		for _, tr in ipairs(tris) do for j = 1, 3 do lo = lo:Min(tr[j]) hi = hi:Max(tr[j]) end end
		local span = hi - lo
		local cells = math.clamp(math.floor((#tris) ^ (1 / 3)) + 1, 1, 24)
		local cs = math.max(span.X, span.Y, span.Z, 1e-3) / cells
		local grid = {}
		local function cellOf(p) return math.floor((p.X - lo.X) / cs), math.floor((p.Y - lo.Y) / cs), math.floor((p.Z - lo.Z) / cs) end
		for _, tr in ipairs(tris) do
			local a, b, c = tr[1], tr[2], tr[3]
			local x0, y0, z0 = cellOf(a:Min(b):Min(c))
			local x1, y1, z1 = cellOf(a:Max(b):Max(c))
			for x = x0, x1 do for y = y0, y1 do for z = z0, z1 do
				local k = x .. "," .. y .. "," .. z
				local l = grid[k]
				if l then l[#l + 1] = tr else grid[k] = { tr } end
			end end end
		end
		local maxR = cells + 2
		for v in pairs(out.verts) do
			local p = v.co
			local cp = p:Max(lo):Min(hi)
			local outside = (p - cp).Magnitude
			local cx, cy, cz = cellOf(cp)
			local best, bd, bn = nil, math.huge, nil
			local seen = {}
			for r = 0, maxR do
				for x = cx - r, cx + r do for y = cy - r, cy + r do for z = cz - r, cz + r do
					if math.max(math.abs(x - cx), math.abs(y - cy), math.abs(z - cz)) == r then
						local l = grid[x .. "," .. y .. "," .. z]
						if l then
							for _, tr in ipairs(l) do
								if not seen[tr] then
									seen[tr] = true
									local q = closestOnTri(p, tr[1], tr[2], tr[3])
									local d = (q - p).Magnitude
									if d < bd then best, bd, bn = q, d, tr[4] end
								end
							end
						end
					end
				end end end
				if best and bd <= r * cs + outside then break end
			end
			if best then v.co = best + bn * offset end
		end
	end
	out:normalsUpdate()
	return out
end

function Mods.active(list)
	for _, m in ipairs(list or {}) do if m.on ~= false then return true end end
	return false
end

-- ===== merge doubles keeping the selection (Auto Merge after a move) =====
function Mods.mergeDoubles(bm, dist)
	dist = dist or 0.001
	local spec = MT.toSpec(bm)
	local cell = {}
	local function key(co, dx, dy, dz)
		return (math.floor(co.X / dist) + dx) .. "," .. (math.floor(co.Y / dist) + dy) .. "," .. (math.floor(co.Z / dist) + dz)
	end
	local map, merged = {}, 0
	for i, sv in ipairs(spec.verts) do
		local hit
		for dx = -1, 1 do
			for dy = -1, 1 do
				for dz = -1, 1 do
					for _, j in ipairs(cell[key(sv.co, dx, dy, dz)] or {}) do
						if not hit and (spec.verts[j].co - sv.co).Magnitude <= dist then hit = j end
					end
				end
			end
		end
		if hit then
			map[i] = hit
			spec.verts[hit].sel = spec.verts[hit].sel or sv.sel
			merged += 1
		else
			map[i] = i
			local k = key(sv.co, 0, 0, 0)
			cell[k] = cell[k] or {}
			table.insert(cell[k], i)
		end
	end
	if merged == 0 then return bm, 0 end
	for _, f in ipairs(spec.faces) do for j, k in ipairs(f.v) do f.v[j] = map[k] end end
	for _, e in ipairs(spec.edges) do e[1], e[2] = map[e[1]], map[e[2]] end
	local new = {}
	for k, fl in pairs(spec.eflags) do
		local a, b = k:match("(%d+):(%d+)")
		a, b = map[tonumber(a)], map[tonumber(b)]
		new[math.min(a, b) .. ":" .. math.max(a, b)] = fl
	end
	spec.eflags = new
	for i in pairs(map) do if map[i] ~= i then spec.verts[i].dead = true spec.verts[i].loose = false end end
	return (MT.fromSpec(spec)), merged
end

return Mods
