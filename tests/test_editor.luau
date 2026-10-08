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
local function beat() MOCK.t += 0.1 S.RunService.Heartbeat:Fire() end
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

-- ===== the Blender-style screen =====
local gui
local function find(class, pred)
	for _, d in ipairs(gui:GetDescendants()) do if d.ClassName == class and pred(d) then return d end end
end
local function menuItem(label)
	local l = find("TextLabel", function(d) return d.Text == label and d.Parent and d.Parent.ClassName == "TextButton" and d.Parent.ZIndex == 21 end)
	assert(l, "menu item " .. label)
	l.Parent.Activated:Fire()
	beat()
end
check("plugin button opens the Blender screen", function()
	MOCK.toolbarButton.Click:Fire()
	gui = S.CoreGui:FindFirstChild("ROBLENDER_UI")
	assert(gui and gui.Enabled, "screen on")
	beat()
	assert(find("TextLabel", function(d) return (d.Text or ""):find("Object Mode") ~= nil end), "says Object Mode")
end)
local p2
check("Shift A menu adds a cube, Tab edits it, stats show", function()
	press("A", { "LeftShift" })
	menuItem("Cube")
	p2 = S.Selection:Get()[1]
	assert(p2 and p2.Name == "ROBLENDER Cube", "added")
	press("Tab") beat()
	beat()
	assert(find("TextLabel", function(d) return (d.Text or ""):find("Vertices  0/8") ~= nil end), "stats")
end)
check("header: face mode button, Mesh menu extrude, Esc", function()
	find("TextButton", function(d) return d.Text == "Select" and d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "Header" end).Activated:Fire()
	menuItem("All")
	MOCK.buttons["Mesh"].Activated:Fire()
	menuItem("Subdivide")
	local _, nf = counts(p2)
	eq(nf, 24, "subdivided all 6 faces")
	MOCK.buttons["Extrude"].Activated:Fire()
	beat()
	assert(find("TextLabel", function(d) return (d.Text or ""):find("MOVE") ~= nil and d.Parent and d.Parent.Visible end), "operator header shows")
	press("Escape") beat()
end)
check("Shift A in edit mode adds into the mesh", function()
	local nv0 = counts(p2)
	press("A", { "LeftShift" })
	menuItem("Plane")
	eq(counts(p2), nv0 + 4, "4 more verts")
	beat()
	assert(find("TextLabel", function(d) return (d.Text or ""):find("Vertices  4/") ~= nil end), "the plane is selected")
end)
check("sidebar: type a median Y moves the selection", function()
	local boxes = {}
	for _, d in ipairs(gui:GetDescendants()) do if d.ClassName == "TextBox" then boxes[#boxes + 1] = d end end
	eq(#boxes, 6, "6 fields")
	local ybox = boxes[2]
	ybox.Text = "50"
	ybox.FocusLost:Fire(true)
	beat()
	local _, hi = bounds(worldVerts(p2))
	assert(near(hi.Y, 50, 1e-2), "plane moved to Y 50: " .. hi.Y)
end)
check("N, T, View menu, X-ray button, help, close", function()
	press("N") press("N") press("T") press("T")
	MOCK.buttons["X-Ray"].Activated:Fire()
	MOCK.buttons["?"].Activated:Fire()
	press("Escape")
	MOCK.buttons["View"].Activated:Fire()
	menuItem("Sidebar")
	MOCK.toolbarButton.Click:Fire()
	beat()
	assert(not gui.Enabled, "screen off")
	assert(not plugin.Active, "left edit mode")
end)

print(("%d passed, %d failed, %d meshes built"):format(pass, fail, MOCK.meshesMade))
if fail > 0 then error("editor tests failed") end
