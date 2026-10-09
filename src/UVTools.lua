--[[
	ROBLEND - UV unwrapping: Unwrap (angle-preserving, cut at seams), Smart UV Project and Pack Islands.
	Converted to Luau (and cut down) from Blender's UV tools:
	  source/blender/editors/uvedit/uvedit_unwrap_ops.cc (unwrap / smart project operators)
	  source/blender/geometry/intern/uv_parametrizer.cc (LSCM: least squares conformal maps, Levy et al. 2002)
	  source/blender/geometry/intern/uv_pack.cc (packing islands into the 0-1 square)
	SPDX-License-Identifier: GPL-2.0-or-later
	Original: Copyright (C) Blender Authors. Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27).

	UVs live on each face corner (loop) as l.uv = Vector2, Blender's way up (0, 0 = bottom left);
	Display turns them the other way up for Roblox. Saved in RB_Data as "uv".
	All functions take opts = { BMesh = BMesh, margin = 0.02, angle = 66 } and a face set (nil = every face).
]]
local UV = {}
local V3, V2 = Vector3.new, Vector2.new

local function faceArea(BMesh, f)
	local vs = BMesh.faceVerts(f)
	local a = V3()
	for i = 2, #vs - 1 do a += (vs[i].co - vs[1].co):Cross(vs[i + 1].co - vs[1].co) end
	return a.Magnitude / 2
end
local function basis(n)
	local u = math.abs(n.Y) < 0.9 and V3(0, 1, 0):Cross(n) or V3(1, 0, 0):Cross(n)
	u = u.Unit
	return u, n:Cross(u)
end

-- pieces of `fs` joined across edges (not across seams when useSeams)
function UV.islands(BMesh, bm, fs, useSeams, sameGroup)
	local seen, out = {}, {}
	for f in pairs(fs) do
		if not seen[f] then
			local isl, stack = {}, { f }
			seen[f] = true
			while #stack > 0 do
				local g = table.remove(stack)
				isl[#isl + 1] = g
				for _, l in ipairs(BMesh.faceLoops(g)) do
					if not (useSeams and l.e.seam) then
						for _, h in ipairs(BMesh.edgeFaces(l.e)) do
							if h ~= g and fs[h] and not seen[h] and (not sameGroup or sameGroup(g, h)) then
								seen[h] = true
								stack[#stack + 1] = h
							end
						end
					end
				end
			end
			out[#out + 1] = isl
		end
	end
	return out
end

-- ===== Pack Islands (uv_pack.cc, cut down: best rotation, then shelves) =====
-- islands = { { loops... }, ... } with l.uv set. Fits them all in the 0-1 square, keeping their relative sizes
function UV.pack(islands, margin, rotate)
	margin = margin or 0.02
	local boxes, totalArea = {}, 0
	for _, isl in ipairs(islands) do
		if #isl > 0 then
			-- the rotation (0..90 degrees) with the smallest bounding box
			local best, bestA = 0, math.huge
			local steps = rotate == false and 0 or 18
			for s = 0, steps do
				local a = math.rad(s * 5)
				local c, sn = math.cos(a), math.sin(a)
				local lx, ly, hx, hy = math.huge, math.huge, -math.huge, -math.huge
				for _, l in ipairs(isl) do
					local x, y = l.uv.X * c - l.uv.Y * sn, l.uv.X * sn + l.uv.Y * c
					lx, ly, hx, hy = math.min(lx, x), math.min(ly, y), math.max(hx, x), math.max(hy, y)
				end
				local ar = (hx - lx) * (hy - ly)
				if ar < bestA - 1e-9 then best, bestA = a, ar end
			end
			local c, sn = math.cos(best), math.sin(best)
			local lx, ly, hx, hy = math.huge, math.huge, -math.huge, -math.huge
			for _, l in ipairs(isl) do
				l.uv = V2(l.uv.X * c - l.uv.Y * sn, l.uv.X * sn + l.uv.Y * c)
				lx, ly, hx, hy = math.min(lx, l.uv.X), math.min(ly, l.uv.Y), math.max(hx, l.uv.X), math.max(hy, l.uv.Y)
			end
			-- stand it up (taller than wide packs better on shelves)
			local w, h = hx - lx, hy - ly
			if w > h * 1.0001 then
				for _, l in ipairs(isl) do l.uv = V2(-l.uv.Y, l.uv.X) end
				lx, ly, hx, hy = -hy, lx, -ly, hx
				w, h = h, w
			end
			boxes[#boxes + 1] = { isl = isl, x0 = lx, y0 = ly, w = w, h = h }
			totalArea += math.max(w, 1e-6) * math.max(h, 1e-6)
		end
	end
	if #boxes == 0 then return end
	local pad = math.sqrt(totalArea) * margin
	table.sort(boxes, function(a, b) return a.h > b.h end)
	-- shelf width: a square-ish layout, at least the widest island
	local width = math.sqrt(totalArea) * 1.15
	for _, b in ipairs(boxes) do width = math.max(width, b.w + pad * 2) end
	local x, y, shelfH, usedW = pad, pad, 0, 0
	for _, b in ipairs(boxes) do
		if x + b.w + pad > width and x > pad then
			x, y = pad, y + shelfH + pad
			shelfH = 0
		end
		b.px, b.py = x, y
		x += b.w + pad
		usedW = math.max(usedW, x)
		shelfH = math.max(shelfH, b.h)
	end
	local usedH = y + shelfH + pad
	local s = 1 / math.max(usedW, usedH, 1e-9)
	for _, b in ipairs(boxes) do
		for _, l in ipairs(b.isl) do l.uv = V2((l.uv.X - b.x0 + b.px) * s, (l.uv.Y - b.y0 + b.py) * s) end
	end
end

local function loopsOf(BMesh, faces)
	local out = {}
	for _, f in ipairs(faces) do for _, l in ipairs(BMesh.faceLoops(f)) do out[#out + 1] = l end end
	return out
end
local function project(BMesh, faces, n)
	local u, v = basis(n)
	for _, f in ipairs(faces) do
		for _, l in ipairs(BMesh.faceLoops(f)) do l.uv = V2(l.v.co:Dot(u), l.v.co:Dot(v)) end
	end
end
local function setOf(bm, fs)
	if fs and next(fs) then return fs end
	local all = {}
	for f in pairs(bm.faces) do all[f] = true end
	return all
end

-- ===== Smart UV Project: faces grouped by which way they face (within the angle), each group flattened
-- straight on, split into connected islands, then packed
local function smartIslands(bm, fs, opts)
	local BMesh = opts.BMesh
	local limit = math.cos(math.rad(opts.angle or 66))
	local list = {}
	for f in pairs(fs) do list[#list + 1] = { f = f, a = faceArea(BMesh, f) } end
	table.sort(list, function(a, b) return a.a > b.a end)
	local groups, groupOf = {}, {}
	for _, it in ipairs(list) do
		local f = it.f
		local best, bd = nil, limit
		for _, g in ipairs(groups) do
			local d = g.n:Dot(f.no)
			if d >= bd then best, bd = g, d end
		end
		if not best then
			best = { n = f.no, sum = V3(), faces = {} }
			groups[#groups + 1] = best
		end
		best.faces[#best.faces + 1] = f
		best.sum += f.no * it.a
		groupOf[f] = best
	end
	local islands = {}
	for _, g in ipairs(groups) do
		local n = g.sum.Magnitude > 1e-9 and g.sum.Unit or g.n
		local set = {}
		for _, f in ipairs(g.faces) do set[f] = true end
		for _, isl in ipairs(UV.islands(BMesh, bm, set, false)) do
			project(BMesh, isl, n)
			islands[#islands + 1] = loopsOf(BMesh, isl)
		end
	end
	return islands
end
function UV.smartProject(bm, fs, opts)
	local islands = smartIslands(bm, setOf(bm, fs), opts)
	UV.pack(islands, opts.margin)
	return #islands
end

-- ===== Unwrap: LSCM (least squares conformal maps) per island cut at seams =====
-- every triangle asks the map to keep its angles (Cauchy-Riemann); two points are pinned; solved with
-- conjugate gradients on the normal equations, starting from a flat projection
local function lscm(BMesh, faces)
	-- UV points: a mesh vert's corners in this island, split wherever a seam runs between them
	-- (corners joined across a shared edge that isn't a seam share one UV point)
	local inIsl = {}
	for _, f in ipairs(faces) do inIsl[f] = true end
	local parent = {}
	local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]] x = parent[x] end return x end
	local corners = {}
	for _, f in ipairs(faces) do for _, l in ipairs(BMesh.faceLoops(f)) do parent[l] = l corners[#corners + 1] = l end end
	local function cornerAt(g, v) for _, x in ipairs(BMesh.faceLoops(g)) do if x.v == v then return x end end end
	for _, l in ipairs(corners) do
		for _, e in ipairs({ l.e, l.prev.e }) do
			if not e.seam then
				for _, g in ipairs(BMesh.edgeFaces(e)) do
					if g ~= l.f and inIsl[g] then
						local m = cornerAt(g, l.v)
						if m then local a, b = find(l), find(m) if a ~= b then parent[a] = b end end
					end
				end
			end
		end
	end
	local idx, verts, groupId = {}, {}, {}
	for _, l in ipairs(corners) do
		local r = find(l)
		if not groupId[r] then verts[#verts + 1] = l.v groupId[r] = #verts end
		idx[l] = groupId[r]
	end
	local n = #verts
	-- start: flat projection along the island's average normal (area weighted)
	local sum = V3()
	for _, f in ipairs(faces) do sum += f.no * faceArea(BMesh, f) end
	local nrm = sum.Magnitude > 1e-9 and sum.Unit or faces[1].no
	local bu, bv = basis(nrm)
	local x = {}
	for i, v in ipairs(verts) do x[2 * i - 1], x[2 * i] = v.co:Dot(bu), v.co:Dot(bv) end
	-- rows: two per triangle (u_x - v_y = 0, u_y + v_x = 0), weighted by 1 / sqrt(area)
	local rows = {}
	for _, f in ipairs(faces) do
		local ls = BMesh.faceLoops(f)
		for t = 2, #ls - 1 do
			local tri = { ls[1], ls[t], ls[t + 1] }
			local p1, p2, p3 = tri[1].v.co, tri[2].v.co, tri[3].v.co
			local ex = p2 - p1
			local len = ex.Magnitude
			local tn = (p2 - p1):Cross(p3 - p1)
			local area = tn.Magnitude / 2
			if len > 1e-9 and area > 1e-12 then
				ex = ex / len
				local ey = tn.Unit:Cross(ex)
				local q = { V2(0, 0), V2(len, 0), V2((p3 - p1):Dot(ex), (p3 - p1):Dot(ey)) }
				local w = 1 / math.sqrt(area)
				local r1, r2 = { ids = {}, cu = {}, cv = {} }, { ids = {}, cu = {}, cv = {} }
				for j = 1, 3 do
					local a, b = q[j % 3 + 1], q[(j + 1) % 3 + 1]   -- edge opposite corner j
					local exj, eyj = b.X - a.X, b.Y - a.Y
					local id = idx[tri[j]]
					r1.ids[j], r1.cu[j], r1.cv[j] = id, -eyj * w, -exj * w
					r2.ids[j], r2.cu[j], r2.cv[j] = id, exj * w, -eyj * w
				end
				rows[#rows + 1] = r1
				rows[#rows + 1] = r2
			end
		end
	end
	if #rows == 0 or n < 3 then return x, verts, idx end
	-- pins: the two points furthest apart along the projection's longer side
	local lo, hi, lo2, hi2 = 1, 1, 1, 1
	for i = 1, n do
		if x[2 * i - 1] < x[2 * lo - 1] then lo = i end
		if x[2 * i - 1] > x[2 * hi - 1] then hi = i end
		if x[2 * i] < x[2 * lo2] then lo2 = i end
		if x[2 * i] > x[2 * hi2] then hi2 = i end
	end
	if x[2 * hi2] - x[2 * lo2] > x[2 * hi - 1] - x[2 * lo - 1] then lo, hi = lo2, hi2 end
	if lo == hi then return x, verts, idx end
	local pinned = { [lo] = true, [hi] = true }
	-- A x and A^T r on flat arrays (no tables made per step: this loop is the slow part)
	local NR = #rows
	local RI, RU, RV = table.create(NR * 3), table.create(NR * 3), table.create(NR * 3)
	for k, row in ipairs(rows) do
		for j = 1, 3 do
			RI[3 * (k - 1) + j] = 2 * row.ids[j] - 1
			RU[3 * (k - 1) + j] = row.cu[j]
			RV[3 * (k - 1) + j] = row.cv[j]
		end
	end
	local rbuf, gbuf = table.create(NR, 0), table.create(2 * n, 0)
	local function residual(vals)
		local r = rbuf
		local m = 1
		for k = 1, NR do
			local a1, a2, a3 = RI[m], RI[m + 1], RI[m + 2]
			r[k] = RU[m] * vals[a1] + RV[m] * vals[a1 + 1] + RU[m + 1] * vals[a2] + RV[m + 1] * vals[a2 + 1] + RU[m + 2] * vals[a3] + RV[m + 2] * vals[a3 + 1]
			m += 3
		end
		return r
	end
	local function atx(r)
		local g = gbuf
		for i = 1, 2 * n do g[i] = 0 end
		local m = 1
		for k = 1, NR do
			local rk = r[k]
			for j = 0, 2 do
				local a = RI[m + j]
				g[a] += RU[m + j] * rk
				g[a + 1] += RV[m + j] * rk
			end
			m += 3
		end
		for i in pairs(pinned) do g[2 * i - 1], g[2 * i] = 0, 0 end
		return g
	end
	-- minimise |A x|^2 over the free variables: conjugate gradients on A^T A x = 0 (pins = fixed values),
	-- preconditioned by the diagonal of A^T A (Jacobi)
	local diag = {}
	for i = 1, 2 * n do diag[i] = 0 end
	for _, row in ipairs(rows) do
		for j = 1, 3 do
			local id = row.ids[j]
			diag[2 * id - 1] += row.cu[j] * row.cu[j]
			diag[2 * id] += row.cv[j] * row.cv[j]
		end
	end
	for i = 1, 2 * n do diag[i] = diag[i] > 1e-30 and 1 / diag[i] or 0 end
	for i in pairs(pinned) do diag[2 * i - 1], diag[2 * i] = 0, 0 end
	local g = table.clone(atx(residual(x)))
	local z, d = {}, {}
	local rz = 0
	for i = 1, 2 * n do z[i] = g[i] * diag[i] d[i] = -z[i] rz += g[i] * z[i] end
	local r0 = rz
	local maxIt = math.min(3000, 60 + 4 * n)
	for _ = 1, maxIt do
		if rz <= r0 * 1e-14 or rz < 1e-26 then break end
		local ad = residual(d)
		local dAd = 0
		for k = 1, #ad do dAd += ad[k] * ad[k] end
		if dAd < 1e-30 then break end
		local alpha = rz / dAd
		for i = 1, 2 * n do x[i] += alpha * d[i] end
		local ag = atx(ad)
		local rz2 = 0
		for i = 1, 2 * n do
			g[i] += alpha * ag[i]
			z[i] = g[i] * diag[i]
			rz2 += g[i] * z[i]
		end
		local beta = rz2 / rz
		for i = 1, 2 * n do d[i] = -z[i] + beta * d[i] end
		rz = rz2
	end
	return x, verts, idx
end

function UV.unwrap(bm, fs, opts)
	local BMesh = opts.BMesh
	fs = setOf(bm, fs)
	local islands, closed = {}, 0
	for _, isl in ipairs(UV.islands(BMesh, bm, fs, true)) do
		-- a closed piece (no open edge or seam round it) can't be flattened: Smart Project it instead
		local open = false
		local inIsl = {}
		for _, f in ipairs(isl) do inIsl[f] = true end
		for _, f in ipairs(isl) do
			for _, l in ipairs(BMesh.faceLoops(f)) do
				if l.e.seam then open = true break end
				local c = 0
				for _, h in ipairs(BMesh.edgeFaces(l.e)) do if inIsl[h] then c += 1 end end
				if c < 2 then open = true break end
			end
			if open then break end
		end
		if open then
			local x, _, idx = lscm(BMesh, isl)
			if idx then
				for _, f in ipairs(isl) do
					for _, l in ipairs(BMesh.faceLoops(f)) do
						local i = idx[l]
						l.uv = V2(x[2 * i - 1], x[2 * i])
					end
				end
			else
				project(BMesh, isl, isl[1].no)
			end
			-- keep it the right way round (not mirrored)
			local signed = 0
			for _, f in ipairs(isl) do
				local ls = BMesh.faceLoops(f)
				for i = 2, #ls - 1 do
					local a, b, c = ls[1].uv, ls[i].uv, ls[i + 1].uv
					signed += (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X)
				end
			end
			if signed < 0 then for _, l in ipairs(loopsOf(BMesh, isl)) do l.uv = V2(-l.uv.X, l.uv.Y) end end
			islands[#islands + 1] = loopsOf(BMesh, isl)
		else
			closed += 1
			local set = {}
			for _, f in ipairs(isl) do set[f] = true end
			for _, l in ipairs(smartIslands(bm, set, opts)) do islands[#islands + 1] = l end
		end
	end
	UV.pack(islands, opts.margin)
	return #islands, closed
end

-- UV space helpers for the UV editor
function UV.facesWithUV(BMesh, bm)
	local n = 0
	for f in pairs(bm.faces) do
		local all = true
		for _, l in ipairs(BMesh.faceLoops(f)) do if not l.uv then all = false break end end
		if all then n += 1 end
	end
	return n
end

return UV
