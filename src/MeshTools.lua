--[[
	ROBLEND - Edit Mode mesh tools (the Modeling tab)
	SPDX-License-Identifier: GPL-2.0-or-later

	Converted to Luau (and cut down) from Blender's BMesh tools + operators:
	  source/blender/bmesh/tools/bmesh_bevel.cc          bevel (offset-meet corners, 1 segment)
	  source/blender/bmesh/tools/bmesh_bisect_plane.cc   bisect / knife plane cuts
	  source/blender/bmesh/operators/bmo_utils.cc        smooth verts, select similar helpers
	  source/blender/bmesh/operators/bmo_poke.cc         poke faces
	  source/blender/bmesh/operators/bmo_triangulate.cc  triangulate (+ tools/bmesh_triangulate.cc)
	  source/blender/bmesh/operators/bmo_join_triangles.cc  tris to quads (greedy, angle measure)
	  source/blender/bmesh/operators/bmo_bridge.cc       bridge edge loops
	  source/blender/bmesh/operators/bmo_dissolve.cc     dissolve verts / edges / faces
	  source/blender/bmesh/operators/bmo_rotate_edges.cc rotate edge
	  source/blender/bmesh/operators/bmo_dupe.cc         duplicate, split, spin
	  source/blender/bmesh/operators/bmo_hull.cc         convex hull
	  source/blender/bmesh/operators/bmo_symmetrize.cc   symmetrize
	  source/blender/bmesh/operators/bmo_normals.cc      recalculate normals
	  source/blender/bmesh/operators/bmo_connect.cc      connect vertex pairs
	  source/blender/bmesh/tools/bmesh_separate.cc       separate / split helpers
	Original: Copyright (C) Blender Authors (GPL-2.0-or-later)
	Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27) - GPL-2.0-or-later.
]]

local BMesh = require(script.Parent.BMesh)
local Ops = require(script.Parent.Ops)
local MT = {}
local V3 = Vector3.new

-- ===== helpers =====
local function fverts(f) return BMesh.faceVerts(f) end
local function set(list) local s = {} for _, x in ipairs(list) do s[x] = true end return s end
local function count(t) local n = 0 for _ in pairs(t) do n += 1 end return n end
MT.count = count

function MT.vertNormal(v)
	local n = V3()
	for _, f in ipairs(BMesh.vertFaces(v)) do n += f.no end
	if n.Magnitude < 1e-9 then return V3(0, 1, 0) end
	return n.Unit
end

-- the loop of face f that sits on vert v
local function loopAt(f, v)
	for _, l in ipairs(BMesh.faceLoops(f)) do if l.v == v then return l end end
end
MT.loopAt = loopAt

-- corners round a vert in order (walking across each corner's incoming edge); nil if the vert is on a border
local function cornersAround(v)
	local fs = BMesh.vertFaces(v)
	if #fs == 0 then return nil end
	local l0 = loopAt(fs[1], v)
	local out, l = {}, l0
	for _ = 1, #fs + 1 do
		out[#out + 1] = l
		local ein = l.prev.e
		local other
		for _, g in ipairs(BMesh.edgeFaces(ein)) do if g ~= l.f then other = g end end
		if not other or BMesh.edgeFaceCount(ein) ~= 2 then return nil end
		local nl
		for _, ll in ipairs(BMesh.faceLoops(other)) do if ll.e == ein then nl = ll end end
		if not nl or nl.v ~= v then return nil end
		l = nl
		if l == l0 then return out end
	end
	return nil
end
MT.cornersAround = cornersAround

-- ===== spec: a plain copy of the mesh to rebuild from (positions + index lists + flags) =====
function MT.toSpec(bm)
	local spec = { verts = {}, faces = {}, edges = {}, eflags = {}, vi = {} }
	for v in pairs(bm.verts) do
		spec.verts[#spec.verts + 1] = { co = v.co, sel = v.sel, loose = v.e == nil, col = v.col }
		spec.vi[v] = #spec.verts
	end
	for f in pairs(bm.faces) do
		local idx, uvk = {}, {}
		for i, l in ipairs(BMesh.faceLoops(f)) do
			idx[i] = spec.vi[l.v]
			if uvk and l.uv then uvk[idx[i]] = l.uv else uvk = nil end
		end
		spec.faces[#spec.faces + 1] = { v = idx, sel = f.sel, smooth = f.smooth, src = f, uvk = uvk }
	end
	for e in pairs(bm.edges) do
		local a, b = spec.vi[e.v1], spec.vi[e.v2]
		if not e.l then spec.edges[#spec.edges + 1] = { a, b, sel = e.sel } end
		if e.sharp or e.seam or e.crease then
			local k = math.min(a, b) .. ":" .. math.max(a, b)
			spec.eflags[k] = { sharp = e.sharp, seam = e.seam, crease = e.crease }
		end
	end
	return spec
end
function MT.addVert(spec, co, sel)
	spec.verts[#spec.verts + 1] = { co = co, sel = sel }
	return #spec.verts
end
-- build a fresh mesh; verts nothing uses are dropped (unless they were loose to start with)
function MT.fromSpec(spec)
	local used = {}
	local faces = {}
	for _, f in ipairs(spec.faces) do
		if not f.dead then
			local list, prev = {}, nil
			for _, k in ipairs(f.v) do if k ~= prev then list[#list + 1] = k prev = k end end
			if #list > 1 and list[1] == list[#list] then table.remove(list) end
			local uniq, ok = {}, #list >= 3
			for _, k in ipairs(list) do if uniq[k] then ok = false end uniq[k] = true end
			if ok then
				faces[#faces + 1] = { v = list, sel = f.sel, smooth = f.smooth, uvk = f.uvk }
				for _, k in ipairs(list) do used[k] = true end
			end
		end
	end
	for _, e in ipairs(spec.edges) do if not e.dead and e[1] ~= e[2] then used[e[1]] = true used[e[2]] = true end end
	local nb = BMesh.new()
	local vs = {}
	for i, sv in ipairs(spec.verts) do
		if used[i] or (sv.loose and not sv.dead) then
			local v = nb:vertCreate(sv.co)
			v.sel = sv.sel == true
			v.col = sv.col
			vs[i] = v
		end
	end
	local fl = {}
	for i, f in ipairs(faces) do
		local list = {}
		for j, k in ipairs(f.v) do list[j] = vs[k] end
		local nf = nb:faceCreate(list)
		if nf then
			nf.sel = f.sel == true nf.smooth = f.smooth fl[i] = nf
			-- UVs come along when every corner still has one
			if f.uvk then
				local all = true
				for _, k in ipairs(f.v) do if not f.uvk[k] then all = false break end end
				if all then for j, l in ipairs(BMesh.faceLoops(nf)) do l.uv = f.uvk[f.v[j]] end end
			end
		end
	end
	for _, e in ipairs(spec.edges) do
		if not e.dead and vs[e[1]] and vs[e[2]] and e[1] ~= e[2] then
			local ne = nb:edgeCreate(vs[e[1]], vs[e[2]], true)
			if ne and e.sel then ne.sel = true end
		end
	end
	for k, fl2 in pairs(spec.eflags) do
		local a, b = k:match("(%d+):(%d+)")
		a, b = vs[tonumber(a)], vs[tonumber(b)]
		local e = a and b and BMesh.edgeExists(a, b)
		if e then e.sharp, e.seam, e.crease = fl2.sharp, fl2.seam, fl2.crease end
	end
	for e in pairs(nb.edges) do if e.v1.sel and e.v2.sel then e.sel = true end end
	nb:normalsUpdate()
	return nb, vs, fl
end

-- selected verts / edges / faces as sets
function MT.selVerts(bm) local s = {} for v in pairs(bm.verts) do if v.sel and not v.hide then s[v] = true end end return s end
function MT.selEdges(bm) local s = {} for e in pairs(bm.edges) do if e.sel and not e.hide then s[e] = true end end return s end
function MT.selFaces(bm) local s = {} for f in pairs(bm.faces) do if f.sel and not f.hide then s[f] = true end end return s end
local function clearSel(bm)
	for v in pairs(bm.verts) do v.sel = false end
	for e in pairs(bm.edges) do e.sel = false end
	for f in pairs(bm.faces) do f.sel = false end
end
MT.clearSel = clearSel
local function selectFace(f)
	f.sel = true
	for _, l in ipairs(BMesh.faceLoops(f)) do l.v.sel = true l.e.sel = true end
end
MT.selectFace = selectFace

-- ===== bevel (bmesh_bevel.cc, cut down: 1 segment, "offset" width, edges or vertices) =====
-- Edge bevel: every selected 2-face edge becomes a band face; at its ends each face corner is moved:
--   both corner edges beveled  -> the offset-meet point inside the face (offset from both edges)
--   one beveled                -> slid along the other (un-beveled) edge by `offset`
--   none beveled (side faces)  -> the corner splits into the two slide points
-- Where 3+ beveled edges meet, the hole is closed with a vertex cap polygon.
-- Vertex bevel: every edge at a selected vert gets a slide point, the vert becomes a cap face.
function MT.bevel(bm, offset, vertexOnly, segments)
	segments = vertexOnly and 1 or math.clamp(math.floor(segments or 1), 1, 32)
	local spec = MT.toSpec(bm)
	local vi = spec.vi
	local SE, BV = {}, {}
	if vertexOnly then
		for v in pairs(bm.verts) do if v.sel and v.e then BV[v] = true end end
	else
		for e in pairs(bm.edges) do
			if e.sel and BMesh.edgeFaceCount(e) == 2 then SE[e] = true BV[e.v1] = true BV[e.v2] = true end
		end
	end
	if not next(BV) then return nil end
	for _, sv in ipairs(spec.verts) do sv.sel = false end
	-- slide points, one per (vert, edge)
	local slide = {}
	local function slidePt(v, e)
		slide[v] = slide[v] or {}
		if slide[v][e] then return slide[v][e] end
		local o = BMesh.otherVert(e, v)
		local d = o.co - v.co
		local len = d.Magnitude
		if len < 1e-6 then slide[v][e] = vi[v] return vi[v] end
		local maxd = (BV[o] and (len * 0.5) or len) * 0.98
		local k = MT.addVert(spec, v.co + d.Unit * math.min(offset, maxd), true)
		slide[v][e] = k
		return k
	end
	local inner = {}
	local function meetPt(l)
		local key = l
		if inner[key] then return inner[key] end
		local v = l.v
		local a, b = (l.prev.v.co - v.co), (l.next.v.co - v.co)
		local la, lb = a.Magnitude, b.Magnitude
		if la < 1e-6 or lb < 1e-6 then inner[key] = vi[v] return vi[v] end
		a, b = a.Unit, b.Unit
		local s = a:Cross(b).Magnitude
		local t = s > 1e-4 and offset / s or offset
		t = math.min(t, la * 0.49, lb * 0.49)
		local k = MT.addVert(spec, v.co + (a + b) * t, true)
		inner[key] = k
		return k
	end
	-- new corner lists for every face
	local cornerPts = {}
	for _, f in ipairs(spec.faces) do
		local src = f.src
		local list = {}
		cornerPts[src] = {}
		for _, l in ipairs(BMesh.faceLoops(src)) do
			local v = l.v
			local pts
			if not BV[v] then
				pts = { vi[v] }
			else
				if vertexOnly then
					pts = { slidePt(v, l.prev.e), slidePt(v, l.e) }
				else
					local sin, sout = SE[l.prev.e], SE[l.e]
					if not sin and not sout then pts = { slidePt(v, l.prev.e), slidePt(v, l.e) }
					elseif sin and not sout then pts = { slidePt(v, l.e) }
					elseif sout and not sin then pts = { slidePt(v, l.prev.e) }
					else pts = { meetPt(l) } end
				end
			end
			cornerPts[src][v] = pts
			for _, k in ipairs(pts) do list[#list + 1] = k end
		end
		f.v = list
		f.sel = false
	end
	-- profiles (segments > 1): the curve across a band's end from p to q, bulging toward the old corner C.
	-- A rational quadratic Bezier with weight sin(theta / 2) is a true circular arc (Blender's default profile 0.5).
	local profiles = {}
	local function profile(p, q, C)
		if segments <= 1 or p == q then return {} end
		local key = p .. ":" .. q
		if profiles[key] then return profiles[key] end
		local rk = q .. ":" .. p
		if profiles[rk] then
			local r = {}
			for i = #profiles[rk], 1, -1 do r[#r + 1] = profiles[rk][i] end
			return r
		end
		local P, Q = spec.verts[p].co, spec.verts[q].co
		local a, b = P - C, Q - C
		local w = 0.7071
		if a.Magnitude > 1e-6 and b.Magnitude > 1e-6 then
			w = math.sin(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)) / 2)
		end
		local mids = {}
		for k = 1, segments - 1 do
			local t = k / segments
			local b0, b1, b2 = (1 - t) ^ 2, 2 * (1 - t) * t * w, t ^ 2
			mids[k] = MT.addVert(spec, (P * b0 + C * b1 + Q * b2) / (b0 + b1 + b2), true)
		end
		profiles[key] = mids
		return mids
	end
	local function run(p, q, C)
		local r = { p }
		if p == q then
			for _ = 1, segments do r[#r + 1] = p end
			return r
		end
		for _, k in ipairs(profile(p, q, C)) do r[#r + 1] = k end
		r[#r + 1] = q
		return r
	end
	-- band faces along beveled edges: quad (B1, A1, A2, B2), or a strip of `segments` quads
	local newFaces = {}
	for e in pairs(SE) do
		local fs = BMesh.edgeFaces(e)
		local l1
		for _, l in ipairs(BMesh.faceLoops(fs[1])) do if l.e == e then l1 = l end end
		local a, b = l1.v, l1.next.v
		local f1, f2 = fs[1], fs[2]
		local A1, B1 = cornerPts[f1][a], cornerPts[f1][b]
		local A2, B2 = cornerPts[f2][a], cornerPts[f2][b]
		-- the point of a corner that sits next to this edge
		local function near(pts, side) return side == "first" and pts[1] or pts[#pts] end
		local pB1, pA1, pA2, pB2 = near(B1, "first"), near(A1, "last"), near(A2, "first"), near(B2, "last")
		if segments <= 1 then
			spec.faces[#spec.faces + 1] = { v = { pB1, pA1, pA2, pB2 }, sel = true }
			newFaces[#newFaces + 1] = spec.faces[#spec.faces]
		else
			local ra, rb = run(pA1, pA2, a.co), run(pB1, pB2, b.co)
			for k = 1, segments do
				spec.faces[#spec.faces + 1] = { v = { rb[k], ra[k], ra[k + 1], rb[k + 1] }, sel = true }
				newFaces[#newFaces + 1] = spec.faces[#spec.faces]
			end
		end
	end
	-- vertex caps
	for v in pairs(BV) do
		local ring = cornersAround(v)
		if ring then
			local pts, seen = {}, {}
			for _, l in ipairs(ring) do
				local cp = cornerPts[l.f][v]
				-- walking across incoming edges goes clockwise: take the corner's points in reverse
				for j = #cp, 1, -1 do
					local k = cp[j]
					if not seen[k] then seen[k] = true pts[#pts + 1] = k end
				end
			end
			if #pts >= 3 then
				-- make it face outward (same way as the faces round the vert)
				local n = V3()
				for i = 1, #pts do
					local p, q = spec.verts[pts[i]].co, spec.verts[pts[i % #pts + 1]].co
					n += V3((p.Y - q.Y) * (p.Z + q.Z), (p.Z - q.Z) * (p.X + q.X), (p.X - q.X) * (p.Y + q.Y))
				end
				if n:Dot(MT.vertNormal(v)) < 0 then
					local r = {}
					for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
					pts = r
				end
				spec.faces[#spec.faces + 1] = { v = pts, sel = true }
			end
		end
	end
	-- every other face that runs straight across a band's end gets the profile points put in (stays watertight)
	if segments > 1 then
		for _, f in ipairs(spec.faces) do
			local out, n = {}, #f.v
			for i = 1, n do
				local p, q = f.v[i], f.v[i % n + 1]
				out[#out + 1] = p
				local mids = profiles[p .. ":" .. q]
				if mids then
					for _, k in ipairs(mids) do out[#out + 1] = k end
				else
					local r = profiles[q .. ":" .. p]
					if r then for j = #r, 1, -1 do out[#out + 1] = r[j] end end
				end
			end
			f.v = out
		end
	end
	for k in pairs(BV) do spec.verts[vi[k]].dead = true end
	local nb = MT.fromSpec(spec)
	for f in pairs(nb.faces) do if f.sel then selectFace(f) end end
	return nb
end

-- ===== loop cut with several cuts (Ctrl R + wheel): cut the ring of e0 n times, evenly =====
function MT.loopCutN(bm, e0, n)
	n = math.max(1, math.floor(n or 1))
	local a, b = e0.v1, e0.v2
	local cur = a
	local all = {}
	for i = 1, n do
		local e = BMesh.edgeExists(cur, b)
		if not e then break end
		local t = 1 / (n - i + 2)
		if e.v1 ~= cur then t = 1 - t end
		local made = Ops.loopCut(bm, e, t)
		for x in pairs(made or {}) do all[x] = true end
		-- the new vert on this edge: joined to both cur and b
		local nxt
		for _, ed in ipairs(BMesh.vertEdges(cur)) do
			local o = BMesh.otherVert(ed, cur)
			if o ~= b and BMesh.edgeExists(o, b) and math.abs((o.co - cur.co).Magnitude + (b.co - o.co).Magnitude - (b.co - cur.co).Magnitude) < 1e-4 then nxt = o end
		end
		if not nxt then break end
		cur = nxt
	end
	return all
end
-- the ring preview for n cuts: segments across each ring face (world points are made by the caller)
function MT.ringCuts(bm, e0, n)
	local ring = Ops.edgeRing(bm, e0)
	if #ring == 0 then return {} end
	-- orient every ring edge the same way as the one before it (a_i joins a_i+1)
	local ends = {}
	for i, r in ipairs(ring) do
		local x, y = r.v1, r.v2
		if i > 1 then
			local pa = ends[i - 1][1]
			if not BMesh.edgeExists(pa, x) and (BMesh.edgeExists(pa, y) or (pa.co - y.co).Magnitude < (pa.co - x.co).Magnitude) then x, y = y, x end
		end
		ends[i] = { x, y }
	end
	local closed = false
	if #ring > 2 and BMesh.edgeFaceCount(ring[1]) == 2 then
		local fs1 = {}
		for _, f in ipairs(BMesh.edgeFaces(ring[1])) do fs1[f] = true end
		for _, f in ipairs(BMesh.edgeFaces(ring[#ring])) do if fs1[f] then closed = true end end
	end
	local lines = {}
	for k = 1, n do
		local f = k / (n + 1)
		local pts = {}
		for i, en in ipairs(ends) do pts[i] = en[1].co:Lerp(en[2].co, f) end
		for i = 1, #pts - 1 do lines[#lines + 1] = { pts[i], pts[i + 1] } end
		if closed then lines[#lines + 1] = { pts[#pts], pts[1] } end
	end
	return lines
end

-- ===== Ctrl click: select the shortest path from the last picked element (editmesh_path.cc idea) =====
function MT.shortestPath(bm, a, b, mode)
	if mode == "face" then
		local dist, prev, done = { [a] = 0 }, {}, {}
		while true do
			local best, bd
			for f, d in pairs(dist) do if not done[f] and (not bd or d < bd) then best, bd = f, d end end
			if not best or best == b then break end
			done[best] = true
			local c = BMesh.faceCenter(best)
			for _, l in ipairs(BMesh.faceLoops(best)) do
				for _, g in ipairs(BMesh.edgeFaces(l.e)) do
					if g ~= best and not g.hide then
						local nd = bd + (BMesh.faceCenter(g) - c).Magnitude
						if not dist[g] or nd < dist[g] then dist[g], prev[g] = nd, best end
					end
				end
			end
		end
		if not dist[b] then return false end
		local x = b
		while x do selectFace(x) x = prev[x] end
		return true
	end
	-- verts (edges: from an end of a to the nearer end of b)
	local va = a.co and a or a.v1
	local targets = b.co and { [b] = true } or { [b.v1] = true, [b.v2] = true }
	local dist, prev, done = { [va] = 0 }, {}, {}
	local hit
	while true do
		local best, bd
		for v, d in pairs(dist) do if not done[v] and (not bd or d < bd) then best, bd = v, d end end
		if not best then break end
		if targets[best] then hit = best break end
		done[best] = true
		for _, e in ipairs(BMesh.vertEdges(best)) do
			local o = BMesh.otherVert(e, best)
			if not e.hide then
				local nd = bd + (o.co - best.co).Magnitude
				if not dist[o] or nd < dist[o] then dist[o], prev[o] = nd, best end
			end
		end
	end
	if not hit then return false end
	local x = hit
	while x do
		x.sel = true
		local p = prev[x]
		if p then local e = BMesh.edgeExists(x, p) if e then e.sel = true end end
		x = p
	end
	if b.v1 then b.sel = true b.v1.sel = true b.v2.sel = true end
	if a.v1 then a.sel = true a.v1.sel = true a.v2.sel = true end
	return true
end

-- ===== knife: cut along a chain of points (each on a vert or an edge), splitting the faces between them =====
-- points: { {v = vert} or {e = edge, t = 0..1 from e.v1} }
function MT.knife(bm, points)
	local verts = {}
	for _, p in ipairs(points) do
		local v = p.v
		if not v and p.e and bm.edges[p.e] then
			if p.t <= 0.001 then v = p.e.v1 elseif p.t >= 0.999 then v = p.e.v2 else v = bm:edgeSplit(p.e, p.e.v1, p.t) end
		end
		if v then verts[#verts + 1] = v end
	end
	local cut = {}
	for i = 2, #verts do
		local a, b = verts[i - 1], verts[i]
		if a ~= b and not BMesh.edgeExists(a, b) then
			for _, f in ipairs(BMesh.vertFaces(a)) do
				local la, lb = loopAt(f, a), loopAt(f, b)
				if la and lb and la.next ~= lb and lb.next ~= la then
					local _, e = bm:faceSplit(f, la, lb)
					if e then cut[e] = true end
					break
				end
			end
		elseif a ~= b then
			cut[BMesh.edgeExists(a, b)] = true
		end
	end
	bm:normalsUpdate()
	return cut, verts
end

-- ===== bisect (bmesh_bisect_plane.cc): cut faces with a plane (point p0, normal n) =====
function MT.bisect(bm, p0, n, faceSet)
	n = n.Unit
	local faces = {}
	for f in pairs(faceSet or bm.faces) do faces[#faces + 1] = f end
	local edges = {}
	for _, f in ipairs(faces) do for _, l in ipairs(BMesh.faceLoops(f)) do edges[l.e] = true end end
	local EPS = 1e-4
	local onPlane = {}
	local function dist(v) return (v.co - p0):Dot(n) end
	for v in pairs(bm.verts) do if math.abs(dist(v)) < EPS then onPlane[v] = true end end
	local list = {}
	for e in pairs(edges) do list[#list + 1] = e end
	for _, e in ipairs(list) do
		local d1, d2 = dist(e.v1), dist(e.v2)
		if (d1 > EPS and d2 < -EPS) or (d1 < -EPS and d2 > EPS) then
			local v = bm:edgeSplit(e, e.v1, d1 / (d1 - d2))
			onPlane[v] = true
		end
	end
	local cut = {}
	local fl = {}
	for f in pairs(bm.faces) do fl[#fl + 1] = f end
	for _, f in ipairs(fl) do
		if bm.faces[f] then
			local on = {}
			for _, l in ipairs(BMesh.faceLoops(f)) do if onPlane[l.v] then on[#on + 1] = l end end
			if #on == 2 and on[1].next ~= on[2] and on[2].next ~= on[1] then
				local _, e = bm:faceSplit(f, on[1], on[2])
				if e then cut[e] = true end
			end
		end
	end
	bm:normalsUpdate()
	return cut, onPlane
end

-- ===== spin (bmo_dupe.cc spin, cut down): sweep the selection round an axis in `steps` extrusions =====
function MT.spin(bm, center, axis, angle, steps)
	steps = math.max(1, steps or 12)
	local rot = CFrame.fromAxisAngle(axis.Unit, angle / steps)
	local function turn(vs) for v in pairs(vs) do v.co = center + rot * (v.co - center) end end
	local fs = MT.selFaces(bm)
	if next(fs) then
		-- a free-standing region keeps its start face (a cap), like Blender
		local capped = {}
		local free = true
		for f in pairs(fs) do
			for _, l in ipairs(BMesh.faceLoops(f)) do
				for _, g in ipairs(BMesh.edgeFaces(l.e)) do if not fs[g] then free = false end end
			end
		end
		if free then for f in pairs(fs) do local vs = fverts(f) capped[#capped + 1] = vs end end
		local front = fs
		for _ = 1, steps do
			local nv, nf = Ops.extrudeFaceRegion(bm, front)
			turn(nv)
			front = nf
		end
		for _, vs in ipairs(capped) do
			local r = {}
			for i = #vs, 1, -1 do r[#r + 1] = vs[i] end
			bm:faceCreate(r)
		end
		clearSel(bm)
		for f in pairs(front) do if bm.faces[f] then selectFace(f) end end
	else
		local es = MT.selEdges(bm)
		if next(es) then
			local front = es
			local lastVerts
			for _ = 1, steps do
				local nv, ne = Ops.extrudeEdges(bm, front)
				turn(nv)
				front, lastVerts = ne, nv
			end
			clearSel(bm)
			for v in pairs(lastVerts or {}) do v.sel = true end
			for e in pairs(front) do e.sel = true end
		else
			local front = MT.selVerts(bm)
			for _ = 1, steps do
				local nv = Ops.extrudeVerts(bm, front)
				turn(nv)
				front = nv
			end
			clearSel(bm)
			for v in pairs(front) do v.sel = true end
		end
	end
	bm:normalsUpdate()
end

-- ===== vertex tools (bmo_utils.cc smooth_vert + the transform modes) =====
function MT.smooth(bm, verts, factor, repeats)
	for _ = 1, repeats or 1 do
		local new = {}
		for v in pairs(verts) do
			local s, n = V3(), 0
			for _, e in ipairs(BMesh.vertEdges(v)) do s += BMesh.otherVert(e, v).co n += 1 end
			if n > 0 then new[v] = v.co:Lerp(s / n, factor) end
		end
		for v, co in pairs(new) do v.co = co end
	end
	bm:normalsUpdate()
end
-- deterministic random so dragging doesn't flicker
local function rand(seed)
	local x = math.sin(seed * 12.9898) * 43758.5453
	return x - math.floor(x)
end
function MT.randomize(bm, verts, amount, seed)
	local i = 0
	for v in pairs(verts) do
		i += 1
		local s = (seed or 1) * 7 + i * 3.17
		local d = V3(rand(s) * 2 - 1, rand(s + 1.3) * 2 - 1, rand(s + 2.7) * 2 - 1)
		v.co += d * amount
	end
	bm:normalsUpdate()
end
function MT.shrinkFatten(verts, orig, normals, d)
	for v in pairs(verts) do v.co = orig[v] + normals[v] * d end
end
function MT.pushPull(verts, orig, center, d)
	for v in pairs(verts) do
		local r = orig[v] - center
		v.co = r.Magnitude > 1e-6 and (orig[v] + r.Unit * d) or orig[v]
	end
end
function MT.shear(verts, orig, center, right, up, f)
	for v in pairs(verts) do v.co = orig[v] + right * ((orig[v] - center):Dot(up) * f) end
end
function MT.toSphere(verts, orig, center, f)
	local r, n = 0, 0
	for v in pairs(verts) do r += (orig[v] - center).Magnitude n += 1 end
	if n == 0 then return end
	r /= n
	for v in pairs(verts) do
		local d = orig[v] - center
		if d.Magnitude > 1e-6 then v.co = orig[v]:Lerp(center + d.Unit * r, math.clamp(f, 0, 1)) end
	end
end

-- ===== duplicate / split / rip (bmo_dupe.cc, bmesh_separate.cc) =====
-- duplicate the selection (faces, plus loose selected edges / verts); the copy ends up selected
function MT.duplicate(bm)
	local spec = MT.toSpec(bm)
	local map = {}
	for _, e in ipairs(spec.edges) do e.sel = false end
	local function dup(v)
		if not map[v] then map[v] = MT.addVert(spec, v.co, true) end
		return map[v]
	end
	for _, sv in ipairs(spec.verts) do sv.sel = false end
	local nf = 0
	for _, f in ipairs(spec.faces) do f.sel = false end
	for f in pairs(bm.faces) do
		if f.sel and not f.hide then
			local list = {}
			for i, v in ipairs(fverts(f)) do list[i] = dup(v) end
			spec.faces[#spec.faces + 1] = { v = list, sel = true, smooth = f.smooth }
			nf += 1
		end
	end
	for e in pairs(bm.edges) do
		if e.sel and not e.hide then
			local inFace = false
			if e.l then for _, g in ipairs(BMesh.edgeFaces(e)) do if g.sel then inFace = true end end end
			if not inFace then spec.edges[#spec.edges + 1] = { dup(e.v1), dup(e.v2), sel = true } end
		end
	end
	for v in pairs(bm.verts) do
		if v.sel and not map[v] and not v.hide then
			local k = dup(v)
			spec.verts[k].loose = true
		end
	end
	return MT.fromSpec(spec)
end
-- Y: split the selected faces off from the rest
function MT.split(bm)
	local fs = MT.selFaces(bm)
	if not next(fs) then return nil end
	local shared = {}
	for f in pairs(fs) do
		for _, v in ipairs(fverts(f)) do
			for _, g in ipairs(BMesh.vertFaces(v)) do if not fs[g] then shared[v] = true end end
		end
	end
	local spec = MT.toSpec(bm)
	local map = {}
	for _, f in ipairs(spec.faces) do
		if fs[f.src] then
			for j, v in ipairs(fverts(f.src)) do
				if shared[v] then
					if not map[v] then map[v] = MT.addVert(spec, v.co, true) end
					f.v[j] = map[v]
				end
			end
		end
	end
	for v in pairs(shared) do spec.verts[spec.vi[v]].sel = false end
	return MT.fromSpec(spec)
end
-- V: rip - the faces round the selected verts on the mouse's side get their own verts; those are returned selected
-- sideOf(face) -> true when the face is on the side being ripped away
function MT.rip(bm, sideOf)
	local sv = MT.selVerts(bm)
	if not next(sv) then return nil end
	local spec = MT.toSpec(bm)
	local map = {}
	local any = false
	for _, f in ipairs(spec.faces) do
		if sideOf(f.src) then
			for j, v in ipairs(fverts(f.src)) do
				if sv[v] then
					if not map[v] then map[v] = MT.addVert(spec, v.co, true) end
					f.v[j] = map[v]
					any = true
				end
			end
		end
	end
	if not any then return nil end
	for v in pairs(sv) do spec.verts[spec.vi[v]].sel = false end
	for _, f in ipairs(spec.faces) do f.sel = false end
	return MT.fromSpec(spec)
end

-- ===== dissolve (bmo_dissolve.cc) =====
-- the polygon left when the faces round an inner vert are joined (walk the corners)
local function unionAround(v)
	local ring = cornersAround(v)
	if not ring then return nil end
	local poly = {}
	for i, l in ipairs(ring) do
		local seq = {}
		local x = l.next
		while x ~= l do seq[#seq + 1] = x.v x = x.next end
		for j, w in ipairs(seq) do
			if not (i > 1 and j == 1) then poly[#poly + 1] = w end
		end
	end
	if #poly > 1 and poly[#poly] == poly[1] then table.remove(poly) end
	local seen = {}
	for _, w in ipairs(poly) do if seen[w] then return nil end seen[w] = true end
	return poly, ring
end
function MT.dissolveVert(bm, v)
	if not bm.verts[v] then return false end
	local fs = BMesh.vertFaces(v)
	if #fs < 2 then
		return false
	end
	local poly, ring = unionAround(v)
	if not poly or #poly < 3 then return false end
	local example = ring[1].f
	local sel = false
	for _, l in ipairs(ring) do if l.f.sel then sel = true end end
	for _, l in ipairs(ring) do bm:faceKill(l.f) end
	bm:vertKill(v)
	local nf = bm:faceCreate(poly, example)
	if nf then nf.sel = sel BMesh.faceNormalUpdate(nf) end
	return true
end
function MT.dissolveVerts(bm, vs)
	local n = 0
	local list = {}
	for v in pairs(vs) do list[#list + 1] = v end
	for _, v in ipairs(list) do if MT.dissolveVert(bm, v) then n += 1 end end
	bm:normalsUpdate()
	return n
end
-- verts with just 2 edges: take them out of the faces they're in
function MT.dissolveDeg2(bm, vs)
	local spec = MT.toSpec(bm)
	local drop = {}
	for v in pairs(vs) do if bm.verts[v] and #BMesh.vertEdges(v) == 2 then drop[spec.vi[v]] = true end end
	if not next(drop) then return false end
	for _, f in ipairs(spec.faces) do
		local out = {}
		for _, k in ipairs(f.v) do if not drop[k] then out[#out + 1] = k end end
		f.v = out
	end
	-- loose edges through the vert: join the two ends
	local joinA = {}
	local keep = {}
	for _, e in ipairs(spec.edges) do
		if drop[e[1]] or drop[e[2]] then
			local mid = drop[e[1]] and e[1] or e[2]
			local other = drop[e[1]] and e[2] or e[1]
			if joinA[mid] then keep[#keep + 1] = { joinA[mid], other } else joinA[mid] = other end
			e.dead = true
		end
	end
	for _, e in ipairs(keep) do spec.edges[#spec.edges + 1] = e end
	for k in pairs(drop) do spec.verts[k].dead = true end
	return true, MT.fromSpec(spec)
end
function MT.dissolveEdge(bm, e)
	if not bm.edges[e] or BMesh.edgeFaceCount(e) ~= 2 then return nil end
	local fs = BMesh.edgeFaces(e)
	local f1, f2 = fs[1], fs[2]
	if f1 == f2 then return nil end
	local l1, l2
	for _, l in ipairs(BMesh.faceLoops(f1)) do if l.e == e then l1 = l end end
	for _, l in ipairs(BMesh.faceLoops(f2)) do if l.e == e then l2 = l end end
	if not (l1 and l2) then return nil end
	local poly = {}
	local x = l1.next
	repeat poly[#poly + 1] = x.v x = x.next until x == l1.next
	-- poly = b ... a (all of f1 starting at b); now f2 from after a up to before b
	x = l2.next.next
	while x ~= l2 do poly[#poly + 1] = x.v x = x.next end
	local seen = {}
	for _, w in ipairs(poly) do if seen[w] then return nil end seen[w] = true end
	local sel = f1.sel or f2.sel
	bm:faceKill(f1)
	bm:faceKill(f2)
	bm:edgeKill(e)
	local nf = bm:faceCreate(poly, f1)
	if nf then nf.sel = sel BMesh.faceNormalUpdate(nf) end
	return nf
end
function MT.dissolveEdges(bm, es)
	local n, ends = 0, {}
	local list = {}
	for e in pairs(es) do list[#list + 1] = e end
	for _, e in ipairs(list) do
		if bm.edges[e] then
			local a, b = e.v1, e.v2
			if MT.dissolveEdge(bm, e) then n += 1 ends[a] = true ends[b] = true end
		end
	end
	return n, ends
end
-- faces: dissolve the verts inside the region first, then the edges between region faces
function MT.dissolveFaces(bm, fs)
	local copy = {}
	for f in pairs(fs) do copy[f] = true end
	fs = copy
	local inner = {}
	for f in pairs(fs) do
		for _, v in ipairs(fverts(f)) do
			local all = true
			for _, g in ipairs(BMesh.vertFaces(v)) do if not fs[g] then all = false end end
			if all then inner[v] = true end
		end
	end
	for v in pairs(inner) do
		if bm.verts[v] then
			local ring = cornersAround(v)
			if ring then
				local ok, newf = pcall(MT.dissolveVert, bm, v)
				if ok and newf then
					-- the joined face stays in the region
					for f in pairs(bm.faces) do if f.sel then fs[f] = true end end
				end
			end
		end
	end
	local again = true
	local guard = 0
	while again and guard < 1000 do
		again = false
		guard += 1
		for e in pairs(bm.edges) do
			if BMesh.edgeFaceCount(e) == 2 then
				local f = BMesh.edgeFaces(e)
				if f[1].sel and f[2].sel then
					if MT.dissolveEdge(bm, e) then again = true break end
				end
			end
		end
	end
	bm:normalsUpdate()
end
-- merge each selected edge (and chains of them) to its middle
function MT.edgeCollapse(bm, es)
	local parent = {}
	local function find(v) while parent[v] and parent[v] ~= v do v = parent[v] end return v end
	for e in pairs(es) do
		parent[e.v1] = parent[e.v1] or e.v1
		parent[e.v2] = parent[e.v2] or e.v2
		local a, b = find(e.v1), find(e.v2)
		if a ~= b then parent[b] = a end
	end
	local groups = {}
	for v in pairs(parent) do local r = find(v) groups[r] = groups[r] or {} table.insert(groups[r], v) end
	local remap = {}
	for r, list in pairs(groups) do
		local s = V3()
		for _, v in ipairs(list) do s += v.co end
		r.co = s / #list
		for _, v in ipairs(list) do remap[v] = r end
	end
	local nb, map = Ops.rebuild(bm, remap)
	for _, r in pairs(remap) do if map[r] then map[r].sel = true end end
	return nb
end
-- delete helpers
function MT.deleteOnlyFaces(bm, fs)
	local list = {}
	for f in pairs(fs) do list[#list + 1] = f end
	for _, f in ipairs(list) do if bm.faces[f] then bm:faceKill(f) end end
end
function MT.deleteEdgesFaces(bm, es, fs)
	for f in pairs(fs) do if bm.faces[f] then bm:faceKill(f) end end
	for e in pairs(es) do if bm.edges[e] then bm:edgeKill(e) end end
end
function MT.deleteLoose(bm)
	local n = 0
	for e in pairs(bm.edges) do if not e.l then bm:edgeKill(e) n += 1 end end
	for v in pairs(bm.verts) do if not v.e then bm:vertKill(v) n += 1 end end
	return n
end

-- ===== rotate edge (bmo_rotate_edges.cc) =====
function MT.rotateEdge(bm, e, ccw)
	if BMesh.edgeFaceCount(e) ~= 2 then return nil end
	local fs = BMesh.edgeFaces(e)
	local l1
	for _, l in ipairs(BMesh.faceLoops(fs[1])) do if l.e == e then l1 = l end end
	local a, b = l1.v, l1.next.v
	local nf = MT.dissolveEdge(bm, e)
	if not nf then return nil end
	local ls = BMesh.faceLoops(nf)
	local ia, ib
	for i, l in ipairs(ls) do if l.v == a then ia = i elseif l.v == b then ib = i end end
	local n = #ls
	local step = ccw and -1 or 1
	local x, y = ls[(ia - 1 + step) % n + 1], ls[(ib - 1 + step) % n + 1]
	if x.next == y or y.next == x or x == y then return nf end
	local _, ne = bm:faceSplit(nf, x, y)
	bm:normalsUpdate()
	return ne
end

-- ===== bridge edge loops (bmo_bridge.cc, cut down: two loops with the same number of verts) =====
local function chains(es)
	local adj = {}
	for e in pairs(es) do
		adj[e.v1] = adj[e.v1] or {} table.insert(adj[e.v1], e.v2)
		adj[e.v2] = adj[e.v2] or {} table.insert(adj[e.v2], e.v1)
	end
	local seen, out = {}, {}
	for v in pairs(adj) do
		if not seen[v] then
			-- start from an end if it's open
			local start = v
			local comp, stack = {}, { v }
			local cs = {}
			while #stack > 0 do
				local x = table.remove(stack)
				if not cs[x] then cs[x] = true comp[#comp + 1] = x for _, y in ipairs(adj[x]) do stack[#stack + 1] = y end end
			end
			for _, x in ipairs(comp) do if #adj[x] == 1 then start = x break end end
			local chain, prev, cur = {}, nil, start
			repeat
				chain[#chain + 1] = cur
				seen[cur] = true
				local nxt
				for _, y in ipairs(adj[cur]) do if y ~= prev and not seen[y] then nxt = y break end end
				prev, cur = cur, nxt
			until not cur
			local closed = #adj[start] == 2 and #chain > 2
			out[#out + 1] = { verts = chain, closed = closed }
		end
	end
	return out
end
MT.chains = chains
function MT.bridge(bm)
	-- faces selected: bridge their border loops and remove them
	local fs = MT.selFaces(bm)
	local es = {}
	if next(fs) then
		for f in pairs(fs) do
			for _, l in ipairs(BMesh.faceLoops(f)) do
				local inside = 0
				for _, g in ipairs(BMesh.edgeFaces(l.e)) do if fs[g] then inside += 1 end end
				if inside == 1 then es[l.e] = true end
			end
		end
		for f in pairs(fs) do bm:faceKill(f) end
	else
		es = MT.selEdges(bm)
	end
	local cs = chains(es)
	if #cs ~= 2 then return nil, "Select two edge loops" end
	local A, B = cs[1].verts, cs[2].verts
	if #A ~= #B then return nil, "The two loops need the same number of verts" end
	local n = #A
	local closed = cs[1].closed and cs[2].closed
	-- best start + direction for B
	local best, bestK, bestDir = math.huge, 0, 1
	for _, dir in ipairs({ 1, -1 }) do
		for k = 0, (closed and n - 1 or 0) do
			local s = 0
			for i = 1, n do
				local j = closed and ((k + (i - 1) * dir) % n + 1) or (dir == 1 and i or n - i + 1)
				s += (A[i].co - B[j].co).Magnitude
			end
			if s < best then best, bestK, bestDir = s, k, dir end
		end
	end
	local Bo = {}
	for i = 1, n do Bo[i] = B[closed and ((bestK + (i - 1) * bestDir) % n + 1) or (bestDir == 1 and i or n - i + 1)] end
	-- winding: if A[1]->A[2] is already used by a face in that direction, the bridge goes the other way
	local flip = false
	local e = BMesh.edgeExists(A[1], A[2])
	if e and e.l and e.l.v == A[1] then flip = true end
	local out = {}
	local last = closed and n or n - 1
	for i = 1, last do
		local i2 = i % n + 1
		local quad = flip and { A[i2], A[i], Bo[i], Bo[i2] } or { A[i], A[i2], Bo[i2], Bo[i] }
		local f = bm:faceCreate(quad)
		if f then out[f] = true end
	end
	clearSel(bm)
	for f in pairs(out) do selectFace(f) end
	bm:normalsUpdate()
	return out
end

-- ===== faces: poke, triangulate, tris to quads, solidify, extrude individual =====
function MT.poke(bm, fs)
	local out = {}
	local list = {}
	for f in pairs(fs) do list[#list + 1] = f end
	for _, f in ipairs(list) do
		if bm.faces[f] then
			local vs = fverts(f)
			local c = BMesh.faceCenter(f)
			local cv = bm:vertCreate(c)
			bm:faceKill(f)
			for i = 1, #vs do
				local t = bm:faceCreate({ vs[i], vs[i % #vs + 1], cv }, f)
				if t then out[t] = true end
			end
		end
	end
	clearSel(bm)
	for f in pairs(out) do selectFace(f) end
	bm:normalsUpdate()
	return out
end
function MT.triangulate(bm, fs, triangulateFn)
	local out = {}
	local list = {}
	for f in pairs(fs) do list[#list + 1] = f end
	for _, f in ipairs(list) do
		if bm.faces[f] and f.len > 3 then
			local vs = fverts(f)
			local tris
			if #vs == 4 then
				-- quads: the shorter diagonal (Blender's "beauty" default)
				if (vs[1].co - vs[3].co).Magnitude <= (vs[2].co - vs[4].co).Magnitude then tris = { { 1, 2, 3 }, { 1, 3, 4 } }
				else tris = { { 1, 2, 4 }, { 2, 3, 4 } } end
			else
				tris = triangulateFn(vs, f.no)
			end
			bm:faceKill(f)
			for _, t in ipairs(tris) do
				local nf = bm:faceCreate({ vs[t[1]], vs[t[2]], vs[t[3]] }, f)
				if nf then out[nf] = true end
			end
		elseif bm.faces[f] then
			out[f] = true
		end
	end
	clearSel(bm)
	for f in pairs(out) do if bm.faces[f] then selectFace(f) end end
	bm:normalsUpdate()
	return out
end
function MT.trisToQuads(bm, fs, maxAngle)
	maxAngle = maxAngle or math.rad(40)
	local cands = {}
	for e in pairs(bm.edges) do
		if BMesh.edgeFaceCount(e) == 2 then
			local f = BMesh.edgeFaces(e)
			if fs[f[1]] and fs[f[2]] and f[1].len == 3 and f[2].len == 3 then
				local ang = math.acos(math.clamp(f[1].no:Dot(f[2].no), -1, 1))
				if ang <= maxAngle then cands[#cands + 1] = { e = e, a = ang } end
			end
		end
	end
	table.sort(cands, function(x, y) return x.a < y.a end)
	local used = {}
	local n = 0
	for _, c in ipairs(cands) do
		if bm.edges[c.e] then
			local f = BMesh.edgeFaces(c.e)
			if not used[f[1]] and not used[f[2]] then
				used[f[1]], used[f[2]] = true, true
				if MT.dissolveEdge(bm, c.e) then n += 1 end
			end
		end
	end
	bm:normalsUpdate()
	return n
end
function MT.solidify(bm, fs, thick)
	local copy = {}
	for f in pairs(fs) do copy[f] = true end
	fs = copy
	local vn = {}
	for f in pairs(fs) do
		for _, v in ipairs(fverts(f)) do
			vn[v] = vn[v] or V3()
			vn[v] += f.no
		end
	end
	local map = {}
	for v, n in pairs(vn) do map[v] = bm:vertCreate(v.co - (n.Magnitude > 1e-9 and n.Unit or V3()) * thick) end
	local out = {}
	for f in pairs(fs) do
		local vs = fverts(f)
		local r = {}
		for i = #vs, 1, -1 do r[#r + 1] = map[vs[i]] end
		local nf = bm:faceCreate(r, f)
		if nf then out[nf] = true end
		for _, l in ipairs(BMesh.faceLoops(f)) do
			local inside = 0
			for _, g in ipairs(BMesh.edgeFaces(l.e)) do if fs[g] then inside += 1 end end
			if inside == 1 then
				local wf = bm:faceCreate({ l.next.v, l.v, map[l.v], map[l.next.v] }, f)
				if wf then out[wf] = true end
			end
		end
	end
	bm:normalsUpdate()
	return out
end
function MT.extrudeIndividual(bm, fs)
	local newVerts, newFaces = {}, {}
	local list = {}
	for f in pairs(fs) do list[#list + 1] = f end
	for _, f in ipairs(list) do
		local nv, nf = Ops.extrudeFaceRegion(bm, { [f] = true })
		for v in pairs(nv) do newVerts[v] = true end
		for g in pairs(nf) do newFaces[g] = true end
	end
	clearSel(bm)
	for f in pairs(newFaces) do if bm.faces[f] then selectFace(f) end end
	bm:normalsUpdate()
	return newVerts, newFaces
end

-- ===== connect vertex pairs (J, bmo_connect.cc): split each face between its selected, non-neighbour verts =====
function MT.connectVerts(bm, vs)
	local fl = {}
	for f in pairs(bm.faces) do fl[#fl + 1] = f end
	local made = {}
	for _, f in ipairs(fl) do
		if bm.faces[f] then
			local pick = {}
			for _, l in ipairs(BMesh.faceLoops(f)) do if vs[l.v] then pick[#pick + 1] = l.v end end
			if #pick >= 2 then
				local face = f
				for i = 2, #pick do
					local a, b = pick[i - 1], pick[i]
					local la, lb = loopAt(face, a), loopAt(face, b)
					if la and lb and la.next ~= lb and lb.next ~= la then
						local f2, e = bm:faceSplit(face, la, lb)
						if e then made[e] = true end
						if f2 and loopAt(f2, b) then face = f2 end
					end
				end
			end
		end
	end
	bm:normalsUpdate()
	return made
end

-- ===== convex hull (bmo_hull.cc, cut down: incremental hull of the selected verts) =====
function MT.convexHull(bm, vs)
	local pts = {}
	for v in pairs(vs) do pts[#pts + 1] = v end
	if #pts < 4 then return nil, "Pick at least 4 verts" end
	local faces = {}
	local function nrm(a, b, c) return (b.co - a.co):Cross(c.co - a.co) end
	-- starting tetrahedron
	local a, b = pts[1], nil
	for _, p in ipairs(pts) do if (p.co - a.co).Magnitude > 1e-6 then b = p break end end
	local c, d
	for _, p in ipairs(pts) do if b and nrm(a, b, p).Magnitude > 1e-6 then c = p break end end
	for _, p in ipairs(pts) do if c and math.abs(nrm(a, b, c):Dot(p.co - a.co)) > 1e-6 then d = p break end end
	if not d then return nil, "The verts are flat - no volume to wrap" end
	local center = (a.co + b.co + c.co + d.co) / 4
	local function add(x, y, z)
		local n = nrm(x, y, z)
		if n:Dot(x.co - center) < 0 then y, z = z, y end
		faces[#faces + 1] = { x, y, z }
	end
	add(a, b, c) add(a, b, d) add(a, c, d) add(b, c, d)
	for _, p in ipairs(pts) do
		if p ~= a and p ~= b and p ~= c and p ~= d then
			local visible, keep = {}, {}
			for _, f in ipairs(faces) do
				if nrm(f[1], f[2], f[3]):Dot(p.co - f[1].co) > 1e-7 then visible[#visible + 1] = f else keep[#keep + 1] = f end
			end
			if #visible > 0 then
				local edgeCount = {}
				for _, f in ipairs(visible) do
					for i = 1, 3 do
						local x, y = f[i], f[i % 3 + 1]
						edgeCount[x] = edgeCount[x] or {}
						edgeCount[x][y] = true
					end
				end
				for _, f in ipairs(visible) do
					for i = 1, 3 do
						local x, y = f[i], f[i % 3 + 1]
						if not (edgeCount[y] and edgeCount[y][x]) then keep[#keep + 1] = { x, y, p } end
					end
				end
				faces = keep
			end
		end
	end
	-- replace: drop faces made only of the hull's verts, add the hull
	for f in pairs(bm.faces) do
		local all = true
		for _, v in ipairs(fverts(f)) do if not vs[v] then all = false end end
		if all then bm:faceKill(f) end
	end
	local out = {}
	for _, f in ipairs(faces) do
		local nf = bm:faceCreate(f)
		if nf then out[nf] = true end
	end
	bm:normalsUpdate()
	-- join coplanar neighbours back into bigger faces
	local again = true
	while again do
		again = false
		for e in pairs(bm.edges) do
			if BMesh.edgeFaceCount(e) == 2 then
				local g = BMesh.edgeFaces(e)
				if out[g[1]] and out[g[2]] and g[1].no:Dot(g[2].no) > 0.9999 then
					local nf = MT.dissolveEdge(bm, e)
					if nf then out[g[1]], out[g[2]] = nil, nil out[nf] = true again = true break end
				end
			end
		end
	end
	for v in pairs(vs) do if bm.verts[v] and not v.e then bm:vertKill(v) end end
	clearSel(bm)
	for f in pairs(out) do if bm.faces[f] then selectFace(f) end end
	return out
end

-- ===== symmetrize (bmo_symmetrize.cc): copy the -X half onto +X (in the mesh's own space) =====
function MT.symmetrize(bm, axis, positiveToNegative)
	local ax = ({ X = V3(1, 0, 0), Y = V3(0, 1, 0), Z = V3(0, 0, 1) })[axis or "X"]
	local sgn = positiveToNegative and -1 or 1
	MT.bisect(bm, V3(), ax)
	local EPS = 1e-4
	local function side(v) return v.co:Dot(ax) * sgn end
	-- drop the half being replaced
	for f in pairs(bm.faces) do
		for _, v in ipairs(fverts(f)) do if side(v) > EPS then bm:faceKill(f) break end end
	end
	for v in pairs(bm.verts) do if side(v) > EPS then bm:vertKill(v) end end
	local spec = MT.toSpec(bm)
	local mirror = {}
	local nv0 = #spec.verts
	for i = 1, nv0 do
		local sv = spec.verts[i]
		local d = sv.co:Dot(ax)
		if math.abs(d) <= EPS then
			sv.co = sv.co - ax * d
			mirror[i] = i
		else
			mirror[i] = MT.addVert(spec, sv.co - ax * (2 * d), sv.sel)
		end
	end
	local n = #spec.faces
	for i = 1, n do
		local f = spec.faces[i]
		local r = {}
		for j = #f.v, 1, -1 do r[#r + 1] = mirror[f.v[j]] end
		spec.faces[#spec.faces + 1] = { v = r, sel = f.sel, smooth = f.smooth }
	end
	return MT.fromSpec(spec)
end

-- ===== recalculate normals (bmo_normals.cc): consistent winding per piece, then pointing outward =====
function MT.recalcNormals(bm, fs, inside)
	fs = fs or bm.faces
	local flip = {}
	local done = {}
	for start in pairs(fs) do
		if not done[start] then
			local piece, queue = {}, { start }
			done[start] = true
			while #queue > 0 do
				local f = table.remove(queue, 1)
				piece[#piece + 1] = f
				for _, l in ipairs(BMesh.faceLoops(f)) do
					for _, g in ipairs(BMesh.edgeFaces(l.e)) do
						if g ~= f and fs[g] and not done[g] then
							-- g must run along this edge the other way; flip it if not
							local gl
							for _, x in ipairs(BMesh.faceLoops(g)) do if x.e == l.e then gl = x end end
							local fSame = (gl.v == l.v)
							local fFlip = flip[f] or false
							flip[g] = (fSame ~= fFlip) and true or false
							if not flip[g] then flip[g] = nil end
							done[g] = true
							queue[#queue + 1] = g
						end
					end
				end
			end
			-- outward: signed volume of the piece (as it will be after flipping)
			local vol = 0
			for _, f in ipairs(piece) do
				local vs = fverts(f)
				if flip[f] then local r = {} for i = #vs, 1, -1 do r[#r + 1] = vs[i] end vs = r end
				for i = 2, #vs - 1 do vol += vs[1].co:Dot(vs[i].co:Cross(vs[i + 1].co)) end
			end
			if (vol < 0) ~= (inside == true) then
				for _, f in ipairs(piece) do flip[f] = not flip[f] or nil end
			end
		end
	end
	if not next(flip) then return bm end
	return Ops.flipFaces(bm, flip)
end

-- ===== selection (bmo_utils.cc + editmesh_select.cc ideas) =====
function MT.selectMore(bm, mode)
	if mode == "face" then
		local add = {}
		for f in pairs(bm.faces) do
			if f.sel then for _, v in ipairs(fverts(f)) do for _, g in ipairs(BMesh.vertFaces(v)) do add[g] = true end end end
		end
		for f in pairs(add) do if not f.hide then selectFace(f) end end
	else
		local add = {}
		for v in pairs(bm.verts) do
			if v.sel then for _, e in ipairs(BMesh.vertEdges(v)) do add[BMesh.otherVert(e, v)] = true end end
		end
		for v in pairs(add) do if not v.hide then v.sel = true end end
	end
end
function MT.selectLess(bm, mode)
	if mode == "face" then
		local drop = {}
		for f in pairs(bm.faces) do
			if f.sel then
				for _, v in ipairs(fverts(f)) do
					for _, g in ipairs(BMesh.vertFaces(v)) do if not g.sel then drop[f] = true end end
				end
			end
		end
		for f in pairs(drop) do f.sel = false end
		for v in pairs(bm.verts) do v.sel = false end
		for e in pairs(bm.edges) do e.sel = false end
		for f in pairs(bm.faces) do if f.sel then selectFace(f) end end
	else
		local drop = {}
		for v in pairs(bm.verts) do
			if v.sel then
				for _, e in ipairs(BMesh.vertEdges(v)) do if not BMesh.otherVert(e, v).sel then drop[v] = true end end
				if not v.e then drop[v] = nil end
			end
		end
		for v in pairs(drop) do v.sel = false end
	end
end
-- everything connected to the selection (or to `seed`)
function MT.selectLinked(bm, seedVerts)
	local queue, seen = {}, {}
	for v in pairs(seedVerts) do queue[#queue + 1] = v seen[v] = true end
	while #queue > 0 do
		local v = table.remove(queue)
		v.sel = true
		for _, e in ipairs(BMesh.vertEdges(v)) do
			local o = BMesh.otherVert(e, v)
			if not seen[o] and not o.hide then seen[o] = true queue[#queue + 1] = o end
		end
	end
	for f in pairs(bm.faces) do
		local all = true
		for _, v in ipairs(fverts(f)) do if not v.sel then all = false end end
		if all then selectFace(f) end
	end
end
-- Shift G (Blender's Select Similar, editmesh_select_similar.cc): select everything that matches a selected element
local function faceArea(f)
	local vs = fverts(f)
	local a = 0
	for i = 2, #vs - 1 do a += (vs[i].co - vs[1].co):Cross(vs[i + 1].co - vs[1].co).Magnitude / 2 end
	return a
end
local function facePerimeter(f)
	local vs, p = fverts(f), 0
	for i = 1, #vs do p += (vs[i % #vs + 1].co - vs[i].co).Magnitude end
	return p
end
MT.SIMILAR = {
	vert = {
		{ "edges", "Amount of Connecting Edges", function(v) return #BMesh.vertEdges(v) end },
		{ "faces", "Amount of Adjacent Faces", function(v) return #BMesh.vertFaces(v) end },
		{ "normal", "Vertex Normal", function(v) return MT.vertNormal(v) end },
	},
	edge = {
		{ "length", "Length", function(e) return (e.v1.co - e.v2.co).Magnitude end },
		{ "direction", "Direction", function(e) local d = e.v2.co - e.v1.co return d.Magnitude > 1e-9 and d.Unit or d end },
		{ "faces", "Amount of Faces Around an Edge", function(e) return BMesh.edgeFaceCount(e) end },
		{ "angle", "Face Angles", function(e) local f = BMesh.edgeFaces(e) if #f ~= 2 then return -1 end return math.acos(math.clamp(f[1].no:Dot(f[2].no), -1, 1)) end },
		{ "sharp", "Sharpness", function(e) return e.sharp and 1 or 0 end },
		{ "seam", "Seam", function(e) return e.seam and 1 or 0 end },
	},
	face = {
		{ "sides", "Amount of Sides", function(f) return f.len end },
		{ "area", "Area", faceArea },
		{ "perimeter", "Perimeter", facePerimeter },
		{ "normal", "Normal", function(f) return f.no end },
		{ "coplanar", "Coplanar", function(f) return { n = f.no, d = f.no:Dot(BMesh.faceCenter(f)) } end },
		{ "smooth", "Flat/Smooth", function(f) return f.smooth and 1 or 0 end },
	},
}
function MT.selectSimilar(bm, mode, kind, threshold)
	threshold = threshold or 0
	local list = MT.SIMILAR[mode]
	local fn
	for _, k in ipairs(list or {}) do if k[1] == kind then fn = k[3] end end
	if not fn then return 0 end
	local src = mode == "vert" and bm.verts or mode == "edge" and bm.edges or bm.faces
	local keys = {}
	for x in pairs(src) do if x.sel and not x.hide then keys[#keys + 1] = fn(x) end end
	if #keys == 0 then return 0 end
	local function same(a, b)
		if type(a) == "number" then
			return math.abs(a - b) <= math.max(threshold * math.max(math.abs(a), 1), 1e-4)
		elseif kind == "coplanar" then
			return a.n:Dot(b.n) >= math.cos(math.max(threshold, 0.01)) and math.abs(a.d - b.d) <= math.max(threshold, 1e-3)
		else -- a direction
			local lim = math.cos(math.max(threshold * math.pi, 0.01))
			if kind == "direction" then return math.abs(a:Dot(b)) >= lim end
			return a:Dot(b) >= lim
		end
	end
	local n = 0
	for x in pairs(src) do
		if not x.sel and not x.hide then
			local k = fn(x)
			for _, s in ipairs(keys) do
				if same(s, k) then
					if mode == "face" then selectFace(x) else x.sel = true if mode == "edge" then x.v1.sel = true x.v2.sel = true end end
					n += 1
					break
				end
			end
		end
	end
	return n
end

-- Shift Ctrl M (Blender's Select Mirror): the selection jumps to the other side of the mesh's own axis
function MT.selectMirror(bm, axis, extend)
	axis = axis or "X"
	local flip = axis == "X" and Vector3.new(-1, 1, 1) or axis == "Y" and Vector3.new(1, -1, 1) or Vector3.new(1, 1, -1)
	local cell = {}
	local function key(co) return math.floor(co.X * 1000 + 0.5) .. "," .. math.floor(co.Y * 1000 + 0.5) .. "," .. math.floor(co.Z * 1000 + 0.5) end
	for v in pairs(bm.verts) do cell[key(v.co)] = v end
	local want = {}
	local n = 0
	for v in pairs(bm.verts) do
		if v.sel then
			local m = cell[key(v.co * flip)]
			if m then want[m] = true n += 1 end
		end
	end
	if not extend then for v in pairs(bm.verts) do v.sel = false end for e in pairs(bm.edges) do e.sel = false end for f in pairs(bm.faces) do f.sel = false end end
	for v in pairs(want) do v.sel = true end
	return n
end

-- Clean Up > Fill Holes: every open border loop (up to maxSides corners, 0 = any) gets a face
function MT.fillHoles(bm, maxSides)
	maxSides = maxSides or 0
	local nextOf = {}
	for e in pairs(bm.edges) do
		if BMesh.edgeFaceCount(e) == 1 then
			local l = e.l
			-- the hole goes round the other way from the face beside it
			nextOf[l.next.v] = l.v
		end
	end
	local made = 0
	local used = {}
	for start in pairs(nextOf) do
		if not used[start] then
			local loop, v, guard = {}, start, 0
			while v and not used[v] and guard < 100000 do
				used[v] = true
				loop[#loop + 1] = v
				v = nextOf[v]
				guard += 1
			end
			if v == start and #loop >= 3 and (maxSides == 0 or #loop <= maxSides) then
				local f = bm:faceCreate(loop)
				if f then made += 1 f.sel = true end
			end
		end
	end
	bm:normalsUpdate()
	return made
end
-- Shade Auto Smooth (Blender's Smooth by Angle): all faces smooth, edges sharper than the angle marked sharp
function MT.smoothByAngle(bm, fs, angleDeg)
	local lim = math.cos(math.rad(angleDeg or 30))
	for f in pairs(fs or bm.faces) do f.smooth = true end
	local n = 0
	for e in pairs(bm.edges) do
		local ef = BMesh.edgeFaces(e)
		if #ef == 2 and (not fs or fs[ef[1]] or fs[ef[2]]) then
			if ef[1].no:Dot(ef[2].no) < lim then e.sharp = true n += 1 end
		end
	end
	return n
end

function MT.selectRandom(bm, mode, ratio, seed)
	local i = 0
	local src = mode == "vert" and bm.verts or mode == "edge" and bm.edges or bm.faces
	local list = {}
	for x in pairs(src) do if x.sel then list[#list + 1] = x end end
	for _, x in ipairs(list) do
		i += 1
		if rand((seed or 1) * 31 + i * 1.7) > ratio then x.sel = false end
	end
end
-- checker deselect: every other element, walking outward from the first selected one
function MT.checkerDeselect(bm, mode)
	local src = mode == "vert" and bm.verts or mode == "edge" and bm.edges or bm.faces
	local start
	for x in pairs(src) do if x.sel then start = x break end end
	if not start then return end
	local depth, queue = { [start] = 0 }, { start }
	local function nbrs(x)
		local out = {}
		if mode == "vert" then for _, e in ipairs(BMesh.vertEdges(x)) do out[#out + 1] = BMesh.otherVert(e, x) end
		elseif mode == "edge" then
			for _, v in ipairs({ x.v1, x.v2 }) do for _, e in ipairs(BMesh.vertEdges(v)) do if e ~= x then out[#out + 1] = e end end end
		else
			for _, l in ipairs(BMesh.faceLoops(x)) do for _, g in ipairs(BMesh.edgeFaces(l.e)) do if g ~= x then out[#out + 1] = g end end end
		end
		return out
	end
	while #queue > 0 do
		local x = table.remove(queue, 1)
		for _, y in ipairs(nbrs(x)) do
			if y.sel and depth[y] == nil then depth[y] = depth[x] + 1 queue[#queue + 1] = y end
		end
	end
	for x, d in pairs(depth) do if d % 2 == 1 then x.sel = false end end
end
function MT.selectNonManifold(bm)
	clearSel(bm)
	for e in pairs(bm.edges) do
		if BMesh.edgeFaceCount(e) ~= 2 then e.sel = true e.v1.sel = true e.v2.sel = true end
	end
end
function MT.selectLoose(bm)
	clearSel(bm)
	for v in pairs(bm.verts) do if not v.e then v.sel = true end end
	for e in pairs(bm.edges) do if not e.l then e.sel = true e.v1.sel = true e.v2.sel = true end end
end
function MT.selectSharp(bm, angle)
	angle = angle or math.rad(30)
	clearSel(bm)
	for e in pairs(bm.edges) do
		if BMesh.edgeFaceCount(e) == 2 then
			local f = BMesh.edgeFaces(e)
			if math.acos(math.clamp(f[1].no:Dot(f[2].no), -1, 1)) > angle then e.sel = true e.v1.sel = true e.v2.sel = true end
		end
	end
end
function MT.selectBySides(bm, n)
	clearSel(bm)
	for f in pairs(bm.faces) do if f.len == n then selectFace(f) end end
end
function MT.selectRing(bm, e0, add)
	if not add then clearSel(bm) end
	for _, e in ipairs(Ops.edgeRing(bm, e0)) do e.sel = true e.v1.sel = true e.v2.sel = true end
end

-- ===== hide / reveal =====
function MT.hide(bm, mode, unselected)
	local function want(x) if unselected then return not x.sel else return x.sel end end
	if mode == "face" then
		for f in pairs(bm.faces) do if want(f) then f.hide = true end end
	elseif mode == "edge" then
		for e in pairs(bm.edges) do if want(e) then e.hide = true end end
		for f in pairs(bm.faces) do for _, l in ipairs(BMesh.faceLoops(f)) do if l.e.hide then f.hide = true end end end
	else
		for v in pairs(bm.verts) do if want(v) then v.hide = true end end
		for e in pairs(bm.edges) do if e.v1.hide or e.v2.hide then e.hide = true end end
		for f in pairs(bm.faces) do for _, v in ipairs(fverts(f)) do if v.hide then f.hide = true end end end
	end
	-- a face that's hidden hides nothing else; verts / edges only used by hidden faces go too
	for e in pairs(bm.edges) do
		if e.l then
			local all = true
			for _, g in ipairs(BMesh.edgeFaces(e)) do if not g.hide then all = false end end
			if all then e.hide = true end
		end
	end
	for v in pairs(bm.verts) do
		if v.e then
			local all = true
			for _, e in ipairs(BMesh.vertEdges(v)) do if not e.hide then all = false end end
			if all then v.hide = true end
		end
	end
	for v in pairs(bm.verts) do if v.hide then v.sel = false end end
	for e in pairs(bm.edges) do if e.hide then e.sel = false end end
	for f in pairs(bm.faces) do if f.hide then f.sel = false end end
end
function MT.reveal(bm)
	for _, t in ipairs({ bm.verts, bm.edges, bm.faces }) do
		for x in pairs(t) do if x.hide then x.hide = nil x.sel = true end end
	end
end

-- ===== mirror (scale -1 about the selection's middle) and snapping helpers =====
function MT.mirror(bm, verts, center, axis)
	for v in pairs(verts) do
		local d = (v.co - center):Dot(axis)
		v.co = v.co - axis * (2 * d)
	end
	-- the selected faces turned inside out: flip them back
	local fs = {}
	for f in pairs(bm.faces) do
		local all = true
		for _, v in ipairs(fverts(f)) do if not verts[v] then all = false end end
		if all then fs[f] = true end
	end
	if next(fs) then return Ops.flipFaces(bm, fs) end
	bm:normalsUpdate()
	return bm
end

return MT
