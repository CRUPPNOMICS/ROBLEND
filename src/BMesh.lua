--[[
	ROBLEND - BMesh (the mesh engine)
	SPDX-License-Identifier: GPL-2.0-or-later

	Converted to Luau (and cut down) from Blender's BMesh:
	  source/blender/bmesh/intern/bmesh_structure.cc  (disk + radial cycles)
	  source/blender/bmesh/intern/bmesh_core.cc       (create / kill / split edge / split face)
	  source/blender/bmesh/intern/bmesh_polygon.cc    (face normal / centre)
	Original: Copyright (C) Blender Authors - https://www.blender.org (GPL-2.0-or-later)
	Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27) - also GPL-2.0-or-later.

	How it's built (same as Blender):
	  Vert  { co, e }                     e = one edge in its DISK cycle (all edges round the vert)
	  Edge  { v1, v2, l, d1, d2 }         d1 / d2 = disk links {next, prev} for v1 / v2; l = one loop in its RADIAL cycle
	  Loop  { v, e, f, next, prev, rnext, rprev }   one corner of a face (face boundary = a ring of loops)
	  Face  { l, len, no }                l = first loop
	Cut out for Roblox: custom data layers, mempools, holes, attributes, the operator API, threading.
]]

local BMesh = {}
BMesh.__index = BMesh

local V3 = Vector3.new

function BMesh.new()
	return setmetatable({ verts = {}, edges = {}, faces = {}, nv = 0, ne = 0, nf = 0 }, BMesh)
end

-- ===== disk cycle (bmesh_structure.cc) =====
local function diskLink(e, v)
	if e.v1 == v then return e.d1 end
	return e.d2
end
BMesh.diskLink = diskLink

function BMesh.diskNext(e, v) return diskLink(e, v).next end
function BMesh.diskPrev(e, v) return diskLink(e, v).prev end

local function diskAppend(e, v)
	if not v.e then
		local dl1 = diskLink(e, v)
		v.e = e
		dl1.next, dl1.prev = e, e
	else
		local dl1 = diskLink(e, v)
		local dl2 = diskLink(v.e, v)
		local dl3 = dl2.prev and diskLink(dl2.prev, v) or nil
		dl1.next = v.e
		dl1.prev = dl2.prev
		dl2.prev = e
		if dl3 then dl3.next = e end
	end
end

local function diskRemove(e, v)
	local dl1 = diskLink(e, v)
	if dl1.prev then diskLink(dl1.prev, v).next = dl1.next end
	if dl1.next then diskLink(dl1.next, v).prev = dl1.prev end
	if v.e == e then v.e = (e ~= dl1.next) and dl1.next or nil end
	dl1.next, dl1.prev = nil, nil
end

-- swap v_src for v_dst in edge e (keeps the disk cycles right)
local function diskVertReplace(e, vDst, vSrc)
	diskRemove(e, vSrc)
	if e.v1 == vSrc then e.v1 = vDst e.d1 = { next = nil, prev = nil }
	else e.v2 = vDst e.d2 = { next = nil, prev = nil } end
	diskAppend(e, vDst)
end

-- every edge round a vert
function BMesh.vertEdges(v)
	local out = {}
	local first = v.e
	if not first then return out end
	local e = first
	repeat
		out[#out + 1] = e
		e = diskLink(e, v).next
	until e == first or e == nil
	return out
end

-- ===== radial cycle =====
local function radialAppend(e, l)
	if e.l == nil then
		e.l = l
		l.rnext, l.rprev = l, l
	else
		l.rprev = e.l
		l.rnext = e.l.rnext
		e.l.rnext.rprev = l
		e.l.rnext = l
		e.l = l
	end
	l.e = e
end

local function radialRemove(e, l)
	if l.rnext ~= l then
		if l == e.l then e.l = l.rnext end
		l.rnext.rprev = l.rprev
		l.rprev.rnext = l.rnext
	elseif l == e.l then
		e.l = nil
	end
	l.rnext, l.rprev, l.e = nil, nil, nil
end

local function radialUnlink(l)
	if l.rnext ~= l then
		l.rnext.rprev = l.rprev
		l.rprev.rnext = l.rnext
	end
	l.rnext, l.rprev, l.e = nil, nil, nil
end

-- every face using an edge
function BMesh.edgeFaces(e)
	local out = {}
	local first = e.l
	if not first then return out end
	local l = first
	repeat
		out[#out + 1] = l.f
		l = l.rnext
	until l == first
	return out
end

function BMesh.edgeFaceCount(e)
	local n, first = 0, e.l
	if not first then return 0 end
	local l = first
	repeat n += 1 l = l.rnext until l == first
	return n
end

-- ===== create (bmesh_core.cc) =====
function BMesh:vertCreate(co)
	local v = { co = co, e = nil, sel = false, hide = false }
	self.verts[v] = true
	self.nv += 1
	return v
end

function BMesh.edgeExists(v1, v2)
	local first = v1.e
	if not first then return nil end
	local e = first
	repeat
		if (e.v1 == v1 and e.v2 == v2) or (e.v1 == v2 and e.v2 == v1) then return e end
		e = diskLink(e, v1).next
	until e == first or e == nil
	return nil
end

-- noDouble: hand back the edge that's already there instead of making a second one
function BMesh:edgeCreate(v1, v2, noDouble)
	if noDouble ~= false then
		local ex = BMesh.edgeExists(v1, v2)
		if ex then return ex end
	end
	local e = { v1 = v1, v2 = v2, l = nil, d1 = { next = nil, prev = nil }, d2 = { next = nil, prev = nil }, sel = false, seam = false }
	diskAppend(e, v1)
	diskAppend(e, v2)
	self.edges[e] = true
	self.ne += 1
	return e
end

local function loopCreate(v, e, f)
	return { v = v, e = e, f = f, next = nil, prev = nil, rnext = nil, rprev = nil }
end

-- a face from an ordered list of verts (edges are made if missing) - BM_face_create_verts
function BMesh:faceCreate(verts, example)
	local n = #verts
	if n < 3 then return nil end
	local f = { l = nil, len = n, no = V3(0, 1, 0), sel = false, mat = example and example.mat or nil, smooth = example and example.smooth or nil }
	local prev, first
	for i = 1, n do
		local v, vn = verts[i], verts[i % n + 1]
		local e = self:edgeCreate(v, vn, true)
		local l = loopCreate(v, nil, f)
		radialAppend(e, l)
		if prev then prev.next = l l.prev = prev else first = l end
		prev = l
	end
	prev.next = first
	first.prev = prev
	f.l = first
	self.faces[f] = true
	self.nf += 1
	BMesh.faceNormalUpdate(f)
	return f
end

-- ===== kill =====
function BMesh:faceKill(f)
	local first = f.l
	if first then
		local l = first
		repeat
			local nx = l.next
			radialRemove(l.e, l)
			l = nx
		until l == first
	end
	f.l = nil
	if self.faces[f] then self.faces[f] = nil self.nf -= 1 end
end

function BMesh:edgeKill(e)
	while e.l do self:faceKill(e.l.f) end
	diskRemove(e, e.v1)
	diskRemove(e, e.v2)
	if self.edges[e] then self.edges[e] = nil self.ne -= 1 end
end

function BMesh:vertKill(v)
	while v.e do self:edgeKill(v.e) end
	if self.verts[v] then self.verts[v] = nil self.nv -= 1 end
end

-- kill a face, then any edge / vert it leaves with nothing (BM_face_kill_loose)
function BMesh:faceKillLoose(f)
	local es = {}
	for _, l in ipairs(BMesh.faceLoops(f)) do es[#es + 1] = l.e end
	self:faceKill(f)
	for _, e in ipairs(es) do
		if self.edges[e] and not e.l then
			local a, b = e.v1, e.v2
			self:edgeKill(e)
			if not a.e then self:vertKill(a) end
			if not b.e then self:vertKill(b) end
		end
	end
end

-- ===== euler: split edge (bmesh_kernel_split_edge_make_vert) =====
-- splits e at its tv end side: returns the new vert (at t along tv -> other) and the new edge (tv - new vert)
function BMesh:edgeSplit(e, tv, t)
	local vOld = (e.v1 == tv) and e.v2 or e.v1
	local vNew = self:vertCreate(tv.co:Lerp(vOld.co, t or 0.5))
	-- eNew = tv - vNew ; e becomes vNew - vOld
	local eNew = { v1 = tv, v2 = vNew, l = nil, d1 = { next = nil, prev = nil }, d2 = { next = nil, prev = nil }, sel = e.sel, seam = e.seam }
	self.edges[eNew] = true
	self.ne += 1
	diskVertReplace(e, vNew, tv)
	diskAppend(eNew, vNew)
	diskAppend(eNew, tv)
	-- every face that used e gets a new corner at vNew
	local lNext = e.l
	e.l = nil
	local isFirst = true
	while lNext do
		local l = lNext
		l.f.len += 1
		lNext = (lNext ~= lNext.rnext) and lNext.rnext or nil
		radialUnlink(l)
		local lNew = loopCreate(vNew, nil, l.f)
		lNew.prev = l
		lNew.next = l.next
		lNew.prev.next = lNew
		lNew.next.prev = lNew
		local a, b = lNew.v, lNew.next.v
		local function inEdge(x) return (x.v1 == a and x.v2 == b) or (x.v1 == b and x.v2 == a) end
		if inEdge(e) then
			if isFirst then isFirst = false l.rnext, l.rprev = nil, nil end
			radialAppend(e, lNew)
			radialAppend(eNew, l)
		else
			if isFirst then isFirst = false l.rnext, l.rprev = nil, nil end
			radialAppend(eNew, lNew)
			radialAppend(e, l)
		end
	end
	return vNew, eNew
end

-- ===== euler: split face (bmesh_kernel_split_face_make_edge) =====
-- lA, lB = two corners of face f (not next to each other); makes edge lA.v - lB.v, returns the NEW face
function BMesh:faceSplit(f, lA, lB)
	local v1, v2 = lA.v, lB.v
	local e = self:edgeCreate(v1, v2, true)
	local f2 = { l = nil, len = 0, no = f.no, sel = f.sel, mat = f.mat, smooth = f.smooth }
	local lF1 = loopCreate(v2, e, f)
	local lF2 = loopCreate(v1, e, f2)
	lF1.prev = lB.prev
	lF2.prev = lA.prev
	lB.prev.next = lF1
	lA.prev.next = lF2
	lF1.next = lA
	lF2.next = lB
	lA.prev = lF1
	lB.prev = lF2
	-- f keeps the ring through lF1, f2 gets the ring through lF2
	f.l = lF1
	f2.l = lF2
	local n2 = 0
	local l = lF2
	repeat l.f = f2 n2 += 1 l = l.next until l == lF2
	local n1 = 0
	l = lF1
	repeat n1 += 1 l = l.next until l == lF1
	lF1.e, lF2.e = nil, nil
	radialAppend(e, lF1)
	radialAppend(e, lF2)
	f.len, f2.len = n1, n2
	self.faces[f2] = true
	self.nf += 1
	BMesh.faceNormalUpdate(f)
	BMesh.faceNormalUpdate(f2)
	return f2, e
end

-- ===== queries (bmesh_query / bmesh_polygon) =====
function BMesh.faceLoops(f)
	local out = {}
	local first = f.l
	if not first then return out end
	local l = first
	repeat out[#out + 1] = l l = l.next until l == first
	return out
end

function BMesh.faceVerts(f)
	local out = {}
	for i, l in ipairs(BMesh.faceLoops(f)) do out[i] = l.v end
	return out
end

-- Newell's method (BM_face_calc_normal)
function BMesh.faceNormalUpdate(f)
	local nx, ny, nz = 0, 0, 0
	local first = f.l
	if not first then return end
	local l = first
	repeat
		local a, b = l.v.co, l.next.v.co
		nx += (a.Y - b.Y) * (a.Z + b.Z)
		ny += (a.Z - b.Z) * (a.X + b.X)
		nz += (a.X - b.X) * (a.Y + b.Y)
		l = l.next
	until l == first
	local n = V3(nx, ny, nz)
	f.no = n.Magnitude > 1e-12 and n.Unit or V3(0, 1, 0)
end

function BMesh.faceCenter(f)
	local s, n = V3(), 0
	for _, v in ipairs(BMesh.faceVerts(f)) do s += v.co n += 1 end
	return n > 0 and s / n or s
end

function BMesh:normalsUpdate()
	for f in pairs(self.faces) do BMesh.faceNormalUpdate(f) end
end

function BMesh.otherVert(e, v) return (e.v1 == v) and e.v2 or e.v1 end

function BMesh.vertFaces(v)
	local out, seen = {}, {}
	for _, e in ipairs(BMesh.vertEdges(v)) do
		for _, f in ipairs(BMesh.edgeFaces(e)) do
			if not seen[f] then seen[f] = true out[#out + 1] = f end
		end
	end
	return out
end

-- the loop of face f sitting on edge e (nil if f doesn't use e)
function BMesh.faceEdgeLoop(f, e)
	local first = e.l
	if not first then return nil end
	local l = first
	repeat
		if l.f == f then return l end
		l = l.rnext
	until l == first
	return nil
end

-- ===== save / load (a plain table: numbered verts + faces as vert-number lists) =====
function BMesh:toData()
	local vi, n = {}, 0
	local vs = {}
	for v in pairs(self.verts) do
		n += 1
		vi[v] = n
		local c = v.co
		vs[#vs + 1] = math.floor(c.X * 10000 + 0.5) / 10000
		vs[#vs + 1] = math.floor(c.Y * 10000 + 0.5) / 10000
		vs[#vs + 1] = math.floor(c.Z * 10000 + 0.5) / 10000
	end
	local fs, fOrder = {}, {}
	for f in pairs(self.faces) do
		local idx = {}
		for i, v in ipairs(BMesh.faceVerts(f)) do idx[i] = vi[v] end
		fs[#fs + 1] = idx
		fOrder[#fOrder + 1] = f
	end
	-- loose edges (no face) too, plus smooth faces and sharp / seam / crease edges
	local es, sm, sh, se, cr = {}, {}, {}, {}, {}
	for e in pairs(self.edges) do
		if not e.l then es[#es + 1] = vi[e.v1] es[#es + 1] = vi[e.v2] end
		if e.sharp then sh[#sh + 1] = vi[e.v1] sh[#sh + 1] = vi[e.v2] end
		if e.seam then se[#se + 1] = vi[e.v1] se[#se + 1] = vi[e.v2] end
		if e.crease then cr[#cr + 1] = vi[e.v1] cr[#cr + 1] = vi[e.v2] end
	end
	for i, f in ipairs(fOrder) do if f.smooth then sm[#sm + 1] = i end end
	local d = { v = vs, f = fs, e = es }
	-- vertex colours (Vertex Paint): one 0xRRGGBB per vert, in vert order; only saved when something is painted
	local vc, anyCol = {}, false
	for v in pairs(self.verts) do
		local c = v.col
		if c then anyCol = true end
		vc[vi[v]] = c and (math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)) or 0xFFFFFF
	end
	if anyCol then d.vc = vc end
	if #sm > 0 then d.s = sm end
	if #sh > 0 then d.sh = sh end
	if #se > 0 then d.se = se end
	if #cr > 0 then d.cr = cr end
	return d, vi, fOrder
end

-- returns the mesh + its verts and faces in data order (so a selection can be carried across)
function BMesh.fromData(d)
	local bm = BMesh.new()
	local vs, fl = {}, {}
	for i = 1, #d.v, 3 do vs[#vs + 1] = bm:vertCreate(V3(d.v[i], d.v[i + 1], d.v[i + 2])) end
	if d.vc then
		for i, hex in ipairs(d.vc) do
			if vs[i] and hex ~= 0xFFFFFF then vs[i].col = Color3.fromRGB(math.floor(hex / 65536) % 256, math.floor(hex / 256) % 256, hex % 256) end
		end
	end
	for _, idx in ipairs(d.f or {}) do
		local list = {}
		for i, k in ipairs(idx) do list[i] = vs[k] end
		fl[#fl + 1] = bm:faceCreate(list) or false
	end
	local es = d.e or {}
	for i = 1, #es, 2 do if vs[es[i]] and vs[es[i + 1]] then bm:edgeCreate(vs[es[i]], vs[es[i + 1]], true) end end
	for _, i in ipairs(d.s or {}) do if fl[i] then fl[i].smooth = true end end
	for key, list in pairs({ sharp = d.sh or {}, seam = d.se or {}, crease = d.cr or {} }) do
		for i = 1, #list, 2 do
			local a, b = vs[list[i]], vs[list[i + 1]]
			local e = a and b and BMesh.edgeExists(a, b)
			if e then e[key] = true end
		end
	end
	return bm, vs, fl
end

function BMesh:copy()
	return BMesh.fromData(self:toData())
end

-- quick health check (used by the tests): every cycle closes, counts match
function BMesh:validate()
	for e in pairs(self.edges) do
		assert(e.v1 ~= e.v2, "edge with the same vert twice")
		for _, v in ipairs({ e.v1, e.v2 }) do
			local dl = diskLink(e, v)
			assert(dl.next and dl.prev, "edge not in its vert's disk cycle")
		end
		if e.l then
			local l, n = e.l, 0
			repeat
				assert(l.e == e, "radial loop points at another edge")
				l = l.rnext n += 1
				assert(n < 10000, "radial cycle doesn't close")
			until l == e.l
		end
	end
	for f in pairs(self.faces) do
		local ls = BMesh.faceLoops(f)
		assert(#ls == f.len, ("face len %d but %d loops"):format(f.len, #ls))
		for _, l in ipairs(ls) do
			assert(l.f == f, "loop points at another face")
			local e = l.e
			assert(e and ((e.v1 == l.v and e.v2 == l.next.v) or (e.v2 == l.v and e.v1 == l.next.v)), "loop edge doesn't join its verts")
		end
	end
	for v in pairs(self.verts) do
		if v.e then
			local n = 0
			local e = v.e
			repeat
				assert(e.v1 == v or e.v2 == v, "disk edge doesn't use the vert")
				e = diskLink(e, v).next
				n += 1
				assert(n < 10000, "disk cycle doesn't close")
			until e == v.e
		end
	end
	return true
end

return BMesh
