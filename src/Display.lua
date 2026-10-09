--[[
	ROBLEND - showing a BMesh in Roblox (EditableMesh -> MeshPart), triangulating n-gons, baking to parts
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27). Ear clipping follows the idea of Blender's
	BLI_polyfill_2d (source/blender/blenlib/intern/polyfill_2d.cc, GPL-2.0-or-later, Blender Authors), cut down.
]]

local AssetService = game:GetService("AssetService")
local BMesh = require(script.Parent.BMesh)
local Display = {}
local V3 = Vector3.new
-- every EditableMesh we make, by the MeshPart showing it (so old ones can be freed - they add up fast while dragging)
Display.emOf = setmetatable({}, { __mode = "k" })
Display.partEm = setmetatable({}, { __mode = "k" })
function Display.free(mp)
	if not mp then return end
	local em = Display.emOf[mp]
	Display.emOf[mp] = nil
	if em then pcall(function() em:Destroy() end) end
	pcall(function() mp:Destroy() end)
end
-- a real part now shows `em` (or an uploaded mesh when em is nil): free the one it showed before
function Display.adopt(part, em)
	local old = Display.partEm[part]
	Display.partEm[part] = em
	if old and old ~= em then pcall(function() old:Destroy() end) end
end
local function finite(v)
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end
Display.finite = finite

-- ===== ear clipping (n-gon -> triangles), in the face's own plane =====
local function cross2(o, a, b) return (a.X - o.X) * (b.Y - o.Y) - (a.Y - o.Y) * (b.X - o.X) end

function Display.triangulate(verts, no)
	local n = #verts
	if n == 3 then return { { 1, 2, 3 } } end
	-- 2D in the face plane
	local ax = (verts[2].co - verts[1].co)
	ax = ax - no * ax:Dot(no)
	if ax.Magnitude < 1e-9 then ax = no:Cross(V3(0, 1, 0)) if ax.Magnitude < 1e-9 then ax = no:Cross(V3(1, 0, 0)) end end
	ax = ax.Unit
	local ay = no:Cross(ax)
	local p = {}
	for i, v in ipairs(verts) do p[i] = Vector2.new(v.co:Dot(ax), v.co:Dot(ay)) end
	-- convex? then a fan is fine and fast
	local convex = true
	for i = 1, n do
		if cross2(p[i], p[i % n + 1], p[(i + 1) % n + 1]) < -1e-9 then convex = false break end
	end
	local tris = {}
	if convex then
		for i = 2, n - 1 do tris[#tris + 1] = { 1, i, i + 1 } end
		return tris
	end
	local idx = {}
	for i = 1, n do idx[i] = i end
	local guard = 0
	while #idx > 3 and guard < n * n do
		guard += 1
		local m = #idx
		local cut = false
		for i = 1, m do
			local a, b, c = idx[(i - 2) % m + 1], idx[i], idx[i % m + 1]
			if cross2(p[a], p[b], p[c]) > 1e-12 then
				local inside = false
				for j = 1, m do
					local q = idx[j]
					if q ~= a and q ~= b and q ~= c then
						if cross2(p[a], p[b], p[q]) >= 0 and cross2(p[b], p[c], p[q]) >= 0 and cross2(p[c], p[a], p[q]) >= 0 then inside = true break end
					end
				end
				if not inside then
					tris[#tris + 1] = { a, b, c }
					table.remove(idx, i)
					cut = true
					break
				end
			end
		end
		if not cut then break end
	end
	if #idx == 3 then tris[#tris + 1] = { idx[1], idx[2], idx[3] } end
	if #tris == 0 then for i = 2, n - 1 do tris[#tris + 1] = { 1, i, i + 1 } end end
	return tris
end

-- every triangle of the mesh as world-or-local points {a, b, c, face}
function Display.triangles(bm, skipHidden)
	local out = {}
	for f in pairs(bm.faces) do
		if skipHidden and f.hide then continue end
		local vs = BMesh.faceVerts(f)
		for _, t in ipairs(Display.triangulate(vs, f.no)) do
			out[#out + 1] = { vs[t[1]].co, vs[t[2]].co, vs[t[3]].co, f }
		end
	end
	return out
end

function Display.bounds(bm)
	local lo, hi = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	local any = false
	for v in pairs(bm.verts) do
		if not finite(v.co) then continue end
		lo = V3(math.min(lo.X, v.co.X), math.min(lo.Y, v.co.Y), math.min(lo.Z, v.co.Z))
		hi = V3(math.max(hi.X, v.co.X), math.max(hi.Y, v.co.Y), math.max(hi.Z, v.co.Z))
		any = true
	end
	if not any then return V3(), V3(1, 1, 1) end
	return (lo + hi) / 2, hi - lo
end

-- build a MeshPart for the mesh. Verts go in centred on their box (centre returned) - flat shaded
-- (every face gets its own corners). selColor: tint for selected faces (edit mode)
-- smooth faces share their corners (so the normals blend); flat faces get their own. skipHidden: leave out
-- faces hidden with H (the edit view only)
-- ===== UVs (Blender's UV > Cube / Cylinder / Sphere Projection, uvproject.cc), worked out from the
-- positions every time the mesh is built, so they follow your edits. Roblox textures: V goes down the image.
-- uv = { mode = "box" | "boxfit" | "cylinder" | "sphere" | "top", scale = studs per texture repeat }
Display.UV_MODES = {
	{ "box", "Cube Projection (tiled)" }, { "boxfit", "Cube Projection (fit)" }, { "cylinder", "Cylinder Projection" },
	{ "sphere", "Sphere Projection" }, { "top", "Project from Top" },
}
local function uvAt(uv, co, n, lo, size)
	local mode, s = uv.mode, math.max(uv.scale or 4, 1e-3)
	local rel = co - lo
	local function fit(a, b) return Vector2.new(a, 1 - b) end
	if mode == "box" or mode == "boxfit" then
		local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
		local u, v, du, dv
		if ax >= ay and ax >= az then u, v, du, dv = (n.X >= 0 and -rel.Z or rel.Z), rel.Y, size.Z, size.Y
			if n.X >= 0 then u += size.Z end
		elseif ay >= az then u, v, du, dv = rel.X, (n.Y >= 0 and -rel.Z or rel.Z), size.X, size.Z
			if n.Y >= 0 then v += size.Z end
		else u, v, du, dv = (n.Z >= 0 and rel.X or -rel.X), rel.Y, size.X, size.Y
			if n.Z < 0 then u += size.X end
		end
		if mode == "boxfit" then return fit(u / math.max(du, 1e-6), v / math.max(dv, 1e-6)) end
		return Vector2.new(u / s, -v / s)
	elseif mode == "cylinder" or mode == "sphere" then
		local c = lo + size / 2
		local d = co - c
		local u = (math.atan2(d.X, d.Z) / (2 * math.pi)) + 0.5
		if mode == "cylinder" then return fit(u, rel.Y / math.max(size.Y, 1e-6)) end
		local r = d.Magnitude
		local v = r > 1e-9 and (1 - math.acos(math.clamp(d.Y / r, -1, 1)) / math.pi) or 0.5
		return fit(u, v)
	else -- top
		return fit(rel.X / math.max(size.X, 1e-6), 1 - rel.Z / math.max(size.Z, 1e-6))
	end
end
-- the UVs of one face's corners (wrap-around fixed for cylinder / sphere so a face never spans the whole image)
function Display.faceUVs(uv, vs, n, lo, size)
	local out = {}
	for i, v in ipairs(vs) do out[i] = uvAt(uv, v.co, n, lo, size) end
	if uv.mode == "cylinder" or uv.mode == "sphere" then
		local mn, mx = math.huge, -math.huge
		for _, p in ipairs(out) do mn = math.min(mn, p.X) mx = math.max(mx, p.X) end
		if mx - mn > 0.5 then
			for i, p in ipairs(out) do if p.X < 0.5 then out[i] = Vector2.new(p.X + 1, p.Y) end end
		end
	end
	return out
end

function Display.build(bm, selColor, skipHidden, uv)
	local c = Display.bounds(bm)
	local lo, size
	if uv and uv.mode then
		local _, sz = Display.bounds(bm)
		size = sz
		lo = c - sz / 2
	end
	-- Roblox limit: 20,000 triangles / 60,000 verts per EditableMesh
	local nt, nvx = 0, 0
	for f in pairs(bm.faces) do nt += f.len - 2 nvx += f.len end
	if nt > 20000 or nvx > 60000 then return nil, c, ("too big for Roblox (%d triangles, max 20000)"):format(nt) end
	local em
	local ok = pcall(function() em = AssetService:CreateEditableMesh({}) end)
	if not ok or not em then em = AssetService:CreateEditableMesh() end
	local white, sel
	pcall(function()
		white = em:AddColor(Color3.new(1, 1, 1), 1)
		if selColor then sel = em:AddColor(selColor, 1) end
	end)
	local tris = 0
	local shared = {}
	-- Auto Smooth / split normals: smooth faces round a vert share its corner only across edges that are
	-- not marked sharp (and between two smooth faces), so sharp edges stay crisp. fan[v][f] = group key
	local fan = {}
	local function fanOf(v, f)
		local m = fan[v]
		if not m then
			m = {}
			fan[v] = m
			local parent = {}
			local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]] x = parent[x] end return x end
			local fs = BMesh.vertFaces(v)
			for _, g in ipairs(fs) do parent[g] = g end
			for _, e in ipairs(BMesh.vertEdges(v)) do
				if not e.sharp then
					local ef = BMesh.edgeFaces(e)
					if #ef == 2 and ef[1].smooth and ef[2].smooth and parent[ef[1]] and parent[ef[2]] then
						local a, b = find(ef[1]), find(ef[2])
						if a ~= b then parent[a] = b end
					end
				end
			end
			for _, g in ipairs(fs) do m[g] = find(g) end
		end
		return m[f] or f
	end
	for f in pairs(bm.faces) do
		if skipHidden and f.hide then continue end
		local vs = BMesh.faceVerts(f)
		-- never hand Roblox a broken point (NaN / huge): it can take Studio down
		local bad = false
		for _, v in ipairs(vs) do if not finite(v.co) then bad = true break end end
		if bad then continue end
		local ids = {}
		for i, v in ipairs(vs) do
			if f.smooth then
				local g = fanOf(v, f)
				local key = shared[v]
				if not key then key = {} shared[v] = key end
				if not key[g] then key[g] = em:AddVertex(v.co - c) end
				ids[i] = key[g]
			else
				ids[i] = em:AddVertex(v.co - c)
			end
		end
		local uvids
		if lo then
			uvids = {}
			pcall(function()
				for i, p in ipairs(Display.faceUVs(uv, vs, f.no, lo, size)) do uvids[i] = em:AddUV(p) end
			end)
		end
		for _, t in ipairs(Display.triangulate(vs, f.no)) do
			local fid = em:AddTriangle(ids[t[1]], ids[t[2]], ids[t[3]])
			tris += 1
			if uvids and uvids[t[3]] then pcall(function() em:SetFaceUVs(fid, { uvids[t[1]], uvids[t[2]], uvids[t[3]] }) end) end
			if white then
				pcall(function()
					local col = (sel and f.sel) and sel or white
					em:SetFaceColors(fid, { col, col, col })
				end)
			end
		end
	end
	if tris == 0 then pcall(function() em:Destroy() end) return nil, c, "no faces" end
	local okM, mp = pcall(function() return AssetService:CreateMeshPartAsync(Content.fromObject(em)) end)
	if not okM then pcall(function() em:Destroy() end) return nil, c, tostring(mp) end
	Display.emOf[mp] = em
	return mp, c, nil, em
end

-- ===== save: upload the mesh as a real Roblox Mesh asset (AssetService:CreateAssetAsync, local plugins,
-- Studio beta "CreateAssetAsync Luau API"). Returns id, err, errKind ("api" = the API isn't available), centre
function Display.upload(bm, params, uv)
	local mp, c, err, em = Display.build(bm, nil, nil, uv)
	if not mp or not em then return nil, err or "no mesh" end
	Display.emOf[mp] = nil
	pcall(function() mp:Destroy() end)
	local ok, result, idOrErr = pcall(function() return AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, params) end)
	pcall(function() em:Destroy() end)
	if not ok then return nil, tostring(result), "api" end
	if result ~= Enum.CreateAssetResult.Success then return nil, tostring(idOrErr or result) end
	return idOrErr, nil, nil, c
end
-- a MeshPart using the uploaded mesh (new uploads can take a moment to be ready, so it retries)
function Display.fromAsset(id)
	local lastErr
	for attempt = 1, 5 do
		for _, make in ipairs({
			function() return Content.fromAssetId(id) end,
			function() return Content.fromUri("rbxassetid://" .. tostring(id)) end,
		}) do
			local ok, mp = pcall(function() return AssetService:CreateMeshPartAsync(make()) end)
			if ok and mp then return mp end
			lastErr = mp
		end
		if attempt < 5 then task.wait(1.5) end
	end
	return nil, tostring(lastErr)
end

-- ===== bake: the mesh as real Roblox parts (wedges), glued - this SAVES and publishes like any part =====
local function wedgePair(a, b, c, thick, parent, look)
	-- longest side = base, the third corner splits the triangle into two right-angled wedges
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then c, a = a, c elseif acd > bcd and acd > abd then a, b = b, a end
	ab, ac, bc = b - a, c - a, c - b
	local nrm = ac:Cross(ab)
	if nrm.Magnitude < 1e-9 then return end
	local right = nrm.Unit
	local up = bc:Cross(right)
	if up.Magnitude < 1e-9 then return end
	up = up.Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.001 then return end
	local z1, z2 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	for _, w in ipairs({ { z1, (a + b) / 2, right, back }, { z2, (a + c) / 2, -right, -back } }) do
		if w[1] >= 0.001 then
			local p = Instance.new("WedgePart")
			p.Anchored = true
			p.Size = V3(thick, height, w[1])
			p.CFrame = CFrame.fromMatrix(w[2], w[3], up, w[4])
			p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			if look then p.Color, p.Material = look.Color, look.Material end
			p.Parent = parent
		end
	end
end

function Display.bake(bm, origin, look, glue)
	local GeometryService = game:GetService("GeometryService")
	local model = Instance.new("Model")
	model.Name = "ROBLEND_Baked"
	local _, size = Display.bounds(bm)
	local thick = math.clamp(math.max(size.X, size.Y, size.Z) * 0.004, 0.05, 0.2)
	for _, t in ipairs(Display.triangles(bm)) do
		wedgePair(origin * t[1], origin * t[2], origin * t[3], thick, model, look)
	end
	if glue then
		local level = {}
		for _, p in ipairs(model:GetChildren()) do level[#level + 1] = p end
		while #level > 1 do
			local nxt = {}
			for i = 1, #level, 150 do
				local first, rest = level[i], {}
				for j = i + 1, math.min(i + 149, #level) do rest[#rest + 1] = level[j] end
				if #rest == 0 then nxt[#nxt + 1] = first else
					local ok, res = pcall(function() return GeometryService:UnionAsync(first, rest, { SplitApart = false }) end)
					if not (ok and res and res[1]) then return model end   -- keep the pieces
					res[1].Parent = model
					first.Parent = nil
					for _, r in ipairs(rest) do r.Parent = nil end
					nxt[#nxt + 1] = res[1]
				end
			end
			level = nxt
		end
	end
	return model
end

-- ===== .obj text (1-based, verts then faces) =====
function Display.toOBJ(bm, name)
	local lines = { "# ROBLEND export", "o " .. (name or "ROBLEND") }
	local idx, n = {}, 0
	for v in pairs(bm.verts) do
		n += 1
		idx[v] = n
		lines[#lines + 1] = string.format("v %.5f %.5f %.5f", v.co.X, v.co.Y, v.co.Z)
	end
	for f in pairs(bm.faces) do
		local parts = {}
		for i, v in ipairs(BMesh.faceVerts(f)) do parts[i] = tostring(idx[v]) end
		lines[#lines + 1] = "f " .. table.concat(parts, " ")
	end
	return table.concat(lines, "\n")
end

return Display
