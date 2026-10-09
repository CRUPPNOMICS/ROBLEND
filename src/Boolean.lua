--[[
	ROBLEND - Boolean: Union, Difference and Intersect between two closed meshes
	(Blender's Boolean modifier, Object > Boolean and Edit Mode's Face > Intersect (Boolean)).
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	The method is constructive solid geometry with binary space partitioning (BSP) trees, the classic
	approach (Thibault & Naylor 1987) also used by Evan Wallace's csg.js (MIT). This is ROBLEND's own Luau
	version of that method, plus a clean-up so the result edits like a Blender mesh: corners welded,
	T-junctions closed, the pieces of each original face joined back into one face, and the extra points
	left on straight edges removed.

	Boolean.run(meshA, meshB, op, opts) -> new mesh or nil, why
	  op = "union" | "difference" | "intersect"; both meshes in the same space.
	  opts = { BMesh = BMesh (required), triangulate = fn(verts, normal) -> {{i, j, k}, ...} for concave faces }
	Boolean.split(mesh, inB(face) -> bool, op, opts) -> new mesh: the faces where inB is true are the
	  cutter, the rest is the base (Edit Mode's Intersect (Boolean): selected faces cut the others).
]]
local Boolean = {}
local V3 = Vector3.new
local EPS = 1e-5
local WELD = 1e-4

-- ===== polygons and the BSP tree =====
local function plane(vs)
	-- Newell's method: a good normal even for slightly bent faces
	local nx, ny, nz = 0, 0, 0
	for i = 1, #vs do
		local a, b = vs[i], vs[i % #vs + 1]
		nx += (a.Y - b.Y) * (a.Z + b.Z)
		ny += (a.Z - b.Z) * (a.X + b.X)
		nz += (a.X - b.X) * (a.Y + b.Y)
	end
	local m = math.sqrt(nx * nx + ny * ny + nz * nz)
	if m < 1e-12 then return nil end
	local n = V3(nx / m, ny / m, nz / m)
	local w = 0
	for _, v in ipairs(vs) do w += n:Dot(v) end
	return n, w / #vs
end
local function newPoly(vs, tag)
	local n, w = plane(vs)
	if not n then return nil end
	return { v = vs, n = n, w = w, tag = tag }
end
local function flip(p)
	local r = {}
	for i = #p.v, 1, -1 do r[#r + 1] = p.v[i] end
	p.v, p.n, p.w = r, -p.n, -p.w
end

local COPLANAR, FRONT, BACK, SPANNING = 0, 1, 2, 3
local function splitPoly(pn, pw, poly, coFront, coBack, front, back)
	local types, all = {}, 0
	for i, v in ipairs(poly.v) do
		local t = pn:Dot(v) - pw
		local ty = (t < -EPS) and BACK or (t > EPS and FRONT or COPLANAR)
		all = bit32.bor(all, ty)
		types[i] = ty
	end
	if all == COPLANAR then
		if pn:Dot(poly.n) > 0 then coFront[#coFront + 1] = poly else coBack[#coBack + 1] = poly end
	elseif all == FRONT then
		front[#front + 1] = poly
	elseif all == BACK then
		back[#back + 1] = poly
	else
		local f, b = {}, {}
		local n = #poly.v
		for i = 1, n do
			local j = i % n + 1
			local ti, tj = types[i], types[j]
			local vi, vj = poly.v[i], poly.v[j]
			if ti ~= BACK then f[#f + 1] = vi end
			if ti ~= FRONT then b[#b + 1] = vi end
			if bit32.bor(ti, tj) == SPANNING then
				local t = (pw - pn:Dot(vi)) / pn:Dot(vj - vi)
				local mid = vi + (vj - vi) * t
				f[#f + 1] = mid
				b[#b + 1] = mid
			end
		end
		if #f >= 3 then front[#front + 1] = { v = f, n = poly.n, w = poly.w, tag = poly.tag } end
		if #b >= 3 then back[#back + 1] = { v = b, n = poly.n, w = poly.w, tag = poly.tag } end
	end
end

local Node = {}
Node.__index = Node
local function newNode() return setmetatable({ polys = {} }, Node) end
-- all of these walk the tree with a list instead of calling themselves: a round shape makes a chain as deep as it
-- has faces, which would overflow Luau's call stack on big meshes
function Node:build(polys)
	local stack = { self, polys }
	while #stack > 0 do
		local list = table.remove(stack)
		local node = table.remove(stack)
		if #list > 0 then
			local start = 1
			if not node.pn then
				-- the first polygon sets this node's plane and always stays here (a slightly bent face would
				-- otherwise be split against its own plane over and over)
				node.pn, node.pw = list[1].n, list[1].w
				node.polys[#node.polys + 1] = list[1]
				start = 2
			end
			local front, back = {}, {}
			for i = start, #list do splitPoly(node.pn, node.pw, list[i], node.polys, node.polys, front, back) end
			if #front > 0 then
				node.front = node.front or newNode()
				stack[#stack + 1] = node.front
				stack[#stack + 1] = front
			end
			if #back > 0 then
				node.back = node.back or newNode()
				stack[#stack + 1] = node.back
				stack[#stack + 1] = back
			end
		end
	end
end
function Node:nodes()
	local out, stack = {}, { self }
	while #stack > 0 do
		local n = table.remove(stack)
		out[#out + 1] = n
		if n.front then stack[#stack + 1] = n.front end
		if n.back then stack[#stack + 1] = n.back end
	end
	return out
end
function Node:invert()
	for _, n in ipairs(self:nodes()) do
		for _, p in ipairs(n.polys) do flip(p) end
		if n.pn then n.pn, n.pw = -n.pn, -n.pw end
		n.front, n.back = n.back, n.front
	end
end
-- keep only the parts of `polys` outside this solid
function Node:clip(polys)
	local out = {}
	local stack = { self, polys }
	while #stack > 0 do
		local list = table.remove(stack)
		local node = table.remove(stack)
		if not node.pn then
			for _, p in ipairs(list) do out[#out + 1] = p end
		else
			local front, back = {}, {}
			for _, p in ipairs(list) do splitPoly(node.pn, node.pw, p, front, back, front, back) end
			if node.front then stack[#stack + 1] = node.front stack[#stack + 1] = front
			else for _, p in ipairs(front) do out[#out + 1] = p end end
			-- behind a leaf = inside the solid: dropped
			if node.back then stack[#stack + 1] = node.back stack[#stack + 1] = back end
		end
	end
	return out
end
function Node:clipTo(other)
	for _, n in ipairs(self:nodes()) do n.polys = other:clip(n.polys) end
end
function Node:all(out)
	out = out or {}
	for _, n in ipairs(self:nodes()) do
		for _, p in ipairs(n.polys) do out[#out + 1] = p end
	end
	return out
end
local function tree(polys)
	local n = newNode()
	n:build(polys)
	return n
end

function Boolean.polys(polysA, polysB, op)
	local a, b = tree(polysA), tree(polysB)
	if op == "union" then
		a:clipTo(b) b:clipTo(a) b:invert() b:clipTo(a) b:invert()
		a:build(b:all())
	elseif op == "intersect" then
		a:invert() b:clipTo(a) b:invert() a:clipTo(b) b:clipTo(a)
		a:build(b:all())
		a:invert()
	else -- difference
		a:invert() a:clipTo(b) b:clipTo(a) b:invert() b:clipTo(a) b:invert()
		a:build(b:all())
		a:invert()
	end
	return a:all()
end

-- ===== mesh <-> polygons =====
local function convex(vs, n)
	local m = #vs
	for i = 1, m do
		local a, b, c = vs[i], vs[i % m + 1], vs[(i + 1) % m + 1]
		if (b - a):Cross(c - b):Dot(n) < -1e-9 then return false end
	end
	return true
end
-- faces of `bm` (only those where keep(f) is true) as polygons; each remembers its face so the pieces join back up
function Boolean.fromMesh(bm, keep, side, opts)
	local BMesh = opts.BMesh
	local out = {}
	for f in pairs(bm.faces) do
		if not keep or keep(f) then
			local vs = {}
			for i, v in ipairs(BMesh.faceVerts(f)) do vs[i] = v.co end
			local tag = { face = f, side = side, smooth = f.smooth }
			local p = newPoly(vs, tag)
			if p then
				-- a face that isn't flat (bent quad, or rounding in Roblox's 32-bit positions) is cut into triangles
				local flat = true
				if #vs > 3 then for _, co in ipairs(vs) do if math.abs(p.n:Dot(co) - p.w) > EPS * 0.5 then flat = false break end end end
				local cv = #vs == 3 or convex(vs, p.n)
				if flat and (cv or not opts.triangulate) then
					out[#out + 1] = p
				elseif cv or not opts.triangulate then
					for i = 2, #vs - 1 do
						local q = newPoly({ vs[1], vs[i], vs[i + 1] }, tag)
						if q then out[#out + 1] = q end
					end
				else
					local wrap = {}
					for i, co in ipairs(vs) do wrap[i] = { co = co } end
					for _, t in ipairs(opts.triangulate(wrap, p.n)) do
						local q = newPoly({ vs[t[1]], vs[t[2]], vs[t[3]] }, tag)
						if q then out[#out + 1] = q end
					end
				end
			end
		end
	end
	return out
end

-- the clean-up, then a mesh. polys -> new BMesh
function Boolean.toMesh(polys, opts)
	local BMesh = opts.BMesh
	-- 1. weld: one point per position
	local pos, idOf = {}, {}
	local function key(v) return math.floor(v.X / WELD + 0.5) .. "," .. math.floor(v.Y / WELD + 0.5) .. "," .. math.floor(v.Z / WELD + 0.5) end
	local function id(v)
		local k = key(v)
		local i = idOf[k]
		if not i then i = #pos + 1 pos[i] = v idOf[k] = i end
		return i
	end
	local faces = {}
	for _, p in ipairs(polys) do
		local loop = {}
		for _, v in ipairs(p.v) do
			local i = id(v)
			if loop[#loop] ~= i then loop[#loop + 1] = i end
		end
		while #loop > 1 and loop[1] == loop[#loop] do table.remove(loop) end
		if #loop >= 3 then faces[#faces + 1] = { v = loop, n = p.n, tag = p.tag } end
	end
	if #faces == 0 then return nil, "nothing left" end

	-- 2. close T-junctions: a point lying on another face's edge goes into that edge too (no cracks)
	local lo, hi = pos[1], pos[1]
	for _, v in ipairs(pos) do lo = lo:Min(v) hi = hi:Max(v) end
	local total, ne = 0, 0
	for _, f in ipairs(faces) do
		for i = 1, #f.v do total += (pos[f.v[i]] - pos[f.v[i % #f.v + 1]]).Magnitude ne += 1 end
	end
	local cell = math.max(total / math.max(ne, 1), 1e-3)
	local grid = {}
	local function ck(x, y, z) return x .. "," .. y .. "," .. z end
	for i, v in ipairs(pos) do
		local k = ck(math.floor(v.X / cell), math.floor(v.Y / cell), math.floor(v.Z / cell))
		local l = grid[k]
		if l then l[#l + 1] = i else grid[k] = { i } end
	end
	local function onEdge(a, b)
		local pa, pb = pos[a], pos[b]
		local d = pb - pa
		local len = d.Magnitude
		if len < WELD then return nil end
		local u = d / len
		local found, seen = nil, {}
		local steps = math.ceil(len / cell)
		for s = 0, steps do
			local c = pa + u * math.min(s * cell, len)
			local cx, cy, cz = math.floor(c.X / cell), math.floor(c.Y / cell), math.floor(c.Z / cell)
			for x = cx - 1, cx + 1 do for y = cy - 1, cy + 1 do for z = cz - 1, cz + 1 do
				local l = grid[ck(x, y, z)]
				if l then
					for _, i in ipairs(l) do
						if i ~= a and i ~= b and not seen[i] then
							seen[i] = true
							local t = (pos[i] - pa):Dot(u)
							if t > WELD and t < len - WELD and (pos[i] - (pa + u * t)).Magnitude < WELD then
								found = found or {}
								found[#found + 1] = { i = i, t = t }
							end
						end
					end
				end
			end end end
		end
		if found then table.sort(found, function(x, y) return x.t < y.t end) end
		return found
	end
	for _, f in ipairs(faces) do
		local out = {}
		local n = #f.v
		for i = 1, n do
			local a, b = f.v[i], f.v[i % n + 1]
			out[#out + 1] = a
			local mids = onEdge(a, b)
			if mids then for _, m in ipairs(mids) do out[#out + 1] = m.i end end
		end
		f.v = out
	end

	-- 3. join the pieces of each original face back into one face (pieces that share a run of edges)
	local function edgeKey(a, b) return a .. ":" .. b end
	local alive = {}
	for i = 1, #faces do alive[i] = true end
	local changed = true
	local guard = 0
	while changed and guard < 64 do
		changed, guard = false, guard + 1
		local owner = {}
		for fi, f in ipairs(faces) do
			if alive[fi] then for i = 1, #f.v do owner[edgeKey(f.v[i], f.v[i % #f.v + 1])] = fi end end
		end
		local touched = {}
		for fi, f in ipairs(faces) do
			if alive[fi] and not touched[fi] then
				local n = #f.v
				for i = 1, n do
					local gi = owner[edgeKey(f.v[i % n + 1], f.v[i])]
					local g = gi and faces[gi]
					if g and gi ~= fi and alive[gi] and not touched[gi] and g.tag == f.tag then
						-- the shared run, as positions in f: shared[i] = f's edge i is also g's (reversed)
						local gset = {}
						for j = 1, #g.v do gset[edgeKey(g.v[j % #g.v + 1], g.v[j])] = true end
						local shared, count = {}, 0
						for j = 1, n do if gset[edgeKey(f.v[j], f.v[j % n + 1])] then shared[j] = true count += 1 end end
						-- find where the run starts (shared, previous not shared) - must be exactly one run
						local starts, s0 = 0, nil
						for j = 1, n do
							local prev = (j - 2) % n + 1
							if shared[j] and not shared[prev] then starts += 1 s0 = j end
						end
						if starts == 1 and count < n then
							local sV = f.v[s0]                       -- run start
							local eV = f.v[(s0 + count - 1) % n + 1] -- run end
							local merged, used, ok = {}, {}, true
							-- f from the run's end round to its start
							local j = (s0 + count - 1) % n + 1
							while true do
								local v = f.v[j]
								if used[v] then ok = false break end
								used[v] = true
								merged[#merged + 1] = v
								if v == sV then break end
								j = j % n + 1
							end
							-- g from the run's start round to its end (not including either)
							if ok then
								local m = #g.v
								local k
								for q = 1, m do if g.v[q] == sV then k = q end end
								if not k then ok = false else
									k = k % m + 1
									while g.v[k] ~= eV do
										local v = g.v[k]
										if used[v] then ok = false break end
										used[v] = true
										merged[#merged + 1] = v
										k = k % m + 1
									end
								end
							end
							if ok and #merged >= 3 then
								f.v = merged
								alive[gi] = false
								touched[fi], touched[gi] = true, true
								changed = true
								break
							end
						end
					end
				end
			end
		end
	end

	-- 4. drop points left in the middle of straight edges (only two faces use them, both see them as straight)
	local users = {}
	for fi, f in ipairs(faces) do
		if alive[fi] then
			for j, i in ipairs(f.v) do
				local l = users[i]
				if l then l[#l + 1] = { f, j } else users[i] = { { f, j } } end
			end
		end
	end
	local function straight(f, j)
		local n = #f.v
		local a, b, c = pos[f.v[(j - 2) % n + 1]], pos[f.v[j]], pos[f.v[j % n + 1]]
		local u, w = b - a, c - b
		if u.Magnitude < 1e-9 or w.Magnitude < 1e-9 then return false end
		return u.Unit:Cross(w.Unit).Magnitude < 1e-6 and u:Dot(w) > 0
	end
	local drop = {}
	for i, l in pairs(users) do
		if #l <= 2 then
			local okAll = true
			for _, use in ipairs(l) do if not straight(use[1], use[2]) then okAll = false break end end
			if okAll then drop[i] = true end
		end
	end
	if next(drop) then
		for fi, f in ipairs(faces) do
			if alive[fi] then
				local out = {}
				for _, i in ipairs(f.v) do if not drop[i] then out[#out + 1] = i end end
				if #out >= 3 then f.v = out else alive[fi] = false end
			end
		end
	end

	-- 5. the mesh
	local bm = BMesh.new()
	local vert = {}
	local function vOf(i)
		if not vert[i] then vert[i] = bm:vertCreate(pos[i]) end
		return vert[i]
	end
	for fi, f in ipairs(faces) do
		if alive[fi] then
			local vs = {}
			for j, i in ipairs(f.v) do vs[j] = vOf(i) end
			local nf = bm:faceCreate(vs)
			if nf and f.tag and f.tag.smooth then nf.smooth = true end
		end
	end
	bm:normalsUpdate()
	if bm.nf == 0 then return nil, "nothing left" end
	return bm
end

function Boolean.run(a, b, op, opts)
	local pa = Boolean.fromMesh(a, nil, "a", opts)
	local pb = Boolean.fromMesh(b, nil, "b", opts)
	if #pa == 0 then return nil, "the mesh has no faces" end
	if #pb == 0 then return nil, "the other mesh has no faces" end
	return Boolean.toMesh(Boolean.polys(pa, pb, op), opts)
end

function Boolean.split(bm, inB, op, opts)
	local pa = Boolean.fromMesh(bm, function(f) return not inB(f) end, "a", opts)
	local pb = Boolean.fromMesh(bm, inB, "b", opts)
	if #pa == 0 or #pb == 0 then return nil, "select the cutter faces (and leave the rest unselected)" end
	return Boolean.toMesh(Boolean.polys(pa, pb, op), opts)
end

return Boolean
