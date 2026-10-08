-- engine tests (run by tools/test.py, which glues mock + BMesh + Ops in front of this)
local pass, fail = 0, 0
local function check(name, fn)
	local ok, err = pcall(fn)
	if ok then pass += 1 print("PASS " .. name) else fail += 1 print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function count(bm) return bm.nv, bm.ne, bm.nf end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end
local function outward(bm)
	-- every face normal points away from the mesh centre (closed convex shapes)
	local c, n = Vector3.new(), 0
	for v in pairs(bm.verts) do c = c + v.co n += 1 end
	c = c / n
	for f in pairs(bm.faces) do
		BMesh.faceNormalUpdate(f)
		local d = BMesh.faceCenter(f) - c
		if d:Dot(f.no) <= 0 then error("a face points inward") end
	end
end

check("cube 8/12/6, valid, outward", function()
	local bm = BMesh.new()
	Ops.cube(bm, 2)
	local v, e, f = count(bm)
	eq(v, 8, "verts") eq(e, 12, "edges") eq(f, 6, "faces")
	bm:validate()
	outward(bm)
	for ed in pairs(bm.edges) do eq(BMesh.edgeFaceCount(ed), 2, "manifold") end
end)

check("cylinder + uv sphere valid, outward", function()
	local bm = BMesh.new()
	Ops.cylinder(bm, 12, 1, 2)
	bm:validate() outward(bm)
	eq(bm.nf, 14, "cyl faces")
	local s = BMesh.new()
	Ops.uvSphere(s, 12, 6, 1)
	s:validate() outward(s)
	for ed in pairs(s.edges) do eq(BMesh.edgeFaceCount(ed), 2, "sphere manifold") end
end)

check("extrude top face of cube", function()
	local bm = BMesh.new()
	Ops.cube(bm, 2)
	local top
	for f in pairs(bm.faces) do if f.no.Y > 0.9 then top = f end end
	local nv, nf = Ops.extrudeFaceRegion(bm, { [top] = true })
	for v in pairs(nv) do v.co = v.co + Vector3.new(0, 1, 0) end
	bm:normalsUpdate()
	bm:validate()
	eq(bm.nv, 12, "verts") eq(bm.nf, 10, "faces") eq(bm.ne, 20, "edges")
	outward(bm)
	for ed in pairs(bm.edges) do eq(BMesh.edgeFaceCount(ed), 2, "still closed") end
end)

check("extrude two neighbouring faces as one region", function()
	local bm = BMesh.new()
	Ops.grid(bm, 2, 1, 2)
	local set = {}
	for f in pairs(bm.faces) do set[f] = true end
	local nv = Ops.extrudeFaceRegion(bm, set)
	for v in pairs(nv) do v.co = v.co + Vector3.new(0, 1, 0) end
	bm:validate()
	-- 2 top faces + 6 border walls (no wall on the shared middle edge)
	eq(bm.nf, 8, "faces")
end)

check("inset a cube face", function()
	local bm = BMesh.new()
	Ops.cube(bm, 2)
	local top
	for f in pairs(bm.faces) do if f.no.Y > 0.9 then top = f end end
	local nv, nf = Ops.insetRegion(bm, { [top] = true }, 0.25, 0)
	bm:validate()
	eq(bm.nf, 10, "faces") -- 5 old + inner + 4 ring
	for v in pairs(nv) do
		if math.abs(math.abs(v.co.X) - 0.75) > 1e-6 or math.abs(math.abs(v.co.Z) - 0.75) > 1e-6 then error("inset corner not 0.25 in: " .. tostring(v.co)) end
	end
	for ed in pairs(bm.edges) do eq(BMesh.edgeFaceCount(ed), 2, "closed") end
end)

check("edge split + face split", function()
	local bm = BMesh.new()
	Ops.plane(bm, 2)
	local f = next(bm.faces)
	local e = next(bm.edges)
	local v = bm:edgeSplit(e, e.v1, 0.5)
	bm:validate()
	eq(f.len, 5, "face got a corner")
	-- split face from the new vert to the vert opposite-ish
	local la, lb
	for _, l in ipairs(BMesh.faceLoops(f)) do if l.v == v then la = l end end
	lb = la.next.next.next
	local f2 = bm:faceSplit(f, la, lb)
	bm:validate()
	eq(bm.nf, 2, "two faces") eq(f.len + f2.len, 7, "corners")
end)

check("loop cut round a cube", function()
	local bm = BMesh.new()
	Ops.cube(bm, 2)
	-- an edge along X on the top
	local e0
	for e in pairs(bm.edges) do
		local d = e.v2.co - e.v1.co
		if math.abs(d.X) > 1 and e.v1.co.Y > 0 and e.v1.co.Z > 0 then e0 = e end
	end
	local ring = Ops.edgeRing(bm, e0)
	eq(#ring, 4, "ring of 4 edges")
	local ne = Ops.loopCut(bm, e0, 0.5)
	bm:validate()
	eq(bm.nf, 10, "faces") eq(bm.nv, 12, "verts")
	local n = 0 for _ in pairs(ne) do n += 1 end
	eq(n, 4, "new loop edges")
	for ed in pairs(bm.edges) do eq(BMesh.edgeFaceCount(ed), 2, "closed") end
	outward(bm)
end)

check("loop cut on an open grid strip", function()
	local bm = BMesh.new()
	Ops.grid(bm, 3, 1, 3)
	local e0
	for e in pairs(bm.edges) do
		local d = e.v2.co - e.v1.co
		if math.abs(d.Z) > 1 and math.abs(e.v1.co.X + 0.5) < 1e-6 then e0 = e end   -- a cross edge in the middle
	end
	local ring = Ops.edgeRing(bm, e0)
	eq(#ring, 4, "ring across all 3 quads of the strip")
	local e1
	for e in pairs(bm.edges) do
		local d = e.v2.co - e.v1.co
		if math.abs(d.X) > 0.5 and e.v1.co.Z < 0 and e.v2.co.Z < 0 then e1 = e break end
	end
	local ring2 = Ops.edgeRing(bm, e1)
	eq(#ring2, 2, "ring along the strip (both long edges)")
	Ops.loopCut(bm, e1, 0.5)
	bm:validate()
	eq(bm.nf, 4, "faces after cut")
end)

check("delete a face, then edges / verts", function()
	local bm = BMesh.new()
	Ops.cube(bm, 2)
	local f = next(bm.faces)
	Ops.deleteFaces(bm, { [f] = true })
	bm:validate()
	eq(bm.nf, 5, "faces") eq(bm.ne, 12, "edges stay (used by other faces)")
	local v = next(bm.verts)
	Ops.deleteVerts(bm, { [v] = true })
	bm:validate()
end)

check("merge at centre + by distance + flip + fill", function()
	local bm = BMesh.new()
	Ops.cube(bm, 2)
	local top = {}
	for v in pairs(bm.verts) do if v.co.Y > 0 then top[v] = true end end
	local nb = Ops.mergeAtCenter(bm, top)
	nb:validate()
	eq(nb.nv, 5, "pyramid verts") eq(nb.nf, 5, "pyramid faces (top gone, sides -> tris)")
	local bm2 = BMesh.new()
	Ops.cube(bm2, 2)
	Ops.cube(bm2, 2)
	local nb2, _, n = Ops.mergeByDistance(bm2, nil, 0.001)
	eq(n, 8, "8 doubles merged")
	nb2:validate()
	local nb3 = Ops.flipFaces(nb2, nb2.faces)
	nb3:validate()
	local p = BMesh.new()
	local a, b, c = p:vertCreate(Vector3.new(0, 0, 0)), p:vertCreate(Vector3.new(1, 0, 0)), p:vertCreate(Vector3.new(0, 0, 1))
	local f = Ops.fill(p, { [a] = true, [b] = true, [c] = true })
	assert(f, "filled") p:validate()
end)

check("save -> load round trip", function()
	local bm = BMesh.new()
	Ops.uvSphere(bm, 8, 4, 1)
	local d = bm:toData()
	local b2 = BMesh.fromData(d)
	b2:validate()
	eq(b2.nv, bm.nv, "verts") eq(b2.nf, bm.nf, "faces") eq(b2.ne, bm.ne, "edges")
end)

check("extrude edges + verts", function()
	local bm = BMesh.new()
	Ops.plane(bm, 2)
	local e = next(bm.edges)
	local nv = Ops.extrudeEdges(bm, { [e] = true })
	bm:validate()
	eq(bm.nf, 2, "wall added")
	local v = next(bm.verts)
	Ops.extrudeVerts(bm, { [v] = true })
	bm:validate()
end)


check("edge loop round a cube's middle + subdivide", function()
	local bm = BMesh.new()
	Ops.cube(bm, 2)
	local e0
	for e in pairs(bm.edges) do
		local d = e.v2.co - e.v1.co
		if math.abs(d.X) > 1 and e.v1.co.Y > 0 and e.v1.co.Z > 0 then e0 = e end
	end
	Ops.loopCut(bm, e0, 0.5)
	-- the new loop goes round 4 edges; an edge on it should walk the whole loop
	local onLoop
	for e in pairs(bm.edges) do
		if math.abs(e.v1.co.X) < 1e-6 and math.abs(e.v2.co.X) < 1e-6 then onLoop = e break end
	end
	local loop = Ops.edgeLoop(bm, onLoop)
	eq(#loop, 4, "edge loop length")
	local s = BMesh.new()
	Ops.cube(s, 2)
	local top
	for f in pairs(s.faces) do if f.no.Y > 0.9 then top = f end end
	local nf = Ops.subdivideFaces(s, { [top] = true })
	s:validate()
	eq(s.nf, 9, "faces after subdividing the top")
	for ed in pairs(s.edges) do eq(BMesh.edgeFaceCount(ed), 2, "closed") end
end)

print(("%d passed, %d failed"):format(pass, fail))
if fail > 0 then error("tests failed") end
