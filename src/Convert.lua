--[[
	ROBLEND - Convert: turn ordinary Roblox parts and meshes into ROBLEND meshes you can edit
	(Blender's Object > Convert / editing any mesh object).
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	Convert.meshOf(part, AssetService, BMesh, Ops, Mods, MT) -> bm (in the part's own space, real size) or nil, why
	  Part (Block / Ball / Cylinder), WedgePart, CornerWedgePart, MeshPart (read with CreateEditableMeshAsync -
	  only meshes you're allowed to edit: your own uploads / the experience's). A MeshPart keeps its UVs (so its
	  texture still fits), its smooth / sharp shading, and gets its quads back.
	Convert.hasUV(bm, BMesh) -> true when every face corner has a UV
]]
local Convert = {}
local V3 = Vector3.new

local function box(bm, size)
	local h = size / 2
	local p = {}
	for i, c in ipairs({ { -1, -1, -1 }, { 1, -1, -1 }, { 1, 1, -1 }, { -1, 1, -1 }, { -1, -1, 1 }, { 1, -1, 1 }, { 1, 1, 1 }, { -1, 1, 1 } }) do
		p[i] = bm:vertCreate(V3(c[1] * h.X, c[2] * h.Y, c[3] * h.Z))
	end
	for _, q in ipairs({ { 1, 4, 3, 2 }, { 5, 6, 7, 8 }, { 1, 2, 6, 5 }, { 4, 8, 7, 3 }, { 1, 5, 8, 4 }, { 2, 3, 7, 6 } }) do
		bm:faceCreate({ p[q[1]], p[q[2]], p[q[3]], p[q[4]] })
	end
end

-- Roblox's WedgePart: full height at the back (+Z), the slope runs down to the front bottom edge (-Z)
local function wedge(bm, size)
	local h = size / 2
	local a = bm:vertCreate(V3(-h.X, -h.Y, -h.Z))
	local b = bm:vertCreate(V3(h.X, -h.Y, -h.Z))
	local c = bm:vertCreate(V3(h.X, -h.Y, h.Z))
	local d = bm:vertCreate(V3(-h.X, -h.Y, h.Z))
	local e = bm:vertCreate(V3(-h.X, h.Y, h.Z))
	local f = bm:vertCreate(V3(h.X, h.Y, h.Z))
	bm:faceCreate({ a, b, c, d })    -- bottom
	bm:faceCreate({ d, c, f, e })    -- back
	bm:faceCreate({ a, e, f, b })    -- slope
	bm:faceCreate({ a, d, e })       -- left
	bm:faceCreate({ b, f, c })       -- right
end

-- Roblox's CornerWedgePart: the peak sits over the back-right corner (+X, +Z)
local function cornerWedge(bm, size)
	local h = size / 2
	local a = bm:vertCreate(V3(-h.X, -h.Y, -h.Z))
	local b = bm:vertCreate(V3(h.X, -h.Y, -h.Z))
	local c = bm:vertCreate(V3(h.X, -h.Y, h.Z))
	local d = bm:vertCreate(V3(-h.X, -h.Y, h.Z))
	local top = bm:vertCreate(V3(h.X, h.Y, -h.Z))
	bm:faceCreate({ a, b, c, d })
	bm:faceCreate({ a, top, b })
	bm:faceCreate({ b, top, c })
	bm:faceCreate({ c, top, d })
	bm:faceCreate({ d, top, a })
end

-- every face pointing outward (Blender's Recalculate Outside; a stretch like the cylinder's X / Y swap mirrors it)
local function fixWinding(bm, MT)
	bm:normalsUpdate()
	if MT then
		local ok, out = pcall(MT.recalcNormals, bm)
		if ok and out then bm = out end
		bm:normalsUpdate()
	end
	return bm
end

-- read a MeshPart's mesh the way Blender would show it after an import: the points the file splits per normal / UV
-- welded back into one surface, the texture's UVs kept on every corner, smooth shading with sharp edges where the
-- file's normals split, and the triangles the export made joined back into the quads they came from
local function fromMeshPart(p, AssetService, BMesh, MT)
	local content
	pcall(function() content = p.MeshContent end)
	if not content or (typeof and typeof(content) == "Content" and content.SourceType == Enum.ContentSourceType.None) then
		local id = p.MeshId
		if not id or id == "" then return nil, "this MeshPart has no mesh" end
		content = Content.fromUri(id)
	end
	local ok, em = pcall(function() return AssetService:CreateEditableMeshAsync(content) end)
	if not ok or not em then
		return nil, "Roblox won't let plugins open this mesh (" .. tostring(em) .. "). Only meshes you or this experience uploaded can be edited."
	end
	local bm = BMesh.new()
	local okS, ms = pcall(function() return p.MeshSize end)
	local lo, hi
	local okV, verts = pcall(function() return em:GetVertices() end)
	if not okV then pcall(function() em:Destroy() end) return nil, "couldn't read the mesh's points" end
	local pos = {}
	for _, vid in ipairs(verts) do
		local q = em:GetPosition(vid)
		pos[vid] = q
		lo = lo and lo:Min(q) or q
		hi = hi and hi:Max(q) or q
	end
	if not lo then pcall(function() em:Destroy() end) return nil, "the mesh is empty" end
	local span = hi - lo
	local ref = (okS and ms and ms.Magnitude > 0) and ms or span
	local scale = V3(ref.X > 1e-6 and p.Size.X / ref.X or 1, ref.Y > 1e-6 and p.Size.Y / ref.Y or 1, ref.Z > 1e-6 and p.Size.Z / ref.Z or 1)
	local centre = (lo + hi) / 2
	-- weld: the file keeps a copy of a point for every normal / UV it has; one point per place here
	local tol = math.max(span.Magnitude * 1e-6, 1e-7)
	local at, idTo = {}, {}
	for _, vid in ipairs(verts) do
		local q = pos[vid]
		local k = math.floor(q.X / tol + 0.5) .. "," .. math.floor(q.Y / tol + 0.5) .. "," .. math.floor(q.Z / tol + 0.5)
		local v = at[k]
		if not v then v = bm:vertCreate((q - centre) * scale) at[k] = v end
		idTo[vid] = v
	end
	local nf = 0
	local useUV, useN = true, true
	local corner = {}      -- face -> { [vert] = the file's normal there }
	for _, fid in ipairs(em:GetFaces()) do
		local ids = em:GetFaceVertices(fid)
		local a, b, c = idTo[ids[1]], idTo[ids[2]], idTo[ids[3]]
		if a and b and c and a ~= b and b ~= c and a ~= c then
			local f = bm:faceCreate({ a, b, c })
			if f then
				nf += 1
				local ls = BMesh.faceLoops(f)
				if useUV then
					local okU, uv = pcall(function()
						local u = em:GetFaceUVs(fid)
						return { em:GetUV(u[1]), em:GetUV(u[2]), em:GetUV(u[3]) }
					end)
					if okU and uv and uv[1] and uv[2] and uv[3] then
						-- Roblox's V runs down the picture, Blender's (and ROBLEND's) runs up
						for i = 1, 3 do ls[i].uv = Vector2.new(uv[i].X, 1 - uv[i].Y) end
					else
						useUV = false
					end
				end
				if useN then
					local okN, nn = pcall(function()
						local u = em:GetFaceNormals(fid)
						return { em:GetNormal(u[1]), em:GetNormal(u[2]), em:GetNormal(u[3]) }
					end)
					if okN and nn and nn[1] and nn[2] and nn[3] then
						local m = {}
						-- a stretched part bends its normals the other way (divide by the stretch)
						for i = 1, 3 do local w = nn[i] / scale m[ls[i].v] = w.Magnitude > 1e-9 and w.Unit or w end
						corner[f] = m
					else
						useN = false
					end
				end
			end
		end
	end
	pcall(function() em:Destroy() end)
	if nf == 0 then return nil, "the mesh has no faces" end
	-- all or nothing: a mesh with UVs on only some faces would look wrong
	if not useUV then for f in pairs(bm.faces) do for _, l in ipairs(BMesh.faceLoops(f)) do l.uv = nil end end end
	-- shading: smooth everywhere, sharp where the file's normals split along an edge (Blender's Smooth by Angle look)
	if useN then
		for f in pairs(bm.faces) do f.smooth = true end
		for e in pairs(bm.edges) do
			local fs = BMesh.edgeFaces(e)
			if #fs == 2 then
				local c1, c2 = corner[fs[1]], corner[fs[2]]
				for _, v in ipairs({ e.v1, e.v2 }) do
					local n1, n2 = c1 and c1[v], c2 and c2[v]
					if not (n1 and n2) or n1:Dot(n2) < 0.9995 then e.sharp = true break end
				end
			end
		end
	end
	bm:normalsUpdate()
	-- the export cut every quad into two triangles: join them back where it's clean (same UVs, no sharp edge, a good shape)
	if MT and MT.trisToQuads then
		local all = {}
		for f in pairs(bm.faces) do all[f] = true end
		pcall(MT.trisToQuads, bm, all, math.rad(40), { uv = true, sharp = true, shape = true })
	end
	return bm
end

-- true when every face corner has a UV (the mesh brought its texture layout with it)
function Convert.hasUV(bm, BMesh)
	local any = false
	for f in pairs(bm.faces) do
		for _, l in ipairs(BMesh.faceLoops(f)) do
			if not l.uv then return false end
			any = true
		end
	end
	return any
end

function Convert.meshOf(p, AssetService, BMesh, Ops, Mods, MT)
	if not (p and p:IsA("BasePart")) then return nil, "pick a part first" end
	local bm = BMesh.new()
	local size = p.Size
	if p:IsA("MeshPart") then
		return fromMeshPart(p, AssetService, BMesh, MT)
	elseif p:IsA("WedgePart") then
		wedge(bm, size)
	elseif p:IsA("CornerWedgePart") then
		cornerWedge(bm, size)
	elseif p:IsA("Part") then
		local shape = p.Shape
		if shape == Enum.PartType.Ball then
			Ops.uvSphere(bm, 24, 12, 1)
			for v in pairs(bm.verts) do v.co = v.co * (size / 2) end
			for f in pairs(bm.faces) do f.smooth = true end
		elseif shape == Enum.PartType.Cylinder then
			-- Roblox cylinders lie along X
			Ops.cylinder(bm, 24, 1, 2)
			for v in pairs(bm.verts) do v.co = V3(v.co.Y * size.X / 2, v.co.X * size.Y / 2, v.co.Z * size.Z / 2) end
		else
			box(bm, size)
		end
	else
		return nil, "ROBLEND can't convert a " .. p.ClassName .. " (Unions can't be read by plugins)"
	end
	return fixWinding(bm, MT)
end

return Convert
