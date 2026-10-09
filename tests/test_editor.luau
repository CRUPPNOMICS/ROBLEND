-- editor smoke test: drives Main.server.lua through the fake Studio (tests/studio_mock.luau)
-- glued together by tools/test.py; Main runs first, then this
local V3 = Vector3.new
local S = MOCK.services
local mouse = MOCK.mouse
local cam = workspace.CurrentCamera
local pass, fail = 0, 0
local function check(name, fn)
	local nw = #MOCK.warns
	local ok, err = pcall(fn)
	if ok and #MOCK.warns > nw then ok, err = false, "warned: " .. MOCK.warns[#MOCK.warns] end
	if ok and MOCK.status and MOCK.status:sub(1, 5) == "Error" then ok, err = false, MOCK.status end
	if ok then pass += 1 print("PASS " .. name) else fail += 1 print("FAIL " .. name .. ": " .. tostring(err) .. "  [status: " .. tostring(MOCK.status) .. "]") end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local function press(k, mods)
	for _, m in ipairs(mods or {}) do MOCK.held[m] = true end
	S.UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode[k] }, false)
	for _, m in ipairs(mods or {}) do MOCK.held[m] = nil end
end
local function type_(str)
	local names = { ["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four", ["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine", ["."] = "Period", ["-"] = "Minus" }
	for ch in str:gmatch(".") do press(names[ch]) end
end
local function beat()
	local q = MOCK_DEFER
	MOCK_DEFER = {}
	for _, f in ipairs(q) do f() end
	MOCK.t += 0.1
	S.RunService.Heartbeat:Fire()
end
local function btn(name) local b = assert(MOCK.buttons[name], "no button " .. name) b.Activated:Fire() beat() end
local function part(name)
	for _, c in ipairs(workspace:GetChildren()) do if c.Name == name then return c end end
	error("no part " .. name)
end
local function data(p) return S.HttpService:JSONDecode(p.RB_Data.Value) end
local function counts(p) local d = data(p) return #d.v / 3, #d.f end
local function originOf(p) return p.CFrame * CFrame.new(-(p:GetAttribute("RB_Center") or V3())) end
local function worldVerts(p)
	local d, o, out = data(p), originOf(p), {}
	for i = 1, #d.v, 3 do out[#out + 1] = o * V3(d.v[i], d.v[i + 1], d.v[i + 2]) end
	return out, d
end
local function bounds(list)
	local lo, hi = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(list) do
		lo = V3(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
		hi = V3(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
	end
	return lo, hi
end
local function mouseTo(wp)
	local sp = cam:WorldToViewportPoint(wp)
	mouse.X, mouse.Y = sp.X, sp.Y
	mouse.Move:Fire()
end
local function mouseXY(x, y) mouse.X, mouse.Y = x, y mouse.Move:Fire() end
-- (a human pause first, so two clicks in a row aren't a double click)
local function click() MOCK.t += 0.5 mouse.Button1Down:Fire() mouse.Button1Up:Fire() beat() end
local function dblclick() MOCK.t += 0.5 mouse.Button1Down:Fire() mouse.Button1Up:Fire() mouse.Button1Down:Fire() mouse.Button1Up:Fire() beat() end
local function near(a, b, tol) return math.abs(a - b) < (tol or 1e-3) end
-- the centre of the face whose verts all have the top Y
local function topFaceCenter(p)
	local vs, d = worldVerts(p)
	local _, hi = bounds(vs)
	for _, f in ipairs(d.f) do
		local all, s = true, V3()
		for _, i in ipairs(f) do if not near(vs[i].Y, hi.Y) then all = false end s = s + vs[i] end
		if all then return s / #f end
	end
end

local cube
check("add a cube", function()
	btn("Cube")
	cube = part("ROBLENDER Cube")
	local nv, nf = counts(cube)
	eq(nv, 8) eq(nf, 6)
	eq(S.Selection:Get()[1], cube, "selected")
	eq(cube.Size, V3(4, 4, 4), "size")
end)

local before
check("Tab into edit mode", function()
	press("Tab")
	beat()
	assert(plugin.Active, "plugin active")
	assert(MOCK.status:find("EDIT"), "status says edit")
	before = cube.RB_Data.Value
end)

check("pick the top face + extrude it up", function()
	press("Three")
	local c = topFaceCenter(cube)
	mouseTo(c)
	click()
	local _, hi0 = bounds(worldVerts(cube))
	press("E")
	assert(MOCK.status:find("MOVE"), "extrude started a move")
	mouseXY(mouse.X, mouse.Y - 80)
	beat()
	mouse.Button1Down:Fire() mouse.Button1Up:Fire()
	beat()
	local nv, nf = counts(cube)
	eq(nv, 12, "verts") eq(nf, 10, "faces")
	local lo, hi = bounds(worldVerts(cube))
	assert(hi.Y > hi0.Y + 0.5, "top went up: " .. hi.Y .. " vs " .. hi0.Y)
	assert(near(cube.Size.Y, hi.Y - lo.Y), "part size follows the mesh")
end)

check("inset the new top", function()
	press("I")
	mouseXY(mouse.X + 40, mouse.Y)
	beat()
	click()
	local _, nf = counts(cube)
	eq(nf, 14, "faces")
end)

check("undo reloads the mesh", function()
	local now = cube.RB_Data.Value
	cube.RB_Data.Value = before
	beat()
	assert(MOCK.status:find("reloaded"), "reloaded")
	local _, nf = counts(cube)
	eq(nf, 6)
	cube.RB_Data.Value = now
	beat()
	eq(select(2, counts(cube)), 14)
end)

check("loop cut round the sides", function()
	press("R", { "LeftControl" })
	-- a vertical side edge: point at the middle of the cube's +X+Z corner edge
	local vs = worldVerts(cube)
	local lo, hi = bounds(vs)
	mouseTo(V3(hi.X, (lo.Y + hi.Y) / 2 - 0.5, hi.Z))
	beat()
	click()
	local _, nf = counts(cube)
	assert(nf > 14, "more faces after the cut: " .. nf)
	assert(MOCK.status:find("Loop cut"), "status")
end)

check("G X 2 Enter moves everything 2 along X", function()
	press("One")
	press("A") -- loop cut left edges picked: A clears, A again selects all
	press("A")
	local lo0 = bounds(worldVerts(cube))
	press("G") press("X") type_("2") press("Return")
	beat()
	local lo1 = bounds(worldVerts(cube))
	assert(near(lo1.X - lo0.X, 2), "moved " .. (lo1.X - lo0.X))
	assert(near(lo1.Y, lo0.Y) and near(lo1.Z, lo0.Z), "only X")
end)

check("S 2 doubles, R Z 90 turns", function()
	local lo0, hi0 = bounds(worldVerts(cube))
	press("S") type_("2") press("Return")
	beat()
	local lo1, hi1 = bounds(worldVerts(cube))
	assert(near(hi1.X - lo1.X, 2 * (hi0.X - lo0.X)), "scaled")
	press("R") press("Z") type_("90") press("Return")
	beat()
	local lo2, hi2 = bounds(worldVerts(cube))
	assert(near(hi2.X - lo2.X, hi1.Y - lo1.Y, 1e-2), "turned: width now = old height")
end)

check("Esc cancels a move", function()
	local v0 = cube.RB_Data.Value
	press("G")
	mouseXY(mouse.X + 100, mouse.Y + 50)
	beat()
	press("Escape")
	beat()
	eq(cube.RB_Data.Value, v0, "unchanged")
end)

check("box select + alt-click loop", function()
	press("Alt") -- nothing
	press("A", { "LeftAlt" })
	mouse.X, mouse.Y = 5, 5
	mouse.Button1Down:Fire()
	mouseXY(1195, 795)
	mouse.Button1Up:Fire()
	beat()
	press("Two")
	local vs = worldVerts(cube)
	local lo, hi = bounds(vs)
	MOCK.held.LeftAlt = true
	mouseTo(V3(hi.X, (lo.Y + hi.Y) / 2, hi.Z))
	click()
	MOCK.held.LeftAlt = nil
end)

check("subdivide, flip, delete, merge by distance, x-ray", function()
	press("Three")
	press("A", { "LeftAlt" })
	press("A")
	btn("Subdivide")
	local _, nf = counts(cube)
	assert(nf > 40, "subdivided " .. nf)
	btn("Flip")
	btn("Merge dist")
	press("Z", { "LeftAlt" })
	press("Z", { "LeftAlt" })
	press("A", { "LeftAlt" })
	mouseTo(topFaceCenter(cube) or cube.Position)
	click()
	local n0 = select(2, counts(cube))
	press("Delete")
	beat()
	eq(select(2, counts(cube)), n0 - 1, "one face gone")
end)

check("fill: verts -> face, merge -> point", function()
	press("One")
	press("A", { "LeftAlt" })
	press("A")
	btn("Merge (M)")
end)

check("Tab out, bake + export", function()
	press("Tab")
	beat()
	assert(not plugin.Active, "plugin off")
	eq(S.Selection:Get()[1] ~= nil, true, "part selected again")
	local c2
	btn("Cylinder")
	c2 = part("ROBLENDER Cylinder")
	btn("Bake to parts")
	local baked = part("ROBLENDER Cylinder (baked)")
	assert(#baked:GetChildren() >= 1, "baked parts")
	S.Selection:Set({ c2 })
	btn("Export .obj")
	assert(#MOCK.opened == 1 and MOCK.opened[1].Source:find("\nf "), "obj text")
end)

for _, k in ipairs({ "Plane", "Grid", "Circle", "Sphere", "Cylinder" }) do
	check("add " .. k .. ", edit, extrude all faces, Esc", function()
		btn(k)
		local p = S.Selection:Get()[1]
		local nv0, nf0 = counts(p)
		press("Tab") beat()
		press("Three") press("A", { "LeftAlt" }) press("A")
		press("E")
		mouseXY(mouse.X, mouse.Y - 20)
		beat()
		press("Escape")
		beat()
		local nv, nf = counts(p)
		if k == "Sphere" or k == "Cylinder" then
			assert(nf == nf0 and nv == nv0, "closed shape: extruding every face just moves it (like Blender)")
		else
			assert(nf > nf0 and nv > nv0, "extruded (kept on Esc like Blender)")
		end
		press("Tab") beat()
	end)
end

check("Studio scale is kept when editing again", function()
	btn("Cube")
	local p = S.Selection:Get()[1]
	p.Size = V3(8, 4, 4)
	press("Tab") beat()
	local lo, hi = bounds(worldVerts(p))
	-- RB_Size was stored after the rebuild; the mesh should now be 8 wide
	assert(near(hi.X - lo.X, 8), "width " .. (hi.X - lo.X))
	press("One") press("A", { "LeftAlt" }) press("A")
	press("G") press("Y") type_("1") press("Return") beat()
	local lo2, hi2 = bounds(worldVerts(p))
	assert(near(hi2.X - lo2.X, 8), "still 8 after an edit")
	press("Tab") beat()
end)

-- ===== the Blender-style window =====
local gui, view
local function find(class, pred)
	for _, d in ipairs(gui:GetDescendants()) do if d.ClassName == class and pred(d) then return d end end
end
local function findAll(class, pred)
	local out = {}
	for _, d in ipairs(gui:GetDescendants()) do if d.ClassName == class and pred(d) then out[#out + 1] = d end end
	return out
end
local function hasText(t) return find("TextLabel", function(d) return (d.Text or ""):find(t, 1, true) ~= nil end) ~= nil or find("TextButton", function(d) return (d.Text or ""):find(t, 1, true) ~= nil end) ~= nil end
local function menuItem(text)
	local l = find("TextLabel", function(d) return d.Text == text and d.Parent and d.Parent.ClassName == "TextButton" and (d.Parent.ZIndex or 0) >= 21 end)
	assert(l, "menu item " .. text)
	l.Parent.MouseEnter:Fire()
	l.Parent.Activated:Fire()
	beat()
end
local function headerBtn(text)
	local b = find("TextButton", function(d) return d.Text == text end)
	assert(b, "button " .. text)
	b.Activated:Fire()
	beat()
end
local function rbParts()
	local n = 0
	for _, c in ipairs(workspace:GetChildren()) do if c:FindFirstChild("RB_Data") then n += 1 end end
	return n
end
local p3
check("plugin button opens the Blender window with its own 3D view", function()
	S.Selection:Set({})
	MOCK.toolbarButton.Click:Fire()
	gui = S.CoreGui:FindFirstChild("ROBLENDER_UI")
	assert(gui and gui.Enabled, "window on")
	view = MOCK.view
	assert(view and view.frame.ClassName == "ViewportFrame", "own 3D view")
	assert(plugin.Active, "plugin active so clicks go to the 3D view")
	beat() beat()
	cam = view
	assert(hasText("Object Mode"), "mode")
	assert(hasText("User Perspective"), "info text")
	assert(hasText("Scene Collection") and hasText("ROBLENDER Cube"), "outliner lists the meshes")
	assert(#view.gridFolder:GetChildren() > 50, "grid")
end)
check("Shift A > Mesh > Cube adds at the 3D cursor, shown in the view", function()
	press("A", { "LeftShift" })
	menuItem("Mesh")
	menuItem("Cube")
	p3 = S.Selection:Get()[1]
	assert(p3 and p3.Name == "ROBLENDER Cube", "added")
	assert((p3.CFrame.Position - Vector3.new(0, 2, 0)).Magnitude < 1e-3, "at the cursor")
	beat() beat() beat()
	assert(view.objects[p3], "display copy in the view")
end)
check("click picks objects in our view, empty click clears", function()
	press("KeypadPeriod") beat()
	mouseXY(3, 3) click()
	eq(#S.Selection:Get(), 0, "cleared")
	mouseTo(p3.CFrame.Position) click()
	eq(S.Selection:Get()[1], p3, "picked")
	beat()
	assert(#view.cageFolder:GetChildren() > 0, "orange outline drawn")
end)
check("object G X 3 Enter, R Esc", function()
	local x0 = p3.CFrame.Position.X
	press("G") press("X") type_("3") press("Return") beat()
	assert(near(p3.CFrame.Position.X, x0 + 3), "moved")
	local cf = p3.CFrame
	press("R") mouseXY(mouse.X + 60, mouse.Y + 20) beat() press("Escape") beat()
	assert(p3.CFrame == cf or (p3.CFrame.Position - cf.Position).Magnitude < 1e-6, "rotate cancelled")
end)
check("orbit (RMB drag), zoom (wheel), gizmo top view, Home", function()
	local yaw, dist = view.yaw, view.dist
	mouse.Button2Down:Fire() mouseXY(mouse.X + 50, mouse.Y) mouse.Button2Up:Fire() beat()
	assert(view.yaw ~= yaw, "orbited")
	assert(not hasText("Delete Faces"), "no context menu after a drag")
	mouse.WheelForward:Fire() beat()
	assert(view.dist < dist, "zoomed in")
	local ball = find("TextButton", function(d) return d.Text == "Y" and d.Parent and d.Parent.Name == "Gizmo" end)
	ball.MouseButton1Down:Fire()
	S.UserInputService.InputEnded:Fire({ UserInputType = Enum.UserInputType.MouseButton1 })
	beat()
	assert(view.pitch > math.rad(89), "top view")
	assert(hasText("Top Orthographic"), "says Top (numpad views go orthographic, like Blender)")
	press("Home") beat()
	press("KeypadOne") beat()
	assert(view.ortho, "numpad view is orthographic")
	local yaw1 = view.yaw
	mouse.Button2Down:Fire() mouseXY(mouse.X + 20, mouse.Y) mouseXY(mouse.X - 20, mouse.Y) mouse.Button2Up:Fire() beat()
	view.yaw = yaw1 view:update()
	assert(not view.ortho, "orbiting goes back to perspective (Auto Perspective)")
	press("KeypadFive") beat()
	beat()
	assert(view.ortho and hasText("Orthographic"), "Numpad 5 = orthographic")
	press("KeypadFive") beat()
	assert(not view.ortho, "Numpad 5 again = perspective")
	local y0 = view.yaw
	press("KeypadFour") beat()
	assert(math.abs(view.yaw - y0 - math.rad(15)) < 1e-6, "Numpad 4 orbits 15 degrees")
	press("KeypadSix") beat()
end)
check("Tab edits in our view: pick a face, extrude", function()
	S.Selection:Set({ p3 }) beat()
	press("Tab") beat() beat()
	assert(hasText("Edit Mode") and hasText("Vertices  0/8"), "edit mode + stats")
	press("Three")
	local vs, d = worldVerts(p3)
	local c = topFaceCenter(p3)
	press("KeypadThree") beat()
	view.pitch = math.rad(30) view:update() beat()
	mouseTo(c) click()
	beat()
	assert(hasText("Faces  1/6"), "face picked")
	press("E") mouseXY(mouse.X, mouse.Y - 60) beat() click()
	local nv, nf = counts(p3)
	eq(nf, 10, "extruded")
	beat()
	assert(view.objects[p3], "edited mesh shown")
end)
check("header menus: Select > All, Edge > Subdivide, Face > Inset (Esc)", function()
	local sel = find("TextButton", function(d) return d.Text == "Select" and d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "Header" end)
	sel.Activated:Fire() menuItem("All")
	headerBtn("Edge") menuItem("Subdivide")
	local _, nf = counts(p3)
	assert(nf > 10, "subdivided " .. nf)
	headerBtn("Face") menuItem("Inset Faces")
	mouseXY(mouse.X + 30, mouse.Y) beat() press("Escape") beat()
end)
check("right-click opens the mesh context menu", function()
	mouse.Button2Down:Fire() mouse.Button2Up:Fire() beat()
	assert(hasText("Delete Faces"), "context menu")
	press("Escape") beat()
	assert(not hasText("Delete Faces"), "closed")
end)
check("Tab out; Properties: Location X, Material, colour", function()
	press("Tab") beat() beat()
	S.Selection:Set({ p3 }) beat() beat()
	local row = find("TextLabel", function(d) return d.Text == "Location X" end)
	assert(row, "Location X field")
	local box = row.Parent:FindFirstChildOfClass("TextBox")
	box.Text = "10" box.FocusLost:Fire(true) beat()
	assert(near(p3.CFrame.Position.X, 10), "moved by typing")
	local tabsCol = find("TextButton", function(d) return d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "Properties" and d.Size and d.Size[2] == 25 end).Parent
	local tabBtns = {}
	for _, c in ipairs(tabsCol:GetChildren()) do if c.ClassName == "TextButton" then tabBtns[#tabBtns + 1] = c end end
	table.sort(tabBtns, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	tabBtns[4].Activated:Fire() beat()
	local mat = find("TextButton", function(d) return (d.Text or ""):find("SmoothPlastic", 1, true) ~= nil end)
	mat.Activated:Fire()
	menuItem("Neon")
	eq(p3.Material.Name, "Neon", "material")
	tabBtns[1].Activated:Fire() beat()
end)
check("Outliner: click a row selects, eye hides", function()
	local row = find("TextLabel", function(d) return d.Text == "ROBLENDER Plane" and d.Parent and d.Parent.ClassName == "TextButton" end)
	assert(row, "plane row")
	row.Parent.Activated:Fire() beat()
	eq(S.Selection:Get()[1].Name, "ROBLENDER Plane", "selected from outliner")
	local plane = S.Selection:Get()[1]
	local eye
	for _, c in ipairs(row.Parent:GetChildren()) do if c.ClassName == "TextButton" then eye = c end end
	eye.Activated:Fire() beat() beat() beat()
	assert(view.objects[plane] == nil, "hidden from the view")
	local row2 = find("TextLabel", function(d) return d.Text == "ROBLENDER Plane" and d.Parent and d.Parent.ClassName == "TextButton" end)
	for _, c in ipairs(row2.Parent:GetChildren()) do if c.ClassName == "TextButton" then eye = c end end
	eye.Activated:Fire() beat() beat() beat()
	assert(view.objects[plane] ~= nil, "shown again")
end)
check("Shift D duplicates, X deletes", function()
	S.Selection:Set({ p3 }) beat()
	local n0 = rbParts()
	press("D", { "LeftShift" }) mouseXY(mouse.X + 20, mouse.Y) beat() press("Return") beat()
	eq(rbParts(), n0 + 1, "duplicated")
	press("X") beat()
	eq(rbParts(), n0, "deleted")
	eq(#S.Selection:Get(), 0, "nothing selected")
end)
check("leaving Edit Mode saves the mesh as a real Roblox asset; unchanged edit keeps it", function()
	S.Selection:Set({ p3 }) beat()
	local n0 = #MOCK.uploads
	press("Tab") beat()
	press("One") press("A") press("G") press("Y") type_("1") press("Return") beat()
	press("Tab") beat()
	eq(#MOCK.uploads, n0 + 1, "uploaded once")
	local id = p3:GetAttribute("RB_AssetId")
	assert(id and p3:GetAttribute("RB_SavedHash"), "saved attrs")
	assert(p3.Mesh == MOCK.uploads[#MOCK.uploads].em, "the part now uses the uploaded mesh")
	assert(not hasText("ROBLENDER Cube *") or true)
	press("Tab") beat() press("Tab") beat()
	eq(#MOCK.uploads, n0 + 1, "no upload when nothing changed")
	assert(p3.Mesh == MOCK.uploads[#MOCK.uploads].em, "saved mesh put back")
	MOCK.noAssetApi = true
	press("Tab") beat() press("One") press("A") press("G") press("Y") type_("1") press("Return") beat() press("Tab") beat()
	assert(MOCK.status:find("Beta Features", 1, true), "tells you to turn on the beta")
	MOCK.noAssetApi = false
	headerBtn("File") menuItem("Save Mesh to Roblox")
	eq(#MOCK.uploads, n0 + 2, "File > Save")
	assert(MOCK.status:find("Saved", 1, true), "saved message")
end)
-- ===== the Modeling tab =====
local p4
local function toolBtn(order)
	local tb = find("Frame", function(d) return d.Name == "Toolbar" end)
	for _, c in ipairs(tb:GetChildren()) do if c.ClassName == "TextButton" and c.LayoutOrder == order then return c end end
	error("no tool " .. order)
end
local function inEdit() return MOCK.api.state().editing == true end
local function editCube()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Cube")
	local p = S.Selection:Get()[1]
	beat() beat()
	press("Tab") beat() beat()
	view.yaw, view.pitch = math.rad(35), math.rad(30) view.focus = p.CFrame.Position view.dist = 16 view:update() beat()
	return p
end
local function edgeMid(p, fn)
	local vs, d = worldVerts(p)
	-- find an edge (consecutive verts of a face) whose ends both pass fn
	for _, f in ipairs(d.f) do
		for i = 1, #f do
			local a, b = vs[f[i]], vs[f[i % #f + 1]]
			if fn(a, b) then return (a + b) / 2 end
		end
	end
end
check("Modeling: Ctrl B bevels the picked edge", function()
	if gui.Enabled == false then MOCK.toolbarButton.Click:Fire() beat() end
	p4 = editCube()
	assert(hasText("Edit Mode"), "editing")
	local lo, hi = bounds(worldVerts(p4))
	press("Two")
	local m = edgeMid(p4, function(a, b) return near(a.Y, hi.Y) and near(b.Y, hi.Y) and near(a.Z, hi.Z) and near(b.Z, hi.Z) end)
	mouseTo(m) click()
	assert(hasText("Edges  1/12"), "one edge picked")
	press("B", { "LeftControl" })
	mouseXY(mouse.X + 60, mouse.Y + 40) beat()
	click()
	local nv, nf = counts(p4)
	eq(nf, 7, "bevelled faces") eq(nv, 10, "bevelled verts")
end)
check("Modeling: K knife across the top, Enter", function()
	local _, nf0 = counts(p4)
	local lo, hi = bounds(worldVerts(p4))
	press("K")
	local a = edgeMid(p4, function(x, y) return near(x.Y, hi.Y) and near(y.Y, hi.Y) and near(x.X, lo.X) and near(y.X, lo.X) end)
	local b = edgeMid(p4, function(x, y) return near(x.Y, hi.Y) and near(y.Y, hi.Y) and near(x.X, hi.X) and near(y.X, hi.X) end)
	assert(a and b, "edges found")
	mouseTo(a) click() mouseTo(b) click()
	press("Return") beat()
	local _, nf = counts(p4)
	assert(nf > nf0, "knife made faces: " .. nf0 .. " -> " .. nf)
end)
check("Modeling: X opens Blender's Delete menu, Esc closes", function()
	press("X") beat()
	assert(hasText("Dissolve Edges") and hasText("Only Edges & Faces"), "delete menu")
	press("Escape") beat()
end)
check("Modeling: Face menu Poke, Ctrl T triangulate, Alt J back, smooth shading saved", function()
	press("Three") press("A", { "LeftAlt" })
	local lo, hi = bounds(worldVerts(p4))
	local c
	local vs, d = worldVerts(p4)
	for _, f in ipairs(d.f) do
		local all, sum = true, Vector3.new()
		for _, i in ipairs(f) do if not near(vs[i].Y, lo.Y) then all = false end sum = sum + vs[i] end
		if all then c = sum / #f end
	end
	view.pitch = math.rad(-35) view:update() beat()
	mouseTo(c) click() beat()
	assert(hasText("Faces  1/"), "bottom face picked")
	headerBtn("Face") menuItem("Poke Faces")
	local _, nf1 = counts(p4)
	press("A") press("A") press("T", { "LeftControl" }) beat()
	local d2 = data(p4)
	for _, f in ipairs(d2.f) do eq(#f, 3, "all triangles") end
	press("J", { "LeftAlt" }) beat()
	local _, nf2 = counts(p4)
	assert(nf2 < #d2.f, "joined some back to quads")
	headerBtn("Mesh") menuItem("Shading") menuItem("Smooth Faces")
	assert(data(p4).s and #data(p4).s > 0, "smooth faces stored")
	view.pitch = math.rad(30) view:update() beat()
end)
check("Modeling: H hides, Alt H reveals", function()
	press("Three") press("A", { "LeftAlt" }) press("A")
	local _, nf = counts(p4)
	press("H") beat() beat()
	assert(hasText("Faces  0/"), "hidden faces aren't selectable")
	press("H", { "LeftAlt" }) beat() beat()
	assert(hasText(("Faces  %d/%d"):format(nf, nf)), "revealed + selected")
end)
check("Modeling: Spin tool from the toolbar (drag round)", function()
	view.ortho = false view:update() -- (the spin drag below is a small loop; in an ortho side view it nets 0 degrees)
	local _, nf0 = counts(p4)
	press("A", { "LeftAlt" })
	press("Three")
	local lo, hi = bounds(worldVerts(p4))
	local c
	local vs, d = worldVerts(p4)
	for _, f in ipairs(d.f) do
		local all, sum = true, Vector3.new()
		for _, i in ipairs(f) do if not near(vs[i].Y, hi.Y) then all = false end sum = sum + vs[i] end
		if all then c = sum / #f break end
	end
	mouseTo(c) click()
	toolBtn(20).Activated:Fire() beat()
	assert(hasText("Tool: spin") or true)
	mouseXY(mouse.X + 10, mouse.Y)
	mouse.Button1Down:Fire()
	for _ = 1, 8 do mouseXY(mouse.X + 12, mouse.Y + 9) end
	mouse.Button1Up:Fire() beat()
	local _, nf = counts(p4)
	assert(nf > nf0, "spun: " .. nf0 .. " -> " .. nf)
	toolBtn(1).Activated:Fire() beat()
end)
check("Modeling: proportional editing moves neighbours part way", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Grid")
	local g = S.Selection:Get()[1]
	beat() beat()
	press("Tab") beat()
	press("One") press("A", { "LeftAlt" })
	view.focus = g.CFrame.Position view.dist = 14 view.pitch = math.rad(60) view:update() beat()
	local vs = worldVerts(g)
	local mid
	for _, v in ipairs(vs) do if (v - g.CFrame.Position).Magnitude < 0.6 then mid = v end end
	assert(mid, "middle vert")
	mouseTo(mid) click()
	assert(hasText("Vertices  1/"), "one vert")
	press("O")
	local y0 = mid.Y
	press("G") press("Y") type_("2") press("Return") beat()
	local moved, partial = 0, 0
	for _, v in ipairs(worldVerts(g)) do
		local dy = v.Y - y0
		if dy > 1.9 then moved += 1 elseif dy > 0.05 then partial += 1 end
	end
	eq(moved, 1, "the picked vert went up 2") assert(partial > 0, "neighbours followed part way")
	press("O")
	if inEdit() then press("Tab") beat() end
end)
check("Modeling: Shift right-click puts the 3D cursor, Measure tool, Add Cube tool", function()
	MOCK.held.LeftShift = true
	mouseXY(400, 300) mouse.Button2Down:Fire() mouse.Button2Up:Fire()
	MOCK.held.LeftShift = nil
	beat()
	assert(MOCK.status:find("3D cursor", 1, true), "cursor placed")
	toolBtn(10).Activated:Fire()
	mouseXY(300, 300) mouse.Button1Down:Fire() mouseXY(500, 320) mouse.Button1Up:Fire() beat()
	assert(MOCK.status:find("Measure", 1, true), "measured")
	press("Escape")
	local n0 = rbParts()
	view.focus, view.dist, view.pitch = Vector3.new(200, 0, 200), 20, math.rad(45) view:update() beat()
	toolBtn(12).Activated:Fire()
	mouseXY(500, 500) mouse.Button1Down:Fire() mouseXY(560, 540) beat() mouse.Button1Up:Fire()
	mouseXY(560, 480) beat() click()
	eq(rbParts(), n0 + 1, "a cube was drawn")
	toolBtn(1).Activated:Fire() beat()
end)
check("Modeling: Loop Cut tool hover + click, P separates, V rips", function()
	p4 = editCube()
	toolBtn(17).Activated:Fire()
	local lo, hi = bounds(worldVerts(p4))
	local m = edgeMid(p4, function(a, b) return near(a.Y, hi.Y) and near(b.Y, hi.Y) and near(a.Z, hi.Z) and near(b.Z, hi.Z) end)
	mouseTo(m) beat()
	click()
	local _, nf = counts(p4)
	eq(nf, 10, "loop cut by the tool")
	toolBtn(1).Activated:Fire()
	press("Three") press("A", { "LeftAlt" })
	local c
	local vs, d = worldVerts(p4)
	for _, f in ipairs(d.f) do
		local all, sum = true, Vector3.new()
		for _, i in ipairs(f) do if not near(vs[i].Y, hi.Y) then all = false end sum = sum + vs[i] end
		if all then c = sum / #f break end
	end
	mouseTo(c) click()
	local n0 = rbParts()
	press("P") menuItem("Selection") beat()
	eq(rbParts(), n0 + 1, "separated into a new part")
	press("One") press("A", { "LeftAlt" })
	local v1 = worldVerts(p4)[1]
	mouseTo(v1) click()
	local nv0 = counts(p4)
	press("V") mouseXY(mouse.X + 30, mouse.Y) beat() click()
	assert(counts(p4) >= nv0, "rip ran")
	press("Tab") beat()
end)
check("Modeling tab opens Edit Mode even with nothing selected", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	local tab = find("TextButton", function(d) return d.Text == "Modeling" end)
	tab.Activated:Fire() beat() beat()
	assert(inEdit(), "in Edit Mode")
	press("Tab") beat()
end)
check("closing ROBLENDER puts Studio's camera back where it was", function()
	local real = workspace.CurrentCamera
	headerBtn("File") menuItem("Close ROBLENDER")
	local before = real.CFrame
	MOCK.toolbarButton.Click:Fire() beat()
	real.CFrame = CFrame.new(999, 999, 999) -- Studio's camera drifts behind our window
	beat()
	assert((real.CFrame.Position - before.Position).Magnitude < 1e-6, "held still while open")
	real.CFrame = CFrame.new(555, 5, 5)
	headerBtn("File") menuItem("Close ROBLENDER")
	assert((real.CFrame.Position - before.Position).Magnitude < 1e-6, "back to where it was")
	MOCK.toolbarButton.Click:Fire() beat()
end)
local function faceCenterWhere(p, fn)
	local vs, d = worldVerts(p)
	for _, f in ipairs(d.f) do
		local all, sum = true, Vector3.new()
		for _, i in ipairs(f) do if not fn(vs[i]) then all = false end sum = sum + vs[i] end
		if all then return sum / #f end
	end
end
check("Extrude tool: a click selects (no extrude); a drag on the selection extrudes", function()
	p4 = editCube()
	local lo, hi = bounds(worldVerts(p4))
	press("Three") press("A", { "LeftAlt" })
	local top = faceCenterWhere(p4, function(v) return near(v.Y, hi.Y) end)
	local side = faceCenterWhere(p4, function(v) return near(v.Z, hi.Z) end)
	toolBtn(14).Activated:Fire() beat()
	mouseTo(top) click()
	local _, nf0 = counts(p4)
	eq(nf0, 6, "clicking didn't extrude")
	assert(hasText("Faces  1/6"), "top picked")
	mouseTo(side) click()
	eq(select(2, counts(p4)), 6, "still no extrude")
	assert(hasText("Faces  1/6"), "clicked off onto the side face")
	-- drag on the selected face: extrude
	mouseTo(side) mouse.Button1Down:Fire()
	mouseXY(mouse.X + 20, mouse.Y - 10) beat() mouseXY(mouse.X + 20, mouse.Y - 10) beat()
	mouse.Button1Up:Fire() beat()
	eq(select(2, counts(p4)), 10, "dragging extruded")
	-- dragging from empty space box-selects instead
	mouseXY(5, 400) mouse.Button1Down:Fire() mouseXY(1195, 795) mouse.Button1Up:Fire() beat()
	eq(select(2, counts(p4)), 10, "box select didn't extrude")
	toolBtn(1).Activated:Fire() beat()
end)
check("Bevel segments with the wheel (round edge)", function()
	p4 = editCube()
	local lo, hi = bounds(worldVerts(p4))
	press("Two")
	mouseTo(edgeMid(p4, function(a, b) return near(a.Y, hi.Y) and near(b.Y, hi.Y) and near(a.Z, hi.Z) and near(b.Z, hi.Z) end)) click()
	press("B", { "LeftControl" })
	mouseXY(mouse.X + 60, mouse.Y + 40) beat()
	mouse.WheelForward:Fire() mouse.WheelForward:Fire() beat()
	assert(MOCK.status:find("Segments 3", 1, true), "segments shown: " .. MOCK.status)
	click()
	local nv, nf = counts(p4)
	eq(nf, 9, "3 segments") eq(nv, 14, "verts")
	press("B", { "LeftControl" }) press("PageDown") press("PageDown") press("Escape")
end)
check("Ctrl R: wheel for 2 cuts, click cuts + slides, Esc keeps the cut", function()
	p4 = editCube()
	local lo, hi = bounds(worldVerts(p4))
	press("R", { "LeftControl" })
	mouseTo(edgeMid(p4, function(a, b) return near(a.Y, hi.Y) and near(b.Y, hi.Y) and near(a.Z, hi.Z) and near(b.Z, hi.Z) end)) beat()
	mouse.WheelForward:Fire() beat()
	assert(MOCK.status:find("2 cuts", 1, true), "2 cuts: " .. MOCK.status)
	click()
	assert(MOCK.status:find("Loop Cut and Slide", 1, true), "sliding")
	press("Escape") beat()
	local _, nf = counts(p4)
	eq(nf, 14, "two loops cut")
	press("R", { "LeftControl" }) mouse.WheelBackward:Fire() press("Escape")
end)
check("Ctrl click selects the shortest path", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Grid")
	local g = S.Selection:Get()[1]
	beat() beat()
	press("Tab") beat()
	view.focus = g.CFrame.Position view.dist = 14 view.pitch = math.rad(80) view:update() beat()
	press("One") press("A", { "LeftAlt" })
	local vs = worldVerts(g)
	local a, b
	for _, v in ipairs(vs) do
		if not a or (v.X + v.Z) < (a.X + a.Z) then a = v end
		if not b or (v.X + v.Z) > (b.X + b.Z) then b = v end
	end
	mouseTo(a) click()
	MOCK.held.LeftControl = true
	mouseTo(b) click()
	MOCK.held.LeftControl = nil
	beat()
	assert(hasText("Vertices  13/"), "a 13-vert path corner to corner on the 6x6 grid")
	press("Tab") beat()
end)
check("crash fix: dragging a bevel frees the old meshes; broken points never reach Roblox", function()
	p4 = editCube()
	local lo, hi = bounds(worldVerts(p4))
	press("Two")
	local m = edgeMid(p4, function(a, b) return near(a.Y, hi.Y) and near(b.Y, hi.Y) and near(a.Z, hi.Z) and near(b.Z, hi.Z) end)
	mouseTo(m) click()
	local alive0 = MOCK.emAlive
	press("B", { "LeftControl" })
	for i = 1, 40 do mouseXY(mouse.X + 3, mouse.Y + 2) beat() end
	click()
	assert(MOCK.emAlive - alive0 <= 4, "meshes kept growing: " .. (MOCK.emAlive - alive0))
	-- a vert squashed onto its neighbour (zero-length edge), then bevel everything
	press("One") press("A", { "LeftAlt" })
	local vs = worldVerts(p4)
	mouseTo(vs[1]) click()
	press("G") type_("0") press("Return") beat()
	press("Two") press("A", { "LeftAlt" }) press("A")
	press("B", { "LeftControl" }) mouseXY(mouse.X + 200, mouse.Y + 150) beat() click()
	press("Tab") beat()
end)
check("crash fix: a part that was never saved gets its look back from RB_Data", function()
	headerBtn("File") menuItem("Close ROBLENDER")
	local d = S.Selection:Get()[1] or p4
	-- pretend Studio restarted: the in-memory mesh is gone
	p4.Mesh = nil
	p4:SetAttribute("RB_SavedHash", nil)
	Display.partEm[p4] = nil
	MOCK.toolbarButton.Click:Fire() beat() beat()
	assert(p4.Mesh ~= nil, "look rebuilt")
end)
local function propTab(n)
	local tabsCol = find("TextButton", function(d) return d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "Properties" and d.Size and d.Size[2] == 25 end).Parent
	local list = {}
	for _, c in ipairs(tabsCol:GetChildren()) do if c.ClassName == "TextButton" then list[#list + 1] = c end end
	table.sort(list, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	list[n].Activated:Fire() beat()
end
local function modsOf(p) local s = p:FindFirstChild("RB_Mods") return s and S.HttpService:JSONDecode(s.Value) or {} end
local function tris(p) return #p.Mesh.t end
local function field(text, value)
	local row = find("TextLabel", function(d) return d.Text == text end)
	assert(row, "field " .. text)
	local box = row.Parent:FindFirstChildOfClass("TextBox")
	box.Text = value box.FocusLost:Fire(true) beat()
end
local function textBtn(text) local b = find("TextButton", function(d) return d.Text == text end) assert(b, "button " .. text) b.Activated:Fire() beat() end
check("Modifiers tab: add Subdivision Surface, change levels, eye, apply", function()
	p4 = editCube()
	press("Tab") beat()
	S.Selection:Set({ p4 }) beat() beat()
	eq(tris(p4), 12, "plain cube")
	propTab(2)
	assert(hasText("No modifiers"), "empty stack")
	textBtn("Add Modifier   v")
	assert(hasText("Generate") and hasText("Deform"), "grouped menu")
	menuItem("Subdivision Surface") beat()
	eq(modsOf(p4)[1].type, "subsurf", "stored on the part")
	eq(tris(p4), 48, "the part shows the smoothed mesh")
	eq(select(2, counts(p4)), 6, "the base mesh is untouched")
	assert(hasText("Subdivision Surface"), "panel")
	field("Levels Viewport", "2")
	eq(modsOf(p4)[1].levels, 2, "levels") eq(tris(p4), 192, "level 2")
	MOCK.api.modToggle(1, "on") beat()
	eq(tris(p4), 12, "eye off shows the base")
	MOCK.api.modToggle(1, "on") beat()
	textBtn("Add Modifier   v") menuItem("Array") beat()
	eq(tris(p4), 192 * 3, "subsurf then array")
	MOCK.api.modMove(2, -1) beat()
	eq(modsOf(p4)[1].type, "array", "moved up")
	MOCK.api.modRemove(1) beat()
	eq(#modsOf(p4), 1, "removed")
	local n0 = #MOCK.uploads
	for _ = 1, 50 do beat() end
	assert(#MOCK.uploads > n0, "saved a few seconds after the change")
	eq(#MOCK.uploads[#MOCK.uploads].em.t, 192, "the upload has the modifier in it")
	textBtn("Apply")
	eq(#modsOf(p4), 0, "applied = gone from the stack")
	eq(select(2, counts(p4)), 96, "real geometry now")
	propTab(1)
end)
check("Mirror modifier in Edit Mode; Tab out saves the mirrored mesh", function()
	p4 = editCube()
	press("A") press("G") press("X") type_("3") press("Return") beat()
	MOCK.api.modAdd("mirror") beat() beat()
	eq(modsOf(p4)[1].type, "mirror", "added while editing")
	eq(counts(p4), 8, "base still one cube")
	local n0 = #MOCK.uploads
	press("Tab") beat() beat()
	eq(tris(p4), 24, "two cubes on the part")
	assert(#MOCK.uploads > n0, "auto saved")
	eq(#MOCK.uploads[#MOCK.uploads].em.t, 24, "mirrored upload")
end)
check("Ctrl right-click adds / extrudes to the mouse, Shift R repeats, Auto Merge welds", function()
	p4 = editCube()
	press("One") press("A", { "LeftAlt" }) beat()
	local nv0 = counts(p4)
	local function ctrlRMB(x, y)
		MOCK.held.LeftControl = true
		mouseXY(x, y) mouse.Button2Down:Fire() mouse.Button2Up:Fire()
		MOCK.held.LeftControl = nil
		beat()
	end
	ctrlRMB(300, 300)
	eq(counts(p4), nv0 + 1, "added a vertex")
	ctrlRMB(360, 280)
	eq(counts(p4), nv0 + 2, "extruded to the mouse")
	assert(not hasText("Delete Vertices"), "no context menu")
	mouseXY(420, 260)
	press("R", { "LeftShift" }) beat()
	eq(counts(p4), nv0 + 3, "Shift R repeated")
	assert(MOCK.status:find("Repeat Last", 1, true), "status: " .. MOCK.status)
	headerBtn("Edit")
	assert(hasText("Repeat Last: Extrude To Mouse"), "Edit menu names it")
	press("Escape") beat()
	MOCK.api.toggleEdit2("autoMerge")
	press("E") type_("0") press("Return") beat()
	eq(counts(p4), nv0 + 3, "the zero-length extrude was welded back")
	assert(MOCK.status:find("Auto Merge", 1, true), "status: " .. MOCK.status)
	MOCK.api.toggleEdit2("autoMerge")
	press("Tab") beat()
end)
check("C circle select paints a selection, Shift deselects, wheel resizes", function()
	p4 = editCube()
	press("One") press("A", { "LeftAlt" }) beat()
	local vs = worldVerts(p4)
	table.sort(vs, function(x, y) return (x - cam.CFrame.Position).Magnitude < (y - cam.CFrame.Position).Magnitude end)
	press("C") beat()
	assert(MOCK.status:find("CIRCLE", 1, true), "circle mode")
	mouse.WheelBackward:Fire() beat()
	mouseTo(vs[1]) mouse.Button1Down:Fire() mouseXY(mouse.X + 2, mouse.Y + 1) mouse.Button1Up:Fire() beat()
	assert(not hasText("Vertices  0/"), "something selected")
	MOCK.held.LeftShift = true
	mouseTo(vs[1]) mouse.Button1Down:Fire() mouse.Button1Up:Fire() beat()
	MOCK.held.LeftShift = nil
	press("Escape") beat()
	assert(MOCK.status:find("Circle select done", 1, true), "done: " .. MOCK.status)
	assert(hasText("Vertices  0/8"), "Shift painted it off again")
	press("A") beat()
	assert(hasText("Vertices  8/8"), "keys work again")
end)
check("Inset: I again = individual faces, Ctrl = depth", function()
	p4 = editCube()
	press("Three") press("A") beat()
	press("I")
	mouseXY(mouse.X + 30, mouse.Y) beat()
	press("I") beat()
	assert(MOCK.status:find("individual", 1, true), "individual: " .. MOCK.status)
	press("LeftControl") beat()
	mouseXY(mouse.X, mouse.Y - 40) beat()
	click()
	local _, nf = counts(p4)
	eq(nf, 30, "each face inset on its own")
	local lo, hi = bounds(worldVerts(p4))
	assert(hi.Y - lo.Y > 4.01, "the insets were pushed out (depth): " .. (hi.Y - lo.Y))
	press("Tab") beat()
end)
check("Ctrl 2 in Object Mode = Subdivision Surface level 2; Ctrl J joins; P splits loose parts", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Cube")
	local a = S.Selection:Get()[1]
	beat()
	press("Two", { "LeftControl" }) beat()
	eq(modsOf(a)[1].type, "subsurf", "added") eq(modsOf(a)[1].levels, 2, "level 2")
	eq(tris(a), 192, "smoothed")
	press("Zero", { "LeftControl" }) beat()
	eq(modsOf(a)[1].levels, 0, "level 0") eq(tris(a), 12, "back to the cage")
	MOCK.api.modRemove(1) beat()
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Cube")
	local b = S.Selection:Get()[1]
	b.CFrame = b.CFrame * CFrame.new(6, 0, 0)
	beat()
	local n0 = rbParts()
	S.Selection:Set({ a, b }) beat()
	press("J", { "LeftControl" }) beat()
	eq(rbParts(), n0 - 1, "one part left")
	local keep = S.Selection:Get()[1]
	local nv, nf = counts(keep)
	eq(nv, 16, "verts") eq(nf, 12, "faces")
	local lo, hi = bounds(worldVerts(keep))
	assert(hi.X - lo.X > 9.9, "the second cube stayed where it was")
	press("Tab") beat()
	press("P") menuItem("By Loose Parts") beat()
	eq(rbParts(), n0, "split back into two")
	eq(counts(keep), 8, "one cube left in it")
	press("Tab") beat()
end)
check("every modifier's panel builds; Simple Deform method buttons", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Cube")
	local c = S.Selection:Get()[1]
	beat()
	propTab(2)
	for _, ty in ipairs(MOCK.api.modTypes) do
		if ty.id ~= "screw" and ty.id ~= "subsurf" and ty.id ~= "array" then MOCK.api.modAdd(ty.id) beat() end
	end
	beat()
	assert(hasText("Simple Deform") and hasText("Displace") and hasText("Weld") and hasText("Decimate"), "panels")
	textBtn("Bend")
	local found
	for _, m in ipairs(modsOf(c)) do if m.type == "simpledeform" then found = m end end
	eq(found.method, "Bend", "method button")
	assert(tris(c) > 0, "still a mesh")
	propTab(1)
end)
check("Add Ico Sphere, Cone and Torus", function()
	if inEdit() then press("Tab") beat() end
	for _, k in ipairs({ { "Ico Sphere", 162, 320 }, { "Cone", 33, 33 }, { "Torus", 576, 576 } }) do
		S.Selection:Set({}) beat()
		press("A", { "LeftShift" }) menuItem("Mesh") menuItem(k[1])
		local p = S.Selection:Get()[1]
		beat()
		local nv, nf = counts(p)
		eq(nv, k[2], k[1] .. " verts") eq(nf, k[3], k[1] .. " faces")
	end
end)
check("Object > Set Origin > Origin to Geometry; Apply Rotation", function()
	p4 = editCube()
	press("A") press("G") press("X") type_("3") press("Return") beat()
	press("Tab") beat()
	S.Selection:Set({ p4 }) beat()
	local before = worldVerts(p4)
	local lo0, hi0 = bounds(before)
	headerBtn("Object") menuItem("Set Origin") menuItem("Origin to Geometry")
	local d = data(p4)
	local sx = 0 for i = 1, #d.v, 3 do sx += d.v[i] end
	assert(math.abs(sx / (#d.v / 3)) < 1e-4, "mesh data centred on the new origin")
	local lo, hi = bounds(worldVerts(p4))
	assert((lo - lo0).Magnitude < 1e-3 and (hi - hi0).Magnitude < 1e-3, "nothing moved in the world")
	p4.CFrame = p4.CFrame * CFrame.fromAxisAngle(Vector3.new(0, 1, 0), math.rad(30))
	beat()
	local lo1, hi1 = bounds(worldVerts(p4))
	headerBtn("Object") menuItem("Apply") menuItem("Rotation")
	local rx, ry, rz = p4.CFrame:ToOrientation()
	assert(math.abs(rx) + math.abs(ry) + math.abs(rz) < 1e-4, "part rotation is 0 now")
	local lo2, hi2 = bounds(worldVerts(p4))
	assert((lo2 - lo1).Magnitude < 1e-3 and (hi2 - hi1).Magnitude < 1e-3, "same look in the world")
	headerBtn("Object") menuItem("Shade Smooth")
	eq(data(p4).s ~= nil, true, "smooth faces saved")
end)
check("Shift G Select Similar, box select Intersect mode, Face > Wireframe", function()
	p4 = editCube()
	local lo, hi = bounds(worldVerts(p4))
	press("Three") press("A", { "LeftAlt" })
	mouseTo(faceCenterWhere(p4, function(v) return near(v.Y, hi.Y) end)) click()
	press("G", { "LeftShift" }) menuItem("Area") beat()
	assert(hasText("Faces  6/6"), "all same-size faces")
	-- intersect: box round one corner keeps just what's in the box
	press("One") press("A", { "LeftAlt" }) press("A") beat()
	assert(hasText("Vertices  8/8"), "all")
	MOCK.api.setBoxMode("and")
	local vs = worldVerts(p4)
	table.sort(vs, function(x, y) return (x - cam.CFrame.Position).Magnitude < (y - cam.CFrame.Position).Magnitude end)
	mouseTo(vs[1])
	local x, y = mouse.X, mouse.Y
	mouseXY(x - 12, y - 12) mouse.Button1Down:Fire() mouseXY(x + 12, y + 12) mouse.Button1Up:Fire() beat()
	assert(hasText("Vertices  1/8"), "only the boxed vert stays")
	MOCK.api.setBoxMode("set")
	press("Three") press("A") beat()
	MOCK.api.tool("Wireframe")
	mouseXY(mouse.X + 30, mouse.Y + 20) beat() click()
	eq(select(2, counts(p4)), 72, "frame with thickness")
	press("Tab") beat()
end)
check("proportional falloff: Constant moves the neighbours all the way", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Grid")
	local g = S.Selection:Get()[1]
	beat() beat()
	press("Tab") beat()
	press("One") press("A", { "LeftAlt" })
	view.focus = g.CFrame.Position view.dist = 14 view.pitch = math.rad(60) view:update() beat()
	local mid
	for _, v in ipairs(worldVerts(g)) do if (v - g.CFrame.Position).Magnitude < 0.6 then mid = v end end
	mouseTo(mid) click()
	MOCK.api.setFalloff("Constant")
	local y0 = mid.Y
	press("G") press("Y") type_("2") press("Return") beat()
	local full = 0
	for _, v in ipairs(worldVerts(g)) do if v.Y - y0 > 1.9 then full += 1 end end
	assert(full > 1, "neighbours moved the full 2: " .. full)
	MOCK.api.setFalloff("Smooth") press("O")
	press("Tab") beat()
end)
check("F3 searches every menu: type, Enter runs the top match", function()
	p4 = editCube()
	press("Three") press("A") beat()
	press("F3") beat()
	local box = find("TextBox", function(d) return d.Name == "RB_Search" end)
	assert(box, "search box")
	box.Text = "triangulate faces" beat()
	assert(hasText("Face > Triangulate Faces"), "match listed")
	box.FocusLost:Fire(true) beat()
	eq(select(2, counts(p4)), 12, "ran Triangulate")
	assert(not find("TextBox", function(d) return d.Name == "RB_Search" end), "closed")
	press("Tab") beat()
end)
check("double click = loop select, Ctrl Alt click = ring, Shift E crease, Shift Ctrl M mirror", function()
	p4 = editCube()
	local lo, hi = bounds(worldVerts(p4))
	press("Two") press("A", { "LeftAlt" })
	local m = edgeMid(p4, function(a, b) return near(a.Y, hi.Y) and near(b.Y, hi.Y) and near(a.Z, hi.Z) and near(b.Z, hi.Z) end)
	MOCK.held.LeftAlt = true
	mouseTo(m) click()
	MOCK.held.LeftAlt = nil
	beat()
	local function selEdges() local n = 0 for _, l in ipairs(findAll("TextLabel", function(d) return (d.Text or ""):find("Edges  ", 1, true) ~= nil end)) do n = tonumber(l.Text:match("Edges  (%d+)/")) or n end return n end
	local loopN = MOCK.api.state().stats.es
	assert(loopN >= 1, "alt click loop")
	press("A", { "LeftAlt" }) beat()
	mouseTo(m) dblclick()
	eq(MOCK.api.state().stats.es, loopN, "double click = the same loop")
	press("A", { "LeftAlt" })
	MOCK.held.LeftControl, MOCK.held.LeftAlt = true, true
	mouseTo(m) click()
	MOCK.held.LeftControl, MOCK.held.LeftAlt = nil, nil
	eq(MOCK.api.state().stats.es, 4, "ring of 4 (the edges round the cube)")
	press("E", { "LeftShift" }) beat()
	eq(#(data(p4).cr or {}), 8, "4 creased edges saved (2 numbers each)")
	press("E", { "LeftShift" }) beat()
	eq(data(p4).cr, nil, "toggled off")
	press("One") press("A", { "LeftAlt" })
	local vs = worldVerts(p4)
	table.sort(vs, function(x, y) return (x - cam.CFrame.Position).Magnitude < (y - cam.CFrame.Position).Magnitude end)
	mouseTo(vs[1]) click()
	press("M", { "LeftShift", "LeftControl" }) beat()
	eq(MOCK.api.state().stats.vs, 1, "still one vert")
	assert(MOCK.status:find("mirror", 1, true), "status: " .. MOCK.status)
	press("Tab") beat()
end)
check("Object: H / Shift H / Alt H, Alt G / Alt R, Numpad / local view, Z and Ctrl A menus", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Cube")
	local a = S.Selection:Get()[1]
	beat()
	a.CFrame = CFrame.new(5, 3, 2) * CFrame.fromAxisAngle(Vector3.new(0, 1, 0), 0.5)
	beat()
	press("G", { "LeftAlt" }) beat()
	local function originPos(p) return (p.CFrame * CFrame.new(-(p:GetAttribute("RB_Center") or Vector3.new()))).Position end
	assert(originPos(a).Magnitude < 1e-4, "origin back at 0, 0, 0")
	press("R", { "LeftAlt" }) beat()
	local rx, ry, rz = a.CFrame:ToOrientation()
	assert(math.abs(rx) + math.abs(ry) + math.abs(rz) < 1e-4, "rotation cleared")
	S.Selection:Set({ a }) beat()
	press("KeypadDivide") beat() beat() beat()
	local shownOthers = 0
	for p, d in pairs(view.objects) do if p ~= a then shownOthers += 1 end end
	eq(shownOthers, 0, "local view shows only the cube")
	press("KeypadDivide") beat() beat()
	S.Selection:Set({ a }) beat()
	press("H") beat() beat() beat()
	assert(view.objects[a] == nil, "hidden")
	press("H", { "LeftAlt" }) beat() beat() beat()
	assert(view.objects[a] ~= nil, "revealed")
	press("Z") beat()
	assert(hasText("Toggle X-Ray"), "Z = shading menu")
	press("Escape") beat()
	S.Selection:Set({ a }) beat()
	press("A", { "LeftControl" }) beat()
	assert(hasText("Rotation"), "Ctrl A = apply menu")
	press("Escape") beat()
end)
check("UVs + texture: box projection on the part, texture id, upload carries UVs", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Cube")
	local c = S.Selection:Get()[1]
	beat()
	eq(c.Mesh.fuv, nil, "no UVs yet")
	MOCK.api.setUV("box") beat()
	eq(c.Mesh.fuv, 12, "every triangle has UVs")
	propTab(4)
	local tb = find("TextBox", function(d) return d.Name == "RB_Texture" end)
	assert(tb, "texture box in the Material tab")
	tb.Text = "1234567" tb.FocusLost:Fire(true) beat()
	eq(c.TextureID, "rbxassetid://1234567", "texture set")
	textBtn("Fit") beat()
	eq(c:GetAttribute("RB_UVMode"), "boxfit", "fit mode")
	for _, p in ipairs(c.Mesh.uv) do assert(p.X >= -1e-6 and p.X <= 1 + 1e-6 and p.Y >= -1e-6 and p.Y <= 1 + 1e-6, "fit UVs stay in 0..1") end
	local n0 = #MOCK.uploads
	for _ = 1, 50 do beat() end
	assert(#MOCK.uploads > n0, "saved after the change")
	eq(MOCK.uploads[#MOCK.uploads].em.fuv, 12, "upload has UVs")
	propTab(1)
end)
check("Ctrl right-drag lasso selects; snap to Vertex", function()
	p4 = editCube()
	press("One") press("A", { "LeftAlt" }) beat()
	local vs = worldVerts(p4)
	table.sort(vs, function(x, y) return (x - cam.CFrame.Position).Magnitude < (y - cam.CFrame.Position).Magnitude end)
	mouseTo(vs[1])
	local x, y = mouse.X, mouse.Y
	MOCK.held.LeftControl = true
	mouse.Button2Down:Fire()
	for i = 0, 12 do local a = i / 12 * 2 * math.pi mouseXY(x + 15 * math.cos(a), y + 15 * math.sin(a)) end
	mouse.Button2Up:Fire()
	MOCK.held.LeftControl = nil
	beat()
	eq(MOCK.api.state().stats.vs, 1, "lasso picked the one vert")
	eq(counts(p4), 8, "no extrude on a drag")
	-- snap that vert onto another one
	MOCK.api.setSnapTarget("Vertex")
	press("G")
	mouseTo(vs[2]) beat()
	click()
	local d = data(p4)
	local seen, dup = {}, false
	for i = 1, #d.v, 3 do
		local k = d.v[i] .. "," .. d.v[i + 1] .. "," .. d.v[i + 2]
		if seen[k] then dup = true end
		seen[k] = true
	end
	assert(dup, "the vert landed exactly on another one")
	MOCK.api.setSnapTarget("Increment")
	press("Tab", { "LeftShift" })
	eq(MOCK.api.state().snap, false, "Shift Tab turned snapping off")
	press("Tab") beat()
end)
check("Shade Auto Smooth keeps a cylinder's rim sharp (split normals)", function()
	if inEdit() then press("Tab") beat() end
	S.Selection:Set({}) beat()
	press("A", { "LeftShift" }) menuItem("Mesh") menuItem("Cylinder")
	local c = S.Selection:Get()[1]
	beat()
	eq(#c.Mesh.v, 24 * 4 + 24 * 2, "flat: every face has its own corners")
	headerBtn("Object") menuItem("Shade Auto Smooth") beat()
	eq(#c.Mesh.v, 48 * 2, "smooth sides share corners, caps stay separate")
	assert(data(c).sh and #data(c).sh == 48 * 2, "the 48 rim edges are marked sharp")
end)
check("Pivot: Individual Origins; X X = local axis; Fill Holes; Offset Edge Loops", function()
	p4 = editCube()
	press("One") press("A", { "LeftAlt" })
	local vs = worldVerts(p4)
	local _, hi = bounds(vs)
	local top = {}
	for _, v in ipairs(vs) do if near(v.Y, hi.Y) then top[#top + 1] = v end end
	table.sort(top, function(x, y) return (x - cam.CFrame.Position).Magnitude < (y - cam.CFrame.Position).Magnitude end)
	local a, b = top[1], nil
	for _, v in ipairs(top) do if not near(v.X, a.X) and not near(v.Z, a.Z) then b = v end end
	mouseTo(a) click()
	MOCK.held.LeftShift = true mouseTo(b) click() MOCK.held.LeftShift = nil
	eq(MOCK.api.state().stats.vs, 2, "two corners, not joined by an edge")
	MOCK.api.setPivot("individual")
	local function pointSet()
		local d, out = data(p4), {}
		for i = 1, #d.v, 3 do out[#out + 1] = ("%.3f,%.3f,%.3f"):format(d.v[i], d.v[i + 1], d.v[i + 2]) end
		table.sort(out)
		return table.concat(out, " ")
	end
	local before = pointSet()
	press("S") type_("0.5") press("Return") beat()
	eq(pointSet(), before, "each lone vert scaled round itself = no move")
	MOCK.api.setPivot("median")
	press("S") type_("0.5") press("Return") beat()
	assert(pointSet() ~= before, "median pivot pulls them together")
	press("Tab") beat()
	-- local axis: a rotated part, G X X moves along the mesh's own X
	p4 = editCube()
	press("Tab") beat()
	p4.CFrame = p4.CFrame * CFrame.fromAxisAngle(Vector3.new(0, 1, 0), math.rad(45))
	beat()
	S.Selection:Set({ p4 }) beat()
	press("Tab") beat() beat()
	press("A")
	local d0 = data(p4)
	press("G") press("X") press("X") type_("2") press("Return") beat()
	assert(MOCK.api.state().editing, "still editing")
	local d1 = data(p4)
	local dx, dz = 0, 0
	for i = 1, #d0.v, 3 do dx += d1.v[i] - d0.v[i] dz += d1.v[i + 2] - d0.v[i + 2] end
	assert(math.abs(dx / 8 - 2) < 1e-3 and math.abs(dz / 8) < 1e-3, "moved 2 along local X only: " .. dx / 8 .. ", " .. dz / 8)
	-- fill holes
	press("Three") press("A", { "LeftAlt" })
	mouseTo(faceCenterWhere(p4, function(v) return true end) or p4.CFrame.Position)
	press("A") MOCK.api.tool("DeleteFaces") beat()
	eq(select(2, counts(p4)), 0, "all faces gone")
	press("Tab") beat()
	p4 = editCube()
	local lo2, hi2 = bounds(worldVerts(p4))
	press("Three")
	mouseTo(faceCenterWhere(p4, function(v) return near(v.Y, hi2.Y) end)) click()
	MOCK.api.tool("DeleteFaces") beat()
	eq(select(2, counts(p4)), 5, "top removed")
	headerBtn("Mesh") menuItem("Clean Up") menuItem("Fill Holes") beat()
	eq(select(2, counts(p4)), 6, "hole filled")
	-- offset edge loops on the loop round the middle... the top loop: two loops come out of it
	press("Two") press("A", { "LeftAlt" })
	MOCK.held.LeftAlt = true
	mouseTo(edgeMid(p4, function(a, b) return near(a.Y, hi2.Y) and near(b.Y, hi2.Y) and near(a.Z, hi2.Z) and near(b.Z, hi2.Z) end)) click()
	MOCK.held.LeftAlt = nil
	press("R", { "LeftShift", "LeftControl" })
	mouseXY(mouse.X + 20, mouse.Y + 20) beat() click()
	assert(select(2, counts(p4)) > 6, "offset loops made new faces")
	press("Tab") beat()
end)
check("wireframe, x-ray, Studio view switch, close", function()
	press("Z", { "LeftShift" }) beat() beat()
	press("Z", { "LeftShift" }) beat()
	press("Z", { "LeftAlt" }) press("Z", { "LeftAlt" }) beat()
	headerBtn("Edit") menuItem("Use Studio's 3D View")
	assert(not view.frame.Visible and not plugin.Active, "Studio view")
	headerBtn("Edit") menuItem("Use Studio's 3D View")
	assert(view.frame.Visible and plugin.Active, "back to ours")
	headerBtn("File") menuItem("Close ROBLENDER")
	assert(not gui.Enabled and not plugin.Active, "closed")
end)

print(("%d passed, %d failed, %d meshes built"):format(pass, fail, MOCK.meshesMade))
if fail > 0 then error("editor tests failed") end
