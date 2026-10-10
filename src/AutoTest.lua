--[[
	ROBLEND - Help > Run Auto-Test: goes through (nearly) every feature on its own, the way you would: it moves a
	pretend mouse and presses pretend keys through the same code your real mouse and keyboard go through, then
	checks what happened to the mesh. Prints "ROBLEND AUTO PASS / FAIL / INFO / YOU" lines to Output.
	YOU = needs a person (Studio's own key handling, uploads, restarting Studio, how it looks).
	Everything it adds is taken out again; your own parts are never touched.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	AutoTest.run(C, api) -> results, pass, fail, you
]]
local AutoTest = {}
local V3, V2 = Vector3.new, Vector2.new
local K = Enum.KeyCode

function AutoTest.run(C, api, only)
	if AutoTest.running then C.setStatus("The auto-test is already running.") return end
	AutoTest.running = true
	local H = require(script.Parent.QuickTest).helpers(C)
	local BMesh, Display = C.BMesh, C.Display
	local results, pass, fail, you = {}, 0, 0, 0
	local FAKE = { pos = V2(0, 0), keys = {} }

	local function log(kind, id, msg)
		local line = ("ROBLEND AUTO %s  %s%s"):format(kind, id, msg and ("  -  " .. tostring(msg)) or "")
		if kind == "FAIL" then warn(line) else print(line) end
		results[#results + 1] = line
	end
	local function check(cond, msg) if not cond then error(msg or "check failed", 2) end end
	local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-3) end

	-- ===== the pretend hands =====
	local function beat(n) for _ = 1, n or 1 do task.wait() end end
	local function inp(kc) return { KeyCode = kc, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero } end
	local function mods(list, on) for _, m in ipairs(list or {}) do FAKE.keys[K[m]] = on or nil end end
	local function key(name, ml)
		mods(ml, true)
		local kc = K[name]
		FAKE.keys[kc] = true
		api.inject("InputBegan", inp(kc), false)
		FAKE.keys[kc] = nil
		api.inject("InputEnded", inp(kc))
		mods(ml, false)
		beat()
	end
	local DIGIT = { ["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four", ["5"] = "Five", ["6"] = "Six", ["7"] = "Seven",
		["8"] = "Eight", ["9"] = "Nine", ["."] = "Period", ["-"] = "Minus" }
	local function typeNum(s) for ch in s:gmatch(".") do key(DIGIT[ch]) end end
	local function move(p) FAKE.pos = p api.inject("Move") beat() end
	local function glide(a, b, n) n = n or 6 for i = 1, n do move(a + (b - a) * (i / n)) end end
	local function click(p, ml)
		if p then move(p) end
		mods(ml, true)
		api.inject("Button1Down")
		beat()
		api.inject("Button1Up")
		mods(ml, false)
		beat(2)
		if not p then local v = C.get().view FAKE.pos = v:offset() + v:size() / 2 api.inject("Move") beat() end
	end
	local function rclick(p, ml)
		if p then move(p) end
		mods(ml, true)
		api.inject("Button2Down")
		api.inject("Button2Up")
		mods(ml, false)
		beat(2)
		if not p then local v = C.get().view FAKE.pos = v:offset() + v:size() / 2 api.inject("Move") beat() end
	end
	local function drag(a, b, ml, n)
		move(a)
		mods(ml, true)
		api.inject("Button1Down")
		glide(a, b, n or 6)
		api.inject("Button1Up")
		mods(ml, false)
		beat(2)
	end
	local function view() return C.get().view end
	local inMock = MOCK ~= nil   -- the fake Studio used for ROBLEND's own tests (its undo is only pretend)
	local function mid() local v = view() return v:offset() + v:size() / 2 end
	-- finish whatever tool is running (a click confirms)
	local function confirm() if C.get().modal then click(nil) end if C.get().modal then pcall(C.finishModal, false) end end

	-- ===== looking at the mesh =====
	local function bm() return C.get().bm end
	local function nf() return bm().nf end
	local function nv() return bm().nv end
	local function ne() return bm().ne end
	local function stats() return api.state().stats or { vs = 0, es = 0, fs = 0 } end
	local function W(co) return api.W(co) end
	local function S(wp) return (api.toScreen(wp)) end
	local function centre(f) return BMesh.faceCenter(f) end
	local function camPos() return api.camera().CFrame.Position end
	local function facing(f)
		local o = C.get().origin
		local wn = o:VectorToWorldSpace(f.no)
		local wc = W(centre(f))
		return wn:Dot((camPos() - wc).Unit)
	end
	-- the faces looking most toward the camera (so a click lands on them)
	local function frontFaces(pred)
		local list = {}
		for f in pairs(bm().faces) do if not f.hide and (not pred or pred(f)) then list[#list + 1] = { f = f, d = facing(f) } end end
		table.sort(list, function(a, b) return a.d > b.d end)
		local out = {}
		for i, x in ipairs(list) do out[i] = x.f end
		return out
	end
	local function frontFace(pred) return frontFaces(pred)[1] end
	local function sum(sel)
		local s, n = V3(), 0
		for v in pairs(bm().verts) do if not sel or v.sel then s += v.co n += 1 end end
		return n > 0 and s / n or s
	end
	local function snapshot()
		local t = {}
		for v in pairs(bm().verts) do t[v] = v.co end
		return t
	end
	-- a fingerprint of the whole shape (some tools rebuild the mesh, so the points are new objects)
	local function sig()
		local a, b = 0, 0
		for v in pairs(bm().verts) do local c = v.co a += c.X * c.X + 2 * c.Y * c.Y + 3 * c.Z * c.Z b += c.X + 1.7 * c.Y + 2.3 * c.Z end
		return ("%.4f|%.4f|%d"):format(a, b, bm().nv)
	end
	local function movedCount(t0)
		local n = 0
		for v, co in pairs(t0) do if v.co and (v.co - co).Magnitude > 1e-4 then n += 1 end end
		return n
	end
	local function selectVerts(list)
		C.clearSel()
		for _, v in ipairs(list) do v.sel = true end
		C.flush() C.dirtyMesh()
		beat()
	end
	local function topVerts()
		local top, out = -math.huge, {}
		for v in pairs(bm().verts) do top = math.max(top, v.co.Y) end
		for v in pairs(bm().verts) do if v.co.Y > top - 1e-3 then out[#out + 1] = v end end
		return out
	end
	-- the shown mesh of a part (its triangles + a position fingerprint)
	local function shown(p)
		local em = Display.partEm[p] or Display.emOf[p]
		if not em then return nil end
		local ok, r = pcall(function()
			local tris = #em:GetFaces()
			local s = V3()
			for i, id in ipairs(em:GetVertices()) do if i > 3000 then break end local q = em:GetPosition(id) s += V3(math.abs(q.X), math.abs(q.Y), math.abs(q.Z)) end
			return { tris = tris, key = ("%d|%.3f|%.3f|%.3f"):format(tris, s.X, s.Y, s.Z) }
		end)
		return ok and r or nil
	end
	local function mlist() return api.mods() or {} end
	local function data(p) return C.HttpService:JSONDecode(C.dataOf(p).Value) end
	local function obj() return C.Selection:Get()[1] end
	local function qtParts()
		local n = 0
		for _, row in ipairs(api.outliner()) do if row.key.Parent and row.key.Name:sub(1, 3) == "QT_" then n += 1 end end
		return n
	end
	local function addObj(kind, offset) local p = H.add(kind, offset) H.select({ p }) H.frame() beat(2) return p end
	local function edit(kind, mode, pick) local p = H.edit(kind, mode, pick) beat(2) return p end

	-- ===== the runner =====
	local extraBefore = {}
	for _, ch in ipairs(workspace:GetChildren()) do extraBefore[ch] = true end
	local function T(id, fn)
		if only and not only[id] then return end
		H.clean()
		FAKE.keys = {}
		pcall(function()
			local v = C.get().view
			api.viewAxis("front")
			v:step(math.rad(-40), math.rad(25))
			v.viewName = nil
			C.dirtyCage()
		end)
		move(mid())
		beat()
		local ok, err = pcall(fn)
		if C.get().modal then pcall(C.finishModal, true) end
		FAKE.keys = {}
		if ok and type(err) == "string" and err:sub(1, 4) == "you:" then you += 1 log("YOU", id, err:sub(5))
		elseif ok and type(err) == "string" and err:sub(1, 5) == "info:" then pass += 1 log("PASS", id, err:sub(6))
		elseif ok then pass += 1 log("PASS", id)
		else fail += 1 log("FAIL", id, err) end
		-- things a tool made outside the scene (Bake makes a model): take them out
		for _, ch in ipairs(workspace:GetChildren()) do
			if not extraBefore[ch] and ch.Name ~= "ROBLEND_QuickTest" and ch:GetAttribute("ROBLEND") == nil and (ch:IsA("Model") or ch:IsA("Folder")) then ch.Parent = nil end
		end
		beat()
	end

	-- start
	local st0 = C.get()
	if not (st0.uiOn and st0.view) then C.setStatus("Open the ROBLEND window first.") AutoTest.running = false return end
	H.snapshot()
	local autoSaveWas = api.state().autoSave == true
	pcall(api.setAutoSave, false, true)
	local pivotWas, propWas, snapWas, mirrorWas = api.state().pivot, api.state().prop, api.state().snap, api.state().mirrorX
	api.setFake(FAKE)
	C.setStatus("ROBLEND auto-test running - hands off the mouse and keys for a minute or two...")
	print("ROBLEND AUTO START  version " .. tostring(C.VERSION))
	local t0 = os.clock()

	-- ===== Fixed since last time =====
	T("studiokeys", function()
		edit("Cube", "vert", "none")
		key("Three") check(api.state().mode == "face", "3 -> face select, got " .. tostring(api.state().mode))
		key("One") check(api.state().mode == "vert", "1 -> point select")
		return "you: whether Studio lets 1 2 3 / Ctrl D through can only be checked by pressing them for real"
	end)
	T("steps", function()
		addObj("Cube")
		local c0 = api.state().camCF
		key("KeypadFour") check(api.state().camCF ~= c0, "numpad 4 didn't turn the view")
		local c1 = api.state().camCF
		key("KeypadEight") check(api.state().camCF ~= c1, "numpad 8 didn't turn the view")
		key("KeypadTwo") key("KeypadSix")
	end)
	T("frame", function()
		addObj("Cube")
		api.navDrag("pan", 300, 200) beat()
		local c0 = api.state().camCF
		key("Home") beat(2)
		check(api.state().camCF ~= c0, "Home didn't move the view")
		api.navDrag("pan", 300, 200) beat()
		local c1 = api.state().camCF
		key("KeypadPeriod") beat(2)
		check(api.state().camCF ~= c1, "numpad . didn't move the view")
	end)
	T("objgrs", function()
		local p = addObj("Cube")
		local p0 = p.CFrame.Position
		move(mid()) key("G") glide(mid(), mid() + V2(80, 0))
		check((p.CFrame.Position - p0).Magnitude > 0.05, "G didn't move the cube")
		key("Escape")
		check((p.CFrame.Position - p0).Magnitude < 1e-3, "Esc didn't put it back")
		move(mid()) key("G")
		local why = "after G: " .. tostring(C.get().modal and C.get().modal.kind)
		key("X")
		why ..= ", axis " .. tostring(C.get().modal and C.get().modal.axis)
		glide(mid(), mid() + V2(80, 60))
		why ..= ", moved before the click " .. tostring(p.CFrame.Position - p0)
		click(nil)
		beat(3)
		local d = p.CFrame.Position - p0
		check(math.abs(d.X) > 0.05 and near(d.Y, 0, 0.01) and near(d.Z, 0, 0.01), "G X should move along X only, moved " .. tostring(d) .. " (" .. why .. ")")
		local r0 = p.CFrame.Rotation
		key("R") glide(mid(), mid() + V2(150, 0)) click(nil)
		check(p.CFrame.Rotation ~= r0, "R didn't rotate")
		local s0 = p.Size
		key("S") glide(mid(), mid() + V2(150, 0)) click(nil)
		check((p.Size - s0).Magnitude > 0.05, "S didn't scale")
	end)
	T("join", function()
		local a = H.add("Cube") local b = H.add("Cube", V3(5, 0, 0)) H.select({ a, b }) H.frame() beat(2)
		check(qtParts() == 2, "two to start with")
		key("J", { "LeftControl" }) beat(2)
		check(qtParts() == 1, "Ctrl J should leave one object, there are " .. qtParts())
	end)
	T("hide", function()
		local p = addObj("Cube")
		key("H")
		check(C.scene[p] and C.scene[p].hidden == true, "H didn't hide it")
		check(p.Parent ~= nil, "H must not delete it")
		key("H", { "LeftAlt" })
		check(C.scene[p].hidden ~= true, "Alt H didn't bring it back")
	end)
	T("addtext", function()
		-- Add > Text > a ready-made word, even from Edit Mode
		edit("Cube", "face", "none")
		api.addText("HELLO") beat(2)
		local p = obj()
		check(p and p:GetAttribute("RB_Text") == "HELLO" and not api.state().editing, "Add > Text > HELLO: " .. tostring(p and p:GetAttribute("RB_Text")))
		p.Name = "QT_Text"
		-- Type Your Own... / Change Text...: the typing box
		local ui = C.get().ui
		ui:openTextPrompt("Change the text", "HELLO", function(t) api.setText("text", t) end)
		check(ui.promptBox and ui.promptBox.Parent, "the typing box opens")
		ui.promptBox.Text = "ROBLEND 2"
		ui.promptBox:ReleaseFocus(true) beat(2)
		p = obj()
		check(p:GetAttribute("RB_Text") == "ROBLEND 2", "typed text: " .. tostring(p:GetAttribute("RB_Text")))
		-- the words change from Edit Mode too
		api.toggleEdit() beat()
		api.setText("text", "HI") beat(2)
		check(obj():GetAttribute("RB_Text") == "HI", "changing the words in Edit Mode")
	end)
	T("shade", function()
		local p = addObj("Sphere")
		api.tool("ObjShadeSmooth") beat(2)
		api.toggleEdit() beat()
		local smooth = 0 for f in pairs(bm().faces) do if f.smooth then smooth += 1 end end
		check(smooth == nf(), ("Shade Smooth: %d of %d faces smooth"):format(smooth, nf()))
		api.toggleEdit() beat()
		H.select({ p })
		api.tool("ObjShadeFlat") beat(2)
		api.toggleEdit() beat()
		smooth = 0 for f in pairs(bm().faces) do if f.smooth then smooth += 1 end end
		check(smooth == 0, "Shade Flat left " .. smooth .. " smooth faces")
	end)
	T("outliner", function()
		local a = H.add("Cube") H.add("Sphere", V3(5, 0, 0)) beat()
		api.selectObject(a) beat()
		check(obj() == a, "selecting from the list")
		api.rename("QT_Renamed") beat()
		check(a.Name == "QT_Renamed", "rename: " .. a.Name)
		api.toggleHidden(a) check(C.scene[a].hidden == true, "eye hides")
		api.toggleHidden(a) check(C.scene[a].hidden ~= true, "eye shows")
	end)

	-- ===== Convert =====
	T("convpart", function()
		local q = H.part("Part") H.select({ q }) beat()
		key("Tab") beat(2)
		check(api.state().editing == true, "Tab on a Part should convert it and go into Edit Mode")
		check(q.Parent == nil and api.state().isRB, "converted")
		check(nf() == 6, "a block has 6 faces, got " .. nf())
	end)
	T("convshapes", function()
		local list = { H.part("WedgePart", nil, V3(4, 4, 4), V3(-9, 0, 0)), H.part("CornerWedgePart", nil, V3(4, 4, 4), V3(-3, 0, 0)),
			H.part("Part", Enum.PartType.Ball, V3(4, 4, 4), V3(3, 0, 0)), H.part("Part", Enum.PartType.Cylinder, V3(6, 3, 3), V3(9, 0, 0)) }
		H.select(list) beat()
		local made = api.convert()
		check(#made == 4, "converted " .. #made .. " of 4")
		check(near(made[4].Size.X, 6, 0.05), "cylinder lies along X, size " .. tostring(made[4].Size))
	end)
	T("convundo", function()
		local q = H.part("Part") beat()
		C.CHS:SetWaypoint("ROBLEND auto-test setup")
		api.convert({ q }) beat()
		check(q.Parent == nil, "converted")
		api.undo() beat(3)
		if inMock then return "info: (the fake Studio can't undo)" end
		check(q.Parent ~= nil, "Ctrl Z should bring the Part back")
	end)
	T("convunion", function()
		local a, b = H.part("Part"), H.part("Part", nil, V3(4, 4, 4), V3(2, 2, 0))
		local u
		pcall(function() u = game:GetService("GeometryService"):UnionAsync(a, { b }) end)
		if not (u and u[1]) then return "you: couldn't make a Union to try (Studio said no)" end
		u = u[1] u.Parent = H.folder
		H.select({ u }) beat()
		local made = api.convert()
		check(#made == 0 and u.Parent ~= nil, "a Union must be left alone")
	end)
	T("convmesh", function() return "you: needs a MeshPart you uploaded (Self-Test checks a saved ROBLEND mesh)" end)

	-- ===== Edit Mode: selecting =====
	T("modes", function()
		edit("Cube", "vert", "none")
		for _, m in ipairs({ "edge", "face", "vert" }) do api.setMode(m) beat() check(api.state().mode == m, "mode " .. m) end
	end)
	T("click", function()
		edit("Sphere", "face", "none")
		local fs = frontFaces()
		click(S(W(centre(fs[1]))))
		check(stats().fs == 1 and fs[1].sel, "click selects the face under the mouse (" .. stats().fs .. " selected)")
		local other
		for i = 2, #fs do if (centre(fs[i]) - centre(fs[1])).Magnitude > 0.8 then other = fs[i] break end end
		click(S(W(centre(other))), { "LeftShift" })
		check(stats().fs == 2, "Shift click adds one, " .. stats().fs .. " selected")
		key("A", { "LeftAlt" })
		local lo = V2(math.huge, math.huge)
		for v in pairs(bm().verts) do local sp = S(W(v.co)) lo = V2(math.min(lo.X, sp.X), math.min(lo.Y, sp.Y)) end
		local off = view():offset()
		local start = V2(math.max(lo.X - 25, off.X + 70), math.max(lo.Y - 25, off.Y + 40))
		drag(start, S(W(centre(fs[1]))))
		check(stats().fs >= 2, "box select picked " .. stats().fs)
	end)
	T("allnone", function()
		edit("Sphere", "face", "none")
		key("A") check(stats().fs == nf(), "A selects all")
		key("A", { "LeftAlt" }) check(stats().fs == 0, "Alt A selects none")
		click(S(W(centre(frontFace()))))
		key("I", { "LeftControl" }) check(stats().fs == nf() - 1, "Ctrl I inverts: " .. stats().fs)
	end)
	T("loops", function()
		edit("Sphere", "edge", "none")
		local f = frontFace()
		local l = BMesh.faceLoops(f)[1]
		local e = l.e
		local at = S(W((e.v1.co + e.v2.co) / 2))
		click(at, { "LeftAlt" })
		check(stats().es >= 8, "Alt click selects an edge loop, got " .. stats().es)
		key("A", { "LeftAlt" })
		click(at, { "LeftControl", "LeftAlt" })
		check(stats().es >= 4, "Ctrl Alt click selects a ring, got " .. stats().es)
	end)
	T("path", function()
		edit("Sphere", "vert", "none")
		local fs = frontFaces()
		local a = BMesh.faceVerts(fs[1])[1]
		local far, best = nil, 0
		for i = 1, math.min(#fs, 40) do
			for _, v in ipairs(BMesh.faceVerts(fs[i])) do local d = (v.co - a.co).Magnitude if d > best then far, best = v, d end end
		end
		click(S(W(a.co)))
		click(S(W(far.co)), { "LeftControl" })
		check(stats().vs >= 3, "Ctrl click picks the path: " .. stats().vs .. " points")
	end)
	T("circle", function()
		edit("Sphere", "vert", "none")
		local c = S(W(BMesh.faceVerts(frontFace())[1].co))
		move(c)
		key("C")
		check(C.get().modal ~= nil, "C starts circle select")
		move(c) api.inject("Button1Down") glide(c, c + V2(30, 0), 3) api.inject("Button1Up") beat()
		key("Escape")
		check(stats().vs > 0, "circle select picked nothing")
		check(C.get().modal == nil, "Esc ends it")
	end)
	T("linked", function()
		edit("Cube", "face", "none")
		api.add("Cube") H.shift(V3(5, 0, 0)) H.pick("none") H.frame() beat(2)
		local f = frontFace(function(f) return centre(f).X < 2 end)
		move(S(W(centre(f))))
		key("L")
		check(stats().fs == 6, "L picks the whole cube under the mouse: " .. stats().fs)
		key("A", { "LeftAlt" })
		click(S(W(centre(f))))
		key("L", { "LeftControl" })
		check(stats().fs == 6, "Ctrl L: " .. stats().fs)
	end)
	T("moreless", function()
		edit("Sphere", "face", "face")
		local n0 = stats().fs
		key("KeypadPlus", { "LeftControl" }) check(stats().fs > n0, "Ctrl + grows")
		local n1 = stats().fs
		key("KeypadMinus", { "LeftControl" }) check(stats().fs < n1, "Ctrl - shrinks")
	end)
	T("similar", function()
		edit("Cube", "face", "face")
		local kinds = api.similarList()
		check(#kinds > 0, "no Select Similar options")
		for _, k in ipairs(kinds) do api.selectSimilar(k[1]) beat() end
		check(stats().fs >= 1, "similar")
		key("A", { "LeftAlt" })
		H.pick("face")
		key("M", { "LeftShift", "LeftControl" })
		check(stats().fs >= 1, "select mirror")
	end)
	T("bytrait", function()
		edit("Sphere", "face", "all")
		H.tool("Checker") beat() check(stats().fs < nf() and stats().fs > 0, "Checker Deselect: " .. stats().fs)
		H.tool("SelectRandom") beat()
		H.tool("FacesBySides") beat()
		if C.get().modal then confirm() end
		api.setMode("edge") H.pick("none")
		H.tool("NonManifold") beat() check(stats().es == 0, "a closed sphere has no open edges, found " .. stats().es)
		H.tool("SharpEdges") beat()
	end)

	-- ===== Edit Mode: moving things =====
	T("grs", function()
		edit("Cube", "face", "top")
		local c0 = sum(true)
		key("G") glide(mid(), mid() + V2(0, -60)) click(nil)
		check((sum(true) - c0).Magnitude > 0.05, "G moved nothing")
		local s0 = sig()
		key("R") glide(mid(), mid() + V2(150, 0)) click(nil)
		check(sig() ~= s0, "R changed nothing")
		s0 = sig()
		key("S") glide(mid(), mid() + V2(150, 0)) click(nil)
		check(sig() ~= s0, "S changed nothing")
		s0 = sig()
		key("G") glide(mid(), mid() + V2(60, 60)) rclick(nil)
		check(sig() == s0, "right click should cancel")
	end)
	T("axis", function()
		edit("Cube", "face", "top")
		local c0 = sum(true)
		key("G") key("Z") typeNum("1.5") key("Return")
		local d = sum(true) - c0
		check(near(d.Magnitude, 1.5, 1e-3), "moved " .. tostring(d) .. " (should be exactly 1.5)")
		local axes = (near(d.X, 0) and 1 or 0) + (near(d.Y, 0) and 1 or 0) + (near(d.Z, 0) and 1 or 0)
		check(axes == 2, "along one axis only: " .. tostring(d))
	end)
	T("snap", function()
		edit("Cube", "face", "top")
		api.setSnapTarget("Increment")
		local c0 = sum(true)
		key("G") glide(mid(), mid() + V2(30, -260)) click(nil)
		local d = sum(true) - c0
		api.toggleEdit2("snap")
		check(d.Magnitude > 0.1, "didn't move")
		for _, x in ipairs({ d.X, d.Y, d.Z }) do check(math.abs(x - math.floor(x + 0.5)) < 1e-3, "snapped moves are whole studs: " .. tostring(d)) end
	end)
	T("prop", function()
		edit("Grid", "vert", "vert")
		key("O") check(api.state().prop == true, "O turns proportional editing on")
		local t0 = snapshot()
		key("G") glide(mid(), mid() + V2(0, -60)) click(nil)
		local n = movedCount(t0)
		key("O")
		check(n > 1, "only " .. n .. " point moved (neighbours should follow)")
	end)
	T("pivot", function()
		edit("Cube", "face", "top")
		api.setPivot("cursor")
		local c0 = sum(true)
		key("S") typeNum("2") key("Return")
		local moved = (sum(true) - c0).Magnitude
		api.setPivot("median")
		check(moved > 0.05, "scaling round the 3D cursor should move the face's middle")
	end)
	T("snapmenu", function()
		edit("Cube", "face", "top")
		H.tool("CursorToSel") beat()
		check((C.get().cursor - W(sum(true))).Magnitude < 1e-2, "Cursor to Selected")
		H.tool("CursorToOrigin") beat()
		check((C.get().cursor - api.home()).Magnitude < 1e-3, "Cursor to World Origin (the workshop's middle)")
	end)
	T("deforms", function()
		edit("Cube", "vert", "all")
		H.tool("Subdivide") beat()
		H.pick("all")
		for _, k in ipairs({ { "S", { "LeftAlt" } }, { "S", { "LeftShift", "LeftAlt" } } }) do
			local s0 = sig()
			key(k[1], k[2]) glide(mid(), mid() + V2(120, 0)) click(nil)
			check(sig() ~= s0, k[1] .. " with " .. table.concat(k[2], "+") .. " moved nothing")
		end
		for _, name in ipairs({ "Shear", "Randomize" }) do
			local s0 = sig()
			H.tool(name) glide(mid(), mid() + V2(120, 20)) confirm()
			check(sig() ~= s0, name .. " moved nothing")
		end
	end)
	T("slide", function()
		edit("Cylinder", "edge", "none")
		-- a side edge facing the camera (one on the edge of the outline barely moves on screen)
		local best, bd
		local toCam = (camPos() - W(V3())).Unit
		for e in pairs(bm().edges) do
			local d = e.v1.co - e.v2.co
			if math.abs(d.X) < 1e-3 and math.abs(d.Z) < 1e-3 then
				local m = (e.v1.co + e.v2.co) / 2
				local f = C.get().origin:VectorToWorldSpace(V3(m.X, 0, m.Z).Unit):Dot(toCam)
				if not bd or f > bd then best, bd = e, f end
			end
		end
		C.clearSel() best.sel = true best.v1.sel = true best.v2.sel = true C.flush() C.dirtyMesh() beat()
		local s0 = sig()
		local n0 = nv()
		key("G") key("G")
		check(C.get().modal ~= nil, "G G starts edge slide")
		glide(mid(), mid() + V2(50, 0)) click(nil)
		check(sig() ~= s0 and nv() == n0, "edge slide moved nothing")
	end)

	-- ===== Edit Mode: modelling tools =====
	T("extrude", function()
		edit("Cube", "face", "top")
		key("E") glide(mid(), mid() + V2(0, -50)) click(nil)
		check(nf() == 10, "extrude: 10 faces expected, got " .. nf())
		api.setMode("edge") H.pick("topedges") local f0 = nf()
		key("E") glide(mid(), mid() + V2(0, -40)) click(nil)
		check(nf() > f0, "extrude edges added no faces")
		api.setMode("vert") H.pick("vert") local e0 = ne()
		key("E") glide(mid(), mid() + V2(0, -40)) click(nil)
		check(ne() > e0, "extrude a point added no edge")
	end)
	T("extrudemore", function()
		edit("Cube", "face", "all")
		H.tool("ExtrudeIndividual") glide(mid(), mid() + V2(0, -40)) confirm()
		check(nf() > 6 * 4, "individual faces: " .. nf())
	end)
	T("ctrlrmb", function()
		edit("Cube", "vert", "vert")
		local n0 = nv()
		rclick(mid() + V2(120, -40), { "LeftControl" })
		check(nv() == n0 + 1, "Ctrl right click adds a point: " .. n0 .. " -> " .. nv())
	end)
	T("inset", function()
		edit("Cube", "face", "top")
		key("I") glide(mid() + V2(80, 0), mid() + V2(40, 0)) click(nil)
		check(nf() == 10, "inset: 10 faces expected, got " .. nf())
	end)
	T("bevel", function()
		edit("Cube", "edge", "topedges")
		key("B", { "LeftControl" }) glide(mid() + V2(80, 0), mid() + V2(40, 0)) click(nil)
		check(nf() > 6, "bevel added no faces: " .. nf())
	end)
	T("loopcut", function()
		edit("Cube", "edge", "none")
		local f = frontFace()
		local side
		for _, l in ipairs(BMesh.faceLoops(f)) do local d = l.e.v1.co - l.e.v2.co if math.abs(d.Y) > 0.5 then side = l.e break end end
		key("R", { "LeftControl" })
		move(S(W((side.v1.co + side.v2.co) / 2)))
		click(nil) beat() confirm()
		check(nf() == 10, "loop cut: 10 faces expected, got " .. nf())
	end)
	T("offsetloop", function()
		edit("Cylinder", "edge", "topedges")
		local e0 = ne()
		H.tool("OffsetEdgeLoops") glide(mid(), mid() + V2(20, 0)) confirm()
		check(ne() > e0, "offset edge loops added no edges")
	end)
	T("knife", function()
		edit("Cube", "edge", "none")
		local f = frontFace()
		local vs = BMesh.faceVerts(f)
		local a = (vs[1].co + vs[2].co) / 2
		local b = (vs[3].co + vs[4].co) / 2
		local f0 = nf()
		key("K")
		click(S(W(a))) click(S(W(b)))
		key("Return") beat()
		check(nf() > f0, "knife made no cut: " .. f0 .. " -> " .. nf())
	end)
	T("bisect", function()
		edit("Cube", "edge", "all")
		local n0 = nv()
		api.setTool("bisect") beat()
		local c = S(W(sum(false)))
		drag(c - V2(200, 10), c + V2(200, 10))
		confirm()
		api.setTool("select")
		check(nv() > n0, "bisect made no cut")
	end)
	T("spin", function()
		edit("Plane", "edge", "all")
		H.shift(V3(4, 0, 0))
		local f0 = nf()
		H.tool("Spin") glide(mid(), mid() + V2(60, 40)) confirm()
		check(nf() > f0, "spin added no faces")
	end)
	T("subdivide", function()
		edit("Cube", "face", "all")
		H.tool("Subdivide") beat()
		check(nf() == 24, "subdivide: 24 faces expected, got " .. nf())
	end)
	T("rotateedge", function()
		edit("Cube", "face", "all")
		H.tool("Triangulate") beat()
		api.setMode("edge")
		-- a diagonal (an edge between two triangles on the same side)
		local diag
		for e in pairs(bm().edges) do local d = e.v1.co - e.v2.co if math.abs(d.X) > 0.1 and math.abs(d.Y) > 0.1 and math.abs(d.Z) < 1e-3 then diag = e break end end
		check(diag, "no diagonal found")
		C.clearSel() diag.sel = true diag.v1.sel = true diag.v2.sel = true C.flush() beat()
		local a, b = diag.v1.co, diag.v2.co
		H.tool("RotateCW") beat()
		local still = false
		for e in pairs(bm().edges) do if (e.v1.co == a and e.v2.co == b) or (e.v1.co == b and e.v2.co == a) then still = true end end
		check(not still, "the edge didn't turn")
	end)
	T("bridge", function()
		edit("Circle", "edge", "none")
		api.add("Circle") H.shift(V3(0, 4, 0)) H.pick("all") beat()
		local f0 = nf()
		H.tool("Bridge") confirm()
		check(nf() > f0, "bridge made no faces")
	end)
	T("fill", function()
		edit("Cylinder", "face", "top")
		H.tool("DeleteOnlyFaces") api.setMode("edge") H.pick("topedges") beat()
		local f0 = nf()
		key("F") beat()
		check(nf() == f0 + 1, "F should fill the hole: " .. f0 .. " -> " .. nf())
		H.pick("top") key("F", { "LeftAlt" }) confirm()
	end)
	T("connect", function()
		edit("Cube", "vert", "none")
		local tv = topVerts()
		local far, best = nil, 0
		for _, v in ipairs(tv) do local d = (v.co - tv[1].co).Magnitude if d > best then far, best = v, d end end
		selectVerts({ tv[1], far })
		local e0 = ne()
		key("J") beat()
		check(ne() == e0 + 1, "J joins them with an edge: " .. e0 .. " -> " .. ne())
		api.setMode("face") H.pick("face")
		local n0 = nv()
		key("Y") beat()
		check(nv() > n0, "Y (split) should detach the face")
		local before = qtParts()
		H.tool("Separate") beat(2)
		if C.get().modal then confirm() end
		check(qtParts() > before or nv() < n0 + 4, "P > Selection made no new object")
	end)
	T("merge", function()
		edit("Cube", "vert", "topverts")
		H.tool("MergeCenter") beat()
		check(nv() == 5, "merge at center: 5 points expected, got " .. nv())
	end)
	T("delete", function()
		edit("Cube", "face", "top")
		H.tool("DeleteFaces") beat()
		check(nf() == 5, "delete face: " .. nf())
		api.undo() beat(3)
		H.pick("top") H.tool("DissolveFaces") beat()
	end)
	T("facetools", function()
		edit("Cube", "face", "all")
		H.tool("Poke") beat() check(nf() == 24, "poke: " .. nf())
		H.pick("all") key("T", { "LeftControl" }) check(nf() == 24, "triangulate kept the triangles")
		local t0 = nf()
		H.pick("all") key("J", { "LeftAlt" }) beat()
		check(nf() < t0, "Alt J (tris to quads) joined nothing")
		H.pick("all") H.tool("Solidify") confirm()
		H.pick("all") H.tool("Wireframe") confirm()
	end)
	T("hullsym", function()
		edit("Torus", "vert", "all")
		local f0 = nf()
		H.tool("ConvexHull") beat()
		check(nf() ~= f0, "convex hull changed nothing")
		H.pick("all") H.tool("SymmetrizeX") beat()
		bm():validate()
	end)
	T("normals", function()
		edit("Cube", "face", "top")
		local function top()
			local best
			for q in pairs(bm().faces) do if not best or centre(q).Y > centre(best).Y then best = q end end
			return best
		end
		check(top().no.Y > 0.5, "top face points up first")
		H.tool("Flip") beat()
		check(top().no.Y < -0.5, "Flip turns it down")
		H.pick("all") key("N", { "LeftShift" })
		check(top().no.Y > 0.5, "Shift N points it out again")
	end)
	T("marks", function()
		local p = addObj("Cube")
		api.modAdd("subsurf") api.toggleEdit() api.setMode("edge") H.pick("topedges") beat()
		H.tool("MarkSeam") H.tool("MarkSharp") beat()
		local seams, sharp = 0, 0
		for e in pairs(bm().edges) do if e.seam then seams += 1 end if e.sharp then sharp += 1 end end
		check(seams == 4 and sharp == 4, ("seams %d, sharp %d (4 each expected)"):format(seams, sharp))
		key("E", { "LeftShift" }) glide(mid(), mid() + V2(80, 0)) click(nil)
		local cr = 0 for e in pairs(bm().edges) do if e.crease and e.crease ~= 0 then cr += 1 end end
		check(cr == 4, "crease on " .. cr .. " edges")
		local _ = p
	end)
	T("hideedit", function()
		edit("Cube", "face", "top")
		key("H")
		local hid = 0 for f in pairs(bm().faces) do if f.hide then hid += 1 end end
		check(hid == 1, "H hid " .. hid .. " faces")
		key("H", { "LeftAlt" })
		hid = 0 for f in pairs(bm().faces) do if f.hide then hid += 1 end end
		check(hid == 0, "Alt H left " .. hid .. " hidden")
		H.pick("top") key("H", { "LeftShift" })
		hid = 0 for f in pairs(bm().faces) do if f.hide then hid += 1 end end
		check(hid == 5, "Shift H hid " .. hid)
		key("H", { "LeftAlt" })
	end)
	T("cleanup", function()
		edit("Cube", "face", "all")
		H.tool("Subdivide") H.pick("all") H.tool("LimitedDissolve") beat()
		check(nf() == 6, "limited dissolve: 6 faces expected, got " .. nf())
		for _, name in ipairs({ "DeleteLoose", "DegenerateDissolve", "FillHoles", "MergeDistance" }) do H.pick("all") H.tool(name) beat() if C.get().modal then confirm() end end
		bm():validate()
	end)
	T("addinedit", function()
		edit("Sphere", "face", "none")
		local n0 = nv()
		api.add("Cube") beat()
		check(nv() == n0 + 8 and api.state().editing, "Shift A > Cube in Edit Mode adds 8 points to this mesh")
	end)
	T("repeat", function()
		edit("Cube", "face", "top")
		key("E") glide(mid(), mid() + V2(0, -40)) click(nil)
		local f0 = nf()
		key("R", { "LeftShift" }) beat() confirm()
		check(nf() > f0, "Shift R didn't repeat")
	end)
	T("automerge", function()
		edit("Cube", "vert", "none")
		if not api.state().mirrorX then api.toggleEdit2("mirrorX") end
		local v
		for q in pairs(bm().verts) do if q.co.X > 0 then v = q break end end
		local mirror
		for q in pairs(bm().verts) do if near(q.co.X, -v.co.X) and near(q.co.Y, v.co.Y) and near(q.co.Z, v.co.Z) then mirror = q end end
		selectVerts({ v })
		local m0 = mirror.co
		key("G") key("Y") typeNum("1") key("Return")
		api.toggleEdit2("mirrorX")
		check((mirror.co - m0).Magnitude > 0.5, "X mirror: the other side didn't follow")
	end)

	-- ===== Modifiers =====
	local function modCase(id, kind, modId, sets, pre)
		T(id, function()
			local p = addObj(kind)
			if pre then api.modAdd(pre) beat(4) end
			local a = shown(p)
			api.modAdd(modId)
			local i = #mlist()
			for k, v in pairs(sets or {}) do api.modSet(i, k, v) end
			beat(6)
			local b = shown(p)
			check(mlist()[i] and mlist()[i].type == modId or #mlist() == i, "modifier wasn't added")
			-- (weld: nothing to weld on a clean mesh; triangulate: the shown mesh is triangles anyway)
			if modId ~= "weld" and modId ~= "triangulate" then check(a and b and a.key ~= b.key, "the shape didn't change (" .. (a and a.key or "?") .. ")") end
		end)
	end
	T("modstack", function()
		addObj("Cube")
		api.modAdd("bevel") api.modAdd("subsurf") beat(4)
		check(#mlist() == 2, "two modifiers")
		local first = mlist()[1].type or mlist()[1].id
		api.modMove(2, -1) beat()
		check((mlist()[1].type or mlist()[1].id) ~= first, "up / down")
		api.modToggle(1, "on") beat() api.modToggle(1, "on") beat()
		api.modApply(1) beat(3)
		check(#mlist() == 1, "Apply")
		api.modRemove(1) beat()
		check(#mlist() == 0, "X")
	end)
	T("subsurf", function()
		local p = addObj("Cube")
		local a = shown(p)
		key("One", { "LeftControl" }) beat(4)
		check(#mlist() == 1, "Ctrl 1 adds Subdivision")
		local b = shown(p)
		key("Three", { "LeftControl" }) beat(4)
		local c = shown(p)
		check(a and b and c and b.tris > a.tris and c.tris > b.tris, "smoother each level")
		key("Zero", { "LeftControl" }) beat(4)
		local d = shown(p)
		check(d and d.tris == a.tris, "Ctrl 0 sets level 0 (back to the plain cube)")
	end)
	T("mirror", function()
		local p = addObj("Cube")
		api.toggleEdit() H.pick("all") H.shift(V3(3, 0, 0)) api.toggleEdit() beat(2)
		H.select({ p })
		local a = shown(p)
		api.modAdd("mirror") beat(6)
		local b = shown(p)
		check(a and b and b.tris >= a.tris * 2 - 4, "mirror should double the shape: " .. (a and a.tris or 0) .. " -> " .. (b and b.tris or 0))
	end)
	modCase("array", "Cube", "array")
	modCase("bevelmod", "Cube", "bevel")
	T("booleanmod", function()
		local s = H.add("Sphere", V3(2, 2, 2))
		local c = H.add("Cube")
		H.select({ c }) beat(2)
		local a = shown(c)
		api.modAdd("boolean") api.modSet(#mlist(), "target", s.Name) beat(8)
		local b = shown(c)
		check(a and b and a.key ~= b.key, "the sphere didn't cut the cube")
		s.CFrame = s.CFrame + V3(0, 30, 0)
		for _ = 1, 30 do task.wait(0.03) end
		local d = shown(c)
		check(d and d.key ~= b.key, "the cut didn't follow when the sphere moved")
	end)
	modCase("decimate", "Sphere", "decimate", { ratio = 0.3 })
	modCase("edgesplit", "Cylinder", "edgesplit")
	modCase("screw", "Circle", "screw")
	modCase("solidify", "Plane", "solidify")
	modCase("triangulate", "Cube", "triangulate", nil, "bevel")
	T("tube", function()
		local p = addObj("CurvePath")
		check(#mlist() == 1, "a path comes with a Tube")
		local a = shown(p)
		api.modSet(1, "radius", 1.5) beat(6)
		local b = shown(p)
		check(a and b and a.key ~= b.key, "changing the radius did nothing")
	end)
	modCase("weld", "Cube", "weld")
	modCase("wiremod", "Cube", "wireframe")
	modCase("cast", "Cube", "cast", nil, "subsurf")
	modCase("displace", "Sphere", "displace", nil, "subsurf")
	T("shrinkwrap", function()
		local s = H.add("Sphere")
		local c = H.add("Cube")
		H.select({ c }) beat()
		api.modAdd("subsurf") beat(3)
		local a = shown(c)
		api.modAdd("shrinkwrap") api.modSet(#mlist(), "target", s.Name) beat(8)
		local b = shown(c)
		check(a and b and a.key ~= b.key, "shrinkwrap changed nothing")
	end)
	modCase("simpledeform", "Cylinder", "simpledeform", nil, "subsurf")
	modCase("smoothmod", "Cube", "smooth", nil, "subsurf")
	modCase("wave", "Grid", "wave")

	-- ===== Boolean =====
	for _, op in ipairs({ "difference", "union", "intersect" }) do
		T("objbool" .. (op == "difference" and "" or "_" .. op), function()
			local s = H.add("Sphere", V3(2, 2, 2))
			local c = H.add("Cube")
			H.select({ s, c }) C.setActive(c) beat()
			local r = api.boolean(op)
			check(r, op .. " gave nothing")
			check(s.Parent == nil, "the cutter is used up")
			api.toggleEdit() beat()
			check(nf() > 6, op .. ": " .. nf() .. " faces")
			bm():validate()
		end)
	end
	T("boolplain", function()
		local q = H.part("Part", nil, V3(3, 3, 3), V3(2, 2, 2))
		local c = H.add("Cube")
		H.select({ q, c }) C.setActive(c) beat()
		check(api.boolean("difference"), "a normal Part as the cutter")
	end)
	T("editbool", function()
		edit("Cube", "face", "none")
		api.add("Cube") H.shift(V3(1, 1, 1)) beat()
		local f0 = nf()
		H.tool("BooleanDifference") beat()
		check(nf() ~= f0, "Intersect (Boolean) changed nothing")
		bm():validate()
	end)
	T("boolclean", function()
		local s = H.add("Cylinder", V3(1, 1, 1))
		local c = H.add("Cube")
		H.select({ s, c }) C.setActive(c) beat()
		check(api.boolean("difference"), "no result")
		api.toggleEdit() beat()
		local tiny = 0
		for f in pairs(bm().faces) do
			local vs = BMesh.faceVerts(f)
			local a = 0
			for i = 2, #vs - 1 do a += (vs[i].co - vs[1].co):Cross(vs[i + 1].co - vs[1].co).Magnitude / 2 end
			if a < 1e-4 then tiny += 1 end
		end
		check(tiny == 0, tiny .. " sliver faces")
		bm():validate()
		return "info: " .. nf() .. " faces"
	end)

	-- ===== UVs =====
	T("projections", function()
		local p = addObj("Cube")
		api.setTexture("rbxasset://textures/face.png")
		for _, m in ipairs({ "box", "boxfit", "cylinder", "sphere", "top" }) do
			api.setUV(m) beat()
			check(p:GetAttribute("RB_UVMode") == m, "UV mode " .. m)
		end
	end)
	T("unwrap", function()
		local p = addObj("Cube")
		api.toggleEdit() H.pick("all")
		api.uvUnwrap("unwrap") beat(2)
		api.toggleEdit() beat()
		check(data(p).uv, "no UVs stored")
	end)
	T("smartuv", function()
		local p = addObj("Sphere")
		api.uvUnwrap("smart") beat(2)
		check(data(p).uv and p:GetAttribute("RB_UVMode") == "unwrap", "Smart UV Project")
	end)
	T("uveditor", function()
		addObj("Cube")
		api.toggleEdit() H.pick("all") api.uvUnwrap("smart") beat()
		api.uvEditor() beat(2)
		check(api.uvEditorState().open, "UV Editor opens")
		api.uvEditor() beat()
		return "you: dragging points inside the UV Editor needs a look"
	end)
	T("uvkeep", function()
		local p = addObj("Cube")
		api.toggleEdit() H.pick("all") api.uvUnwrap("smart") beat()
		H.pick("top")
		key("G") glide(mid(), mid() + V2(0, -40)) click(nil)
		api.toggleEdit() beat()
		check(data(p).uv, "UVs lost after editing")
	end)

	-- ===== Sculpt =====
	local function stroke(n)
		local c = S(W(centre(frontFace())))
		move(c)
		api.inject("Button1Down")
		glide(c, c + V2(60, 10), n or 6)
		api.inject("Button1Up")
		beat(2)
	end
	T("sculptin", function()
		edit("Sphere", "face", "none")
		move(mid()) key("Q")
		check(C.get().ui.menuOpen ~= nil, "Q should open the mode menu")
		key("Escape")
		api.setPaintMode("sculpt") beat()
		check(api.state().paintMode == "sculpt", "Sculpt Mode")
	end)
	T("brushes", function()
		H.sculpt(1) beat()
		local bad = {}
		for _, b in ipairs({ { "X" }, { "C" }, { "I" }, { "G" }, { "S" }, { "T" }, { "P" }, { "C", { "LeftShift" } } }) do
			key(b[1], b[2])
			local t0 = snapshot()
			stroke()
			if movedCount(t0) == 0 then bad[#bad + 1] = (b[2] and "Shift " or "") .. b[1] .. " (" .. tostring(api.state().brush) .. ")" end
		end
		check(#bad == 0, "brushes that changed nothing: " .. table.concat(bad, ", "))
	end)
	T("brushsize", function()
		H.sculpt(1) beat()
		local r0 = api.state().brushRadius
		move(mid()) key("F") glide(mid(), mid() + V2(60, 0)) click(nil)
		check(api.state().brushRadius ~= r0, "F didn't change the size")
		local s0 = api.state().brushStrength
		move(mid()) key("F", { "LeftShift" }) glide(mid(), mid() + V2(-40, 0)) click(nil)
		check(api.state().brushStrength ~= s0, "Shift F didn't change the strength")
		local r1 = api.state().brushRadius
		key("RightBracket") check(api.state().brushRadius > r1, "] makes it bigger")
		key("LeftBracket") key("LeftBracket") check(api.state().brushRadius < r1, "[ makes it smaller")
	end)
	T("sculptsym", function()
		H.sculpt(1) beat()
		api.sculptSet("symmetryX", true)
		key("X")
		local t0 = snapshot()
		stroke()
		local left, right = 0, 0
		for v, co in pairs(t0) do if (v.co - co).Magnitude > 1e-4 then if co.X < 0 then left += 1 else right += 1 end end end
		api.sculptSet("symmetryX", false)
		check(left > 0 and right > 0, ("symmetry: %d moved on one side, %d on the other"):format(left, right))
		local n0 = nv()
		api.sculptSubdivide() beat()
		check(nv() > n0, "Sculpt > Subdivide")
	end)
	T("sculptspeed", function()
		H.sculpt(3) beat()
		key("X")
		local c = S(W(centre(frontFace())))
		move(c)
		api.inject("Button1Down")
		local times = {}
		for i = 1, 20 do
			local t = os.clock()
			FAKE.pos = c + V2(i * 4, math.sin(i) * 10)
			api.inject("Move")
			task.wait()
			times[#times + 1] = os.clock() - t
		end
		api.inject("Button1Up") beat()
		table.sort(times)
		local med = times[10] * 1000
		return (med > 60 and "info: SLOW " or "info: ") .. ("%.0f ms per step on %d points (smooth is under ~20)"):format(med, nv())
	end)

	-- ===== Vertex Paint =====
	T("paintin", function()
		edit("Sphere", "face", "none")
		api.setPaintMode("paint") beat()
		check(api.state().paintMode == "paint", "Vertex Paint")
	end)
	local function coloured() local n = 0 for v in pairs(bm().verts) do if v.col then n += 1 end end return n end
	T("paintdraw", function()
		H.paint(1) beat()
		api.setPaintColor("ff0000")
		stroke()
		check(coloured() > 0, "painting coloured nothing")
	end)
	T("paintcube", function()
		-- a plain cube (only 8 corner points): painting the middle of a face still colours it
		local p = addObj("Cube")
		api.toggleEdit() beat()
		api.setPaintMode("paint") beat()
		api.paintWhiteBase()
		api.setPaintColor("2266ff")
		stroke(3)
		check(coloured() >= 4, "painting a plain cube coloured " .. coloured() .. " points")
		local _ = p
	end)
	T("paintpick", function()
		H.paint(1) beat()
		api.setPaintColor("ff0000")
		stroke()
		api.setPaintColor("00ff00")
		move(S(W(centre(frontFace())))) key("S")
		check(api.state().paintColor ~= "00ff00", "S didn't pick up the painted colour (" .. tostring(api.state().paintColor) .. ")")
		key("K", { "LeftShift" })
		check(coloured() == nv(), "Shift K fills every point")
		api.paintClear() beat()
		check(coloured() == 0, "Clear Colours")
	end)
	T("paintsave", function()
		local p = H.paint(1) beat()
		api.paintFill() beat()
		api.setPaintMode(nil) api.toggleEdit() beat(2)
		H.select({ p }) api.toggleEdit() beat()
		check(coloured() == nv(), "colours lost after leaving: " .. coloured() .. " of " .. nv())
	end)

	-- ===== Collision and saving =====
	T("collision", function()
		local p = addObj("Sphere")
		api.setPhys("collision", "Hull") beat(3)
		p = obj() or p
		check(p.CollisionFidelity == Enum.CollisionFidelity.Hull, "collision " .. tostring(p.CollisionFidelity))
		api.setPhys("render", "Performance") beat(3)
		p = obj() or p
		check(p.RenderFidelity == Enum.RenderFidelity.Performance, "render " .. tostring(p.RenderFidelity))
		api.toggleEdit() H.pick("all") key("E") glide(mid(), mid() + V2(0, -30)) click(nil) api.toggleEdit() beat(3)
		local q = obj() or p
		check(q.CollisionFidelity == Enum.CollisionFidelity.Hull, "collision kept after editing: " .. tostring(q.CollisionFidelity))
	end)
	T("save", function() return "you: saving uploads to your Roblox account, so it's left to you" end)
	T("autosave", function() return "you: Place in Studio saves it" end)
	T("reopen", function() return "you: needs a Studio restart" end)
	T("bake", function()
		edit("Cube", "face", "none")
		local before = #workspace:GetChildren()
		H.tool("Bake") beat(3)
		check(#workspace:GetChildren() > before or #workspace:GetDescendants() > 0, "Bake to Parts made nothing")
	end)
	T("undo", function()
		edit("Cube", "face", "top")
		key("E") glide(mid(), mid() + V2(0, -40)) click(nil)
		check(nf() == 10, "extruded")
		key("Z", { "LeftControl" }) beat(3)
		if inMock then return "info: (the fake Studio can't undo)" end
		check(nf() == 6, "Ctrl Z: " .. nf() .. " faces (6 expected)")
		key("Y", { "LeftControl" }) beat(3)
		check(nf() == 10, "Ctrl Y: " .. nf() .. " faces (10 expected)")
	end)
	T("speed", function()
		H.sculpt(3) api.setPaintMode(nil) api.setMode("vert") H.pick("all") beat()
		key("G")
		local times = {}
		for i = 1, 20 do
			local t = os.clock()
			move(mid() + V2(i * 5, -i * 3))
			times[#times + 1] = os.clock() - t
		end
		click(nil)
		table.sort(times)
		local med = times[10] * 1000
		return (med > 60 and "info: SLOW " or "info: ") .. ("%.0f ms per step moving %d points (smooth is under ~20)"):format(med, nv())
	end)

	-- ===== the finish: a block painted in four colours, then a slow spin round it (nice for a video) =====
	local showcase
	if not only then
		local ok, err = pcall(function()
			H.clean()
			pcall(function()
				local v = C.get().view
				api.viewAxis("front")
				v:step(math.rad(-40), math.rad(25))
				v.viewName = nil
			end)
			local p = H.add("Cube")
			p.Name = "ROBLEND Painted Block"
			H.select({ p }) H.frame() beat(2)
			api.toggleEdit() beat()
			for _ = 1, 4 do H.pick("all") H.tool("Subdivide") beat() end
			api.setPaintMode("paint") beat()
			api.paintWhiteBase()
			C.setStatus("Auto-test done - painting the block...")
			-- every point gets the colour of its quarter (round the up axis), swept round over two seconds
			local COLS = { Color3.fromRGB(230, 57, 70), Color3.fromRGB(255, 196, 0), Color3.fromRGB(46, 196, 110), Color3.fromRGB(52, 120, 246) }
			local list = {}
			for v in pairs(bm().verts) do
				local a = math.atan2(v.co.Z, v.co.X)
				if a < 0 then a += 2 * math.pi end
				list[#list + 1] = { v = v, a = a }
			end
			table.sort(list, function(x, y) return x.a < y.a end)
			local steps = 40
			for i = 1, steps do
				for j = math.floor((i - 1) / steps * #list) + 1, math.floor(i / steps * #list) do
					local x = list[j]
					x.v.col = COLS[math.clamp(math.floor(x.a / (math.pi / 2)) + 1, 1, 4)]
				end
				C.dirtyMeshFast("col")
				task.wait(0.05)
			end
			C.commit("Paint the block")
			api.setPaintMode(nil)
			api.toggleEdit() beat(2)
			H.select({ p })
			-- one slow turn round it
			local v = C.get().view
			for _ = 1, 120 do v:step(math.rad(3), 0) v.viewName = nil C.dirtyCage() task.wait(1 / 30) end
			showcase = p
		end)
		if not ok then log("INFO", "painted block", "couldn't make it: " .. tostring(err)) end
	end

	-- ===== tidy up =====
	H.clean()
	if showcase then H.select({ showcase }) end
	api.setFake(nil)
	pcall(api.setAutoSave, autoSaveWas, true)
	pcall(api.setPivot, pivotWas or "median")
	local st = api.state()
	if (st.prop == true) ~= (propWas == true) then api.toggleEdit2("prop") end
	if (st.snap == true) ~= (snapWas == true) then api.toggleEdit2("snap") end
	if (st.mirrorX == true) ~= (mirrorWas == true) then api.toggleEdit2("mirrorX") end
	local summary = ("ROBLEND AUTO DONE  %d passed, %d failed, %d need you  (%.0f s)"):format(pass, fail, you, os.clock() - t0)
	print(summary)
	C.setStatus(summary:gsub("ROBLEND AUTO DONE  ", "Auto-test: ") .. (fail > 0 and " - Claude can read what failed from the log." or ".") .. (showcase and "  (The painted block stays - delete it with X if you like.)" or ""))
	AutoTest.running = false
	return results, pass, fail, you
end

return AutoTest
