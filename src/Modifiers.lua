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
	{ id = "subsurf", name = "Subdivision Surface", group = "Generate", defaults = { levels = 1 } },
	{ id = "smooth", name = "Smooth", group = "Deform", defaults = { factor = 0.5, ["repeat"] = 1 } },
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
