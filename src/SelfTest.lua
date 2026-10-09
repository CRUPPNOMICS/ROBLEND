--[[
	ROBLEND - Help > Run Self-Test: checks ROBLEND's features inside the real Studio (real EditableMesh,
	AssetService, collision, Boolean, UVs, modifiers, Edit Mode tools) without any clicking, and prints a
	report to the Output window ("ROBLEND TEST ..." lines). Everything it makes goes in a folder that is taken
	out of the place when it finishes; your own parts are never touched.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	SelfTest.run(C, api) - C is the plugin's shared context (Main.server.lua "ctx").
]]
local SelfTest = {}
local V3 = Vector3.new

function SelfTest.run(C, api)
	if SelfTest.running then C.setStatus("The self-test is already running.") return end
	SelfTest.running = true
	local BMesh, Ops, Mods, MT, Display = C.BMesh, C.Ops, C.Mods, C.MT, C.Display
	local results, pass, fail, skip = {}, 0, 0, 0
	local function log(kind, name, msg)
		local line = ("ROBLEND TEST %s  %s%s"):format(kind, name, msg and ("  -  " .. tostring(msg)) or "")
		if kind == "FAIL" then warn(line) else print(line) end
		results[#results + 1] = line
	end
	local function T(name, fn)
		local ok, err = pcall(fn)
		if ok and err == "skip" then skip += 1 log("SKIP", name)
		elseif ok and type(err) == "string" and err:sub(1, 5) == "skip:" then skip += 1 log("SKIP", name, err:sub(6))
		elseif ok then pass += 1 log("PASS", name)
		else fail += 1 log("FAIL", name, err) end
		task.wait()
	end
	local function check(cond, msg) if not cond then error(msg or "check failed", 2) end end
	local function faces(p) local d = C.HttpService:JSONDecode(C.dataOf(p).Value) return #d.f end
	local function cube(s) local m = BMesh.new() Ops.cube(m, s or 4) m:normalsUpdate() return m end
	local function emFaces(p) local em = Display.partEm[p] or Display.emOf[p] if not em then return nil end local ok, f = pcall(function() return #em:GetFaces() end) return ok and f or nil end

	local st0 = C.get()
	if st0.editing then api.toggleEdit() task.wait() end
	local savedSel = C.Selection:Get()
	local folder = Instance.new("Folder")
	folder.Name = "ROBLEND_SelfTest"
	folder.Parent = workspace
	local stamp = tostring(math.floor(os.clock() * 1000) % 100000)
	local function part(class, name, size, at)
		local q = Instance.new(class)
		q.Name = name .. "_" .. stamp
		q.Size = size
		q.CFrame = CFrame.new(at)
		q.Anchored = true
		q.Parent = folder
		return q
	end
	local ORIGIN = V3(0, 400, 0)   -- far up, out of the way
	C.setStatus("ROBLEND self-test running... (watch the Output window)")
	print("ROBLEND TEST START  version " .. tostring(C.VERSION))

	-- ===== Studio APIs ROBLEND relies on =====
	T("EditableMesh + MeshPart build", function()
		local m = cube()
		local mp, _, err, em = Display.build(m)
		check(mp and em, "build failed: " .. tostring(err))
		check(#em:GetFaces() == 12, "expected 12 triangles, got " .. #em:GetFaces())
		mp.Parent = folder
	end)
	T("fast path: SetPosition / SetFaceColors in place", function()
		local m = cube()
		local mp, _, _, em = Display.build(m)
		check(mp and em, "build failed")
		mp.Parent = folder
		local v = next(m.verts)
		v.co += V3(0, 1, 0)
		check(Display.updatePositions(em, m), "updatePositions returned false")
		local id = Display.maps[em].v[v][1]
		local p = em:GetPosition(id)
		local want = v.co - Display.maps[em].c
		check((p - want).Magnitude < 1e-3, "position not updated: " .. tostring(p) .. " vs " .. tostring(want))
		for q in pairs(m.verts) do q.col = Color3.new(1, 0, 0) end
		check(Display.updateColors(em, m), "updateColors returned false")
	end)
	T("collision / render options on new mesh parts", function()
		local m = cube()
		local mp = Display.build(m, nil, nil, nil, { CollisionFidelity = Enum.CollisionFidelity.Hull, RenderFidelity = Enum.RenderFidelity.Performance })
		check(mp, "build failed")
		mp.Parent = folder
		check(mp.CollisionFidelity == Enum.CollisionFidelity.Hull, "collision is " .. tostring(mp.CollisionFidelity))
		check(mp.RenderFidelity == Enum.RenderFidelity.Performance, "render is " .. tostring(mp.RenderFidelity))
	end)
	T("undo recording", function()
		local id = C.CHS:TryBeginRecording("ROBLEND", "ROBLEND self-test")
		check(id, "TryBeginRecording gave nothing (another recording open?)")
		C.CHS:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end)
	T("Studio tool watch (1 2 3 4 keys)", function()
		local t = C.plugin:GetSelectedRibbonTool()
		check(t ~= nil, "GetSelectedRibbonTool gave nothing")
	end)
	T("text sizes (menu widths)", function()
		local v = game:GetService("TextService"):GetTextSize("Double click / Ctrl Alt click", 11, Enum.Font.Gotham, Vector2.new(2000, 40))
		check(v.X > 50, "width " .. tostring(v.X))
	end)

	-- ===== Convert =====
	local shapes = {
		{ "Part", "Block", V3(4, 2, 6), 6 },
		{ "WedgePart", "Wedge", V3(2, 4, 6), 5 },
		{ "CornerWedgePart", "CornerWedge", V3(2, 2, 2), 5 },
	}
	for i, s in ipairs(shapes) do
		T("convert " .. s[2], function()
			local q = part(s[1], "RBT_" .. s[2], s[3], ORIGIN + V3(i * 10, 0, 0))
			local made = api.convert({ q })
			check(made[1] and C.isRB(made[1]), "not converted: " .. tostring(C.get().ui and "" or ""))
			check(faces(made[1]) == s[4], ("expected %d faces, got %d"):format(s[4], faces(made[1])))
			check(q.Parent == nil, "the original should be taken out")
		end)
	end
	T("convert Ball and Cylinder", function()
		local b = part("Part", "RBT_Ball", V3(4, 4, 4), ORIGIN + V3(40, 0, 0))
		b.Shape = Enum.PartType.Ball
		local cy = part("Part", "RBT_Cyl", V3(6, 2, 2), ORIGIN + V3(50, 0, 0))
		cy.Shape = Enum.PartType.Cylinder
		local made = api.convert({ b, cy })
		check(#made == 2, "converted " .. #made .. " of 2")
		check(math.abs(made[2].Size.X - 6) < 0.05, "cylinder should lie along X, size " .. tostring(made[2].Size))
	end)
	T("convert a saved MeshPart", function()
		local id
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("MeshPart") and d:GetAttribute("RB_AssetId") then id = d:GetAttribute("RB_AssetId") break end
		end
		if not id then return "skip: no saved ROBLEND mesh in this place yet (File > Save Mesh one first)" end
		local mp = C.AssetService:CreateMeshPartAsync(Content.fromAssetId(id))
		mp.Name = "RBT_Saved_" .. stamp
		mp.Anchored = true
		mp.CFrame = CFrame.new(ORIGIN + V3(60, 0, 0))
		mp.Parent = folder
		local made = api.convert({ mp })
		check(made[1], "couldn't open it: " .. tostring(C.lastStatus and C.lastStatus() or ""))
		check(faces(made[1]) > 0, "no faces")
	end)

	-- ===== Boolean =====
	local base, cutter
	T("Object > Boolean (difference)", function()
		base = api.convert({ part("Part", "RBT_Base", V3(4, 4, 4), ORIGIN + V3(0, 0, 20)) })[1]
		cutter = api.convert({ part("Part", "RBT_Cutter", V3(4, 4, 4), ORIGIN + V3(2, 2, 22)) })[1]
		check(base and cutter, "convert failed")
		C.Selection:Set({ cutter, base })
		C.setActive(base)
		local res = api.boolean("difference")
		check(res, "no result")
		check(faces(res) == 9, "expected 9 faces, got " .. faces(res))
		check(cutter.Parent == nil, "the cutter should be used up")
		base = res
	end)
	T("Boolean modifier follows its cutter", function()
		check(base, "needs the Boolean result")
		local cut = api.convert({ part("Part", "RBT_LiveCutter", V3(2, 2, 2), ORIGIN + V3(-2, -2, 18)) })[1]
		check(cut, "convert failed")
		C.Selection:Set({ base })
		C.setActive(base)
		api.modAdd("boolean")
		local list = api.mods()
		api.modSet(#list, "target", cut.Name)
		for _ = 1, 10 do task.wait(0.05) end
		local f1 = emFaces(base)
		cut.CFrame = CFrame.new(ORIGIN + V3(0, 200, 0))
		for _ = 1, 30 do task.wait(0.05) end
		local f2 = emFaces(base)
		check(f1 and f2 and f1 ~= f2, ("the cut didn't follow (triangles %s then %s)"):format(tostring(f1), tostring(f2)))
		api.modRemove(#api.mods())
	end)
	T("Boolean engine on round shapes", function()
		local a = BMesh.new() Ops.uvSphere(a, 16, 8, 1.5)
		local b = BMesh.new() Ops.cylinder(b, 12, 0.5, 4)
		local t0 = os.clock()
		local r = C.Boolean.run(a, b, "difference", { BMesh = BMesh, triangulate = Display.triangulate })
		check(r and r.nf > 0, "no result")
		log("INFO", "boolean sphere - cylinder took", ("%.0f ms"):format((os.clock() - t0) * 1000))
	end)

	-- ===== UVs =====
	T("Smart UV Project + stored UVs on the part", function()
		local p = api.convert({ part("Part", "RBT_UV", V3(4, 4, 4), ORIGIN + V3(0, 0, 40)) })[1]
		C.Selection:Set({ p })
		C.setActive(p)
		api.uvUnwrap("smart")
		local d = C.HttpService:JSONDecode(C.dataOf(p).Value)
		check(d.uv, "no UVs saved")
		check(p:GetAttribute("RB_UVMode") == "unwrap", "UV mode " .. tostring(p:GetAttribute("RB_UVMode")))
		local em = Display.partEm[p] or Display.emOf[p]
		if em then
			local ok, uvs = pcall(function() return em:GetUVs() end)
			if ok then check(#uvs > 0, "the shown mesh has no UVs") end
		end
	end)
	T("Unwrap speed (1,681-point wavy grid)", function()
		local g = BMesh.new() Ops.grid(g, 40, 40, 10)
		for v in pairs(g.verts) do v.co = v.co + V3(0, math.sin(v.co.X) * 1.5, 0) end
		g:normalsUpdate()
		local t0 = os.clock()
		C.UVTools.unwrap(g, nil, { BMesh = BMesh })
		log("INFO", "unwrap took", ("%.0f ms"):format((os.clock() - t0) * 1000))
	end)

	-- ===== modifiers =====
	T("every modifier evaluates", function()
		local bad = {}
		for _, t in ipairs(Mods.TYPES) do
			if t.id ~= "boolean" and t.id ~= "shrinkwrap" then
				local m = BMesh.new()
				if t.id == "tube" or t.id == "screw" then
					local a, b, c = m:vertCreate(V3(1, 0, 0)), m:vertCreate(V3(1, 1, 0)), m:vertCreate(V3(2, 2, 0))
					m:edgeCreate(a, b) m:edgeCreate(b, c)
				else
					Ops.uvSphere(m, 12, 6, 2)
				end
				local md = Mods.new(t.id)
				local ok, r = pcall(Mods.evaluate, m, { md }, { target = function() return nil end })
				if not ok or not r or r.nf == 0 then bad[#bad + 1] = t.id .. (ok and "" or (": " .. tostring(r))) end
			end
		end
		check(#bad == 0, "failed: " .. table.concat(bad, ", "))
	end)
	T("Shrinkwrap onto another part", function()
		local bp = part("Part", "RBT_WrapBall", V3(4, 4, 4), ORIGIN + V3(0, 0, 60))
		bp.Shape = Enum.PartType.Ball
		local ball = api.convert({ bp })[1]
		check(ball, "convert failed")
		local box = api.convert({ part("Part", "RBT_WrapBox", V3(2, 2, 2), ORIGIN + V3(0, 0, 60)) })[1]
		C.Selection:Set({ box })
		C.setActive(box)
		api.modAdd("shrinkwrap")
		api.modSet(#api.mods(), "target", ball.Name)
		api.modApply(#api.mods())
		local d = C.HttpService:JSONDecode(C.dataOf(box).Value)
		local o = box.CFrame * CFrame.new(-(box:GetAttribute("RB_Center") or V3()))
		for i = 1, #d.v, 3 do
			local w = o * V3(d.v[i], d.v[i + 1], d.v[i + 2])
			local r = (w - (ORIGIN + V3(0, 0, 60))).Magnitude
			check(math.abs(r - 2) < 0.15, "a point is " .. ("%.2f"):format(r) .. " from the ball's middle (should be 2)")
		end
	end)

	-- ===== brushes and text =====
	T("sculpt and paint brushes", function()
		local m = BMesh.new() Ops.uvSphere(m, 16, 8, 2)
		m:normalsUpdate()
		for _, b in ipairs(C.Sculpt.BRUSHES) do
			if b.id ~= "grab" then C.Sculpt.dab(m, b.id, V3(0, 2, 0), 1, 0.5, { BMesh = BMesh }) end
		end
		local n = C.Paint.dab(m, V3(0, 2, 0), 1.5, Color3.new(1, 0, 0), 1, { BMesh = BMesh })
		check(n > 0, "paint changed nothing")
	end)
	T("text mesh", function()
		local m = BMesh.new()
		C.Font.build(m, "ROBLEND 123", { pixel = 0.5, depth = 1 })
		check(m.nf > 100, "too few faces: " .. m.nf)
	end)

	-- ===== Edit Mode operators (each on a fresh cube, everything selected) =====
	T("Edit Mode operators", function()
		local p = api.convert({ part("Part", "RBT_Edit", V3(4, 4, 4), ORIGIN + V3(0, 0, 80)) })[1]
		C.Selection:Set({ p })
		C.setActive(p)
		api.toggleEdit()
		task.wait()
		check(C.get().editing, "couldn't enter Edit Mode")
		local bad = {}
		for _, name in ipairs({ "Subdivide", "Poke", "Triangulate", "TrisToQuads", "ConvexHull", "SymmetrizeX", "RecalcOutside", "RecalcInside",
			"ShadeSmooth", "ShadeFlat", "ShadeAutoSmooth", "FillHoles", "LimitedDissolve", "DegenerateDissolve", "SelectMore", "SelectLess",
			"SelectLinked", "SelectRandom", "Checker", "NonManifold", "Loose", "SharpEdges", "Hide", "Reveal", "CursorToSel", "CursorToOrigin",
			"ExtrudeIndividual", "Solidify", "Wireframe", "Bevel", "Smooth", "Randomize", "ShrinkFatten", "ToSphere", "Spin", "Duplicate",
			"BooleanDifference", "DissolveFaces", "DeleteFaces" }) do
			local m = cube()
			for v in pairs(m.verts) do v.sel = true end
			for e in pairs(m.edges) do e.sel = true end
			for f in pairs(m.faces) do f.sel = true end
			C.setBm(m)
			local ok, err = true, nil
			if not api.hasTool(name) then ok, err = false, "no such command" else ok, err = pcall(api.tool, name) end
			if ok and C.get().modal then
				ok, err = pcall(C.finishModal, false)
			end
			if ok then
				local okV, errV = pcall(function() C.get().bm:validate() end)
				if not okV then ok, err = false, "broken mesh: " .. tostring(errV) end
			end
			if not ok then bad[#bad + 1] = name .. ": " .. tostring(err) end
			task.wait()
		end
		if C.get().modal then pcall(C.finishModal, true) end
		C.setBm(cube())
		api.toggleEdit()
		check(#bad == 0, table.concat(bad, " | "))
	end)

	-- ===== keyboard =====
	T("keyboard holding (shortcut blocking)", function()
		local KC = api.keyCapture()
		check(KC, "no key capture")
		if not KC.enabled then return "skip: switched off in Edit > Block Studio Shortcuts" end
		if KC.failed then return "skip: it switched itself off this session (restart Studio)" end
		KC.grab()
		task.wait()
		local f = game:GetService("UserInputService"):GetFocusedTextBox()
		check(f ~= nil and KC.isOurs(f), "the invisible box didn't get the keyboard")
	end)

	-- ===== tidy up =====
	if C.get().modal then pcall(C.finishModal, true) end
	if C.get().editing then api.toggleEdit() end
	folder.Parent = nil
	pcall(function() C.Selection:Set(savedSel) end)
	local summary = ("ROBLEND TEST DONE  %d passed, %d failed, %d skipped"):format(pass, fail, skip)
	print(summary)
	C.setStatus(summary:gsub("ROBLEND TEST DONE  ", "Self-test: ") .. (fail > 0 and " - see the Output window for what failed." or "."))
	SelfTest.running = false
	return results, pass, fail, skip
end

return SelfTest
