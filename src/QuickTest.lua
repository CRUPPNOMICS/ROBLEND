--[[
	ROBLEND - Help > Quick Test: a card that walks through every feature. For each one it sets the scene up
	itself (adds the right shape, picks the mode, selects the faces), says what to press and what you should
	see, and has Works / Broken / Skip buttons. "Show me" does the action for you where it can.
	Results are printed to Output ("ROBLEND CHECK ..." lines) and remembered between sessions.
	Everything it adds is taken out again when it moves on or closes; parts that were there before it opened
	are never touched.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	QuickTest.new(C) -> Q ; QuickTest.ITEMS is plain data (tested headless).
]]
local QuickTest = {}
local V3 = Vector3.new

-- ===== scene helpers (H is passed to every setup / show function) =====
local function helpers(C)
	local H = {}
	local api = function() return C.api end
	H.keep = {}
	H.folder = nil

	function H.exitAll()
		local a = api()
		if C.get().modal then pcall(C.finishModal, true) end
		if a.state().paintMode then pcall(a.setPaintMode, nil) end
		if C.get().editing then pcall(a.toggleEdit) end
	end
	-- take out everything added since the Quick Test opened
	function H.clean()
		H.exitAll()
		-- only what the Quick Test made (named QT_...), so a part of yours converted during a test is kept
		for _, row in ipairs(api().outliner()) do
			local p = row.key
			if not H.keep[p] and p.Parent and p.Name:sub(1, 3) == "QT_" then p.Parent = nil end
		end
		if H.folder then for _, ch in ipairs(H.folder:GetChildren()) do ch.Parent = nil end end
		pcall(function() C.Selection:Set({}) end)
		C.setActive(nil)
		C.dirtyCage()
	end
	function H.snapshot()
		H.keep = {}
		for _, row in ipairs(api().outliner()) do H.keep[row.key] = true end
	end
	-- add a ROBLEND shape in Object Mode (offset moves it)
	function H.add(kind, offset)
		if C.get().editing then H.exitAll() end
		api().add(kind)
		local p = C.Selection:Get()[1]
		if p then
			H.n = (H.n or 0) + 1
			p.Name = ("QT_%s%d"):format(kind, H.n)
			if offset then p.CFrame = p.CFrame + offset end
		end
		return p
	end
	function H.select(parts)
		C.Selection:Set(parts)
		C.setActive(parts[#parts])
		C.dirtyCage()
	end
	function H.frame() pcall(api().frameSelected) end
	-- a normal Studio part (not ROBLEND), selected
	function H.part(class, shape, size, offset)
		if not (H.folder and H.folder.Parent) then
			H.folder = Instance.new("Folder")
			H.folder.Name = "ROBLEND_QuickTest"
			H.folder.Parent = workspace
		end
		local q = Instance.new(class)
		H.n = (H.n or 0) + 1
		q.Name = ("QT_%s%d"):format(shape and shape.Name or class, H.n)
		if shape then q.Shape = shape end
		q.Size = size or V3(4, 4, 4)
		q.Anchored = true
		q.Color = Color3.fromRGB(70, 130, 220)
		q.CFrame = CFrame.new((C.get().cursor or V3()) + V3(0, 2, 0) + (offset or V3()))
		q.Parent = H.folder
		return q
	end
	-- Edit Mode on a new shape: mode = "vert" | "edge" | "face", pick = see H.pick
	function H.edit(kind, mode, pick)
		local p = H.add(kind)
		H.select({ p })
		H.frame()
		api().toggleEdit()
		if mode then api().setMode(mode) end
		H.pick(pick or "none")
		return p
	end
	local function centre(f)
		local s, n = V3(), 0
		for _, v in ipairs(C.BMesh.faceVerts(f)) do s += v.co n += 1 end
		return s / math.max(n, 1)
	end
	-- select part of the mesh in Edit Mode: "all", "none", "top" (top faces), "face" (one face), "vert" (one top point),
	-- "topverts", "topedges" (the top ring), "edge" (one side edge)
	function H.pick(what)
		local st = C.get()
		local bm = st.bm
		if not (st.editing and bm) then return end
		C.clearSel()
		local top = -math.huge
		for v in pairs(bm.verts) do top = math.max(top, v.co.Y) end
		local function isTop(v) return v.co.Y > top - 1e-3 end
		if what == "all" then
			for v in pairs(bm.verts) do v.sel = true end
			for e in pairs(bm.edges) do e.sel = true end
			for f in pairs(bm.faces) do f.sel = true end
		elseif what == "top" or what == "face" then
			local best, bestY
			for f in pairs(bm.faces) do
				local c = centre(f)
				if what == "top" then
					local all = true
					for _, v in ipairs(C.BMesh.faceVerts(f)) do if not isTop(v) then all = false break end end
					if all then f.sel = true end
				elseif not bestY or c.X > bestY then best, bestY = f, c.X end
			end
			if best then best.sel = true end
			for f in pairs(bm.faces) do if f.sel then for _, v in ipairs(C.BMesh.faceVerts(f)) do v.sel = true end end end
			for e in pairs(bm.edges) do if e.v1.sel and e.v2.sel then e.sel = true end end
		elseif what == "vert" then
			for v in pairs(bm.verts) do if isTop(v) then v.sel = true break end end
		elseif what == "topverts" then
			for v in pairs(bm.verts) do if isTop(v) then v.sel = true end end
		elseif what == "topedges" then
			for e in pairs(bm.edges) do if isTop(e.v1) and isTop(e.v2) then e.sel = true e.v1.sel = true e.v2.sel = true end end
		elseif what == "edge" then
			for e in pairs(bm.edges) do
				local d = e.v1.co - e.v2.co
				if math.abs(d.X) < 1e-3 and math.abs(d.Z) < 1e-3 then e.sel = true e.v1.sel = true e.v2.sel = true break end
			end
		end
		C.flush()
		C.dirtyMesh()
	end
	-- move the selected points (Edit Mode) and keep it
	function H.shift(d)
		local bm = C.get().bm
		if not bm then return end
		for v in pairs(bm.verts) do if v.sel then v.co += d end end
		bm:normalsUpdate()
		C.commit("Quick Test")
		C.dirtyMesh()
	end
	-- a shape with a modifier on it (sets = { key = value })
	function H.mod(kind, id, sets)
		local p = H.add(kind)
		H.select({ p })
		H.frame()
		api().modAdd(id)
		local i = #api().mods()
		for k, v in pairs(sets or {}) do pcall(api().modSet, i, k, v) end
		return p, i
	end
	function H.sculpt(times)
		local p = H.add("Sphere")
		H.select({ p })
		H.frame()
		api().setPaintMode("sculpt")
		for _ = 1, times or 0 do api().sculptSubdivide() end
		return p
	end
	function H.paint(times)
		local p = H.add("Sphere")
		H.select({ p })
		H.frame()
		api().setPaintMode("paint")
		for _ = 1, times or 0 do
			-- subdivide from Sculpt Mode, then back to paint
			api().setPaintMode("sculpt") api().sculptSubdivide() api().setPaintMode("paint")
		end
		api().paintWhiteBase()
		return p
	end
	function H.tool(name) if api().hasTool(name) then api().tool(name) end end
	return H
end

-- ===== the tests =====
-- { id, group, title, act = what to press, see = what should happen, setup = fn(H, api), show = fn(H, api) or nil }
local I = {}
local function add(group, id, title, act, see, setup, show)
	I[#I + 1] = { id = id, group = group, title = title, act = act, see = see, setup = setup, show = show }
end

local G = "Fixed since last time"
add(G, "studiokeys", "Studio shortcuts blocked", "Mouse over the 3D view. Press 1, 2, 3 on the number row (above the letters), then Ctrl D.",
	"1 2 3 switch to points / edges / faces (the three little header buttons light up). Studio's move arrows never appear, and Ctrl D doesn't make a copy in Explorer.",
	function(H) H.edit("Cube", "vert", "none") end)
add(G, "steps", "Orbit in steps", "Press numpad 4, 6, 8 and 2 (Num Lock on).",
	"The view turns left, right, up and down in steps.", function(H) H.add("Cube") H.frame() end)
add(G, "frame", "Frame all / selected", "Press Home. Then press numpad . (the dot on the number pad).",
	"Home fits everything in view, numpad dot zooms to the cube. Studio's Explorer doesn't jump.", function(H) H.add("Cube") end)
add(G, "objgrs", "Move, then cancel", "Press G and move the mouse, then press Esc. Try G then X (or Y or Z) too.",
	"The cube follows the mouse; Esc puts it back. X / Y / Z lock it to that direction (a coloured line shows).",
	function(H) local p = H.add("Cube") H.select({ p }) H.frame() end)
add(G, "join", "Join", "Both cubes are selected. Press Ctrl J.",
	"They become one object (one name in the Outliner). Studio's Explorer doesn't open.",
	function(H) local a = H.add("Cube") local b = H.add("Cube", V3(5, 0, 0)) H.select({ a, b }) H.frame() end,
	function(H) H.tool("Join") end)
add(G, "hide", "Hide / reveal", "Press H, then Alt H.",
	"H hides the cube (it's not deleted: it's still in the Outliner). Alt H brings it back.",
	function(H) local p = H.add("Cube") H.select({ p }) H.frame() end)
add(G, "addtext", "Text", "Properties on the right: the green triangle tab (Data). Click the Text box, type a word, press Enter.",
	"The 3D text changes to your word. (The letters are blocky on purpose.)",
	function(H) local p = H.add("Text") H.select({ p }) H.frame() end)
add(G, "shade", "Shade smooth / flat", "Object menu (in the header) > Shade Smooth, then Shade Flat, then Shade Auto Smooth.",
	"Smooth: the sphere looks round. Flat: you see the little flat faces. Auto: round, but sharp corners stay sharp.",
	function(H) local p = H.add("Sphere") H.select({ p }) H.frame() end, function(H) H.tool("ObjShadeSmooth") end)
add(G, "outliner", "Outliner", "Click the names in the Outliner (top right). Double-click one to rename it. Click its eye icon.",
	"Clicking selects it in 3D, renaming works, the eye hides / shows it.",
	function(H) local a = H.add("Cube") local b = H.add("Sphere", V3(5, 0, 0)) H.select({ a, b }) H.frame() end)

G = "Edit any part (Convert)"
add(G, "convpart", "Convert a Part", "A normal blue Studio Part is selected (you can't see plain Parts in ROBLEND's view yet). Press Tab with the mouse over the 3D view.",
	"It appears as a ROBLEND mesh (still blue) and goes straight into Edit Mode.",
	function(H) local q = H.part("Part") H.select({ q }) end, function(_, api) api.toggleEdit() end)
add(G, "convshapes", "Wedge, corner wedge, ball, cylinder", "Four normal Studio parts are selected. Object menu > Convert to ROBLEND Mesh (or press Show me).",
	"Four blue shapes appear: a wedge, a corner wedge, a ball and a cylinder lying on its side. Each keeps its shape and size.",
	function(H)
		H.select({ H.part("WedgePart", nil, V3(4, 4, 4), V3(-9, 0, 0)), H.part("CornerWedgePart", nil, V3(4, 4, 4), V3(-3, 0, 0)),
			H.part("Part", Enum.PartType.Ball, V3(4, 4, 4), V3(3, 0, 0)), H.part("Part", Enum.PartType.Cylinder, V3(6, 3, 3), V3(9, 0, 0)) })
	end, function(H, api) api.convert() H.frame() end)
add(G, "convundo", "Undo a convert", "This one was just converted. Press Ctrl Z.",
	"It goes back to a normal Studio Part (it disappears from ROBLEND's view and the Outliner).",
	function(H, api) local q = H.part("Part") api.convert({ q }) H.frame() end)
add(G, "convunion", "Union refused", "A Union is selected (Show me if not). Object menu > Convert to ROBLEND Mesh.",
	"A message at the bottom says it can't read Unions. Nothing changes.",
	function(H)
		local a, b = H.part("Part", nil, V3(4, 4, 4)), H.part("Part", nil, V3(4, 4, 4), V3(2, 2, 0))
		local u
		pcall(function() u = game:GetService("GeometryService"):UnionAsync(a, { b }) end)
		if u and u[1] then u = u[1] u.Parent = H.folder a.Parent = nil b.Parent = nil H.select({ u }) else H.select({ a, b }) end
	end, function(_, api) api.convert() end)
add(G, "convmesh", "Convert a MeshPart", "Select a MeshPart whose mesh YOU uploaded (Explorer), then Object menu > Convert to ROBLEND Mesh. Skip if you don't have one.",
	"It opens as one editable shape. Someone else's mesh gives a clear message instead.", function(H) H.clean() end)

G = "Edit Mode: selecting"
add(G, "modes", "Point / edge / face", "Click the three little square buttons in the header (left of View).",
	"Dots / lines / face dots; the button you clicked lights up.", function(H) H.edit("Cube", "vert", "none") end)
add(G, "click", "Click, Shift-click, box", "Click a face, Shift + click another face, then drag a box from empty space over part of the sphere.",
	"Selected faces turn orange; the box selects the faces inside it (only the front ones).", function(H) H.edit("Sphere", "face", "none") end)
add(G, "allnone", "All / none / invert", "A, then Alt A, then select one face and press Ctrl I.",
	"Everything / nothing / everything except that face.", function(H) H.edit("Sphere", "face", "none") end)
add(G, "loops", "Loops and rings", "Alt + click an edge. Double-click a different edge. Ctrl Alt + click another edge.",
	"A whole ring of edges around the sphere / the same / a ring of edges side by side.", function(H) H.edit("Sphere", "edge", "none") end)
add(G, "path", "Shortest path", "One point is selected (top). Ctrl + click a point far away.",
	"Every point along the shortest path between them is selected.", function(H) H.edit("Sphere", "vert", "vert") end)
add(G, "circle", "Circle and lasso", "Press C and drag over points (mouse wheel = bigger / smaller), then Esc. Then hold Ctrl and right-drag a loop.",
	"C paints a selection; the lasso selects the points inside the loop.", function(H) H.edit("Sphere", "vert", "none") end)
add(G, "linked", "Linked", "Point at one of the two cubes (they're one mesh) and press L. Then select one face and press Ctrl L.",
	"The whole cube you pointed at is selected, not the other one.",
	function(H, api) H.edit("Cube", "face", "none") api.add("Cube") H.shift(V3(5, 0, 0)) H.pick("none") H.frame() end)
add(G, "moreless", "More / less", "One face is selected. Ctrl + numpad plus a few times, then Ctrl + numpad minus.",
	"The selection grows by a ring each time, then shrinks back.", function(H) H.edit("Sphere", "face", "face") end, function(H) H.tool("SelectMore") end)
add(G, "similar", "Similar and mirror", "One face is selected. Shift G > pick an option. Then Shift Ctrl M.",
	"Faces like it get selected / the face on the other side is selected.", function(H) H.edit("Sphere", "face", "face") end)
add(G, "bytrait", "Select menu extras", "Select menu > Select Random, Checker Deselect (with all selected), Select All by Trait > Faces by Sides, Select Sharp Edges.",
	"Each one selects what its name says.", function(H) H.edit("Sphere", "face", "all") end, function(H) H.tool("Checker") end)

G = "Edit Mode: moving things"
add(G, "grs", "G / R / S", "The top face is selected. Press G and move the mouse, click. Then R, then S. Try right-click to cancel one.",
	"The face follows the mouse smoothly; cancel puts it back.", function(H) H.edit("Cube", "face", "top") end)
add(G, "axis", "Axis lock and typed values", "Press G, then Z, type 1.5, press Enter.",
	"The top face moves up exactly 1.5 (the cube gets taller).", function(H) H.edit("Cube", "face", "top") end)
add(G, "snap", "Snapping", "Turn on the magnet in the header (or Shift Tab). Press G and move: it jumps in whole studs. The arrow next to the magnet: try Vertex.",
	"Increment: moves in whole steps. Vertex: snaps onto other points.", function(H) H.edit("Cube", "face", "top") end)
add(G, "prop", "Proportional editing", "One point is selected. Press O (circle icon lights up), then G and roll the mouse wheel while moving.",
	"Nearby points follow in a smooth hill; the wheel changes the circle size.", function(H) H.edit("Grid", "vert", "vert") end)
add(G, "pivot", "Pivot point", "Press . (full stop) > 3D Cursor. Then S and move the mouse.",
	"The faces scale toward the 3D cursor (the red and white circle), not their own middle.", function(H) H.edit("Cube", "face", "top") end)
add(G, "snapmenu", "Snap menu", "Shift S > Cursor to Selected. Then Shift S > Cursor to World Origin.",
	"The 3D cursor jumps onto the top face / back to the middle of the world.", function(H) H.edit("Cube", "face", "top") end,
	function(H) H.tool("CursorToSel") end)
add(G, "deforms", "Shrink/Fatten, To Sphere, Shear, Randomize", "Everything is selected. Alt S (fatten), Shift Alt S (to sphere), Mesh > Transform > Shear / Randomize. Move the mouse each time.",
	"Each one changes the shape as named, following the mouse.", function(H) H.edit("Cube", "vert", "all") H.tool("Subdivide") end)
add(G, "slide", "Edge slide / vertex slide", "One side edge is selected. Press G twice, move the mouse. Then select a point and press Shift V.",
	"The edge slides along the faces next to it without leaving the surface.", function(H) H.edit("Cylinder", "edge", "edge") end)

G = "Edit Mode: modelling tools"
add(G, "extrude", "Extrude", "The top face is selected. Press E and move the mouse, click.",
	"A new block pulls out of the top.", function(H) H.edit("Cube", "face", "top") end)
add(G, "extrudemore", "Extrude variants", "All faces selected. Alt E > Individual Faces, move the mouse.",
	"Every face pushes out on its own.", function(H) H.edit("Cube", "face", "all") end)
add(G, "ctrlrmb", "Extrude to mouse", "One point is selected. Ctrl + right-click in empty space a few times.",
	"Each click adds a new point joined by an edge, where you clicked.", function(H) H.edit("Cube", "vert", "vert") end)
add(G, "inset", "Inset", "The top face is selected. Press I and move the mouse, click.",
	"A smaller face inside the top face.", function(H) H.edit("Cube", "face", "top") end)
add(G, "bevel", "Bevel", "The top edges are selected. Ctrl B and move the mouse; roll the wheel for more segments; click.",
	"The top edges get rounded.", function(H) H.edit("Cube", "edge", "topedges") end)
add(G, "loopcut", "Loop Cut and Slide", "Ctrl R, point at a side edge (a yellow ring shows), roll the wheel for more cuts, click, move, click.",
	"New rings of edges all the way round, slid where you put them.", function(H) H.edit("Cube", "edge", "none") end)
add(G, "offsetloop", "Offset edge loops", "The top ring is selected. Shift Ctrl R.",
	"Two new rings either side of it.", function(H) H.edit("Cylinder", "edge", "topedges") end)
add(G, "knife", "Knife", "Press K, click points across the front faces, press Enter.",
	"New edges along your clicks.", function(H) H.edit("Cube", "edge", "none") end)
add(G, "bisect", "Bisect", "Everything is selected. Mesh menu > Bisect, drag a line across the cube.",
	"The cube is cut in two along that line.", function(H) H.edit("Cube", "edge", "all") end)
add(G, "spin", "Spin", "Everything is selected. F3, type Spin, Enter, move the mouse.",
	"The shape is swept round the 3D cursor.", function(H, api) H.edit("Plane", "edge", "all") H.shift(V3(4, 0, 0)) end)
add(G, "subdivide", "Subdivide", "Everything is selected. Edge menu > Subdivide.",
	"Each face splits into four.", function(H) H.edit("Cube", "face", "all") end, function(H) H.tool("Subdivide") end)
add(G, "rotateedge", "Rotate edge", "One edge is selected. Edge menu > Rotate Edge CW.",
	"The edge turns to join the next pair of corners.", function(H, api) H.edit("Cube", "face", "all") H.tool("Triangulate") api.setMode("edge") H.pick("edge") end,
	function(H) H.tool("RotateCW") end)
add(G, "bridge", "Bridge edge loops", "Two circles are selected. Edge menu > Bridge Edge Loops. Move the mouse right, roll the wheel, press T.",
	"A tube joins them; mouse = curve, wheel = more rings, T = twist.",
	function(H, api) H.edit("Circle", "edge", "none") api.add("Circle") H.shift(V3(0, 4, 0)) H.pick("all") H.frame() end)
add(G, "fill", "Fill / new face", "The top ring of the open cylinder is selected. Press F. Then Alt F.",
	"A face fills the hole; Alt F tidies its triangles.",
	function(H, api) H.edit("Cylinder", "face", "top") H.tool("DeleteOnlyFaces") api.setMode("edge") H.pick("topedges") end,
	function(H) H.tool("Fill") end)
add(G, "connect", "Connect, rip, split, separate", "Point mode: select two corners on the same face and press J. Then: select a face, Y (split), P > Selection.",
	"J draws an edge between them; Y detaches the face; P makes it its own object.", function(H) H.edit("Cube", "vert", "none") end)
add(G, "merge", "Merge", "The top points are selected. M > At Center.",
	"The four points join into one (a pyramid).", function(H) H.edit("Cube", "vert", "topverts") end, function(H) H.tool("MergeCenter") end)
add(G, "delete", "Delete and dissolve", "The top face is selected. X > Faces. Undo (Ctrl Z), then X > Dissolve Faces.",
	"Delete leaves a hole; dissolve keeps it closed.", function(H) H.edit("Cube", "face", "top") end, function(H) H.tool("DeleteFaces") end)
add(G, "facetools", "Face tools", "Everything is selected. Face menu > Poke, then Ctrl T, then Alt J.",
	"Poke: a point in each face. Ctrl T: triangles. Alt J: back to squares.", function(H) H.edit("Cube", "face", "all") end,
	function(H) H.tool("Poke") end)
add(G, "hullsym", "Convex Hull, Symmetrize", "Mesh menu > Convex Hull. Then Mesh > Symmetrize.",
	"A wrapped shell around the points / one side copied onto the other.", function(H) H.edit("Torus", "vert", "all") end)
add(G, "normals", "Normals", "Everything is selected. Mesh > Normals > Flip. Then Shift N.",
	"Flip: the cube looks inside-out (dark). Shift N fixes it.", function(H) H.edit("Cube", "face", "all") end, function(H) H.tool("Flip") end)
add(G, "marks", "Seams, sharp, crease", "The top edges are selected. Edge menu > Mark Seam, Mark Sharp. Then Shift E and move the mouse.",
	"Red line = seam, cyan = sharp, pink = crease. With the Subdivision modifier on, creased edges stay sharp.",
	function(H, api) local p = H.add("Cube") H.select({ p }) H.frame() api.modAdd("subsurf") api.toggleEdit() api.setMode("edge") H.pick("topedges") end)
add(G, "hideedit", "Hide in Edit Mode", "The top face is selected. H, then Alt H. Then Shift H.",
	"H hides that face; Alt H brings it back; Shift H hides everything else.", function(H) H.edit("Cube", "face", "top") end)
add(G, "cleanup", "Clean Up", "Mesh menu > Clean Up > Limited Dissolve (on the subdivided cube).",
	"The extra edges on the flat sides disappear.", function(H) H.edit("Cube", "face", "all") H.tool("Subdivide") end,
	function(H) H.tool("LimitedDissolve") end)
add(G, "addinedit", "Add in Edit Mode", "Shift A > Cube while in Edit Mode.",
	"A cube is added into this same mesh (one name in the Outliner), selected.", function(H) H.edit("Sphere", "face", "none") end)
add(G, "repeat", "Repeat last", "The top face is selected. E, move, click. Then Shift R twice.",
	"It extrudes again each time.", function(H) H.edit("Cube", "face", "top") end)
add(G, "automerge", "Auto Merge and X mirror", "Header: turn on the X mirror button (butterfly / X). Move a point on one side with G.",
	"The matching point on the other side moves too.", function(H) H.edit("Cube", "vert", "vert") end)

G = "Modifiers (the wrench tab)"
add(G, "modstack", "The stack", "Properties > wrench tab: two modifiers are on. Try the eye, the up / down arrows, Apply, and X.",
	"Each button does what it says; Apply bakes it into the mesh.",
	function(H, api) H.mod("Cube", "bevel") api.modAdd("subsurf") end)
add(G, "subsurf", "Subdivision Surface", "Press Ctrl 1, Ctrl 2, Ctrl 3, then Ctrl 0.",
	"Smoother each time; Ctrl 0 takes it off.", function(H) local p = H.add("Cube") H.select({ p }) H.frame() end)
add(G, "mirror", "Mirror", "Look. Then change the axis to Y / Z in the wrench tab.",
	"A copy of the cube appears on the other side of its middle.",
	function(H, api) local p = H.add("Cube") H.select({ p }) H.frame() api.toggleEdit() H.pick("all") H.shift(V3(3, 0, 0)) api.toggleEdit() api.modAdd("mirror") end)
add(G, "array", "Array", "Look. Change Count and the offset in the wrench tab.",
	"Copies of the cube in a row.", function(H) H.mod("Cube", "array") end)
add(G, "bevelmod", "Bevel", "Look. Change Amount and Segments.",
	"The cube's edges are rounded.", function(H) H.mod("Cube", "bevel") end)
add(G, "booleanmod", "Boolean", "The sphere cuts the cube. Select the sphere and move it with G.",
	"The hole follows the sphere when you move it.",
	function(H, api)
		local s = H.add("Sphere", V3(2, 2, 2))
		local c = H.add("Cube")
		H.select({ c }) H.frame()
		api.modAdd("boolean")
		api.modSet(#api.mods(), "target", s.Name)
	end)
add(G, "decimate", "Decimate", "Look. Lower the Ratio in the wrench tab.",
	"Fewer triangles, same rough shape.", function(H) H.mod("Sphere", "decimate") end)
add(G, "edgesplit", "Edge Split", "Look at the smooth-shaded cylinder.",
	"Sharp edges stay crisp; the round side stays smooth.", function(H) local p = H.mod("Cylinder", "edgesplit") H.tool("ObjShadeSmooth") return p end)
add(G, "screw", "Screw", "Look. Change Screw height and Steps.",
	"The circle is swept round into a ring / spring.", function(H) H.mod("Circle", "screw") end)
add(G, "solidify", "Solidify", "Look. Change Thickness.",
	"The flat plane gets thickness.", function(H) H.mod("Plane", "solidify") end)
add(G, "triangulate", "Triangulate", "Look (Alt Z X-ray helps).",
	"Every face is made of triangles.", function(H) H.mod("Cube", "triangulate") end)
add(G, "tube", "Tube", "Change radius and sides in the wrench tab.",
	"A round pipe along the path.", function(H) local p = H.add("CurvePath") H.select({ p }) H.frame() end)
add(G, "weld", "Weld", "Look.", "Nothing breaks (on a clean mesh there's nothing to weld).", function(H) H.mod("Cube", "weld") end)
add(G, "wiremod", "Wireframe", "Look. Change Thickness.", "Every edge becomes a beam.", function(H) H.mod("Cube", "wireframe") end)
add(G, "cast", "Cast", "Look. Change Factor.", "The shape pulls toward a ball.",
	function(H, api) H.mod("Cube", "subsurf") api.modAdd("cast") end)
add(G, "displace", "Displace", "Look. Change Strength and Seed.", "A bumpy, rocky surface.",
	function(H, api) H.mod("Sphere", "subsurf") api.modAdd("displace") end)
add(G, "shrinkwrap", "Shrinkwrap", "The cube is wrapped onto the ball next to it. Try Surface / Vertex / Project.",
	"The cube's points sit on the ball's surface.",
	function(H, api)
		local s = H.add("Sphere")
		local c = H.add("Cube")
		H.select({ c }) H.frame()
		api.modAdd("subsurf") api.modAdd("shrinkwrap")
		api.modSet(#api.mods(), "target", s.Name)
	end)
add(G, "simpledeform", "Simple Deform", "Look. Switch Twist / Bend / Taper / Stretch.", "The whole shape twists or bends.",
	function(H, api) H.mod("Cylinder", "subsurf") api.modAdd("simpledeform") end)
add(G, "smoothmod", "Smooth", "Look. Change Factor and Repeat.", "The shape relaxes / softens.",
	function(H, api) H.mod("Cube", "subsurf") api.modAdd("smooth") end)
add(G, "wave", "Wave", "Look. Change Height and Width.", "Ripples across the grid.", function(H) H.mod("Grid", "wave") end)

G = "Boolean"
add(G, "objbool", "Object > Boolean", "Both are selected (cube last). Object menu > Boolean > Difference. Ctrl Z, then try Union and Intersect.",
	"The cube is cut / joined / trimmed by the sphere; the sphere is used up.",
	function(H) local s = H.add("Sphere", V3(2, 2, 2)) local c = H.add("Cube") H.select({ s, c }) H.frame() end,
	function(_, api) api.boolean("difference") end)
add(G, "boolplain", "With a normal Part", "The cutter is a normal blue Studio Part. Object menu > Boolean > Difference.",
	"Works the same (the Part is converted on the way).",
	function(H) local q = H.part("Part", nil, V3(3, 3, 3), V3(2, 2, 2)) local c = H.add("Cube") H.select({ q, c }) H.frame() end,
	function(_, api) api.boolean("difference") end)
add(G, "editbool", "Intersect in Edit Mode", "The small cube (selected) is inside the same mesh. Face menu > Intersect (Boolean) > Difference.",
	"The selected cube cuts a notch out of the big one.",
	function(H, api) H.edit("Cube", "face", "none") api.add("Cube") H.shift(V3(2, 2, 2)) H.frame() end,
	function(H) H.tool("BooleanDifference") end)
add(G, "boolclean", "Clean result", "Press Tab and look at the cut.",
	"Whole faces (not lots of slivers), no gaps or cracks.",
	function(H, api) local s = H.add("Cylinder", V3(1, 1, 1)) local c = H.add("Cube") H.select({ s, c }) api.boolean("difference") H.frame() end)

G = "UVs and textures"
add(G, "projections", "Projections", "A test face texture is on. U > Cube, then U > Cylinder, then U > Sphere.",
	"The face picture wraps round differently each time.",
	function(H, api) local p = H.add("Cube") H.select({ p }) H.frame() api.setTexture("rbxasset://textures/face.png") end)
add(G, "unwrap", "Unwrap with seams", "Everything is selected. U > Unwrap. Then U > UV Editor to look.",
	"Flat pieces laid out in the square, no stretching.",
	function(H, api) local p = H.add("Cube") H.select({ p }) H.frame() api.setTexture("rbxasset://textures/face.png") api.toggleEdit() H.pick("all") end)
add(G, "smartuv", "Smart UV Project", "U > Smart UV Project.", "The picture looks even all round.",
	function(H, api) local p = H.add("Sphere") H.select({ p }) H.frame() api.setTexture("rbxasset://textures/face.png") api.toggleEdit() H.pick("all") end,
	function(_, api) api.uvUnwrap("smart") end)
add(G, "uveditor", "UV Editor", "U > UV Editor. Click points, drag them, box select, A, G / S / R, Pack.",
	"UV lines over the picture; moving them changes how the picture sits on the mesh.",
	function(H, api) local p = H.add("Cube") H.select({ p }) H.frame() api.setTexture("rbxasset://textures/face.png") api.toggleEdit() H.pick("all") api.uvUnwrap("smart") end)
add(G, "uvkeep", "UVs kept", "Move a few points with G, then press Tab to leave Edit Mode.",
	"The picture still sits right after leaving Edit Mode.",
	function(H, api) local p = H.add("Cube") H.select({ p }) H.frame() api.setTexture("rbxasset://textures/face.png") api.toggleEdit() H.pick("all") api.uvUnwrap("smart") H.pick("top") end)

G = "Sculpt Mode"
add(G, "sculptin", "Enter Sculpt Mode", "Click the mode button at the top left (it says Edit Mode) > Sculpt Mode. (Ctrl Tab may not work: Studio keeps that key.)",
	"A brush circle follows the mouse; brush buttons appear on the left.", function(H) H.edit("Sphere", "face", "none") end)
add(G, "brushes", "Brushes", "Drag on the sphere. Then press X, C, I, G, S, T, P and drag with each. Hold Ctrl to do the opposite.",
	"Draw (X) raises, Clay (C) builds up, Inflate (I) puffs, Grab (G) pulls, Smooth (S) relaxes, Flatten (T), Pinch (P).",
	function(H) H.sculpt(2) end)
add(G, "brushsize", "Size and strength", "Press F and move the mouse, click. Shift F and move, click. Then [ and ].",
	"The circle grows / shrinks smoothly; strength changes.", function(H) H.sculpt(2) end)
add(G, "sculptsym", "Symmetry and subdivide", "Turn on X sym in the header, drag on one side. Then Sculpt menu > Subdivide.",
	"The other side copies your stroke; Subdivide makes it smoother / more detailed.", function(H) H.sculpt(1) end)
add(G, "sculptspeed", "Sculpt speed", "Drag around on the sphere with the Draw brush.",
	"It keeps up with the mouse (no stutter).", function(H) H.sculpt(3) end)

G = "Vertex Paint"
add(G, "paintin", "Enter Vertex Paint", "Click the mode button at the top left > Vertex Paint.",
	"The header shows a colour square and a hex box; the Mesh menu becomes Paint.", function(H) H.edit("Sphere", "face", "none") end)
add(G, "paintdraw", "Paint", "Drag on the sphere. Click the colour square to pick another colour. Hold Ctrl to paint white.",
	"Colour spreads smoothly across the surface.", function(H) H.paint(2) end)
add(G, "paintpick", "Pick, fill, clear", "Paint a bit, then press S over it (picks that colour). Shift K fills everything. Paint menu > Clear Colours.",
	"Picks the colour / fills everything / clears it.", function(H) H.paint(2) end, function(_, api) api.paintFill() end)
add(G, "paintsave", "Colours kept", "It's been filled with colour. Press Tab to leave.",
	"The colours stay on the object.", function(H, api) H.paint(1) api.paintFill() end)

G = "Collision and saving"
add(G, "collision", "Collision panel", "Properties > orange square tab (Object) > Collision: try Box / Hull / Precise, Can Collide, Anchored.",
	"Each one changes the part (check in Studio's Properties after closing ROBLEND).", function(H) local p = H.add("Sphere") H.select({ p }) H.frame() end)
add(G, "save", "Save to Roblox", "File > Save Mesh (needs the CreateAssetAsync beta). Skip if you haven't turned that on.",
	"The bottom bar says Saved with an rbxassetid; the shape looks the same.", function(H) local p = H.add("Torus") H.select({ p }) H.frame() end)
add(G, "autosave", "Auto save", "Press Tab, change something (E on a face), press Tab again. (Needs the CreateAssetAsync beta; skip if not.)",
	"It saves by itself after leaving Edit Mode (bottom bar).", function(H) local p = H.add("Cube") H.select({ p }) H.frame() end)
I[#I].autoSave = true
add(G, "bake", "Bake to Parts / Export .obj", "Mesh menu (Edit Mode) > Bake to Parts. Then Export .obj.",
	"A copy made of normal parts appears / an OBJ script opens to copy.", function(H) H.edit("Cube", "face", "none") end)
add(G, "speed", "Speed on a big mesh", "Everything is selected on a big sphere. Press G and move the mouse around.",
	"It moves smoothly with the mouse.",
	function(H, api) H.sculpt(3) api.setPaintMode(nil) api.setMode("vert") H.pick("all") end)
add(G, "reopen", "After a restart", "Last one: save the place, close Studio, open it again, open ROBLEND.",
	"Your meshes are still there and look right.", function(H) H.clean() end)

QuickTest.ITEMS = I
QuickTest.helpers = helpers

-- ===== the card =====
function QuickTest.new(C)
	local Q = { open = false, i = 1, results = {}, busy = false }
	local H = helpers(C)
	Q.H = H
	pcall(function() Q.results = C.plugin:GetSetting("RB_QuickTest") or {} end)
	if type(Q.results) ~= "table" then Q.results = {} end

	local card, head, title, act, see, note, msg
	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = parent
		return o
	end
	local function btn(parent, text, pos, size, col, fn)
		local b = mk("TextButton", { Size = size, Position = pos, BackgroundColor3 = col, BorderSizePixel = 0, AutoButtonColor = true,
			Text = text, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(240, 240, 240), ZIndex = 71 }, parent)
		mk("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
		b.Activated:Connect(function() if not Q.busy then fn() end end)
		return b
	end
	local function label(props, parent)
		local d = { BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Color3.fromRGB(215, 215, 220), TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 71, Text = "" }
		for k, v in pairs(props) do d[k] = v end
		return mk("TextLabel", d, parent)
	end
	local function build()
		local st = C.get()
		local gui = st.ui and st.ui.gui
		if not gui then return false end
		card = mk("Frame", { Name = "RB_QuickTest", Size = UDim2.fromOffset(440, 236), Position = UDim2.new(0, 60, 1, -300), BackgroundColor3 = Color3.fromRGB(36, 36, 42),
			BorderSizePixel = 0, ZIndex = 70, Active = true }, gui)
		mk("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
		mk("UIStroke", { Color = Color3.fromRGB(230, 180, 40), Thickness = 2 }, card)
		head = label({ Size = UDim2.new(1, -40, 0, 14), Position = UDim2.fromOffset(12, 8), TextSize = 10, TextColor3 = Color3.fromRGB(230, 190, 80) }, card)
		title = label({ Name = "RB_QuickTestTitle", Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 23), Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.fromRGB(245, 245, 245) }, card)
		label({ Size = UDim2.fromOffset(40, 14), Position = UDim2.fromOffset(12, 46), TextSize = 10, Font = Enum.Font.GothamBold, Text = "DO", TextColor3 = Color3.fromRGB(120, 170, 255) }, card)
		act = label({ Size = UDim2.new(1, -60, 0, 50), Position = UDim2.fromOffset(48, 45) }, card)
		label({ Size = UDim2.fromOffset(40, 14), Position = UDim2.fromOffset(12, 100), TextSize = 10, Font = Enum.Font.GothamBold, Text = "SHOULD", TextColor3 = Color3.fromRGB(110, 210, 120) }, card)
		see = label({ Size = UDim2.new(1, -72, 0, 46), Position = UDim2.fromOffset(60, 99), TextColor3 = Color3.fromRGB(190, 225, 195) }, card)
		msg = label({ Size = UDim2.new(1, -24, 0, 14), Position = UDim2.fromOffset(12, 148), TextSize = 10, TextColor3 = Color3.fromRGB(160, 160, 170) }, card)
		local grey, green, red = Color3.fromRGB(78, 78, 86), Color3.fromRGB(46, 130, 70), Color3.fromRGB(165, 55, 55)
		Q.showBtn = btn(card, "Show me", UDim2.fromOffset(12, 166), UDim2.fromOffset(76, 22), Color3.fromRGB(60, 95, 160), function() Q.show() end)
		btn(card, "Set up again", UDim2.fromOffset(94, 166), UDim2.fromOffset(92, 22), grey, function() Q.go(Q.i) end)
		btn(card, "Back", UDim2.fromOffset(192, 166), UDim2.fromOffset(56, 22), grey, function() Q.go(Q.i - 1) end)
		btn(card, "X", UDim2.new(1, -30, 0, 6), UDim2.fromOffset(22, 20), grey, function() Q.close() end)
		note = mk("TextBox", { Name = "RB_QuickTestNote", Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 194 - 2 + 0), BackgroundColor3 = Color3.fromRGB(24, 24, 28),
			BorderSizePixel = 0, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Color3.fromRGB(230, 230, 230), PlaceholderText = "What's wrong? (optional, type before pressing Broken)",
			PlaceholderColor3 = Color3.fromRGB(120, 120, 130), Text = "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 71 }, card)
		note.Size = UDim2.new(1, -230, 0, 22)
		note.Position = UDim2.fromOffset(12, 204)
		mk("UICorner", { CornerRadius = UDim.new(0, 4) }, note)
		mk("UIPadding", { PaddingLeft = UDim.new(0, 6) }, note)
		Q.worksBtn = btn(card, "Works", UDim2.new(1, -212, 0, 204), UDim2.fromOffset(66, 22), green, function() Q.mark("works") end)
		btn(card, "Broken", UDim2.new(1, -140, 0, 204), UDim2.fromOffset(66, 22), red, function() Q.mark("broken") end)
		btn(card, "Skip", UDim2.new(1, -68, 0, 204), UDim2.fromOffset(56, 22), grey, function() Q.mark("skip") end)
		if st.ui.blockers then table.insert(st.ui.blockers, card) end
		return true
	end
	local function count()
		local n = 0
		for _, it in ipairs(I) do if Q.results[it.id] then n += 1 end end
		return n
	end
	local function show()
		local it = I[Q.i]
		if not (card and it) then return end
		local r = Q.results[it.id]
		head.Text = ("QUICK TEST   %d / %d   ·   %s%s"):format(Q.i, #I, it.group:upper(), r and ("   ·   last time: " .. r) or "")
		title.Text = it.title
		act.Text = it.act
		see.Text = it.see
		Q.showBtn.Visible = it.show ~= nil
		note.Text = ""
	end
	function Q.go(i)
		if i < 1 then i = 1 end
		if i > #I then Q.finish() return end
		Q.i = i
		show()
		local it = I[i]
		Q.busy = true
		if msg then msg.Text = "Setting up..." end
		task.defer(function()
			H.clean()
			-- auto save is paused during the test (it would upload every test shape), except for its own test
			pcall(C.api.setAutoSave, it.autoSave == true and true or false, true)
			local ok, err = true, nil
			if it.setup then ok, err = pcall(it.setup, H, C.api) end
			Q.busy = false
			Q.setupErr = (not ok) and tostring(err) or nil
			if msg then msg.Text = ok and ("Ready. " .. count() .. " of " .. #I .. " done.") or ("Setup hit a problem: " .. tostring(err)) end
			if not ok then warn("ROBLEND CHECK setup error " .. it.id .. ": " .. tostring(err)) end
		end)
	end
	function Q.show()
		local it = I[Q.i]
		if not (it and it.show) then return end
		local ok, err = pcall(it.show, H, C.api)
		Q.showErr = (not ok) and tostring(err) or nil
		if msg then msg.Text = ok and "Done it for you - does it look right?" or ("Show me hit a problem: " .. tostring(err)) end
	end
	function Q.mark(status)
		local it = I[Q.i]
		if not it then return end
		local text = note and note.Text or ""
		Q.results[it.id] = status
		pcall(function() C.plugin:SetSetting("RB_QuickTest", Q.results) end)
		local line = ("ROBLEND CHECK %s %s%s"):format(it.id, status, text ~= "" and ("  -  " .. text) or "")
		if status == "broken" then warn(line) else print(line) end
		Q.go(Q.i + 1)
	end
	function Q.finish()
		H.clean()
		if Q.autoSaveWas ~= nil then pcall(C.api.setAutoSave, Q.autoSaveWas, true) end
		local w, b, s = 0, 0, 0
		for _, it in ipairs(I) do
			local r = Q.results[it.id]
			if r == "works" then w += 1 elseif r == "broken" then b += 1 elseif r == "skip" then s += 1 end
		end
		local line = ("ROBLEND CHECK DONE  %d works, %d broken, %d skipped"):format(w, b, s)
		print(line)
		if card then
			head.Text = "QUICK TEST"
			title.Text = "All done!"
			act.Text = ("%d work, %d broken, %d skipped. Tell Claude you've finished: the results are in Studio's log."):format(w, b, s)
			see.Text = "Back goes to the last one. Help > Quick Test again starts from the first one you haven't done."
			Q.showBtn.Visible = false
			Q.i = #I + 1
			msg.Text = ""
		end
	end
	function Q.openTest()
		if not card then if not build() then return end end
		if Q.autoSaveWas == nil then Q.autoSaveWas = C.api.state().autoSave == true end
		card.Visible = true
		Q.open = true
		H.snapshot()
		print("ROBLEND CHECK START  version " .. tostring(C.VERSION))
		local first = #I + 1
		for i, it in ipairs(I) do if not Q.results[it.id] then first = i break end end
		if first > #I then first = 1 end
		Q.go(first)
	end
	function Q.close()
		if not Q.open then return end
		Q.open = false
		if card then card.Visible = false end
		pcall(H.clean)
		if Q.autoSaveWas ~= nil then pcall(C.api.setAutoSave, Q.autoSaveWas, true) Q.autoSaveWas = nil end
	end
	function Q.toggle() if Q.open then Q.close() else Q.openTest() end end
	function Q.reset() Q.results = {} pcall(function() C.plugin:SetSetting("RB_QuickTest", {}) end) end
	return Q
end

return QuickTest
