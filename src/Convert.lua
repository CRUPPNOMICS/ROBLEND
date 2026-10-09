--[[
	ROBLEND - Convert: turn ordinary Roblox parts and meshes into ROBLEND meshes you can edit
	(Blender's Object > Convert / editing any mesh object).
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	Convert.meshOf(part, AssetService, BMesh, Ops, Mods, MT) -> bm (in the part's own space, real size) or nil, why
	  Part (Block / Ball / Cylinder), WedgePart, CornerWedgePart, MeshPart (read with CreateEditableMeshAsync -
	  only meshes you're allowed to edit: your own uploads / the experience's).
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

-- read a MeshPart's mesh (its own triangles), scaled to the part's real size, corners welded back together
local function fromMeshPart(p, AssetService, BMesh, Mods)
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
	local scale = V3(1, 1, 1)
	local okS, ms = pcall(function() return p.MeshSize end)
	local lo, hi
	local idTo = {}
	local okV, verts = pcall(function() return em:GetVertices() end)
	if not okV then pcall(function() em:Destroy() end) return nil, "couldn't read the mesh's points" end
	for _, vid in ipairs(verts) do
		local pos = em:GetPosition(vid)
		lo = lo and lo:Min(pos) or pos
		hi = hi and hi:Max(pos) or pos
	end
	if not lo then pcall(function() em:Destroy() end) return nil, "the mesh is empty" end
	local span = hi - lo
	local ref = (okS and ms and ms.Magnitude > 0) and ms or span
	scale = V3(ref.X > 1e-6 and p.Size.X / ref.X or 1, ref.Y > 1e-6 and p.Size.Y / ref.Y or 1, ref.Z > 1e-6 and p.Size.Z / ref.Z or 1)
	local centre = (lo + hi) / 2
	for _, vid in ipairs(verts) do idTo[vid] = bm:vertCreate((em:GetPosition(vid) - centre) * scale) end
	local nf = 0
	for _, fid in ipairs(em:GetFaces()) do
		local ids = em:GetFaceVertices(fid)
		local a, b, c = idTo[ids[1]], idTo[ids[2]], idTo[ids[3]]
		if a and b and c and a ~= b and b ~= c and a ~= c then
			if bm:faceCreate({ a, b, c }) then nf += 1 end
		end
	end
	pcall(function() em:Destroy() end)
	if nf == 0 then return nil, "the mesh has no faces" end
	-- the file splits corners per normal / UV: weld them back so it edits as one surface
	local welded = Mods.mergeDoubles(bm, 1e-4)
	welded:normalsUpdate()
	return welded
end

function Convert.meshOf(p, AssetService, BMesh, Ops, Mods, MT)
	if not (p and p:IsA("BasePart")) then return nil, "pick a part first" end
	local bm = BMesh.new()
	local size = p.Size
	if p:IsA("MeshPart") then
		return fromMeshPart(p, AssetService, BMesh, Mods)
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
