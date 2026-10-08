--[[
	ROBLENDER - showing a BMesh in Roblox (EditableMesh -> MeshPart), triangulating n-gons, baking to parts
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27). Ear clipping follows the idea of Blender's
	BLI_polyfill_2d (source/blender/blenlib/intern/polyfill_2d.cc, GPL-2.0-or-later, Blender Authors), cut down.
]]

local AssetService = game:GetService("AssetService")
local BMesh = require(script.Parent.BMesh)
local Display = {}
local V3 = Vector3.new

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
function Display.triangles(bm)
	local out = {}
	for f in pairs(bm.faces) do
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
		lo = V3(math.min(lo.X, v.co.X), math.min(lo.Y, v.co.Y), math.min(lo.Z, v.co.Z))
		hi = V3(math.max(hi.X, v.co.X), math.max(hi.Y, v.co.Y), math.max(hi.Z, v.co.Z))
		any = true
	end
	if not any then return V3(), V3(1, 1, 1) end
	return (lo + hi) / 2, hi - lo
end

-- build a MeshPart for the mesh. Verts go in centred on their box (centre returned) - flat shaded
-- (every face gets its own corners). selColor: tint for selected faces (edit mode)
function Display.build(bm, selColor)
	local c = Display.bounds(bm)
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
	for f in pairs(bm.faces) do
		local vs = BMesh.faceVerts(f)
		local ids = {}
		for i, v in ipairs(vs) do ids[i] = em:AddVertex(v.co - c) end
		for _, t in ipairs(Display.triangulate(vs, f.no)) do
			local fid = em:AddTriangle(ids[t[1]], ids[t[2]], ids[t[3]])
			tris += 1
			if white then
				pcall(function()
					local col = (sel and f.sel) and sel or white
					em:SetFaceColors(fid, { col, col, col })
				end)
			end
		end
	end
	if tris == 0 then return nil, c, "no faces" end
	local okM, mp = pcall(function() return AssetService:CreateMeshPartAsync(Content.fromObject(em)) end)
	if not okM then return nil, c, tostring(mp) end
	return mp, c, nil, em
end

-- ===== save: upload the mesh as a real Roblox Mesh asset (AssetService:CreateAssetAsync, local plugins,
-- Studio beta "CreateAssetAsync Luau API"). Returns id, err, errKind ("api" = the API isn't available), centre
function Display.upload(bm, params)
	local mp, c, err, em = Display.build(bm)
	if not mp or not em then return nil, err or "no mesh" end
	mp:Destroy()
	local ok, result, idOrErr = pcall(function() return AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, params) end)
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
	model.Name = "ROBLENDER_Baked"
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
	local lines = { "# ROBLENDER export", "o " .. (name or "ROBLENDER") }
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
