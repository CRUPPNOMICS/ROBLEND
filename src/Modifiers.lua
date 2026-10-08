--[[
	ROBLENDER - modifiers: a non-destructive stack on each mesh (Blender's Properties > Modifiers)
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
	Original: Copyright (C) Blender Authors (GPL-2.0-or-later)
	Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27) - GPL-2.0-or-later.

	The base mesh is never changed: evaluate() works on a copy. The list is stored on the part as JSON
	(StringValue RB_Mods): { {type = "mirror", on = true, ...settings}, ... }
]]

local BMesh = require(script.Parent.BMesh)
local MT = require(script.Parent.MeshTools)
local Mods = {}
local V3 = Vector3.new

-- types, Blender's names, default settings (in Blender's Add Modifier menu order)
Mods.TYPES = {
	{ id = "array", name = "Array", group = "Generate", defaults = { count = 3, axis = "X", relative = 1 } },
	{ id = "bevel", name = "Bevel", group = "Generate", defaults = { amount = 0.2, segments = 2, angle = 30 } },
	{ id = "mirror", name = "Mirror", group = "Generate", defaults = { x = true, y = false, z = false, merge = true, mergeDist = 0.001 } },
	{ id = "solidify", name = "Solidify", group = "Generate", defaults = { thickness = 0.2, offset = -1 } },
	{ id = "decimate", name = "Decimate", group = "Generate", defaults = { angle = 5 } },
	{ id = "screw", name = "Screw", group = "Generate", defaults = { angle = 360, steps = 16, screw = 0, axis = "Y" } },
	{ id = "subsurf", name = "Subdivision Surface", group = "Generate", defaults = { levels = 1 } },
	{ id = "triangulate", name = "Triangulate", group = "Generate", defaults = {} },
	{ id = "weld", name = "Weld", group = "Generate", defaults = { distance = 0.01 } },
	{ id = "cast", name = "Cast", group = "Deform", defaults = { factor = 0.5 } },
	{ id = "displace", name = "Displace", group = "Deform", defaults = { strength = 0.3, size = 1, seed = 0 } },
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
local function mirrorAxis(bm, axis, merge, dist)
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
		if m[a[1]] then out = mirrorAxis(out, a[2], m.merge ~= false, math.max(m.mergeDist or 0.001, 1e-5)) end
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
		if #fs == 2 then co = (e.v1.co + e.v2.co + spec.verts[fp[fs[1]]].co + spec.verts[fp[fs[2]]].co) / 4
		else co = (e.v1.co + e.v2.co) / 2 end
		ep[e] = add(co, e.sel)
	end
	for v in pairs(bm.verts) do
		local edges = BMesh.vertEdges(v)
		local border = {}
		for _, e in ipairs(edges) do if BMesh.edgeFaceCount(e) < 2 then border[#border + 1] = e end end
		local co
		if #border >= 2 then
			local b1, b2 = BMesh.otherVert(border[1], v).co, BMesh.otherVert(border[2], v).co
			co = (b1 + b2 + v.co * 6) / 8
		elseif #border == 1 or #edges < 3 then
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
	local step = axis * ((hi - lo):Dot(axis) * (m.relative or 1))
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
	return (MT.fromSpec(spec))
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
function Mods.evaluate(bm, list)
	if not list or #list == 0 then return bm end
	local out = bm
	for _, m in ipairs(list) do
		if m.on ~= false and Mods[m.type] then
			local ok, res = pcall(Mods[m.type], out, m)
			if ok and res then out = res end
		end
	end
	if out ~= bm then out:normalsUpdate() end
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
