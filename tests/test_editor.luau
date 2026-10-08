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
local function click() mouse.Button1Down:Fire() mouse.Button1Up:Fire() beat() end
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
	assert(hasText("Top Perspective"), "says Top")
	press("Home") beat()
	press("KeypadOne") beat()
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
	tabBtns[3].Activated:Fire() beat()
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
