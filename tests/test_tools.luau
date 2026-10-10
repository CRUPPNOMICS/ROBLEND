-- Modeling-tab mesh tools tests (MeshTools.lua), run after test_engine.luau's helpers
local pass2, fail2 = 0, 0
local function check2(name, fn)
	local ok, err = pcall(fn)
	if ok then pass2 += 1 print("PASS " .. name) else fail2 += 1 print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end
local function closed(bm) for ed in pairs(bm.edges) do eq(BMesh.edgeFaceCount(ed), 2, "closed") end end
local function outward(bm)
	local c, n = Vector3.new(), 0
	for v in pairs(bm.verts) do c = c + v.co n += 1 end
	c = c / n
	for f in pairs(bm.faces) do
		BMesh.faceNormalUpdate(f)
		if (BMesh.faceCenter(f) - c):Dot(f.no) <= 0 then error("a face points inward") end
	end
end
local function cube() local bm = BMesh.new() Ops.cube(bm, 2) return bm end
local function edgeWhere(bm, fn) for e in pairs(bm.edges) do if fn(e.v1.co, e.v2.co) then return e end end end
local function topFace(bm) local t for f in pairs(bm.faces) do if f.no.Y > 0.9 then t = f end end return t end
local fan = function(vs) local t = {} for i = 2, #vs - 1 do t[#t + 1] = { 1, i, i + 1 } end return t end

check2("bevel one cube edge", function()
	local bm = cube()
	edgeWhere(bm, function(a, b) return a.Y > 0 and b.Y > 0 and a.Z > 0 and b.Z > 0 end).sel = true
	local nb = MT.bevel(bm, 0.25)
	nb:validate()
	eq(nb.nf, 7, "faces") eq(nb.nv, 10, "verts")
	closed(nb) outward(nb)
end)
check2("bevel all 12 edges (corners get caps)", function()
	local bm = cube()
	for e in pairs(bm.edges) do e.sel = true end
	local nb = MT.bevel(bm, 0.2)
	nb:validate()
	eq(nb.nf, 26, "faces") eq(nb.nv, 24, "verts")
	closed(nb) outward(nb)
end)
check2("vertex bevel a corner", function()
	local bm = cube()
	for v in pairs(bm.verts) do if v.co.X > 0 and v.co.Y > 0 and v.co.Z > 0 then v.sel = true end end
	local nb = MT.bevel(bm, 0.3, true)
	nb:validate()
	eq(nb.nf, 7, "faces") eq(nb.nv, 10, "verts")
	closed(nb) outward(nb)
end)
check2("knife across the top", function()
	local bm = cube()
	local e1 = edgeWhere(bm, function(a, b) return a.Y > 0 and b.Y > 0 and a.Z > 0 and b.Z > 0 end)
	local e2 = edgeWhere(bm, function(a, b) return a.Y > 0 and b.Y > 0 and a.Z < 0 and b.Z < 0 end)
	local cut = MT.knife(bm, { { e = e1, t = 0.5 }, { e = e2, t = 0.5 } })
	bm:validate()
	eq(bm.nf, 7, "faces") eq(bm.nv, 10, "verts") eq(MT.count(cut), 1, "one cut edge")
	closed(bm)
end)
check2("bisect a cube through the middle", function()
	local bm = cube()
	MT.bisect(bm, Vector3.new(), Vector3.new(0, 1, 0))
	bm:validate()
	eq(bm.nv, 12, "verts") eq(bm.nf, 10, "faces")
	closed(bm) outward(bm)
end)
check2("spin an edge round Y (lathe)", function()
	local bm = BMesh.new()
	local a, b = bm:vertCreate(Vector3.new(1, 0, 0)), bm:vertCreate(Vector3.new(1, 2, 0))
	local e = bm:edgeCreate(a, b)
	a.sel, b.sel, e.sel = true, true, true
	MT.spin(bm, Vector3.new(), Vector3.new(0, 1, 0), math.rad(360), 8)
	bm:validate()
	eq(bm.nf, 8, "faces")
	local m = MT.mergeVerts and nil
	local nb = Ops.mergeByDistance(bm, nil, 0.001)
	nb:validate()
	eq(nb.nv, 16, "verts after welding the seam")
end)
check2("spin a face keeps the start cap", function()
	local bm = BMesh.new()
	Ops.plane(bm, 2)
	for f in pairs(bm.faces) do MT.selectFace(f) end
	for v in pairs(bm.verts) do v.co = v.co + Vector3.new(3, 0, 0) end
	bm:normalsUpdate()
	MT.spin(bm, Vector3.new(), Vector3.new(0, 0, 1), math.rad(90), 4)
	bm:validate()
	closed(bm)
end)
check2("smooth + randomize + to sphere", function()
	local bm = cube()
	local top = {}
	for v in pairs(bm.verts) do if v.co.Y > 0 then top[v] = true end end
	MT.smooth(bm, top, 0.5, 1)
	for v in pairs(top) do assert(v.co.Y < 1, "moved toward neighbours") end
	MT.randomize(bm, top, 0.1, 3)
	local all, orig = {}, {}
	for v in pairs(bm.verts) do all[v] = true orig[v] = v.co end
	MT.toSphere(all, orig, Vector3.new(), 1)
	local r
	for v in pairs(all) do local m = v.co.Magnitude r = r or m assert(math.abs(m - r) < 1e-6, "on a sphere") end
end)
check2("duplicate / split / rip", function()
	local bm = cube()
	MT.selectFace(topFace(bm))
	local d = MT.duplicate(bm)
	d:validate()
	eq(d.nf, 7, "dup faces") eq(d.nv, 12, "dup verts")
	local bm2 = cube()
	MT.selectFace(topFace(bm2))
	local s = MT.split(bm2)
	s:validate()
	eq(s.nf, 6, "split faces") eq(s.nv, 12, "split verts")
	local bm3 = cube()
	for v in pairs(bm3.verts) do if v.co.Y > 0 and v.co.Z > 0 then v.sel = true end end
	local t3 = topFace(bm3)
	local r = MT.rip(bm3, function(f) return f == t3 end)
	r:validate()
	eq(r.nv, 10, "ripped verts")
	local n = 0
	for v in pairs(r.verts) do if v.sel then n += 1 end end
	eq(n, 2, "the ripped copies are selected")
end)
check2("dissolve edge / vert / faces, edge collapse, delete loose", function()
	local bm = cube()
	local e = edgeWhere(bm, function(a, b) return a.Y > 0 and b.Y > 0 and a.Z > 0 and b.Z > 0 end)
	assert(MT.dissolveEdge(bm, e), "joined")
	bm:validate()
	eq(bm.nf, 5, "faces")
	local s = cube()
	local top = topFace(s)
	local nf = Ops.subdivideFaces(s, { [top] = true })
	s:validate()
	local mid
	for v in pairs(s.verts) do if math.abs(v.co.X) < 1e-6 and math.abs(v.co.Z) < 1e-6 and v.co.Y > 0 then mid = v end end
	assert(MT.dissolveVert(s, mid), "dissolved the middle")
	s:validate()
	eq(s.nf, 6, "back to 6 faces")
	local g = BMesh.new()
	Ops.grid(g, 2, 2, 2)
	local all = {}
	for f in pairs(g.faces) do all[f] = true f.sel = true end
	MT.dissolveFaces(g, all)
	g:validate()
	eq(g.nf, 1, "grid dissolved to one face")
	local c = cube()
	local ce = edgeWhere(c, function(a, b) return a.Y > 0 and b.Y > 0 and a.Z > 0 and b.Z > 0 end)
	local cc = MT.edgeCollapse(c, { [ce] = true })
	cc:validate()
	eq(cc.nv, 7, "collapsed")
	local l = BMesh.new()
	l:vertCreate(Vector3.new())
	Ops.plane(l, 1)
	l:edgeCreate(l:vertCreate(Vector3.new(5, 0, 0)), l:vertCreate(Vector3.new(6, 0, 0)))
	eq(MT.deleteLoose(l), 4, "loose removed (vert, edge + its 2 verts)")
	l:validate()
end)
check2("rotate edge, bridge loops, connect verts", function()
	local g = BMesh.new()
	Ops.grid(g, 2, 1, 2)
	local mid = edgeWhere(g, function(a, b) return math.abs(a.X) < 1e-6 and math.abs(b.X) < 1e-6 end)
	assert(MT.rotateEdge(g, mid, false), "rotated")
	g:validate()
	eq(g.nf, 2, "faces")
	local b = BMesh.new()
	Ops.circle(b, 8, 1, false)
	local c2 = BMesh.new()
	for v in pairs(b.verts) do v.sel = true end
	for e in pairs(b.edges) do e.sel = true end
	-- second ring above
	local ring = {}
	for i = 1, 8 do local a = (i - 1) / 8 * math.pi * 2 ring[i] = b:vertCreate(Vector3.new(math.cos(a), 2, math.sin(a))) end
	for i = 1, 8 do local e = b:edgeCreate(ring[i], ring[i % 8 + 1]) e.sel = true ring[i].sel = true end
	local out = MT.bridge(b)
	assert(out, "bridged")
	b:validate()
	eq(b.nf, 8, "8 quads")
	local p = BMesh.new()
	Ops.plane(p, 2)
	local vs = {}
	local list = {}
	for v in pairs(p.verts) do list[#list + 1] = v end
	table.sort(list, function(x, y) return x.co.X + x.co.Z < y.co.X + y.co.Z end)
	local made = MT.connectVerts(p, { [list[1]] = true, [list[4]] = true })
	p:validate()
	eq(p.nf, 2, "split across")
	eq(MT.count(made), 1, "one new edge")
end)
check2("poke, triangulate, tris to quads, solidify, extrude individual", function()
	local bm = cube()
	MT.poke(bm, { [topFace(bm)] = true })
	bm:validate() eq(bm.nf, 9, "poked") closed(bm) outward(bm)
	local t = cube()
	MT.triangulate(t, t.faces, fan)
	t:validate() eq(t.nf, 12, "triangulated") closed(t) outward(t)
	local all = {}
	for f in pairs(t.faces) do all[f] = true end
	MT.trisToQuads(t, all)
	t:validate() eq(t.nf, 6, "back to quads") closed(t)
	local p = BMesh.new()
	Ops.plane(p, 2)
	MT.solidify(p, { [next(p.faces)] = true }, 0.5)
	p:validate() eq(p.nf, 6, "solid") closed(p) outward(p)
	local g = BMesh.new()
	Ops.grid(g, 2, 1, 2)
	local fs = {}
	for f in pairs(g.faces) do fs[f] = true end
	local nv, nf = MT.extrudeIndividual(g, fs)
	g:validate()
	eq(MT.count(nf), 2, "two tops") eq(g.nf, 10, "faces")
end)
check2("tris to quads keeps UVs, and with uv / sharp / shape only joins clean pairs (MeshPart import)", function()
	-- a square as two triangles that share their UVs: joins, and the quad keeps the four UVs
	local function square(seam)
		local bm = BMesh.new()
		local a, b, c, d = bm:vertCreate(Vector3.new(0, 0, 0)), bm:vertCreate(Vector3.new(1, 0, 0)), bm:vertCreate(Vector3.new(1, 0, 1)), bm:vertCreate(Vector3.new(0, 0, 1))
		local uv = { [a] = Vector2.new(0, 0), [b] = Vector2.new(1, 0), [c] = Vector2.new(1, 1), [d] = Vector2.new(0, 1) }
		local f1, f2 = bm:faceCreate({ a, c, b }), bm:faceCreate({ a, d, c })
		for _, l in ipairs(BMesh.faceLoops(f1)) do l.uv = uv[l.v] end
		for _, l in ipairs(BMesh.faceLoops(f2)) do l.uv = (seam and l.v == c) and Vector2.new(5, 5) or uv[l.v] end
		bm:normalsUpdate()
		return bm, { [f1] = true, [f2] = true }, uv
	end
	local bm, fs, uv = square(false)
	eq(MT.trisToQuads(bm, fs, nil, { uv = true, sharp = true, shape = true }), 1, "joined")
	local q = next(bm.faces)
	eq(q.len, 4, "a quad")
	for _, l in ipairs(BMesh.faceLoops(q)) do assert(l.uv and (l.uv - uv[l.v]).Magnitude < 1e-9, "UV kept on the quad") end
	-- a UV seam down the diagonal: stays two triangles
	local s2, fs2 = square(true)
	eq(MT.trisToQuads(s2, fs2, nil, { uv = true }), 0, "not across a UV seam")
	-- a sharp diagonal: stays
	local s3, fs3 = square(false)
	for e in pairs(s3.edges) do if BMesh.edgeFaceCount(e) == 2 then e.sharp = true end end
	eq(MT.trisToQuads(s3, fs3, nil, { sharp = true }), 0, "not across a sharp edge")
end)
check2("convex hull, symmetrize, recalc normals", function()
	local h = BMesh.new()
	local vs = {}
	for _, x in ipairs({ -1, 1 }) do for _, y in ipairs({ -1, 1 }) do for _, z in ipairs({ -1, 1 }) do vs[h:vertCreate(Vector3.new(x, y, z))] = true end end end
	vs[h:vertCreate(Vector3.new(0.1, 0.2, 0))] = true
	MT.convexHull(h, vs)
	h:validate()
	eq(h.nf, 6, "box hull") eq(h.nv, 8, "inner point gone") closed(h) outward(h)
	local s = cube()
	for v in pairs(s.verts) do if v.co.X > 0 then v.co = v.co + Vector3.new(1, 0, 0) end end
	s:normalsUpdate()
	local nb = MT.symmetrize(s, "X")
	nb:validate()
	closed(nb)
	local mx = 0
	for v in pairs(nb.verts) do mx = math.max(mx, v.co.X) end
	assert(math.abs(mx - 1) < 1e-6, "+X now mirrors -X: " .. mx)
	local c = cube()
	local some = {}
	local i = 0
	for f in pairs(c.faces) do i += 1 if i % 2 == 0 then some[f] = true end end
	local flipped = Ops.flipFaces(c, some)
	local fixed = MT.recalcNormals(flipped)
	fixed:validate()
	outward(fixed)
end)
check2("selection: more / less / linked / non-manifold / sharp / sides / checker / random", function()
	local bm = BMesh.new()
	Ops.grid(bm, 4, 4, 4)
	local start
	for v in pairs(bm.verts) do if math.abs(v.co.X) < 1e-6 and math.abs(v.co.Z) < 1e-6 then start = v end end
	start.sel = true
	MT.selectMore(bm, "vert")
	local n = 0 for v in pairs(bm.verts) do if v.sel then n += 1 end end
	eq(n, 5, "grew to neighbours")
	MT.selectLess(bm, "vert")
	n = 0 for v in pairs(bm.verts) do if v.sel then n += 1 end end
	eq(n, 1, "shrank back")
	MT.selectLinked(bm, { [start] = true })
	n = 0 for v in pairs(bm.verts) do if v.sel then n += 1 end end
	eq(n, 25, "whole grid")
	MT.selectNonManifold(bm)
	n = 0 for e in pairs(bm.edges) do if e.sel then n += 1 end end
	eq(n, 16, "border edges")
	local c = cube()
	MT.selectSharp(c)
	n = 0 for e in pairs(c.edges) do if e.sel then n += 1 end end
	eq(n, 12, "all cube edges are sharp")
	MT.selectBySides(c, 4)
	n = 0 for f in pairs(c.faces) do if f.sel then n += 1 end end
	eq(n, 6, "quads")
	MT.checkerDeselect(c, "face")
	n = 0 for f in pairs(c.faces) do if f.sel then n += 1 end end
	assert(n > 0 and n < 6, "checker left some " .. n)
	MT.selectRandom(c, "face", 0.5, 1)
end)
check2("hide / reveal, mirror, smooth flag + sharp saved", function()
	local c = cube()
	local t = topFace(c)
	MT.selectFace(t)
	MT.hide(c, "face")
	assert(t.hide and not t.sel, "hidden")
	MT.reveal(c)
	assert(not t.hide and t.sel, "revealed + selected")
	local all, orig = {}, {}
	for v in pairs(c.verts) do all[v] = true end
	local m = MT.mirror(c, all, Vector3.new(), Vector3.new(1, 0, 0))
	m:validate()
	outward(m)
	for f in pairs(m.faces) do f.smooth = true end
	local e = next(m.edges)
	e.sharp = true
	local d = m:toData()
	local back = BMesh.fromData(d)
	local sm = 0 for f in pairs(back.faces) do if f.smooth then sm += 1 end end
	eq(sm, 6, "smooth kept")
	local sh = 0 for ed in pairs(back.edges) do if ed.sharp then sh += 1 end end
	eq(sh, 1, "sharp kept")
end)

check2("bevel with segments: a round edge, watertight", function()
	local bm = cube()
	edgeWhere(bm, function(a, b) return a.Y > 0 and b.Y > 0 and a.Z > 0 and b.Z > 0 end).sel = true
	local nb = MT.bevel(bm, 0.4, false, 3)
	nb:validate()
	eq(nb.nf, 9, "faces") eq(nb.nv, 14, "verts")
	closed(nb) outward(nb)
	-- the middle profile points sit on a circle round the rounded edge's axis
	local all = cube()
	for e in pairs(all.edges) do e.sel = true end
	local r = MT.bevel(all, 0.3, false, 2)
	r:validate()
	closed(r)
end)
check2("loop cut with 3 cuts + ring preview + shortest path", function()
	local bm = cube()
	local e0 = edgeWhere(bm, function(a, b) return math.abs(a.Y - b.Y) > 1 and a.X > 0 and a.Z > 0 end)
	local lines = MT.ringCuts(bm, e0, 2)
	eq(#lines, 8, "2 cuts round 4 faces")
	local made = MT.loopCutN(bm, e0, 3)
	bm:validate()
	eq(bm.nf, 18, "faces") closed(bm)
	local ys = {}
	for v in pairs(bm.verts) do ys[math.floor(v.co.Y * 1000 + 0.5)] = true end
	local n = 0 for _ in pairs(ys) do n += 1 end
	eq(n, 5, "evenly spaced levels")
	local g = BMesh.new()
	Ops.grid(g, 4, 4, 4)
	local a, b
	for v in pairs(g.verts) do
		if v.co.X < -1.9 and v.co.Z < -1.9 then a = v end
		if v.co.X > 1.9 and v.co.Z > 1.9 then b = v end
	end
	assert(MT.shortestPath(g, a, b, "vert"), "path found")
	local c = 0 for v in pairs(g.verts) do if v.sel then c += 1 end end
	eq(c, 9, "corner to corner is 9 verts")
end)

-- ===== modifiers (Modifiers.lua) =====
check2("mirror modifier (half cube -> closed cube)", function()
	local bm = BMesh.new()
	-- an open half cube on +X: delete the -X face of a cube shifted so its -X side sits on the plane
	Ops.cube(bm, 2)
	for v in pairs(bm.verts) do v.co = v.co + Vector3.new(1, 0, 0) end
	local kill
	for f in pairs(bm.faces) do BMesh.faceNormalUpdate(f) if f.no.X < -0.9 then kill = f end end
	bm:faceKill(kill)
	local out = Mods.evaluate(bm, { Mods.new("mirror") })
	out:validate()
	eq(out.nf, 10, "faces") eq(out.nv, 12, "verts")
	closed(out) outward(out)
	eq(bm.nf, 5, "base untouched")
end)
check2("subsurf cube: level 1 = 24 quads, level 2 = 96", function()
	local m = Mods.new("subsurf")
	local out = Mods.evaluate(cube(), { m })
	out:validate()
	eq(out.nf, 24, "faces") eq(out.nv, 26, "verts")
	closed(out) outward(out)
	-- corners pull in (Catmull-Clark shrinks a cube)
	for v in pairs(out.verts) do assert(v.co.Magnitude < 1.74, "inside the cage") end
	m.levels = 2
	out = Mods.evaluate(cube(), { m })
	eq(out.nf, 96, "level 2") closed(out)
end)
check2("solidify a plane = closed 6-face slab", function()
	local bm = BMesh.new() Ops.plane(bm, 2)
	local out = Mods.evaluate(bm, { Mods.new("solidify") })
	out:validate()
	eq(out.nf, 6, "faces") closed(out)
	local lo, hi = math.huge, -math.huge
	for v in pairs(out.verts) do lo = math.min(lo, v.co.Y) hi = math.max(hi, v.co.Y) end
	assert(math.abs(hi - lo - 0.2) < 1e-3, "0.2 thick, got " .. (hi - lo))
end)
check2("array of 3 cubes along X + toggled off", function()
	local m = Mods.new("array")
	local out = Mods.evaluate(cube(), { m })
	eq(out.nf, 18, "faces") eq(out.nv, 24, "verts")
	local hx = -math.huge
	for v in pairs(out.verts) do hx = math.max(hx, v.co.X) end
	assert(math.abs(hx - 5) < 1e-4, "last copy ends at x = 5")
	m.on = false
	local base = cube()
	assert(Mods.evaluate(base, { m }) == base, "disabled stack returns the base")
	assert(not Mods.active({ m }), "nothing active")
end)
check2("bevel modifier rounds every cube edge", function()
	local m = Mods.new("bevel")
	m.segments = 1
	local out = Mods.evaluate(cube(), { m })
	out:validate()
	eq(out.nf, 26, "faces") closed(out) outward(out)
	m.segments = 3
	out = Mods.evaluate(cube(), { m })
	out:validate() closed(out)
	assert(out.nf > 26, "more segments, more faces")
end)
check2("stack: mirror -> subsurf -> smooth, base unchanged", function()
	local bm = cube()
	local out = Mods.evaluate(bm, { Mods.new("array"), Mods.new("subsurf"), Mods.new("smooth") })
	out:validate() closed(out)
	eq(out.nf, 72, "3 cubes x 24") eq(bm.nf, 6, "base")
end)
check2("merge doubles welds two touching cubes' shared corners", function()
	local bm = cube()
	local out = Mods.evaluate(bm, { Mods.new("array") })
	local nb, n = Mods.mergeDoubles(out, 0.001)
	eq(n, 8, "merged") nb:validate()
	eq(nb.nv, 16, "verts")
	local same, k = Mods.mergeDoubles(cube(), 0.001)
	eq(k, 0, "nothing to merge")
end)
check2("weld + triangulate modifiers", function()
	local out = Mods.evaluate(cube(), { Mods.new("array"), Mods.new("weld") })
	eq(out.nv, 16, "array copies welded")
	local tri = Mods.evaluate(cube(), { Mods.new("triangulate") })
	eq(tri.nf, 12, "12 triangles") closed(tri) outward(tri)
end)
check2("decimate (planar) joins a flat grid back into one face", function()
	local g = BMesh.new() Ops.grid(g, 4, 4, 4)
	local planar = Mods.new("decimate")
	planar.mode = "Planar"
	local out = Mods.evaluate(g, { planar })
	out:validate()
	eq(out.nf, 1, "one face") eq(out.nv, 4, "4 corners")
	local c = Mods.evaluate(Mods.evaluate(cube(), { Mods.new("subsurf") }), { planar })
	eq(c.nf, 24, "a curved surface is left alone")
end)
check2("screw: a line spun 360 degrees makes a closed tube band", function()
	local bm = BMesh.new()
	local a, b = bm:vertCreate(Vector3.new(1, -1, 0)), bm:vertCreate(Vector3.new(1, 1, 0))
	bm:edgeCreate(a, b)
	local m = Mods.new("screw")
	m.steps = 8
	local out = Mods.evaluate(bm, { m })
	out:validate()
	eq(out.nf, 8, "faces") eq(out.nv, 16, "verts")
	for v in pairs(out.verts) do assert(math.abs(Vector3.new(v.co.X, 0, v.co.Z).Magnitude - 1) < 1e-4, "radius 1") end
	m.angle, m.screw = 180, 2
	out = Mods.evaluate(bm, { m })
	eq(out.nf, 8, "half turn faces") eq(out.nv, 18, "open ends")
end)
check2("simple deform: twist keeps the ends, bend curls, taper narrows the top", function()
	local tall = cube()
	for v in pairs(tall.verts) do v.co = Vector3.new(v.co.X, v.co.Y * 4, v.co.Z) end
	local m = Mods.new("simpledeform")
	m.angle = 90
	local out = Mods.evaluate(tall, { m })
	out:validate()
	for v in pairs(out.verts) do
		assert(math.abs(Vector3.new(v.co.X, 0, v.co.Z).Magnitude - math.sqrt(2)) < 1e-4, "twist keeps the radius")
		assert(math.abs(math.abs(v.co.Y) - 4) < 1e-4, "same height")
	end
	m.method = "Taper"
	out = Mods.evaluate(tall, { m })
	for v in pairs(out.verts) do
		if v.co.Y > 0 then assert(math.abs(math.abs(v.co.X) - 1.5) < 1e-4, "top wider by factor") else assert(math.abs(math.abs(v.co.X) - 0.5) < 1e-4, "bottom narrower") end
	end
	local long = cube()
	for v in pairs(long.verts) do v.co = Vector3.new(v.co.X * 4, v.co.Y, v.co.Z) end
	m.method, m.angle, m.axis = "Bend", 180, "Z"
	out = Mods.evaluate(long, { m })
	out:validate()
	local hy = -math.huge
	for v in pairs(out.verts) do hy = math.max(hy, v.co.Y) end
	assert(hy > 2.5, "the ends curl up into a half circle: " .. hy)
	m.method, m.axis = "Stretch", "Y"
	out = Mods.evaluate(tall, { m })
	local hy = 0 for v in pairs(out.verts) do hy = math.max(hy, v.co.Y) end
	assert(math.abs(hy - 6) < 1e-4, "stretched to 1.5x")
end)
check2("cast to sphere, wave, displace", function()
	local m = Mods.new("cast") m.factor = 1
	local s = Mods.evaluate(Mods.evaluate(cube(), { Mods.new("subsurf") }), { m })
	local r
	for v in pairs(s.verts) do
		local d = v.co.Magnitude
		r = r or d
		assert(math.abs(d - r) < 1e-4, "all on one sphere")
	end
	local g = BMesh.new() Ops.grid(g, 8, 8, 8)
	local w = Mods.evaluate(g, { Mods.new("wave") })
	local lo, hi = math.huge, -math.huge
	for v in pairs(w.verts) do lo = math.min(lo, v.co.Y) hi = math.max(hi, v.co.Y) end
	assert(hi - lo > 0.5, "waves")
	local d = Mods.evaluate(g, { Mods.new("displace") })
	local diff = 0
	for v in pairs(d.verts) do diff += math.abs(v.co.Y) end
	assert(diff > 0.1, "displaced")
	local d2 = Mods.evaluate(g, { Mods.new("displace") })
	local same = true
	local ys = {} for v in pairs(d.verts) do ys[#ys + 1] = v.co.Y end
	table.sort(ys)
	local ys2 = {} for v in pairs(d2.verts) do ys2[#ys2 + 1] = v.co.Y end
	table.sort(ys2)
	for i = 1, #ys do if math.abs(ys[i] - ys2[i]) > 1e-9 then same = false end end
	assert(same, "same result every time")
end)
check2("cone, torus and ico sphere are closed and face outwards", function()
	local c = BMesh.new() Ops.cone(c, 16, 2, 4) c:validate() closed(c) outward(c) eq(c.nf, 17, "cone faces")
	local t = BMesh.new() Ops.torus(t, 24, 8, 2, 0.5) t:validate() closed(t) eq(t.nf, 192, "torus faces")
	for f in pairs(t.faces) do
		BMesh.faceNormalUpdate(f)
		local cc = BMesh.faceCenter(f)
		local tube = Vector3.new(cc.X, 0, cc.Z).Unit * 2
		assert((cc - tube):Dot(f.no) > 0, "torus face points out of the tube")
	end
	local s = BMesh.new() Ops.icoSphere(s, 2, 2) s:validate() closed(s) outward(s)
	eq(s.nf, 320, "ico faces") eq(s.nv, 162, "ico verts")
	for v in pairs(s.verts) do assert(math.abs(v.co.Magnitude - 2) < 1e-4, "on the sphere") end
end)
check2("wireframe modifier: a cube becomes 12 closed beams' worth of frame", function()
	local out = Mods.evaluate(cube(), { Mods.new("wireframe") })
	out:validate()
	closed(out)
	eq(out.nf, 24 * 3, "frame quads outside + inside + the rims round the 6 holes")
end)
check2("select similar: face area, edge length, vert edge count", function()
	local bm = cube()
	local g = BMesh.new() Ops.grid(g, 2, 2, 4)
	local f1 = next(g.faces)
	f1.sel = true
	local n = MT.selectSimilar(g, "face", "area")
	eq(n, 3, "the other 3 grid squares")
	for e in pairs(bm.edges) do e.sel = false end
	local e0 = next(bm.edges) e0.sel = true
	eq(MT.selectSimilar(bm, "edge", "length"), 11, "all cube edges are the same length")
	for v in pairs(bm.verts) do v.sel = false end
	local vv = next(bm.verts) vv.sel = true
	eq(MT.selectSimilar(bm, "vert", "edges"), 7, "all corners have 3 edges")
	for f in pairs(bm.faces) do f.sel = false end
	local top = topFace(bm) top.sel = true
	eq(MT.selectSimilar(bm, "face", "normal"), 0, "no other face points up")
end)
check2("creased edges keep subdivision sharp; crease saves and loads", function()
	local bm = cube()
	for e in pairs(bm.edges) do e.crease = true end
	local out = Mods.evaluate(bm, { Mods.new("subsurf") })
	for v in pairs(out.verts) do
		assert(math.abs(math.abs(v.co.X) - 1) < 1e-4 or math.abs(math.abs(v.co.Y) - 1) < 1e-4 or math.abs(math.abs(v.co.Z) - 1) < 1e-4, "every vert stays on the cube's surface")
	end
	local m2 = Mods.new("subsurf") m2.levels = 2
	local out2 = Mods.evaluate(bm, { m2 })
	local corners = 0
	for v in pairs(out2.verts) do if math.abs(math.abs(v.co.X) - 1) + math.abs(math.abs(v.co.Y) - 1) + math.abs(math.abs(v.co.Z) - 1) < 1e-4 then corners += 1 end end
	eq(corners, 8, "level 2 keeps the corners")
	local back = BMesh.fromData(bm:toData())
	local n = 0 for e in pairs(back.edges) do if e.crease then n += 1 end end
	eq(n, 12, "creases saved")
end)
check2("select mirror (X)", function()
	local bm = cube()
	local v0
	for v in pairs(bm.verts) do if v.co.X > 0 and v.co.Y > 0 and v.co.Z > 0 then v0 = v end end
	v0.sel = true
	eq(MT.selectMirror(bm, "X", false), 1, "found")
	assert(not v0.sel, "moved off")
	for v in pairs(bm.verts) do if v.sel then assert(v.co.X < 0 and v.co.Y > 0, "the -X twin") end end
end)
check2("array: constant offset + merge welds touching copies", function()
	local m = Mods.new("array")
	m.merge = true
	local out = Mods.evaluate(cube(), { m })
	eq(out.nv, 16, "welded where the copies touch")
	m.merge, m.relative, m.constant = false, 0, 3
	out = Mods.evaluate(cube(), { m })
	local hx = -math.huge for v in pairs(out.verts) do hx = math.max(hx, v.co.X) end
	assert(math.abs(hx - 7) < 1e-4, "2 copies 3 studs apart: " .. hx)
end)
check2("fill holes, smooth by angle, mirror bisect", function()
	local bm = cube()
	local kill = {}
	for f in pairs(bm.faces) do if math.abs(f.no.Y) > 0.9 then kill[f] = true end end
	for f in pairs(kill) do bm:faceKill(f) end
	eq(bm.nf, 4, "a tube: two holes")
	local n = MT.fillHoles(bm, 0)
	bm:validate()
	eq(n, 2, "both ends filled") closed(bm) outward(bm)
	local c = cube()
	eq(MT.smoothByAngle(c, nil, 30), 12, "every cube edge is sharp at 30 degrees")
	for f in pairs(c.faces) do assert(f.smooth, "all smooth") end
	local m = Mods.new("mirror") m.bisect = true
	local shifted = cube()
	for v in pairs(shifted.verts) do v.co = v.co + Vector3.new(0.5, 0, 0) end
	local out = Mods.evaluate(shifted, { m })
	out:validate() closed(out)
	local lo, hi = math.huge, -math.huge
	for v in pairs(out.verts) do lo = math.min(lo, v.co.X) hi = math.max(hi, v.co.X) end
	assert(math.abs(lo + 1.5) < 1e-4 and math.abs(hi - 1.5) < 1e-4, "cut at 0 then mirrored: " .. lo .. " " .. hi)
end)
-- ===== Sculpt brushes (Sculpt.lua) =====
local function sgrid()
	local g = BMesh.new() Ops.grid(g, 16, 16, 8)
	g:normalsUpdate()
	local up = 0 for f in pairs(g.faces) do up += f.no.Y end
	return g, (up > 0) and 1 or -1
end
local function heightAt(g, x, z)
	local best, bd = nil, math.huge
	for v in pairs(g.verts) do local d = (v.co.X - x) ^ 2 + (v.co.Z - z) ^ 2 if d < bd then best, bd = v, d end end
	return best.co.Y
end
check2("sculpt: draw raises, Ctrl lowers, only inside the brush", function()
	local g, s = sgrid()
	local n = Sculpt.dab(g, "draw", Vector3.new(0, 0, 0), 2, 1, { BMesh = BMesh })
	assert(n > 0, "moved verts")
	assert(heightAt(g, 0, 0) * s > 0.1, "centre went out along the normal")
	eq(heightAt(g, 3.5, 3.5), 0, "outside the brush unchanged")
	local g2 = sgrid()
	Sculpt.dab(g2, "draw", Vector3.new(0, 0, 0), 2, 1, { BMesh = BMesh, invert = true })
	assert(heightAt(g2, 0, 0) * s < -0.1, "inverted went in")
	g2:validate()
end)
check2("sculpt: smooth + flatten calm a bump, inflate grows a sphere, pinch pulls in, crease digs", function()
	local g, s = sgrid()
	for _ = 1, 3 do Sculpt.dab(g, "draw", Vector3.new(0, 0, 0), 2, 1, { BMesh = BMesh }) end
	local h0 = math.abs(heightAt(g, 0, 0))
	Sculpt.dab(g, "smooth", Vector3.new(0, 0, 0), 3, 1, { BMesh = BMesh })
	assert(math.abs(heightAt(g, 0, 0)) < h0, "smooth lowered the peak")
	local h1 = math.abs(heightAt(g, 0, 0))
	Sculpt.dab(g, "flatten", Vector3.new(0, 0, 0), 3, 1, { BMesh = BMesh })
	assert(math.abs(heightAt(g, 0, 0)) < h1, "flatten lowered it more")
	local sp = BMesh.new() Ops.uvSphere(sp, 16, 8, 2) sp:normalsUpdate()
	Sculpt.dab(sp, "inflate", Vector3.new(0, 2, 0), 1.5, 1, { BMesh = BMesh })
	local top = 0 for v in pairs(sp.verts) do top = math.max(top, v.co.Y) end
	assert(top > 2.01, "inflate pushed the top out: " .. top)
	local g3 = sgrid()
	local near = {}
	for v in pairs(g3.verts) do if Vector3.new(v.co.X, 0, v.co.Z).Magnitude < 1.5 then near[v] = true end end
	local function spread() local s2 = 0 for v in pairs(near) do s2 += Vector3.new(v.co.X, 0, v.co.Z).Magnitude end return s2 end
	local before = spread()
	Sculpt.dab(g3, "pinch", Vector3.new(0, 0, 0), 2, 1, { BMesh = BMesh })
	assert(spread() < before, "pinch pulled points to the middle")
	local g4, s4 = sgrid()
	Sculpt.dab(g4, "crease", Vector3.new(0, 0, 0), 2, 1, { BMesh = BMesh })
	assert(heightAt(g4, 0, 0) * s4 < 0, "crease dug in")
	local g5, s5 = sgrid()
	Sculpt.dab(g5, "clay", Vector3.new(0, 0, 0), 2, 1, { BMesh = BMesh })
	assert(heightAt(g5, 0, 0) * s5 > 0, "clay built up")
end)
check2("sculpt: grab drags the captured points", function()
	local g = sgrid()
	local hits = Sculpt.capture(BMesh, g, Vector3.new(0, 0, 0), 2)
	assert(#hits > 0, "captured")
	Sculpt.dab(g, "grab", nil, 2, 1, { BMesh = BMesh, grab = hits, grabDelta = Vector3.new(0, 3, 0) })
	assert(math.abs(heightAt(g, 0, 0) - 3) < 1e-6, "centre followed fully")
	eq(heightAt(g, 3.5, 3.5), 0, "far points stayed")
end)
check2("vertex paint: draw, erase, blur, fill, sample, colours save + survive edits", function()
	local g = BMesh.new() Ops.grid(g, 8, 8, 8) g:normalsUpdate()
	local red = Color3.fromRGB(255, 0, 0)
	local n = Paint.dab(g, Vector3.new(0, 0, 0), 2, red, 1, { BMesh = BMesh })
	assert(n > 0, "painted")
	local mid = Paint.sample(g, Vector3.new(0, 0, 0))
	assert(mid.R > 0.99 and mid.G < 0.01, "centre is red")
	local edge = Paint.sample(g, Vector3.new(3.9, 0, 3.9))
	assert(edge.G > 0.99, "far corner still white")
	Paint.dab(g, Vector3.new(0, 0, 0), 2, red, 1, { BMesh = BMesh, erase = true })
	assert(Paint.sample(g, Vector3.new(0, 0, 0)).G > 0.99, "Ctrl paints white back")
	Paint.dab(g, Vector3.new(0, 0, 0), 2, red, 1, { BMesh = BMesh })
	Paint.dab(g, Vector3.new(0, 0, 0), 3, red, 1, { BMesh = BMesh, brush = "blur" })
	local d = g:toData()
	assert(d.vc and #d.vc == g.nv, "colours saved per point")
	local back = BMesh.fromData(d)
	local reds = 0 for v in pairs(back.verts) do if v.col and v.col.G < 0.5 then reds += 1 end end
	assert(reds > 0, "colours load back")
	local spec = MT.toSpec(back)
	local again = MT.fromSpec(spec)
	local reds2 = 0 for v in pairs(again.verts) do if v.col and v.col.G < 0.5 then reds2 += 1 end end
	eq(reds2, reds, "colours survive a rebuild (spec)")
	Paint.fill(g, Color3.fromRGB(0, 0, 255))
	for v in pairs(g.verts) do assert(v.col.B > 0.99 and v.col.R < 0.01, "filled blue") end
	eq(Paint.hex(Paint.fromHex("#ff8800")), "FF8800", "hex round trip")
	eq(BMesh.fromData(cube():toData()).verts ~= nil, true, "a never-painted mesh has no vc")
	eq(cube():toData().vc, nil, "no colours saved when nothing is painted")
end)
check2("tube modifier: a line becomes a capped pipe, a loop becomes a ring", function()
	local bm = BMesh.new()
	local a, b = bm:vertCreate(Vector3.new(-2, 0, 0)), bm:vertCreate(Vector3.new(2, 0, 0))
	bm:edgeCreate(a, b)
	local out = Mods.evaluate(bm, { Mods.new("tube") })
	out:validate() closed(out) outward(out)
	eq(out.nf, 4 * 8 + 2, "4 smooth steps x 8 sides + 2 caps")
	for v in pairs(out.verts) do assert(math.abs(Vector3.new(0, v.co.Y, v.co.Z).Magnitude - 0.25) < 1e-4, "radius 0.25 round the line") end
	local ring = BMesh.new()
	local vs = {}
	for i = 0, 11 do local an = i / 12 * 2 * math.pi vs[#vs + 1] = ring:vertCreate(Vector3.new(math.cos(an) * 3, 0, math.sin(an) * 3)) end
	for i = 1, 12 do ring:edgeCreate(vs[i], vs[i % 12 + 1]) end
	local m = Mods.new("tube") m.resolution = 2
	local tor = Mods.evaluate(ring, { m })
	tor:validate() closed(tor)
	eq(tor.nf, 24 * 8, "a closed ring of pipe, no caps")
end)
check2("text: HI builds closed solid letters", function()
	local bm = BMesh.new()
	local fs = Font.build(bm, "HI", { pixel = 0.5, depth = 1 })
	bm:validate() closed(bm)
	for f in pairs(bm.faces) do
		BMesh.faceNormalUpdate(f)
		local c = BMesh.faceCenter(f)
		if math.abs(c.Z + 0.5) < 1e-6 then assert(f.no.Z < -0.9, "front faces point -Z") end
		if math.abs(c.Z - 0.5) < 1e-6 then assert(f.no.Z > 0.9, "back faces point +Z") end
	end
	assert(#fs > 0, "faces")
	local lo, hi = math.huge, -math.huge
	for v in pairs(bm.verts) do lo = math.min(lo, v.co.X) hi = math.max(hi, v.co.X) end
	assert(math.abs(hi - lo - 11 * 0.5) < 1e-6, "two letters + a gap = 11 blocks wide")
	assert(math.abs(lo + hi) < 1e-6, "centred")
	local cells, w = Font.cells("A B")
	eq(w, 5 + 1 + 3 + 1 + 5, "a space is 3 blocks")
end)
-- ===== 0.20: bridge options, knife cut-through =====
check2("bridge: cuts add rings, smoothness bulges to follow the surfaces, twist turns it", function()
	local function flared()
		local b = BMesh.new()
		local A, Ain, B, Bin = {}, {}, {}, {}
		for i = 1, 8 do
			local a = (i - 1) / 8 * math.pi * 2
			local c, s2 = math.cos(a), math.sin(a)
			Ain[i] = b:vertCreate(Vector3.new(c * 0.5, -1, s2 * 0.5))
			A[i] = b:vertCreate(Vector3.new(c, 0, s2))
			B[i] = b:vertCreate(Vector3.new(c, 2, s2))
			Bin[i] = b:vertCreate(Vector3.new(c * 0.5, 3, s2 * 0.5))
		end
		for i = 1, 8 do
			local j = i % 8 + 1
			b:faceCreate({ Ain[i], Ain[j], A[j], A[i] })
			b:faceCreate({ B[i], B[j], Bin[j], Bin[i] })
		end
		for i = 1, 8 do A[i].sel, B[i].sel = true, true end
		for e in pairs(b.edges) do e.sel = e.v1.sel and e.v2.sel end
		b:normalsUpdate()
		return b
	end
	local b = flared()
	local out = assert(MT.bridge(b, { cuts = 3 }))
	local n = 0 for _ in pairs(out) do n += 1 end
	eq(n, 32, "4 rows of 8 quads")
	b:validate()
	local function midRadius(m)
		local r = 0
		for v in pairs(m.verts) do if math.abs(v.co.Y - 1) < 1e-6 then r = math.max(r, math.sqrt(v.co.X ^ 2 + v.co.Z ^ 2)) end end
		return r
	end
	assert(math.abs(midRadius(b) - 1) < 1e-6, "straight: the middle ring stays at radius 1")
	local s = flared()
	MT.bridge(s, { cuts = 3, smooth = 1 })
	assert(midRadius(s) > 1.05, "smooth: it bulges out like the flares: " .. midRadius(s))
	local tw = flared()
	MT.bridge(tw, { twist = 1 })
	tw:validate()
end)
check2("knife cut through: every crossed edge is cut, front and back", function()
	local bm = cube()
	local xs = {}
	for e in pairs(bm.edges) do
		if math.abs(e.v1.co.X - e.v2.co.X) < 1e-6 and math.abs(e.v1.co.Z - e.v2.co.Z) < 1e-6 then xs[#xs + 1] = { e = e, t = 0.5 } end
	end
	eq(#xs, 4, "the 4 upright edges")
	local cut = MT.knifeThrough(bm, xs)
	local n = 0 for _ in pairs(cut) do n += 1 end
	eq(n, 4, "a ring of 4 new edges")
	eq(bm.nf, 10, "the 4 sides are split")
	bm:validate()
	closed(bm)
end)
check2("Decimate Collapse: a quarter of the triangles, still closed and the same size", function()
	local sp = BMesh.new() Ops.uvSphere(sp, 24, 12, 2)
	local t0 = 0 for f in pairs(sp.faces) do t0 += f.len - 2 end
	local out = assert(Mods.decimate(sp, { mode = "Collapse", ratio = 0.25 }))
	out:validate()
	local t1 = 0 for f in pairs(out.faces) do t1 += f.len - 2 end
	assert(t1 <= math.ceil(t0 * 0.25) + 2 and t1 >= t0 * 0.2, ("triangles %d of %d"):format(t1, t0))
	closed(out)
	for v in pairs(out.verts) do assert(math.abs(v.co.Magnitude - 2) < 0.35, "stays on the sphere: " .. v.co.Magnitude) end
	-- an open grid keeps its outline
	local g = BMesh.new() Ops.grid(g, 10, 10, 10)
	local og = assert(Mods.collapse(g, 0.1))
	local lo, hi = math.huge, -math.huge
	for v in pairs(og.verts) do lo = math.min(lo, v.co.X) hi = math.max(hi, v.co.X) end
	assert(math.abs(lo + 5) < 1e-4 and math.abs(hi - 5) < 1e-4, "outline kept")
	local g2 = BMesh.new() Ops.grid(g2, 4, 4, 4)
	eq(assert(Mods.decimate(g2, { angle = 5 })).nf, 1, "old saves (no mode) are still Planar")
end)
check2("Edge Split: a cube comes apart at its corners", function()
	local out = assert(Mods.edgesplit(cube(), { angle = 30 }))
	out:validate()
	eq(out.nv, 24, "4 points per side") eq(out.nf, 6, "faces")
	eq(Mods.edgesplit(cube(), { useAngle = false, sharp = true }), nil, "nothing marked sharp")
end)
check2("Shrinkwrap: onto a sphere's surface, onto its points, projected onto a floor", function()
	local sphere = BMesh.new() Ops.uvSphere(sphere, 24, 12, 2)
	local env = { target = function() return BMesh.fromData(sphere:toData()) end }
	local out = assert(Mods.shrinkwrap(cube(), { target = "x" }, env))
	for v in pairs(out.verts) do assert(math.abs(v.co.Magnitude - 2) < 0.1, "on the sphere: " .. v.co.Magnitude) end
	local nv = assert(Mods.shrinkwrap(cube(), { target = "x", mode = "Nearest Vertex" }, env))
	for v in pairs(nv.verts) do assert(math.abs(v.co.Magnitude - 2) < 1e-3, "on a sphere point") end
	local floor = BMesh.new() Ops.plane(floor, 20)
	local g = BMesh.new() Ops.grid(g, 3, 3, 4)
	for v in pairs(g.verts) do v.co = v.co + Vector3.new(0, -1, 0) end
	g:normalsUpdate()
	local pr = assert(Mods.shrinkwrap(g, { target = "x", mode = "Project", offset = 0.5 }, { target = function() return BMesh.fromData(floor:toData()) end }))
	for v in pairs(pr.verts) do assert(math.abs(math.abs(v.co.Y) - 0.5) < 1e-6, "projected onto the floor, 0.5 off it: " .. v.co.Y) end
	eq(Mods.shrinkwrap(cube(), { target = "" }, { target = function() return nil end }), nil, "no target, no change")
end)
-- ===== Boolean (0.18) =====
local function volume(bm)
	local vol = 0
	for f in pairs(bm.faces) do
		local vs = BMesh.faceVerts(f)
		for i = 2, #vs - 1 do vol += vs[1].co:Dot(vs[i].co:Cross(vs[i + 1].co)) end
	end
	return vol / 6
end
local function boxAt(size, at)
	local bm = BMesh.new()
	Ops.cube(bm, 1)
	for v in pairs(bm.verts) do v.co = v.co * size + at end
	bm:normalsUpdate()
	return bm
end
local BOPTS = { BMesh = BMesh, triangulate = fan }
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-4) end
check2("boolean difference: a corner notch, faces joined back up", function()
	local nb = assert(Boolean.run(cube(), boxAt(Vector3.new(1, 1, 1), Vector3.new(1, 1, 1)), "difference", BOPTS))
	nb:validate()
	assert(near(volume(nb), 7.875), "volume " .. volume(nb))
	closed(nb)
	eq(nb.nf, 9, "faces (3 L-shapes + 3 untouched + 3 in the notch)")
	eq(nb.nv, 14, "points")
end)
check2("boolean union and intersect", function()
	local u = assert(Boolean.run(cube(), boxAt(Vector3.new(1, 1, 1), Vector3.new(1, 1, 1)), "union", BOPTS))
	assert(near(volume(u), 8.875), "union volume " .. volume(u))
	closed(u)
	local i = assert(Boolean.run(cube(), boxAt(Vector3.new(1, 1, 1), Vector3.new(1, 1, 1)), "intersect", BOPTS))
	assert(near(volume(i), 0.125), "intersect volume " .. volume(i))
	closed(i) outward(i)
	eq(i.nf, 6, "a little cube") eq(i.nv, 8, "8 corners")
	local none = Boolean.run(cube(), boxAt(Vector3.new(1, 1, 1), Vector3.new(5, 0, 0)), "intersect", BOPTS)
	eq(none, nil, "nothing in common")
end)
check2("boolean: a hole right through stays closed", function()
	local nb = assert(Boolean.run(cube(), boxAt(Vector3.new(0.5, 4, 0.5), Vector3.new()), "difference", BOPTS))
	nb:validate()
	assert(near(volume(nb), 7.5), "volume " .. volume(nb))
	closed(nb)
end)
check2("boolean of round shapes (sphere minus cylinder)", function()
	local a = BMesh.new() Ops.uvSphere(a, 16, 8, 1.5)
	local b = BMesh.new() Ops.cylinder(b, 12, 0.5, 4)
	local nb = assert(Boolean.run(a, b, "difference", BOPTS))
	nb:validate()
	closed(nb)
	assert(volume(nb) > 0 and volume(nb) < volume(a), "smaller than the sphere")
end)
check2("painting a plain cube: a brush between the corners colours that face (0.23.4)", function()
	local m = BMesh.new() Ops.cube(m, 4) m:normalsUpdate()
	local n = Paint.dab(m, Vector3.new(0, 2, 0), 0.3, Color3.new(1, 0, 0), 1, { BMesh = BMesh })
	assert(n == 0, "the small brush reaches no corner")
	n = Paint.dabFace(m, Vector3.new(0, 2, 0), Color3.new(1, 0, 0), 1, { BMesh = BMesh, facing = Vector3.new(0, 1, 0) })
	assert(n == 4, "the top face's 4 corners: " .. n)
	for v in pairs(m.verts) do if v.co.Y > 1 then assert(v.col and v.col.R > 0.99, "top corner red") else assert(v.col == nil, "bottom untouched") end end
end)
check2("boolean with bent faces and a dense sphere: no endless splitting, no stack overflow (0.22.2)", function()
	-- bent quads (like Roblox's 32-bit positions far from the middle) used to split against their own plane forever
	local s = BMesh.new() Ops.uvSphere(s, 24, 12, 2)
	local k = 0
	for v in pairs(s.verts) do k += 1 v.co = v.co + Vector3.new(2, 2, 2) + Vector3.new(((k * 7) % 5 - 2) * 3e-5, ((k * 3) % 5 - 2) * 3e-5, 0) end
	s:normalsUpdate()
	local nb = assert(Boolean.run(boxAt(Vector3.new(4, 4, 4), Vector3.new(0, 0, 0)), s, "difference", BOPTS))
	assert(nb.nf > 6, "cut: " .. nb.nf)
	nb:validate()
	-- a convex shape with thousands of faces makes a chain that deep: must not recurse per level
	local d = BMesh.new() Ops.uvSphere(d, 96, 48, 2)
	local nb2 = assert(Boolean.run(d, boxAt(Vector3.new(2, 2, 2), Vector3.new(1.5, 0, 0)), "difference", BOPTS))
	assert(nb2.nf > 100, "dense cut: " .. nb2.nf)
end)
check2("Intersect (Boolean) in Edit Mode: the selected faces cut the rest", function()
	local bm = cube()
	local cut = boxAt(Vector3.new(1, 1, 1), Vector3.new(1, 1, 1))
	local map = {}
	for v in pairs(cut.verts) do map[v] = bm:vertCreate(v.co) end
	for f in pairs(cut.faces) do
		local vs = {}
		for i, v in ipairs(BMesh.faceVerts(f)) do vs[i] = map[v] end
		bm:faceCreate(vs).sel = true
	end
	bm:normalsUpdate()
	local nb = assert(Boolean.split(bm, function(f) return f.sel == true end, "difference", BOPTS))
	assert(near(volume(nb), 7.875), "volume " .. volume(nb))
	closed(nb)
end)
-- ===== UVs (0.19) =====
local UVO = { BMesh = BMesh, margin = 0.02 }
local function allUV(bm)
	for f in pairs(bm.faces) do
		for _, l in ipairs(BMesh.faceLoops(f)) do
			assert(l.uv, "every corner has a UV")
			assert(l.uv.X > -1e-6 and l.uv.X < 1 + 1e-6 and l.uv.Y > -1e-6 and l.uv.Y < 1 + 1e-6, "inside 0-1: " .. l.uv.X .. ", " .. l.uv.Y)
		end
	end
end
local function uvSquare(f)
	local ls = BMesh.faceLoops(f)
	assert(#ls == 4, "quad")
	local a, b, c, d = ls[1].uv, ls[2].uv, ls[3].uv, ls[4].uv
	local s1, s2 = (b - a), (c - b)
	local l1, l2 = math.sqrt(s1:Dot(s1)), math.sqrt(s2:Dot(s2))
	assert(math.abs(l1 / l2 - 1) < 0.02, "square sides " .. l1 .. " " .. l2)
	assert(math.abs(s1:Dot(s2)) < 0.02 * l1 * l2, "right angle")
	-- not mirrored: corners go round the same way as the face
	assert(s1.X * s2.Y - s1.Y * s2.X > 0, "not mirrored")
	return l1
end
local function boxesOverlap(bm)
	-- islands are separate faces here: no two faces' UV boxes overlap
	local boxes = {}
	for f in pairs(bm.faces) do
		local lx, ly, hx, hy = math.huge, math.huge, -math.huge, -math.huge
		for _, l in ipairs(BMesh.faceLoops(f)) do lx, ly, hx, hy = math.min(lx, l.uv.X), math.min(ly, l.uv.Y), math.max(hx, l.uv.X), math.max(hy, l.uv.Y) end
		boxes[#boxes + 1] = { lx + 1e-4, ly + 1e-4, hx - 1e-4, hy - 1e-4 }
	end
	for i = 1, #boxes do for j = i + 1, #boxes do
		local a, b = boxes[i], boxes[j]
		if a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] then return true end
	end end
	return false
end
check2("Unwrap: a cube cut at seams opens flat into 6 equal squares", function()
	local bm = cube()
	local function faceN(n) for f in pairs(bm.faces) do if f.no:Dot(n) > 0.9 then return f end end end
	local F, B, T, D, L, R = faceN(Vector3.new(0, 0, -1)), faceN(Vector3.new(0, 0, 1)), faceN(Vector3.new(0, 1, 0)), faceN(Vector3.new(0, -1, 0)), faceN(Vector3.new(-1, 0, 0)), faceN(Vector3.new(1, 0, 0))
	local hinge = { { F, T }, { F, D }, { F, L }, { F, R }, { T, B } }
	for e in pairs(bm.edges) do
		local fs = BMesh.edgeFaces(e)
		local isHinge = false
		for _, h in ipairs(hinge) do if (fs[1] == h[1] and fs[2] == h[2]) or (fs[1] == h[2] and fs[2] == h[1]) then isHinge = true end end
		e.seam = not isHinge or nil
	end
	local n, closedN = UVTools.unwrap(bm, nil, UVO)
	eq(n, 1, "one island") eq(closedN, 0, "nothing closed")
	allUV(bm)
	local side
	for f in pairs(bm.faces) do
		local s = uvSquare(f)
		side = side or s
		assert(math.abs(s / side - 1) < 0.02, "same size squares")
	end
end)
check2("Unwrap without seams (closed) falls back to Smart Project; Smart UV Project packs without overlaps", function()
	local bm = cube()
	local n, closedN = UVTools.unwrap(bm, nil, UVO)
	eq(closedN, 1, "the cube is closed") eq(n, 6, "6 islands")
	allUV(bm)
	for f in pairs(bm.faces) do uvSquare(f) end
	assert(not boxesOverlap(bm), "islands don't overlap")
	local sp = BMesh.new() Ops.uvSphere(sp, 16, 8, 2)
	local k = UVTools.smartProject(sp, nil, UVO)
	assert(k > 2, "a sphere splits into several islands")
	allUV(sp)
end)
check2("Unwrap a flat grid: squares stay square; UVs survive save / load and mesh tools", function()
	local bm = BMesh.new() Ops.grid(bm, 4, 4, 4)
	UVTools.unwrap(bm, nil, UVO)
	allUV(bm)
	for f in pairs(bm.faces) do uvSquare(f) end
	local back = BMesh.fromData(bm:toData())
	allUV(back)
	local spec = MT.fromSpec(MT.toSpec(back))
	allUV(spec)
	for f in pairs(spec.faces) do uvSquare(f) end
end)
print(("%d tool tests passed, %d failed"):format(pass2, fail2))
if fail2 > 0 then error("tool tests failed") end
