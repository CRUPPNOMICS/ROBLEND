--[[
	ROBLEND - Object Mode tools: Join, Set Origin, Apply Rotation, Shade Smooth / Flat / Auto, Hide / Reveal,
	Clear Location / Rotation, Local View, Convert to ROBLEND Mesh. Converted from Blender's object operators
	(source/blender/editors/object/object_transform.cc, object_relations.cc, view3d localview).
	SPDX-License-Identifier: GPL-2.0-or-later
	Original: Copyright (C) Blender Authors. Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27).

	ObjectTools.new(C): C is the plugin's shared context (see Main.server.lua "ctx"):
	  helpers (setStatus, loadFrom, originOf, encode, applyMesh, dataOf, isRB, record, selectedParts, commit),
	  services (Selection), modules (MT, Display), C.get() = live state, C.setActive(p), C.dirtyCage().
]]
local ObjectTools = {}
local V3 = Vector3.new

function ObjectTools.new(C)
	local OT = {}
	local NAME, Selection, MT, Display = C.NAME, C.Selection, C.MT, C.Display
	local setStatus, loadFrom, originOf, encode, applyMesh, dataOf, isRB, record, selectedParts, commit =
		C.setStatus, C.loadFrom, C.originOf, C.encode, C.applyMesh, C.dataOf, C.isRB, C.record, C.selectedParts, C.commit
	local scene = C.scene

	-- Ctrl J (Blender's Join): the other selected meshes go into the active one
	function OT.join()
		local ps = {}
		for _, p in ipairs(selectedParts()) do if isRB(p) then ps[#ps + 1] = p end end
		local act = (isRB(C.get().activeObj) and table.find(ps, C.get().activeObj)) and C.get().activeObj or ps[1]
		if #ps < 2 then setStatus("Select two or more " .. NAME .. " meshes to join (Shift click).") return end
		local base = loadFrom(act)
		local spec = MT.toSpec(base)
		local o = originOf(act)
		for _, p in ipairs(ps) do
			if p ~= act then
				local m = loadFrom(p)
				local src = MT.toSpec(m)
				local op = originOf(p)
				local off = #spec.verts
				for _, sv in ipairs(src.verts) do
					spec.verts[#spec.verts + 1] = { co = o:PointToObjectSpace(op * sv.co), sel = false, loose = sv.loose }
				end
				for _, f in ipairs(src.faces) do
					local r = {}
					for j, k in ipairs(f.v) do r[j] = k + off end
					spec.faces[#spec.faces + 1] = { v = r, sel = false, smooth = f.smooth }
				end
				for _, e in ipairs(src.edges) do spec.edges[#spec.edges + 1] = { e[1] + off, e[2] + off } end
				for k, fl in pairs(src.eflags) do
					local a, b = k:match("(%d+):(%d+)")
					spec.eflags[(tonumber(a) + off) .. ":" .. (tonumber(b) + off)] = fl
				end
			end
		end
		local joined = MT.fromSpec(spec)
		record("Join", function()
			dataOf(act).Value = encode(joined)
			local _, _, np = applyMesh(act, joined, false)
			act = np or act
			for _, p in ipairs(ps) do if p ~= act then p.Parent = nil end end
		end)
		Selection:Set({ act })
		C.setActive(act)
		if scene[act] then scene[act].data = nil end
		C.dirtyCage()
		setStatus(("Joined %d meshes into %s."):format(#ps, act.Name))
	end
	-- rebuild a part with new mesh coords and a new origin (keeps where the mesh is in the world unless asked)
	function OT.reshapePart(p, m, newOrigin, what)
		record(what, function()
			dataOf(p).Value = encode(m)
			-- point the part's origin at newOrigin, then applyMesh puts the mesh round it
			p.CFrame = newOrigin * CFrame.new(p:GetAttribute("RB_Center") or V3())
			local _, _, np = applyMesh(p, m, false)
			p = np or p
		end)
		if scene[p] then scene[p].data = nil end
		return p
	end
	function OT.rbSelected()
		local out = {}
		for _, p in ipairs(selectedParts()) do if isRB(p) then out[#out + 1] = p end end
		return out
	end
	-- Object > Set Origin (Blender's object.origin_set)
	function OT.setOrigin(how)
		if C.get().editing then setStatus("Set Origin works in Object Mode (Tab).") return end
		local ps = OT.rbSelected()
		if #ps == 0 then setStatus("Select a " .. NAME .. " mesh first.") return end
		for _, p in ipairs(ps) do
			local m = loadFrom(p)
			local o = originOf(p)
			local c = Display.bounds(m)
			local newO = o
			if how == "geometry" then
				-- Origin to Geometry: the origin moves to the middle of the mesh
				newO = o * CFrame.new(c)
				for v in pairs(m.verts) do v.co -= c end
			elseif how == "cursor" then
				newO = CFrame.new(C.get().cursor) * o.Rotation
				for v in pairs(m.verts) do v.co = newO:PointToObjectSpace(o * v.co) end
			else
				-- Geometry to Origin: the mesh moves so its middle is on the origin
				for v in pairs(m.verts) do v.co -= c end
			end
			m:normalsUpdate()
			OT.reshapePart(p, m, newO, "Set Origin")
		end
		C.dirtyCage()
		setStatus(({ geometry = "Origin moved to the middle of the mesh.", cursor = "Origin moved to the 3D cursor.", origin = "Mesh moved onto its origin." })[how] or "Origin set.")
	end
	-- Object > Apply > Rotation: bake the part's rotation into the mesh, the part goes back to 0, 0, 0
	function OT.applyRotation()
		if C.get().editing then return end
		local ps = OT.rbSelected()
		if #ps == 0 then setStatus("Select a " .. NAME .. " mesh first.") return end
		for _, p in ipairs(ps) do
			local m = loadFrom(p)
			local o = originOf(p)
			local newO = CFrame.new(o.Position)
			for v in pairs(m.verts) do v.co = newO:PointToObjectSpace(o * v.co) end
			m:normalsUpdate()
			OT.reshapePart(p, m, newO, "Apply Rotation")
		end
		setStatus("Rotation applied: the mesh keeps its look, the part's rotation is 0.")
	end
	-- Object > Shade Smooth / Shade Flat (every face of the selected meshes)
	function OT.shade(smooth, autoAngle)
		local ps = OT.rbSelected()
		if #ps == 0 then setStatus("Select a " .. NAME .. " mesh first.") return end
		for _, p in ipairs(ps) do
			local S = C.get()
			local m = (S.editing and p == S.obj) and S.bm or loadFrom(p)
			for f in pairs(m.faces) do f.smooth = smooth or nil end
			if autoAngle then MT.smoothByAngle(m, nil, autoAngle) end
			if S.editing and p == S.obj then commit("Shade") else OT.reshapePart(p, m, originOf(p), "Shade") end
		end
		setStatus(autoAngle and "Shade Auto Smooth (30 degrees)." or smooth and "Shade Smooth." or "Shade Flat.")
	end

	-- H / Shift H / Alt H in Object Mode (the Outliner eye)
	function OT.hide(which)
		local sel = {}
		for _, p in ipairs(Selection:Get()) do sel[p] = true end
		local n = 0
		for p, r in pairs(scene) do
			if which == "reveal" then
				if r.hidden then r.hidden = false n += 1 end
			elseif (which == "selected") == (sel[p] == true) and not r.hidden then
				r.hidden = true
				n += 1
			end
		end
		if which ~= "reveal" then Selection:Set({}) end
		C.dirtyCage()
		setStatus(which == "reveal" and ("Revealed %d."):format(n) or ("Hid %d."):format(n))
	end
	-- Alt G / Alt R: put the origin back at the world centre / clear the rotation (the part moves, the mesh doesn't change)
	function OT.clearTransform(what)
		local ps = OT.rbSelected()
		if #ps == 0 then setStatus("Select a " .. NAME .. " mesh first.") return end
		record(what == "loc" and "Clear Location" or "Clear Rotation", function()
			for _, p in ipairs(ps) do
				local o = originOf(p)
				local newO = (what == "loc") and o.Rotation or CFrame.new(o.Position)
				p.CFrame = newO * CFrame.new(p:GetAttribute("RB_Center") or V3())
			end
		end)
		C.dirtyCage()
		setStatus(what == "loc" and "Location cleared (origin at 0, 0, 0)." or "Rotation cleared.")
	end
	-- Numpad / (Local View): show only the selected meshes; again to bring the rest back
	local localView = nil
	function OT.toggleLocalView()
		if localView then
			for _, r in pairs(scene) do r.localOut = nil end
			localView = nil
			setStatus("Local view off.")
		else
			local set = {}
			for _, p in ipairs(Selection:Get()) do set[p] = true end
			local S = C.get()
			if S.editing and S.obj then set[S.obj] = true end
			if not next(set) then setStatus("Select something for Local View.") return end
			for p, r in pairs(scene) do r.localOut = not set[p] or nil end
			localView = set
			setStatus("Local view: only the selection is shown (Numpad / again to leave).")
		end
		C.dirtyCage()
	end

	-- Object > Convert to ROBLEND Mesh (Blender's Object > Convert): any Part / Wedge / Ball / Cylinder / MeshPart
	-- becomes a ROBLEND mesh in the same place, with the same look; the original is taken out (Ctrl Z brings it back)
	local KEEP = { "Name", "Color", "Material", "Transparency", "Reflectance", "Anchored", "CanCollide", "CanTouch", "CanQuery", "CastShadow", "Massless", "Locked" }
	function OT.convert(parts)
		parts = parts or selectedParts()
		local made, why = {}, nil
		for _, p in ipairs(parts) do
			if p:IsA("BasePart") and not isRB(p) then
				local m, err = C.Convert.meshOf(p, C.AssetService, C.BMesh, C.Ops, C.Mods, MT)
				if not m then
					why = err
				else
					-- a MeshPart keeps its collision / render detail; a plain part gets Roblox's Default
					local fo = {}
					if p:IsA("MeshPart") then pcall(function() fo.CollisionFidelity, fo.RenderFidelity = p.CollisionFidelity, p.RenderFidelity end) end
					local mp, c, err2 = Display.build(m, nil, nil, nil, fo)
					if not mp then
						why = err2
					else
						record("Convert", function()
							for _, k in ipairs(KEEP) do pcall(function() mp[k] = p[k] end) end
							mp.CFrame = p.CFrame * CFrame.new(c)
							local sv = Instance.new("StringValue")
							sv.Name = "RB_Data"
							sv.Value = encode(m)
							sv.Parent = mp
							for k, v in pairs(p:GetAttributes()) do pcall(function() mp:SetAttribute(k, v) end) end
							mp:SetAttribute("RB_Center", c)
							mp:SetAttribute("RB_Size", mp.Size)
							mp:SetAttribute("ROBLEND", C.VERSION)
							pcall(Display.rememberFidelity, mp)
							-- children (decals, scripts, welds...) come along; joints elsewhere that held the old part hold the new one
							for _, ch in ipairs(p:GetChildren()) do ch.Parent = mp end
							local root = p.Parent
							if root then
								for _, d in ipairs(root:GetDescendants()) do
									if d:IsA("WeldConstraint") or d:IsA("JointInstance") or d:IsA("NoCollisionConstraint") then
										pcall(function()
											if d.Part0 == p then d.Part0 = mp end
											if d.Part1 == p then d.Part1 = mp end
										end)
									end
								end
							end
							mp.Parent = root or workspace
							Display.adopt(mp, Display.emOf[mp])
							p.Parent = nil
						end)
						if scene then scene[mp] = scene[mp] or { part = mp } end
						made[#made + 1] = mp
					end
				end
			end
		end
		if #made > 0 then
			Selection:Set(made)
			C.setActive(made[#made])
			C.dirtyCage()
			setStatus(("Converted %d part%s into %s mesh%s (Tab to edit, Ctrl Z to undo)."):format(#made, #made == 1 and "" or "s", NAME, #made == 1 and "" or "es"))
		else
			setStatus(why and ("Couldn't convert: " .. why) or ("Select a Part, Wedge or MeshPart to turn into a " .. NAME .. " mesh."))
		end
		return made
	end

	-- Object > Boolean (like Blender's Boolean modifier applied, or the Bool Tool add-on): the active mesh is cut by /
	-- joined with / trimmed to the other selected parts, which are then taken out (Ctrl Z brings everything back)
	function OT.boolean(op)
		if C.get().editing then setStatus("Object > Boolean works in Object Mode (Tab). In Edit Mode use Face > Intersect (Boolean).") return end
		local ps = selectedParts()
		local act = C.get().activeObj
		if not (act and table.find(ps, act)) then act = nil end
		act = act or ps[1]
		if #ps < 2 or not act then setStatus("Select two or more parts: the one to keep last (it's the active one), then the cutters with Shift.") return end
		if not isRB(act) then
			local made = OT.convert({ act })
			if not made[1] then return end
			for i, q in ipairs(ps) do if q == act then ps[i] = made[1] end end
			act = made[1]
		end
		local base = loadFrom(act)
		local o = originOf(act)
		local cutters, result, err = {}, base, nil
		for _, q in ipairs(ps) do
			if q ~= act and q:IsA("BasePart") then
				local m, qo
				if isRB(q) then
					m, qo = C.evaluated(q, (loadFrom(q))), originOf(q)
				else
					m, err = C.Convert.meshOf(q, C.AssetService, C.BMesh, C.Ops, C.Mods, MT)
					qo = q.CFrame
				end
				if m then
					for v in pairs(m.verts) do v.co = o:PointToObjectSpace(qo * v.co) end
					m:normalsUpdate()
					local nb, why = C.Boolean.run(result, m, op, { BMesh = C.BMesh, triangulate = Display.triangulate })
					if nb then
						result = nb
						cutters[#cutters + 1] = q
					elseif op == "intersect" and why == "nothing left" then
						setStatus("Intersect: those parts don't overlap, so nothing would be left.")
						return
					else
						err = why
					end
				end
			end
		end
		if #cutters == 0 then setStatus("Boolean: " .. tostring(err or "nothing to cut with")) return end
		local name = ({ difference = "Difference", union = "Union", intersect = "Intersect" })[op] or op
		record("Boolean " .. name, function()
			dataOf(act).Value = encode(result)
			local _, _, np = applyMesh(act, result, false)
			act = np or act
			for _, q in ipairs(cutters) do q.Parent = nil end
		end)
		if scene[act] then scene[act].data = nil end
		Selection:Set({ act })
		C.setActive(act)
		C.dirtyCage()
		setStatus(("Boolean %s: %s now has %d faces (%d cutter%s used and taken out - Ctrl Z brings them back)."):format(name, act.Name, result.nf, #cutters, #cutters == 1 and "" or "s"))
		return act
	end

	return OT
end

return ObjectTools
