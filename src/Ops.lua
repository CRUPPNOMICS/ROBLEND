--[[
	ROBLENDER - mesh operators
	SPDX-License-Identifier: GPL-2.0-or-later

	Converted to Luau (and cut down) from Blender's BMesh operators:
	  source/blender/bmesh/operators/bmo_primitive.cc  (cube, plane, grid, circle, cylinder, UV sphere)
	  source/blender/bmesh/operators/bmo_extrude.cc    (extrude face region / edges / verts)
	  source/blender/bmesh/operators/bmo_inset.cc      (inset region / individual - simplified)
	  source/blender/bmesh/operators/bmo_subdivide.cc  (edge ring + loop cut)
	  source/blender/bmesh/intern/bmesh_delete.cc      (delete verts / edges / faces)
	Original: Copyright (C) Blender Authors (GPL-2.0-or-later)
	Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27) - GPL-2.0-or-later.

	Sets are plain tables used as { [element] = true }.
]]

local BMesh = require(script.Parent.BMesh)
local Ops = {}
local V3 = Vector3.new
local PI = math.pi

-- ===== primitives (bmo_primitive.cc) - Roblox: Y is up, faces wind anticlockwise seen from outside =====
function Ops.cube(bm, s)
	local h = (s or 4) / 2
	local p = {}
	for i, c in ipairs({
		{ -1, -1, -1 }, { 1, -1, -1 }, { 1, 1, -1 }, { -1, 1, -1 },
		{ -1, -1, 1 }, { 1, -1, 1 }, { 1, 1, 1 }, { -1, 1, 1 },
	}) do p[i] = bm:vertCreate(V3(c[1] * h, c[2] * h, c[3] * h)) end
	local out = {}
	for _, q in ipairs({
		{ 1, 4, 3, 2 }, -- -Z
		{ 5, 6, 7, 8 }, -- +Z
		{ 1, 2, 6, 5 }, -- -Y
		{ 4, 8, 7, 3 }, -- +Y
		{ 1, 5, 8, 4 }, -- -X
		{ 2, 3, 7, 6 }, -- +X
	}) do out[#out + 1] = bm:faceCreate({ p[q[1]], p[q[2]], p[q[3]], p[q[4]] }) end
	return out
end

function Ops.plane(bm, s)
	local h = (s or 4) / 2
	local a, b, c, d = bm:vertCreate(V3(-h, 0, -h)), bm:vertCreate(V3(-h, 0, h)), bm:vertCreate(V3(h, 0, h)), bm:vertCreate(V3(h, 0, -h))
	return { bm:faceCreate({ a, b, c, d }) }   -- facing up
end

function Ops.grid(bm, nx, nz, s)
	nx, nz = math.max(1, nx or 4), math.max(1, nz or 4)
	local h = (s or 4) / 2
	local g = {}
	for i = 0, nx do
		g[i] = {}
		for j = 0, nz do g[i][j] = bm:vertCreate(V3(-h + 2 * h * i / nx, 0, -h + 2 * h * j / nz)) end
	end
	local out = {}
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do out[#out + 1] = bm:faceCreate({ g[i][j], g[i][j + 1], g[i + 1][j + 1], g[i + 1][j] }) end
	end
	return out
end

-- a ring of verts round the Y axis at height y
local function ring(bm, segs, r, y)
	local out = {}
	for i = 0, segs - 1 do
		local a = 2 * PI * i / segs
		out[i + 1] = bm:vertCreate(V3(math.cos(a) * r, y, math.sin(a) * r))
	end
	return out
end

function Ops.circle(bm, segs, r, fill)
	segs = math.max(3, segs or 32)
	local rv = ring(bm, segs, r or 2, 0)
	if fill ~= false then
		local rev = {}
		for i = segs, 1, -1 do rev[#rev + 1] = rv[i] end
		return { bm:faceCreate(rev) }   -- facing up
	end
	for i = 1, segs do bm:edgeCreate(rv[i], rv[i % segs + 1]) end
	return {}
end

function Ops.cylinder(bm, segs, r, depth)
	segs = math.max(3, segs or 32)
	r, depth = r or 2, depth or 4
	local lo, hi = ring(bm, segs, r, -depth / 2), ring(bm, segs, r, depth / 2)
	local out = {}
	for i = 1, segs do
		local j = i % segs + 1
		out[#out + 1] = bm:faceCreate({ lo[i], hi[i], hi[j], lo[j] })
	end
	local top, bot = {}, {}
	for i = segs, 1, -1 do top[#top + 1] = hi[i] end
	for i = 1, segs do bot[#bot + 1] = lo[i] end
	out[#out + 1] = bm:faceCreate(top)
	out[#out + 1] = bm:faceCreate(bot)
	return out
end

function Ops.uvSphere(bm, segs, rings, r)
	segs, rings, r = math.max(3, segs or 32), math.max(2, rings or 16), r or 2
	local top, bot = bm:vertCreate(V3(0, r, 0)), bm:vertCreate(V3(0, -r, 0))
	local rows = {}
	for k = 1, rings - 1 do
		local phi = PI * k / rings
		rows[k] = ring(bm, segs, r * math.sin(phi), r * math.cos(phi))
	end
	local out = {}
	for i = 1, segs do
		local j = i % segs + 1
		out[#out + 1] = bm:faceCreate({ top, rows[1][j], rows[1][i] })
		out[#out + 1] = bm:faceCreate({ bot, rows[rings - 1][i], rows[rings - 1][j] })
		for k = 1, rings - 2 do
			out[#out + 1] = bm:faceCreate({ rows[k][i], rows[k][j], rows[k + 1][j], rows[k + 1][i] })
		end
	end
	return out
end

-- ===== extrude (bmo_extrude.cc) =====
-- face region: the faces are copied onto new verts, side walls fill every edge on the region's border,
-- the old faces go (and any edge / vert they leave with nothing). Returns new verts, new faces.
function Ops.extrudeFaceRegion(bm, faceSet)
	local vmap = {}
	local newVerts, newFaces = {}, {}
	local regionVerts = {}
	for f in pairs(faceSet) do
		for _, v in ipairs(BMesh.faceVerts(f)) do
			if not vmap[v] then
				local nv = bm:vertCreate(v.co)
				vmap[v] = nv
				newVerts[nv] = true
				regionVerts[v] = true
			end
		end
	end
	-- border edges: used by exactly one region face (or by a region face and faces outside it)
	local sides = {}
	for f in pairs(faceSet) do
		for _, l in ipairs(BMesh.faceLoops(f)) do
			local inside = 0
			for _, g in ipairs(BMesh.edgeFaces(l.e)) do if faceSet[g] then inside += 1 end end
			if inside == 1 then sides[#sides + 1] = { a = l.v, b = l.next.v, f = f } end
		end
	end
	-- the copied faces (same winding)
	for f in pairs(faceSet) do
		local list = {}
		for i, v in ipairs(BMesh.faceVerts(f)) do list[i] = vmap[v] end
		local nf = bm:faceCreate(list, f)
		if nf then newFaces[nf] = true end
	end
	-- side walls: (a, b, b', a') points outward when the face winds a -> b
	for _, s in ipairs(sides) do
		bm:faceCreate({ s.a, s.b, vmap[s.b], vmap[s.a] }, s.f)
	end
	-- old faces out, then anything they leave with nothing
	for f in pairs(faceSet) do bm:faceKill(f) end
	for v in pairs(regionVerts) do
		for _, e in ipairs(BMesh.vertEdges(v)) do
			if bm.edges[e] and not e.l then
				local o = BMesh.otherVert(e, v)
				if regionVerts[o] then bm:edgeKill(e) end
			end
		end
	end
	for v in pairs(regionVerts) do if bm.verts[v] and not v.e then bm:vertKill(v) end end
	return newVerts, newFaces
end

-- edges (no faces): every edge sweeps into a new quad
function Ops.extrudeEdges(bm, edgeSet)
	local vmap, newVerts, newEdges = {}, {}, {}
	local function nv(v)
		if not vmap[v] then vmap[v] = bm:vertCreate(v.co) newVerts[vmap[v]] = true end
		return vmap[v]
	end
	local list = {}
	for e in pairs(edgeSet) do list[#list + 1] = e end
	for _, e in ipairs(list) do
		local a, b = e.v1, e.v2
		-- keep the wall facing the same way as a face already on the edge
		if e.l and e.l.v == b then a, b = b, a end
		local a2, b2 = nv(a), nv(b)
		bm:faceCreate({ b, a, a2, b2 })
		local ne = BMesh.edgeExists(a2, b2)
		if ne then newEdges[ne] = true end
	end
	return newVerts, newEdges
end

-- verts: each one grows a new vert on a new edge
function Ops.extrudeVerts(bm, vertSet)
	local newVerts = {}
	local list = {}
	for v in pairs(vertSet) do list[#list + 1] = v end
	for _, v in ipairs(list) do
		local n = bm:vertCreate(v.co)
		bm:edgeCreate(v, n)
		newVerts[n] = true
	end
	return newVerts
end

-- ===== inset (bmo_inset.cc, simplified) =====
-- region: extrude with no depth, then pull every border corner in along the face, `thick` studs from each
-- border edge, and push the whole new top out by `depth` along the region's normal
function Ops.insetRegion(bm, faceSet, thick, depth)
	-- remember the border, before extrude changes things: corner -> its two border edges' inward directions
	local inward = {}
	for f in pairs(faceSet) do
		for _, l in ipairs(BMesh.faceLoops(f)) do
			local inside = 0
			for _, g in ipairs(BMesh.edgeFaces(l.e)) do if faceSet[g] then inside += 1 end end
			if inside == 1 then
				local a, b = l.v, l.next.v
				local d = b.co - a.co
				if d.Magnitude > 1e-9 then
					local inn = f.no:Cross(d).Unit   -- points into the face
					for _, v in ipairs({ a, b }) do
						inward[v] = inward[v] or {}
						table.insert(inward[v], inn)
					end
				end
			end
		end
	end
	local avgN = V3()
	for f in pairs(faceSet) do avgN += f.no end
	avgN = avgN.Magnitude > 1e-9 and avgN.Unit or V3(0, 1, 0)
	local before = {}
	for f in pairs(faceSet) do for _, v in ipairs(BMesh.faceVerts(f)) do before[v] = true end end
	local newVerts, newFaces = Ops.extrudeFaceRegion(bm, faceSet)
	-- map new verts back to the old ones by position (extrude copies them exactly)
	local byPos = {}
	for v in pairs(before) do byPos[tostring(v.co)] = v end
	for nv in pairs(newVerts) do
		local ov = byPos[tostring(nv.co)]
		local dirs = ov and inward[ov]
		local off = V3()
		if dirs and #dirs > 0 then
			local s = V3()
			for _, d in ipairs(dirs) do s += d end
			if s.Magnitude > 1e-9 then
				local u = s.Unit
				local cosA = math.max(0.25, u:Dot(dirs[1]))   -- mitre: corners go further in so every edge ends `thick` in
				off = u * (thick / cosA)
			end
		end
		nv.co = nv.co + off + avgN * (depth or 0)
	end
	bm:normalsUpdate()
	return newVerts, newFaces
end

-- individual: every face on its own
function Ops.insetIndividual(bm, faceSet, thick, depth)
	local allV, allF = {}, {}
	local list = {}
	for f in pairs(faceSet) do list[#list + 1] = f end
	for _, f in ipairs(list) do
		local nv, nf = Ops.insetRegion(bm, { [f] = true }, thick, depth)
		for v in pairs(nv) do allV[v] = true end
		for g in pairs(nf) do allF[g] = true end
	end
	return allV, allF
end

-- ===== edge ring + loop cut (bmo_subdivide.cc "subdivide_edgering", simplified) =====
-- across quads: from edge e, step over each quad to its opposite edge, both ways. Returns the ring IN ORDER
-- and the set of quads crossed.
function Ops.edgeRing(bm, e0)
	local seenE, quads = { [e0] = true }, {}
	local function walk(e, f)
		local out = {}
		while f and f.len == 4 and not quads[f] do
			local l = BMesh.faceEdgeLoop(f, e)
			if not l then break end
			quads[f] = true
			local opp = l.next.next.e
			if seenE[opp] then break end   -- came all the way round (a closed ring)
			seenE[opp] = true
			out[#out + 1] = opp
			local nf
			for _, g in ipairs(BMesh.edgeFaces(opp)) do if g ~= f then nf = g break end end
			e, f = opp, nf
		end
		return out
	end
	local fs = BMesh.edgeFaces(e0)
	local A = walk(e0, fs[1])
	local B = fs[2] and walk(e0, fs[2]) or {}
	local ring = {}
	for i = #B, 1, -1 do ring[#ring + 1] = B[i] end
	ring[#ring + 1] = e0
	for _, e in ipairs(A) do ring[#ring + 1] = e end
	return ring, quads
end

-- cut a new loop through the ring, t (0..1) along each edge from the same side all the way round
function Ops.loopCut(bm, e0, t)
	t = t or 0.5
	local ring, quads = Ops.edgeRing(bm, e0)
	if #ring == 0 then return {}, {} end
	-- which end each edge is measured from: the one joined (by a quad side) to the previous edge's start
	local from = { [ring[1]] = ring[1].v1 }
	for i = 2, #ring do
		local e, p = ring[i], from[ring[i - 1]]
		from[e] = BMesh.edgeExists(p, e.v1) and e.v1 or e.v2
	end
	local newVSet, newV = {}, {}
	for _, e in ipairs(ring) do
		local v = bm:edgeSplit(e, from[e], t)
		newVSet[v] = true
		newV[#newV + 1] = v
	end
	-- each crossed quad now has two new corners: join them
	local newEdges = {}
	for f in pairs(quads) do
		if bm.faces[f] then
			local a, b
			for _, l in ipairs(BMesh.faceLoops(f)) do
				if newVSet[l.v] then
					if not a then a = l elseif not b then b = l end
				end
			end
			if a and b and a.next ~= b and b.next ~= a then
				local _, ne = bm:faceSplit(f, a, b)
				if ne then newEdges[ne] = true end
			end
		end
	end
	return newEdges, newV
end

-- ===== edge loop (Alt+click) - the BMW_EDGELOOP walker, cut down: through 4-edge verts, straight across =====
function Ops.edgeLoop(bm, e0)
	local out, seen = { e0 }, { [e0] = true }
	local function step(e, v)
		while true do
			local es = BMesh.vertEdges(v)
			if #es ~= 4 then return end
			local myFaces = {}
			for _, f in ipairs(BMesh.edgeFaces(e)) do myFaces[f] = true end
			local nxt
			for _, c in ipairs(es) do
				if c ~= e then
					local shares = false
					for _, f in ipairs(BMesh.edgeFaces(c)) do if myFaces[f] then shares = true break end end
					if not shares then nxt = c break end
				end
			end
			if not nxt or seen[nxt] then return end
			seen[nxt] = true
			out[#out + 1] = nxt
			e, v = nxt, BMesh.otherVert(nxt, v)
		end
	end
	step(e0, e0.v2)
	step(e0, e0.v1)
	return out
end

-- ===== subdivide (simple: every picked quad -> 4, triangles / n-gons -> a fan of quads round the middle) =====
function Ops.subdivideFaces(bm, faceSet)
	local mids = {}
	local function mid(e)
		if mids[e] then return mids[e] end
		mids[e] = bm:edgeSplit(e, e.v1, 0.5)
		return mids[e]
	end
	local list = {}
	for f in pairs(faceSet) do list[#list + 1] = { f = f, vs = BMesh.faceVerts(f), es = {} } end
	for _, it in ipairs(list) do
		for _, l in ipairs(BMesh.faceLoops(it.f)) do it.es[#it.es + 1] = l.e end
	end
	local newFaces = {}
	for _, it in ipairs(list) do
		local corners, ms = it.vs, {}
		for i, e in ipairs(it.es) do ms[i] = mids[e] or mid(e) end
		local c = BMesh.faceCenter(it.f)
		local example = it.f
		bm:faceKill(it.f)
		local cv = bm:vertCreate(c)
		local n = #corners
		for i = 1, n do
			local prevMid = ms[(i - 2) % n + 1]
			local nf = bm:faceCreate({ corners[i], ms[i], cv, prevMid }, example)
			if nf then newFaces[nf] = true end
		end
	end
	return newFaces
end

-- ===== delete (bmesh_delete.cc) =====
function Ops.deleteFaces(bm, faceSet)
	for f in pairs(faceSet) do if bm.faces[f] then bm:faceKillLoose(f) end end
end
function Ops.deleteEdges(bm, edgeSet)
	for e in pairs(edgeSet) do
		if bm.edges[e] then
			local a, b = e.v1, e.v2
			bm:edgeKill(e)
			if bm.verts[a] and not a.e then bm:vertKill(a) end
			if bm.verts[b] and not b.e then bm:vertKill(b) end
		end
	end
end
function Ops.deleteVerts(bm, vertSet)
	for v in pairs(vertSet) do if bm.verts[v] then bm:vertKill(v) end end
end

-- ===== rebuild helpers: merge / flip (done by rebuilding the mesh, simple + safe) =====
-- remap: old vert -> vert it becomes (verts not in it stay); returns the new mesh + old->new vert map
function Ops.rebuild(bm, remap, flipSet)
	local data = { v = {}, f = {}, e = {} }
	local idx, n = {}, 0
	local final = {}
	for v in pairs(bm.verts) do
		local t = remap and remap[v] or v
		final[v] = t
	end
	for v in pairs(bm.verts) do
		local t = final[v]
		if not idx[t] then
			n += 1
			idx[t] = n
			local c = t.co
			table.insert(data.v, c.X) table.insert(data.v, c.Y) table.insert(data.v, c.Z)
		end
	end
	for f in pairs(bm.faces) do
		local list, prev = {}, nil
		for _, v in ipairs(BMesh.faceVerts(f)) do
			local k = idx[final[v]]
			if k ~= prev then list[#list + 1] = k prev = k end
		end
		if #list > 1 and list[1] == list[#list] then table.remove(list) end
		local uniq, ok = {}, true
		for _, k in ipairs(list) do if uniq[k] then ok = false end uniq[k] = true end
		if ok and #list >= 3 then
			if flipSet and flipSet[f] then
				local r = {}
				for i = #list, 1, -1 do r[#r + 1] = list[i] end
				list = r
			end
			data.f[#data.f + 1] = list
		end
	end
	for e in pairs(bm.edges) do
		if not e.l then
			local a, b = idx[final[e.v1]], idx[final[e.v2]]
			if a ~= b then table.insert(data.e, a) table.insert(data.e, b) end
		end
	end
	local nb = BMesh.fromData(data)
	-- old vert -> new vert
	local byIdx = {}
	local list = {}
	for v in pairs(nb.verts) do list[#list + 1] = v end
	-- fromData makes verts in data order: rebuild the index -> vert table by position match
	local pos = {}
	for v in pairs(nb.verts) do pos[tostring(v.co)] = pos[tostring(v.co)] or v end
	local map = {}
	for v in pairs(bm.verts) do map[v] = pos[tostring(final[v].co)] end
	return nb, map
end

-- merge the given verts into one at their middle (M > At Center)
function Ops.mergeAtCenter(bm, vertSet)
	local s, n, keep = V3(), 0, nil
	for v in pairs(vertSet) do s += v.co n += 1 keep = keep or v end
	if n < 2 then return bm, nil end
	keep.co = s / n
	local remap = {}
	for v in pairs(vertSet) do remap[v] = keep end
	return Ops.rebuild(bm, remap)
end

-- merge verts closer than dist (Merge by Distance / remove doubles)
function Ops.mergeByDistance(bm, vertSet, dist)
	dist = dist or 0.001
	local list = {}
	for v in pairs(vertSet or bm.verts) do list[#list + 1] = v end
	local remap, n = {}, 0
	for i = 1, #list do
		local a = list[i]
		if not remap[a] then
			for j = i + 1, #list do
				local b = list[j]
				if not remap[b] and (a.co - b.co).Magnitude <= dist then remap[b] = a n += 1 end
			end
		end
	end
	local nb, map = Ops.rebuild(bm, remap)
	return nb, map, n
end

function Ops.flipFaces(bm, faceSet)
	return Ops.rebuild(bm, nil, faceSet)
end

-- ===== fill (F): a face from the picked verts (in order round them), or an edge for 2 =====
function Ops.fill(bm, vertSet)
	local vs = {}
	for v in pairs(vertSet) do vs[#vs + 1] = v end
	if #vs == 2 then return nil, bm:edgeCreate(vs[1], vs[2]) end
	if #vs < 3 then return nil end
	local c = V3()
	for _, v in ipairs(vs) do c += v.co end
	c /= #vs
	-- best-fit normal (Newell over the points in angle order needs an order first: use the biggest cross product)
	local nrm = V3()
	for i = 1, #vs do
		for j = i + 1, #vs do
			local cr = (vs[i].co - c):Cross(vs[j].co - c)
			if cr.Magnitude > nrm.Magnitude then nrm = cr end
		end
	end
	if nrm.Magnitude < 1e-9 then return nil end
	nrm = nrm.Unit
	local ax = (vs[1].co - c)
	ax = (ax - nrm * ax:Dot(nrm))
	if ax.Magnitude < 1e-9 then return nil end
	ax = ax.Unit
	local ay = nrm:Cross(ax)
	table.sort(vs, function(a, b)
		local da, db = a.co - c, b.co - c
		return math.atan2(da:Dot(ay), da:Dot(ax)) < math.atan2(db:Dot(ay), db:Dot(ax))
	end)
	return bm:faceCreate(vs)
end

return Ops
