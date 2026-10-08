--[[
	ROBLENDER - a free, open-source mesh editor for Roblox Studio
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27). Mesh engine converted from Blender's BMesh
	(Copyright (C) Blender Authors, GPL-2.0-or-later). Not made or endorsed by the Blender Foundation.

	This program is free software; you can redistribute it and/or modify it under the terms of the GNU
	General Public License as published by the Free Software Foundation; either version 2 of the License,
	or (at your option) any later version. It comes WITHOUT ANY WARRANTY. See LICENSE.

	Keys (edit mode, like Blender): Tab edit on/off | 1 2 3 vertex / edge / face | click, Shift-click,
	drag a box, Alt-click = loop | A all, Alt+A none, Ctrl+I invert | G move, S scale, R rotate
	(then X / Y / Z to lock, type a number, Ctrl = snap, click / Enter = done, Esc / right-click = cancel)
	| E extrude | I inset | Ctrl+R loop cut | X / Delete delete | M merge | F fill | Alt+Z x-ray
]]

local NAME = "ROBLENDER"
local VERSION = "0.2.0"

local BMesh = require(script.BMesh)
local Ops = require(script.Ops)
local Display = require(script.Display)
local UI = require(script.UI)

local Selection = game:GetService("Selection")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CHS = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local V3 = Vector3.new
local TERRAIN = workspace:FindFirstChildOfClass("Terrain")
local SEL_COL = Color3.fromRGB(255, 150, 40)
local ACT_COL = Color3.fromRGB(255, 255, 255)
local WIRE_COL = Color3.fromRGB(20, 20, 24)

-- ===== state =====
local obj = nil          -- the MeshPart being edited
local bm = nil           -- its mesh
local origin = CFrame.identity
local editing = false
local mode = "vert"      -- vert / edge / face
local xray = false
local modal = nil        -- the running G / S / R / inset / loop cut
local hover = nil
local lastWritten = nil
local dirtyMesh, dirtyCage, lastBuild = false, false, 0
local worldTris = nil    -- cache for picking
local dataConn = nil
local ui = nil            -- the Blender-style screen (UI.lua)

-- ===== UI =====
local toolbar = plugin:CreateToolbar(NAME)
local btnMain = toolbar:CreateButton(NAME, "Open " .. NAME .. " - Blender-style mesh editing (free, open source)", "rbxassetid://0", NAME)
btnMain.ClickableWhenViewportHidden = true
local widget = plugin:CreateDockWidgetPluginGui(NAME .. "_Panel", DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 270, 520, 230, 300))
widget.Title = NAME .. " " .. VERSION

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.fromScale(1, 1)
scroll.BackgroundColor3 = Color3.fromRGB(36, 37, 43)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = widget
local list = Instance.new("UIListLayout") list.Padding = UDim.new(0, 4) list.SortOrder = Enum.SortOrder.LayoutOrder list.Parent = scroll
local pad = Instance.new("UIPadding") pad.PaddingLeft = UDim.new(0, 8) pad.PaddingRight = UDim.new(0, 8) pad.PaddingTop = UDim.new(0, 8) pad.Parent = scroll
local order = 0
local function nextOrder() order += 1 return order end
local function label(text, size, col)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = nextOrder()
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.GothamMedium
	l.TextSize = size or 12
	l.TextColor3 = col or Color3.fromRGB(220, 222, 230)
	l.Text = text
	l.Parent = scroll
	return l
end
local function row()
	local f = Instance.new("Frame")
	f.LayoutOrder = nextOrder()
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, 26)
	local h = Instance.new("UIListLayout") h.FillDirection = Enum.FillDirection.Horizontal h.Padding = UDim.new(0, 4) h.Parent = f
	f.Parent = scroll
	return f
end
local buttons = {}
local function button(parent, text, w, fn, col)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 1, 0)
	b.BackgroundColor3 = col or Color3.fromRGB(58, 61, 72)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = b
	b.Parent = parent
	b.Activated:Connect(function()
		local ok, err = pcall(fn)
		if not ok then warn(NAME .. ": " .. tostring(err)) end
	end)
	buttons[text] = b
	return b
end

label(NAME .. " " .. VERSION, 16, Color3.fromRGB(255, 170, 80))
label("Free + open source mesh editor (GPL). Mesh engine converted from Blender. Not made by the Blender Foundation.", 10, Color3.fromRGB(150, 155, 170))
local status = label("Add a shape, or click a " .. NAME .. " part and press Tab.", 12, Color3.fromRGB(140, 220, 255))
local lastStatus = ""
local function setStatus(t) status.Text = t lastStatus = t if ui then ui:setReport(t) end end

-- ===== saving on the part =====
local function isRB(p) return p and p:IsA("MeshPart") and p:FindFirstChild("RB_Data") ~= nil end
local function dataOf(p) return p:FindFirstChild("RB_Data") end

local function encode(b) return HttpService:JSONEncode(b:toData()) end

local function loadFrom(p)
	local d = HttpService:JSONDecode(dataOf(p).Value)
	local m = BMesh.fromData(d)
	-- the part was scaled in Studio: scale the mesh to match
	local stored = p:GetAttribute("RB_Size")
	if typeof(stored) == "Vector3" then
		local sx = stored.X > 1e-4 and p.Size.X / stored.X or 1
		local sy = stored.Y > 1e-4 and p.Size.Y / stored.Y or 1
		local sz = stored.Z > 1e-4 and p.Size.Z / stored.Z or 1
		if math.abs(sx - 1) + math.abs(sy - 1) + math.abs(sz - 1) > 1e-3 then
			local c = p:GetAttribute("RB_Center") or V3()
			for v in pairs(m.verts) do v.co = c + (v.co - c) * V3(sx, sy, sz) end
			m:normalsUpdate()
			return m, true
		end
	end
	return m, false
end

local function originOf(p)
	local c = p:GetAttribute("RB_Center") or V3()
	return p.CFrame * CFrame.new(-c)
end

-- put the mesh on the part (new look). Keeps the part where its origin is.
local function applyMesh(p, b, tint)
	local mp, c, err = Display.build(b, tint and SEL_COL or nil)
	if not mp then return false, err end
	local o = originOf(p)
	local ok = pcall(function() p:ApplyMesh(mp) end)
	if not ok then
		-- older Studio: swap the part out for the new one
		mp.Name, mp.Color, mp.Material, mp.Anchored = p.Name, p.Color, p.Material, p.Anchored
		for _, ch in ipairs(p:GetChildren()) do ch.Parent = mp end
		for k, v in pairs(p:GetAttributes()) do mp:SetAttribute(k, v) end
		mp.Parent = p.Parent
		p.Parent = nil
		if obj == p then obj = mp end
		p = mp
	else
		p.Size = mp.Size
		mp:Destroy()
	end
	p.CFrame = o * CFrame.new(c)
	p:SetAttribute("RB_Center", c)
	p:SetAttribute("RB_Size", p.Size)
	return true, nil, p
end

-- ===== world helpers =====
local function W(co) return origin * co end
local function camera() return workspace.CurrentCamera end
local function toScreen(wp)
	local sp, vis = camera():WorldToViewportPoint(wp)
	return Vector2.new(sp.X, sp.Y), vis and sp.Z > 0, sp.Z
end
local mouse = plugin:GetMouse()
local function mousePos() return Vector2.new(mouse.X, mouse.Y) end

local function buildWorldTris()
	worldTris = {}
	for _, t in ipairs(Display.triangles(bm)) do
		worldTris[#worldTris + 1] = { W(t[1]), W(t[2]), W(t[3]), t[4] }
	end
end
-- Moller-Trumbore
local function rayTri(o, d, a, b, c)
	local e1, e2 = b - a, c - a
	local p = d:Cross(e2)
	local det = e1:Dot(p)
	if math.abs(det) < 1e-9 then return nil end
	local inv = 1 / det
	local s = o - a
	local u = s:Dot(p) * inv
	if u < 0 or u > 1 then return nil end
	local q = s:Cross(e1)
	local v = d:Dot(q) * inv
	if v < 0 or u + v > 1 then return nil end
	local t = e2:Dot(q) * inv
	return t > 1e-6 and t or nil
end
local function rayMesh(o, d)
	if not worldTris then buildWorldTris() end
	local bt, bf
	for _, t in ipairs(worldTris) do
		local hit = rayTri(o, d, t[1], t[2], t[3])
		if hit and (not bt or hit < bt) then bt, bf = hit, t[4] end
	end
	return bt, bf
end
-- is world point wp hidden behind the mesh (from the camera)?
local function occluded(wp, ownFaces)
	if xray then return false end
	local o = camera().CFrame.Position
	local d = wp - o
	local dist = d.Magnitude
	if dist < 1e-6 then return false end
	d = d.Unit
	if not worldTris then buildWorldTris() end
	for _, t in ipairs(worldTris) do
		if not (ownFaces and ownFaces[t[4]]) then
			local hit = rayTri(o, d, t[1], t[2], t[3])
			if hit and hit < dist - 0.01 then return true end
		end
	end
	return false
end
local function faceSetOfVert(v) local s = {} for _, f in ipairs(BMesh.vertFaces(v)) do s[f] = true end return s end
local function faceSetOfEdge(e) local s = {} for _, f in ipairs(BMesh.edgeFaces(e)) do s[f] = true end return s end

-- ===== selection (Blender-style flushing) =====
local function flush()
	if mode == "vert" then
		for e in pairs(bm.edges) do e.sel = e.v1.sel and e.v2.sel end
		for f in pairs(bm.faces) do
			local all = true
			for _, v in ipairs(BMesh.faceVerts(f)) do if not v.sel then all = false break end end
			f.sel = all
		end
	elseif mode == "edge" then
		for v in pairs(bm.verts) do v.sel = false end
		for e in pairs(bm.edges) do if e.sel then e.v1.sel = true e.v2.sel = true end end
		for f in pairs(bm.faces) do
			local all = true
			for _, l in ipairs(BMesh.faceLoops(f)) do if not l.e.sel then all = false break end end
			f.sel = all
		end
	else
		for v in pairs(bm.verts) do v.sel = false end
		for e in pairs(bm.edges) do e.sel = false end
		for f in pairs(bm.faces) do
			if f.sel then
				for _, l in ipairs(BMesh.faceLoops(f)) do l.v.sel = true l.e.sel = true end
			end
		end
	end
end
local function clearSel()
	for v in pairs(bm.verts) do v.sel = false end
	for e in pairs(bm.edges) do e.sel = false end
	for f in pairs(bm.faces) do f.sel = false end
end
local function selSet(kind)
	local s, n = {}, 0
	local src = (kind == "vert" and bm.verts) or (kind == "edge" and bm.edges) or bm.faces
	for x in pairs(src) do if x.sel then s[x] = true n += 1 end end
	return s, n
end
local function setMode(m)
	if editing and bm then
		-- carry the selection across like Blender
		if m == "edge" then for e in pairs(bm.edges) do e.sel = e.v1.sel and e.v2.sel end
		elseif m == "face" then
			for f in pairs(bm.faces) do
				local all = true
				for _, v in ipairs(BMesh.faceVerts(f)) do if not v.sel then all = false break end end
				f.sel = all
			end
		end
	end
	mode = m
	if editing and bm then flush() end
	for _, k in ipairs({ "Vertex (1)", "Edge (2)", "Face (3)" }) do
		local on = (k:sub(1, 1) == "V" and m == "vert") or (k:sub(1, 1) == "E" and m == "edge") or (k:sub(1, 1) == "F" and m == "face")
		if buttons[k] then buttons[k].BackgroundColor3 = on and Color3.fromRGB(0, 120, 215) or Color3.fromRGB(58, 61, 72) end
	end
	dirtyCage, dirtyMesh = true, true
end

-- ===== the cage (verts / edges / face dots drawn over the mesh) =====
local cageFolder = Instance.new("Folder")
cageFolder.Name = NAME .. "_Cage"
cageFolder.Parent = CoreGui
local pools = {}
local function pool(class)
	local p = pools[class]
	if not p then p = { items = {}, n = 0, class = class } pools[class] = p end
	return p
end
local function pGet(p)
	p.n += 1
	local x = p.items[p.n]
	if not x then
		x = Instance.new(p.class)
		x.Adornee = TERRAIN
		x.AlwaysOnTop = true
		x.ZIndex = 3
		x.Parent = cageFolder
		p.items[p.n] = x
	end
	x.Visible = true
	return x
end
local function pBegin() for _, p in pairs(pools) do p.n = 0 end end
local function pEnd() for _, p in pairs(pools) do for i = p.n + 1, #p.items do p.items[i].Visible = false end end end
local function line(a, b, col, w)
	local d = b - a
	local len = d.Magnitude
	if len < 1e-4 then return end
	local x = pGet(pool("BoxHandleAdornment"))
	local mid = (a + b) / 2
	local up = math.abs(d.Unit.Y) > 0.99 and V3(1, 0, 0) or V3(0, 1, 0)
	local cw = (camera().CFrame.Position - mid).Magnitude * 0.0016 * (w or 1)
	x.CFrame = CFrame.lookAt(mid, b, up)
	x.Size = V3(cw, cw, len)
	x.Color3 = col
	x.Transparency = 0
end
local function dot(p, col, s)
	local x = pGet(pool("SphereHandleAdornment"))
	x.CFrame = CFrame.new(p)
	x.Radius = (camera().CFrame.Position - p).Magnitude * 0.0045 * (s or 1)
	x.Color3 = col
	x.Transparency = 0
end

local function drawCage()
	pBegin()
	if editing and bm then
		local many = bm.ne > 6000
		for e in pairs(bm.edges) do
			local on = e.sel
			if on or not many then
				local col = (hover == e) and ACT_COL or (on and SEL_COL or WIRE_COL)
				line(W(e.v1.co), W(e.v2.co), col, (mode == "edge" and (on or hover == e)) and 2.2 or 1)
			end
		end
		if mode == "vert" and bm.nv < 6000 then
			for v in pairs(bm.verts) do
				dot(W(v.co), (hover == v) and ACT_COL or (v.sel and SEL_COL or WIRE_COL), (v.sel or hover == v) and 1.2 or 0.8)
			end
		elseif mode == "face" and bm.nf < 6000 then
			for f in pairs(bm.faces) do
				dot(W(BMesh.faceCenter(f)), (hover == f) and ACT_COL or (f.sel and SEL_COL or WIRE_COL), 0.7)
			end
		end
		-- loop cut preview
		if modal and modal.kind == "loopcut" and modal.preview then
			for _, seg in ipairs(modal.preview) do line(seg[1], seg[2], Color3.fromRGB(255, 220, 60), 2) end
		end
	end
	pEnd()
end

-- ===== saving + undo (each change = one Studio undo step; Ctrl+Z reloads the mesh) =====
local function commit(what)
	if not (obj and bm) then return end
	local rec
	pcall(function() rec = CHS:TryBeginRecording("ROBLENDER", "ROBLENDER " .. what) end)
	local val = encode(bm)
	lastWritten = val
	dataOf(obj).Value = val
	local ok, _, np = applyMesh(obj, bm, editing)
	if np then obj = np end
	origin = originOf(obj)
	worldTris = nil
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else CHS:SetWaypoint("ROBLENDER " .. what) end
	dirtyCage = true
	lastBuild = os.clock()
	dirtyMesh = false
end

local function watchData()
	if dataConn then dataConn:Disconnect() dataConn = nil end
	if not obj then return end
	dataConn = dataOf(obj):GetPropertyChangedSignal("Value"):Connect(function()
		if not editing or modal then return end
		local v = dataOf(obj).Value
		if v ~= lastWritten then
			-- undo / redo changed the mesh: load it again
			lastWritten = v
			local ok, m = pcall(loadFrom, obj)
			if ok and m then
				bm = m
				origin = originOf(obj)
				worldTris = nil
				dirtyMesh, dirtyCage = true, true
				setStatus("Undo / redo: mesh reloaded.")
			end
		end
	end)
end

-- ===== edit mode =====
local function enterEdit(p)
	if not isRB(p) then setStatus("Click a " .. NAME .. " part first (or add a shape).") return end
	local ok, m, scaled = pcall(loadFrom, p)
	if not ok then setStatus("Couldn't read the mesh: " .. tostring(m)) return end
	if scaled then
		-- the part was resized in Studio: keep that size in the saved mesh
		dataOf(p).Value = encode(m)
		p:SetAttribute("RB_Size", p.Size)
	end
	obj, bm = p, m
	origin = originOf(p)
	editing = true
	worldTris = nil
	lastWritten = dataOf(p).Value
	clearSel()
	Selection:Set({})
	plugin:Activate(true)
	watchData()
	setMode(mode)
	dirtyMesh, dirtyCage = true, true
	setStatus("EDIT: " .. p.Name .. ". 1/2/3 = vertex/edge/face, G S R E I, Ctrl+R loop cut, Tab = done.")
	if buttons["Edit (Tab)"] then buttons["Edit (Tab)"].BackgroundColor3 = Color3.fromRGB(0, 150, 90) end
end

local function exitEdit()
	if not editing then return end
	modal = nil
	if obj and bm then
		editing = false
		local ok, _, np = applyMesh(obj, bm, false)
		if np then obj = np end
		Selection:Set({ obj })
	end
	editing = false
	if dataConn then dataConn:Disconnect() dataConn = nil end
	bm = nil
	obj = nil
	worldTris = nil
	hover = nil
	pBegin() pEnd()
	plugin:Deactivate()
	setStatus("Object mode. Click a " .. NAME .. " part and press Tab to edit it.")
	if buttons["Edit (Tab)"] then buttons["Edit (Tab)"].BackgroundColor3 = Color3.fromRGB(58, 61, 72) end
end

plugin.Deactivation:Connect(function() if editing then exitEdit() end end)

-- ===== adding shapes =====
local function spawnPoint()
	local cam = camera()
	local res = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 500)
	local p = res and res.Position or (cam.CFrame.Position + cam.CFrame.LookVector * 20)
	return V3(math.floor(p.X + 0.5), math.floor(p.Y + 0.5), math.floor(p.Z + 0.5))
end
local function primitive(m, kind)
	if kind == "Cube" then Ops.cube(m, 4)
	elseif kind == "Plane" then Ops.plane(m, 4)
	elseif kind == "Grid" then Ops.grid(m, 6, 6, 6)
	elseif kind == "Circle" then Ops.circle(m, 32, 2)
	elseif kind == "Cylinder" then Ops.cylinder(m, 24, 2, 4)
	elseif kind == "Sphere" then Ops.uvSphere(m, 24, 12, 2) end
end
local function addShape(kind)
	if editing and bm and not modal then
		-- edit mode: add into this mesh, at its middle, and select just the new part (like Blender)
		local old = {}
		for v in pairs(bm.verts) do old[v] = true end
		local c = (bm.nv > 0) and Display.bounds(bm) or V3()
		primitive(bm, kind)
		clearSel()
		for v in pairs(bm.verts) do if not old[v] then v.co += c v.sel = true end end
		for e in pairs(bm.edges) do e.sel = e.v1.sel and e.v2.sel end
		for f in pairs(bm.faces) do
			local all = true
			for _, v in ipairs(BMesh.faceVerts(f)) do if not v.sel then all = false break end end
			f.sel = all
		end
		bm:normalsUpdate()
		flush()
		worldTris = nil
		commit("Add " .. kind)
		setStatus("Added a " .. kind .. " to the mesh (it's selected - G to move it).")
		return
	end
	if editing then exitEdit() end
	local m = BMesh.new()
	primitive(m, kind)
	local mp, c, err = Display.build(m)
	if not mp then
		setStatus("Couldn't make the mesh: " .. tostring(err) .. "  (Game Settings > Security > allow Mesh / Image APIs, then try again)")
		return
	end
	local rec
	pcall(function() rec = CHS:TryBeginRecording("ROBLENDER", "ROBLENDER add " .. kind) end)
	mp.Name = NAME .. " " .. kind
	mp.Anchored = true
	mp.Color = Color3.fromRGB(200, 200, 205)
	mp.Material = Enum.Material.SmoothPlastic
	local base = spawnPoint() + V3(0, 2, 0)
	mp.CFrame = CFrame.new(base + c)
	local sv = Instance.new("StringValue")
	sv.Name = "RB_Data"
	sv.Value = encode(m)
	sv.Parent = mp
	mp:SetAttribute("RB_Center", c)
	mp:SetAttribute("RB_Size", mp.Size)
	mp:SetAttribute("ROBLENDER", VERSION)
	mp.Parent = workspace
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else CHS:SetWaypoint("ROBLENDER add") end
	Selection:Set({ mp })
	setStatus("Added a " .. kind .. ". Press Tab (or Edit) to edit it.")
end

-- ===== picking =====
local PICK_PX = 14
local function pickVert(mp)
	local best, bd, bz = nil, PICK_PX, math.huge
	for v in pairs(bm.verts) do
		local wp = W(v.co)
		local sp, vis, z = toScreen(wp)
		if vis then
			local d = (sp - mp).Magnitude
			if d < bd or (d < PICK_PX and math.abs(d - bd) < 2 and z < bz) then
				if not occluded(wp, faceSetOfVert(v)) then best, bd, bz = v, d, z end
			end
		end
	end
	return best
end
local function segDist2(p, a, b)
	local ab = b - a
	local l2 = ab:Dot(ab)
	local t = l2 > 1e-9 and math.clamp((p - a):Dot(ab) / l2, 0, 1) or 0
	return (a + ab * t - p).Magnitude, t
end
local function pickEdge(mp)
	local best, bd = nil, 10
	for e in pairs(bm.edges) do
		local a, b = W(e.v1.co), W(e.v2.co)
		local sa, va = toScreen(a)
		local sb, vb = toScreen(b)
		if va and vb then
			local d, t = segDist2(mp, sa, sb)
			if d < bd then
				local wp = a:Lerp(b, t)
				if not occluded(wp, faceSetOfEdge(e)) then best, bd = e, d end
			end
		end
	end
	return best
end
local function pickFace()
	local r = mouse.UnitRay
	local _, f = rayMesh(r.Origin, r.Direction)
	if f then return f end
	-- x-ray: nearest face dot on screen
	local mp = mousePos()
	local best, bd = nil, PICK_PX
	for g in pairs(bm.faces) do
		local sp, vis = toScreen(W(BMesh.faceCenter(g)))
		if vis and (sp - mp).Magnitude < bd then best, bd = g, (sp - mp).Magnitude end
	end
	return best
end
local function pickAny()
	local mp = mousePos()
	if mode == "vert" then return pickVert(mp) elseif mode == "edge" then return pickEdge(mp) else return pickFace() end
end

local function toggle(x, on)
	if on == nil then on = not x.sel end
	x.sel = on
end

-- ===== modal tools =====
local function selectedVertsList()
	local out = {}
	for v in pairs(bm.verts) do if v.sel then out[#out + 1] = v end end
	return out
end
local function centerOf(vs)
	local s = V3()
	for _, v in ipairs(vs) do s += v.co end
	return #vs > 0 and s / #vs or s
end
local AXES = { X = V3(1, 0, 0), Y = V3(0, 1, 0), Z = V3(0, 0, 1) }

local function planeHit(ray, p0, n)
	local dn = ray.Direction:Dot(n)
	if math.abs(dn) < 1e-6 then return nil end
	local t = (p0 - ray.Origin):Dot(n) / dn
	return ray.Origin + ray.Direction * t
end
-- along an axis line through c (world): the point on it nearest the mouse ray
local function axisParam(ray, c, dir)
	local d = ray.Direction
	local b = dir:Dot(d)
	local den = 1 - b * b
	if den < 1e-6 then return nil end
	local w = c - ray.Origin
	return (b * d:Dot(w) - dir:Dot(w)) / den
end

local function startTransform(kind, opts)
	local vs = selectedVertsList()
	if #vs == 0 then setStatus("Nothing selected.") return end
	local orig = {}
	for _, v in ipairs(vs) do orig[v] = v.co end
	local cLocal = centerOf(vs)
	local m = mousePos()
	modal = {
		kind = kind, verts = vs, orig = orig, c = cLocal, cw = W(cLocal), m0 = m, ray0 = mouse.UnitRay,
		axis = opts and opts.axis or nil, axisWorld = opts and opts.axisWorld or nil, num = "", what = opts and opts.what or nil,
	}
	local sc = toScreen(modal.cw)
	modal.cs = sc
	setStatus(({ G = "MOVE", S = "SCALE", R = "ROTATE" })[kind] .. ": move the mouse. X / Y / Z = lock to an axis, type a number, Ctrl = snap. Click / Enter = done, Esc = cancel.")
end

local function applyTransform()
	local M = modal
	local mp = mousePos()
	local num = tonumber(M.num)
	local snap = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local axisW = M.axisWorld or (M.axis and AXES[M.axis])
	local axisL = axisW and origin:VectorToObjectSpace(axisW).Unit
	if M.kind == "G" then
		local dL
		if axisW then
			local t
			if num then t = num else
				local t1, t0 = axisParam(mouse.UnitRay, M.cw, axisW), axisParam(M.ray0, M.cw, axisW)
				t = (t1 and t0) and (t1 - t0) or 0
				if snap then t = math.floor(t + 0.5) end
			end
			dL = axisL * t
		else
			local n = camera().CFrame.LookVector
			local p1, p0 = planeHit(mouse.UnitRay, M.cw, n), planeHit(M.ray0, M.cw, n)
			local dW = (p1 and p0) and (p1 - p0) or V3()
			if num then dW = camera().CFrame.RightVector * num end
			if snap then dW = V3(math.floor(dW.X + 0.5), math.floor(dW.Y + 0.5), math.floor(dW.Z + 0.5)) end
			dL = origin:VectorToObjectSpace(dW)
		end
		for _, v in ipairs(M.verts) do v.co = M.orig[v] + dL end
		M.info = ("Move %.2f"):format(dL.Magnitude)
	elseif M.kind == "S" then
		local d0 = (M.m0 - M.cs).Magnitude
		local f = num or (d0 > 1 and (mp - M.cs).Magnitude / d0 or 1)
		if snap and not num then f = math.floor(f * 10 + 0.5) / 10 end
		for _, v in ipairs(M.verts) do
			local r = M.orig[v] - M.c
			if axisL then
				local along = axisL * r:Dot(axisL)
				v.co = M.c + (r - along) + along * f
			else
				v.co = M.c + r * f
			end
		end
		M.info = ("Scale %.3f"):format(f)
	elseif M.kind == "R" then
		local a0 = math.atan2(M.m0.Y - M.cs.Y, M.m0.X - M.cs.X)
		local a1 = math.atan2(mp.Y - M.cs.Y, mp.X - M.cs.X)
		local ang = num and math.rad(num) or -(a1 - a0)
		if snap and not num then ang = math.rad(math.floor(math.deg(ang) / 15 + 0.5) * 15) end
		local axL = axisL or origin:VectorToObjectSpace(-camera().CFrame.LookVector).Unit
		local rot = CFrame.fromAxisAngle(axL, ang)
		for _, v in ipairs(M.verts) do v.co = M.c + rot * (M.orig[v] - M.c) end
		M.info = ("Rotate %.1f deg"):format(math.deg(ang))
	end
	bm:normalsUpdate()
	worldTris = nil
	dirtyMesh, dirtyCage = true, true
	setStatus((M.info or "") .. (M.axis and ("  along " .. M.axis) or "") .. (M.num ~= "" and ("  [" .. M.num .. "]") or "") .. "   click / Enter = done, Esc = cancel")
end

local function finishModal(cancel)
	local M = modal
	if not M then return end
	modal = nil
	if M.kind == "G" or M.kind == "S" or M.kind == "R" then
		if cancel then
			for v, co in pairs(M.orig) do v.co = co end
			bm:normalsUpdate()
			if M.what then commit(M.what) setStatus(M.what .. " (not moved).") else dirtyMesh, dirtyCage = true, true setStatus("Cancelled.") end
		else
			commit(M.what or ({ G = "Move", S = "Scale", R = "Rotate" })[M.kind])
			setStatus((M.what or "Done") .. ".")
		end
	elseif M.kind == "inset" then
		if cancel then
			bm = BMesh.fromData(M.snap)
			dirtyMesh, dirtyCage = true, true
			worldTris = nil
			setStatus("Inset cancelled.")
		else
			commit("Inset")
			setStatus("Inset done.")
		end
	elseif M.kind == "loopcut" then
		if not cancel and M.edge and bm.edges[M.edge] then
			local newEdges = Ops.loopCut(bm, M.edge, 0.5)
			clearSel()
			setMode("edge")
			for e in pairs(newEdges) do e.sel = true end
			flush()
			worldTris = nil
			commit("Loop cut")
			setStatus("Loop cut. G = slide it (move), Ctrl+R again for another.")
		else
			setStatus("Loop cut cancelled.")
		end
	end
	dirtyCage = true
end

-- ===== tools =====
local Tools = {}
function Tools.extrude()
	if mode == "face" then
		local fs, n = selSet("face")
		if n == 0 then setStatus("Pick faces to extrude.") return end
		local nrm = V3()
		for f in pairs(fs) do nrm += f.no end
		local nv, nf = Ops.extrudeFaceRegion(bm, fs)
		clearSel()
		for f in pairs(nf) do f.sel = true end
		flush()
		worldTris = nil
		local aw = nrm.Magnitude > 1e-6 and origin:VectorToWorldSpace(nrm.Unit) or nil
		startTransform("G", { axisWorld = aw, what = "Extrude" })
	elseif mode == "edge" then
		local es, n = selSet("edge")
		if n == 0 then setStatus("Pick edges to extrude.") return end
		local nv = Ops.extrudeEdges(bm, es)
		clearSel()
		for v in pairs(nv) do v.sel = true end
		for e in pairs(bm.edges) do e.sel = e.v1.sel and e.v2.sel end
		worldTris = nil
		startTransform("G", { what = "Extrude" })
	else
		local vs, n = selSet("vert")
		if n == 0 then setStatus("Pick verts to extrude.") return end
		local nv = Ops.extrudeVerts(bm, vs)
		clearSel()
		for v in pairs(nv) do v.sel = true end
		worldTris = nil
		startTransform("G", { what = "Extrude" })
	end
end
function Tools.inset()
	if mode ~= "face" then setMode("face") end
	local fs, n = selSet("face")
	if n == 0 then setStatus("Pick faces to inset.") return end
	local snap, vi, fOrder = bm:toData()
	local picked = {}
	for i, f in ipairs(fOrder) do if fs[f] then picked[#picked + 1] = i end end
	local vs = {}
	for f in pairs(fs) do for _, v in ipairs(BMesh.faceVerts(f)) do vs[#vs + 1] = v end end
	local c = W(centerOf(vs))
	modal = { kind = "inset", snap = snap, picked = picked, cw = c, cs = toScreen(c), m0 = mousePos(), num = "" }
	setStatus("INSET: move the mouse (or type a size). Click / Enter = done, Esc = cancel.")
end
local function updateInset()
	local M = modal
	local cam = camera()
	local depth = (cam.CFrame.Position - M.cw).Magnitude
	local wpp = 2 * depth * math.tan(math.rad(cam.FieldOfView) / 2) / math.max(1, cam.ViewportSize.Y)
	local thick = tonumber(M.num) or math.abs((mousePos() - M.cs).Magnitude - (M.m0 - M.cs).Magnitude) * wpp
	local nb, _, fl = BMesh.fromData(M.snap)
	local set = {}
	for _, i in ipairs(M.picked) do if fl[i] then set[fl[i]] = true end end
	local _, nf = Ops.insetRegion(nb, set, thick, 0)
	bm = nb
	clearSel()
	for f in pairs(nf) do f.sel = true end
	flush()
	worldTris = nil
	dirtyMesh, dirtyCage = true, true
	setStatus(("INSET %.3f   click / Enter = done, Esc = cancel"):format(thick))
end
function Tools.loopCut()
	modal = { kind = "loopcut", num = "" }
	setStatus("LOOP CUT: point at an edge (yellow = where the cut goes), click to cut. Esc = cancel.")
end
local function updateLoopCut()
	local M = modal
	local e = pickEdge(mousePos())
	M.edge = e
	M.preview = nil
	if e then
		local ring = Ops.edgeRing(bm, e)
		local mids = {}
		for i, r in ipairs(ring) do mids[i] = W((r.v1.co + r.v2.co) / 2) end
		M.preview = {}
		for i = 1, #mids - 1 do M.preview[#M.preview + 1] = { mids[i], mids[i + 1] } end
		-- closed ring: join the ends
		if #ring > 2 and BMesh.edgeFaceCount(ring[1]) == 2 then
			local fs1 = faceSetOfEdge(ring[1])
			for _, f in ipairs(BMesh.edgeFaces(ring[#ring])) do if fs1[f] then M.preview[#M.preview + 1] = { mids[#mids], mids[1] } break end end
		end
	end
	dirtyCage = true
end
function Tools.delete()
	if mode == "vert" then Ops.deleteVerts(bm, (selSet("vert")))
	elseif mode == "edge" then Ops.deleteEdges(bm, (selSet("edge")))
	else Ops.deleteFaces(bm, (selSet("face"))) end
	worldTris = nil
	commit("Delete")
	setStatus("Deleted.")
end
function Tools.merge()
	local vs, n = selSet("vert")
	if n < 2 then setStatus("Pick 2+ verts to merge.") return end
	local nb, map = Ops.mergeAtCenter(bm, vs)
	bm = nb
	clearSel()
	for old in pairs(vs) do local nv = map and map[old] if nv then nv.sel = true end end
	flush()
	worldTris = nil
	commit("Merge")
	setStatus("Merged " .. n .. " verts.")
end
function Tools.mergeDist()
	local nb, _, n = Ops.mergeByDistance(bm, nil, 0.001)
	bm = nb
	clearSel()
	worldTris = nil
	commit("Merge by distance")
	setStatus("Merged " .. n .. " doubled verts.")
end
function Tools.fill()
	local vs, n = selSet("vert")
	if n < 2 then setStatus("Pick 2+ verts to fill.") return end
	local f = Ops.fill(bm, vs)
	worldTris = nil
	commit("Fill")
	setStatus(f and "Filled a face." or "Joined with an edge.")
end
function Tools.flip()
	local fs, n = selSet("face")
	if n == 0 then fs = bm.faces end
	bm = Ops.flipFaces(bm, fs)
	clearSel()
	worldTris = nil
	commit("Flip normals")
	setStatus("Flipped.")
end
function Tools.subdivide()
	local fs, n = selSet("face")
	if n == 0 then setStatus("Pick faces to subdivide.") return end
	local nf = Ops.subdivideFaces(bm, fs)
	clearSel()
	for f in pairs(nf) do
		f.sel = true
		for _, l in ipairs(BMesh.faceLoops(f)) do l.v.sel = true l.e.sel = true end
	end
	flush()
	worldTris = nil
	commit("Subdivide")
	setStatus("Subdivided.")
end
function Tools.selectAll()
	local any = false
	for v in pairs(bm.verts) do if v.sel then any = true break end end
	clearSel()
	if not any then
		for v in pairs(bm.verts) do v.sel = true end
		for e in pairs(bm.edges) do e.sel = true end
		for f in pairs(bm.faces) do f.sel = true end
	end
	flush()
	dirtyCage, dirtyMesh = true, true
end
function Tools.invert()
	if mode == "vert" then for v in pairs(bm.verts) do v.sel = not v.sel end
	elseif mode == "edge" then for e in pairs(bm.edges) do e.sel = not e.sel end
	else for f in pairs(bm.faces) do f.sel = not f.sel end end
	flush()
	dirtyCage, dirtyMesh = true, true
end
function Tools.bake()
	local p = (editing and obj) or Selection:Get()[1]
	if not isRB(p) then setStatus("Pick a " .. NAME .. " part to bake.") return end
	local m = bm or loadFrom(p)
	local o = (p == obj) and origin or originOf(p)
	setStatus("Baking to parts...")
	local rec
	pcall(function() rec = CHS:TryBeginRecording("ROBLENDER", "ROBLENDER bake") end)
	local model = Display.bake(m, o, p, true)
	model.Name = p.Name .. " (baked)"
	model.Parent = p.Parent
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	setStatus("Baked: a copy made of normal parts (saves + publishes). The mesh part is still there.")
end
function Tools.exportOBJ()
	local p = (editing and obj) or Selection:Get()[1]
	if not isRB(p) then setStatus("Pick a " .. NAME .. " part to export.") return end
	local m = bm or loadFrom(p)
	local ms = Instance.new("ModuleScript")
	ms.Name = p.Name .. "_obj"
	ms.Source = "--[==[ Copy everything between the brackets into a text file and save it as .obj\n" .. Display.toOBJ(m, p.Name) .. "\n]==]\nreturn nil"
	ms.Parent = workspace
	plugin:OpenScript(ms)
	setStatus("OBJ text opened: copy it into a .obj file, then import it with the 3D Importer for a permanent mesh.")
end

-- ===== panel buttons =====
label("ADD", 11, Color3.fromRGB(150, 155, 170))
local r = row()
for _, k in ipairs({ "Cube", "Plane", "Grid" }) do button(r, k, 76, function() addShape(k) end) end
r = row()
for _, k in ipairs({ "Cylinder", "Sphere", "Circle" }) do button(r, k, 76, function() addShape(k) end) end
label("EDIT", 11, Color3.fromRGB(150, 155, 170))
r = row()
button(r, "Edit (Tab)", 120, function() if editing then exitEdit() else enterEdit(Selection:Get()[1]) end end)
button(r, "X-ray (Alt+Z)", 110, function() xray = not xray worldTris = nil dirtyCage = true setStatus("X-ray " .. (xray and "on" or "off")) end)
r = row()
button(r, "Vertex (1)", 76, function() setMode("vert") end)
button(r, "Edge (2)", 76, function() setMode("edge") end)
button(r, "Face (3)", 76, function() setMode("face") end)
label("TOOLS", 11, Color3.fromRGB(150, 155, 170))
local function tool(fn) return function() if not editing then setStatus("Press Tab on a " .. NAME .. " part first.") return end fn() end end
r = row()
button(r, "Extrude (E)", 76, tool(Tools.extrude))
button(r, "Inset (I)", 76, tool(Tools.inset))
button(r, "Loop cut", 76, tool(Tools.loopCut))
r = row()
button(r, "Move (G)", 76, tool(function() startTransform("G") end))
button(r, "Scale (S)", 76, tool(function() startTransform("S") end))
button(r, "Rotate (R)", 76, tool(function() startTransform("R") end))
r = row()
button(r, "Delete (X)", 76, tool(Tools.delete))
button(r, "Merge (M)", 76, tool(Tools.merge))
button(r, "Fill (F)", 76, tool(Tools.fill))
r = row()
button(r, "Subdivide", 76, tool(Tools.subdivide))
button(r, "Flip", 76, tool(Tools.flip))
button(r, "Merge dist", 76, tool(Tools.mergeDist))
label("OBJECT", 11, Color3.fromRGB(150, 155, 170))
r = row()
button(r, "Bake to parts", 116, Tools.bake, Color3.fromRGB(40, 130, 80))
button(r, "Export .obj", 116, Tools.exportOBJ)
label("KEYS: Tab edit | 1 2 3 modes | click / Shift-click / drag box / Alt-click loop | A all, Alt+A none, Ctrl+I invert | G S R (+ X Y Z, numbers, Ctrl snap) | E extrude | I inset | Ctrl+R loop cut | X delete | M merge | F fill | Alt+Z x-ray | Ctrl+Z undo", 10, Color3.fromRGB(150, 155, 170))
label("SAVING: the mesh is kept on the part and comes back when you edit it. Roblox doesn't save plugin-made meshes into the place yet - use Bake to parts (normal parts) or Export .obj (3D Importer) to keep it for good.", 10, Color3.fromRGB(255, 200, 120))

-- ===== the Blender-style screen (UI.lua) =====
local function toggleXray() xray = not xray worldTris = nil dirtyCage = true setStatus("X-ray " .. (xray and "on" or "off")) end
local function toggleEdit()
	if editing then exitEdit() else enterEdit(Selection:Get()[1]) end
end
local function needEdit(fn)
	return function()
		if not editing then setStatus("Tab into Edit Mode on a " .. NAME .. " part first.") return end
		if modal then return end
		fn()
	end
end
local TOOL = {
	G = needEdit(function() startTransform("G") end),
	R = needEdit(function() startTransform("R") end),
	S = needEdit(function() startTransform("S") end),
	Extrude = needEdit(Tools.extrude), Inset = needEdit(Tools.inset), LoopCut = needEdit(Tools.loopCut),
	Subdivide = needEdit(Tools.subdivide), Merge = needEdit(Tools.merge), MergeDist = needEdit(Tools.mergeDist),
	Fill = needEdit(Tools.fill), Delete = needEdit(Tools.delete), Flip = needEdit(Tools.flip),
	SelectAll = needEdit(function() clearSel() for v in pairs(bm.verts) do v.sel = true end for e in pairs(bm.edges) do e.sel = true end for f in pairs(bm.faces) do f.sel = true end flush() dirtyCage, dirtyMesh = true, true end),
	SelectNone = needEdit(function() clearSel() flush() dirtyCage, dirtyMesh = true, true end),
	Invert = needEdit(Tools.invert),
	Bake = Tools.bake, Export = Tools.exportOBJ,
}
TOOL.Move, TOOL.Rotate, TOOL.Scale = TOOL.G, TOOL.R, TOOL.S
local function selectedPart()
	local p = (editing and obj) or Selection:Get()[1]
	if p and p:IsA("BasePart") then return p end
	return nil
end
local api = {}
function api.state()
	local st = { editing = editing, mode = mode, xray = xray, modal = modal and modal.kind or nil, modalWhat = modal and modal.what or nil, modalText = lastStatus }
	local p = selectedPart()
	if p then st.objName = p.Name st.isRB = isRB(p) end
	if editing and bm then
		local s = { v = bm.nv, e = bm.ne, f = bm.nf, vs = 0, es = 0, fs = 0, t = 0 }
		local sum, n = V3(), 0
		for v in pairs(bm.verts) do if v.sel then s.vs += 1 sum += v.co n += 1 end end
		for e in pairs(bm.edges) do if e.sel then s.es += 1 end end
		for f in pairs(bm.faces) do s.t += f.len - 2 if f.sel then s.fs += 1 end end
		st.stats = s
		if n > 0 then st.loc = W(sum / n) end
	elseif p then
		st.loc, st.dim = p.Position, p.Size
	end
	return st
end
api.toggleEdit = toggleEdit
api.toggleXray = toggleXray
api.togglePanel = function() widget.Enabled = not widget.Enabled end
api.setMode = function(m) if editing and not modal then setMode(m) end end
api.add = function(kind) addShape(kind) end
api.tool = function(name) local f = TOOL[name] if f then f() end end
function api.setField(key, axis, value)
	if editing and bm then
		if key ~= "loc" or modal then return end
		local vs = selectedVertsList()
		if #vs == 0 then return end
		local cw = W(centerOf(vs))
		local target = V3(axis == "X" and value or cw.X, axis == "Y" and value or cw.Y, axis == "Z" and value or cw.Z)
		local dL = origin:VectorToObjectSpace(target - cw)
		for _, v in ipairs(vs) do v.co += dL end
		bm:normalsUpdate()
		worldTris = nil
		commit("Move")
		setStatus(("Moved the selection to %s = %g"):format(axis, value))
	else
		local p = selectedPart()
		if not p then return end
		local rec
		pcall(function() rec = CHS:TryBeginRecording("ROBLENDER", "ROBLENDER " .. key) end)
		if key == "loc" then
			local q = p.Position
			p.CFrame = p.CFrame + (V3(axis == "X" and value or q.X, axis == "Y" and value or q.Y, axis == "Z" and value or q.Z) - q)
		elseif value > 0 then
			local q = p.Size
			p.Size = V3(axis == "X" and value or q.X, axis == "Y" and value or q.Y, axis == "Z" and value or q.Z)
		end
		if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else CHS:SetWaypoint("ROBLENDER " .. key) end
	end
end
ui = UI.new(api, CoreGui)
local uiOn = false
local function setUIOn(on)
	uiOn = on
	ui:setOn(on)
	pcall(function() btnMain:SetActive(on) end)
	if not on and editing then exitEdit() end
	if on then setStatus("Welcome to " .. NAME .. ". Shift A = add a mesh, select one and press Tab to edit it.") end
end
btnMain.Click:Connect(function() setUIOn(not uiOn) end)
plugin.Unloading:Connect(function()
	pcall(function() if editing then exitEdit() end end)
	ui:destroy()
	cageFolder.Parent = nil
end)

-- ===== mouse =====
local boxGui = Instance.new("ScreenGui")
boxGui.Name = NAME .. "_Box"
boxGui.IgnoreGuiInset = true
boxGui.DisplayOrder = 40
boxGui.Parent = CoreGui
plugin.Unloading:Connect(function() boxGui.Parent = nil end)
local boxFrame = Instance.new("Frame")
boxFrame.BackgroundColor3 = Color3.fromRGB(255, 150, 40)
boxFrame.BackgroundTransparency = 0.85
boxFrame.BorderSizePixel = 0
boxFrame.Visible = false
local st = Instance.new("UIStroke") st.Color = Color3.fromRGB(255, 170, 80) st.Parent = boxFrame
boxFrame.Parent = boxGui
local down = nil

local function boxSelect(a, b, add, sub)
	local lo = Vector2.new(math.min(a.X, b.X), math.min(a.Y, b.Y))
	local hi = Vector2.new(math.max(a.X, b.X), math.max(a.Y, b.Y))
	local function inside(wp)
		local sp, vis = toScreen(wp)
		return vis and sp.X >= lo.X and sp.X <= hi.X and sp.Y >= lo.Y and sp.Y <= hi.Y
	end
	if not add and not sub then clearSel() end
	if mode == "vert" then
		for v in pairs(bm.verts) do
			local wp = W(v.co)
			if inside(wp) and not occluded(wp, faceSetOfVert(v)) then v.sel = not sub end
		end
	elseif mode == "edge" then
		for e in pairs(bm.edges) do
			local a2, b2 = W(e.v1.co), W(e.v2.co)
			if inside(a2) and inside(b2) and not occluded((a2 + b2) / 2, faceSetOfEdge(e)) then e.sel = not sub end
		end
	else
		for f in pairs(bm.faces) do
			local c = W(BMesh.faceCenter(f))
			if inside(c) and not occluded(c, { [f] = true }) then f.sel = not sub end
		end
	end
	flush()
	dirtyCage, dirtyMesh = true, true
end

mouse.Button1Down:Connect(function()
	if not editing then return end
	if ui:overUI(mousePos()) then return end
	if modal then
		if modal.kind == "loopcut" then updateLoopCut() end
		local ok, err = pcall(finishModal, false)
		if not ok then warn(NAME .. ": " .. tostring(err)) end
		return
	end
	down = mousePos()
end)
mouse.Button1Up:Connect(function()
	if not editing or not down then return end
	local a, b = down, mousePos()
	down = nil
	boxFrame.Visible = false
	local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local alt = UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
	local ok, err = pcall(function()
		if (b - a).Magnitude > 6 then boxSelect(a, b, shift, ctrl) return end
		if alt then
			-- loop select (edge loop through the edge under the mouse)
			local e = pickEdge(b)
			if e then
				if not shift then clearSel() end
				for _, le in ipairs(Ops.edgeLoop(bm, e)) do
					if mode == "face" then for _, f in ipairs(BMesh.edgeFaces(le)) do f.sel = true end
					else le.sel = true le.v1.sel = true le.v2.sel = true end
				end
				flush()
			end
		else
			local x = pickAny()
			if x then
				if shift then toggle(x) else clearSel() toggle(x, true) end
			elseif not shift then clearSel() end
			flush()
		end
		dirtyCage, dirtyMesh = true, true
	end)
	if not ok then warn(NAME .. ": " .. tostring(err)) end
end)
mouse.Button2Down:Connect(function()
	if editing and modal then pcall(finishModal, true) end
end)
mouse.Move:Connect(function()
	if not editing then return end
	local ok, err = pcall(function()
		if modal then
			if modal.kind == "G" or modal.kind == "S" or modal.kind == "R" then applyTransform()
			elseif modal.kind == "inset" then updateInset()
			elseif modal.kind == "loopcut" then updateLoopCut() end
			return
		end
		if not down and ui:overUI(mousePos()) then
			if hover then hover = nil dirtyCage = true end
			return
		end
		if down then
			local a, b = down, mousePos()
			if (b - a).Magnitude > 6 then
				boxFrame.Visible = true
				boxFrame.Position = UDim2.fromOffset(math.min(a.X, b.X), math.min(a.Y, b.Y))
				boxFrame.Size = UDim2.fromOffset(math.abs(a.X - b.X), math.abs(a.Y - b.Y))
			end
			return
		end
		local h = pickAny()
		if h ~= hover then hover = h dirtyCage = true end
	end)
	if not ok then warn(NAME .. ": " .. tostring(err)) end
end)

-- ===== keys =====
UIS.InputBegan:Connect(function(input, gp)
	if UIS:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local k = input.KeyCode
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local alt = UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
	local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
	if uiOn and ui.menuOpen then
		if k == Enum.KeyCode.Escape then ui:closeMenu() end
		return
	end
	if k == Enum.KeyCode.Tab and not ctrl and not alt then
		if modal then return end
		if editing then exitEdit() elseif isRB(Selection:Get()[1]) then enterEdit(Selection:Get()[1])
		elseif uiOn then setStatus("Select a " .. NAME .. " mesh first (Shift A adds one).") end
		return
	end
	if uiOn and not modal and not ctrl and not alt then
		local ok, used = pcall(function()
			if k == Enum.KeyCode.A and shift then ui:openAddMenu(mousePos()) return true end
			if k == Enum.KeyCode.N and not shift then ui:toggleSidebar() return true end
			if k == Enum.KeyCode.T and not shift then ui:toggleToolbar() return true end
			return false
		end)
		if not ok then warn(NAME .. ": " .. tostring(used)) return end
		if used then return end
	end
	if not editing then return end
	local ok, err = pcall(function()
		if modal then
			if k == Enum.KeyCode.Escape then finishModal(true) return end
			if k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter then
				if modal.kind == "loopcut" then updateLoopCut() end
				finishModal(false) return
			end
			if modal.kind == "G" or modal.kind == "S" or modal.kind == "R" then
				if k == Enum.KeyCode.X or k == Enum.KeyCode.Y or k == Enum.KeyCode.Z then
					local a = k.Name
					modal.axisWorld = nil
					if modal.axis == a then modal.axis = nil else modal.axis = a end
					applyTransform()
					return
				end
			end
			-- typed numbers
			local digits = { Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
				KeypadZero = "0", KeypadOne = "1", KeypadTwo = "2", KeypadThree = "3", KeypadFour = "4", KeypadFive = "5", KeypadSix = "6", KeypadSeven = "7", KeypadEight = "8", KeypadNine = "9",
				Period = ".", KeypadPeriod = ".", Minus = "-", KeypadMinus = "-" }
			local ch = digits[k.Name]
			if ch then modal.num = (modal.num or "") .. ch
			elseif k == Enum.KeyCode.Backspace then modal.num = (modal.num or ""):sub(1, -2)
			else return end
			if modal.kind == "inset" then updateInset() elseif modal.kind ~= "loopcut" then applyTransform() end
			return
		end
		if k == Enum.KeyCode.One then setMode("vert")
		elseif k == Enum.KeyCode.Two then setMode("edge")
		elseif k == Enum.KeyCode.Three then setMode("face")
		elseif k == Enum.KeyCode.A and alt then clearSel() flush() dirtyCage, dirtyMesh = true, true
		elseif k == Enum.KeyCode.A then Tools.selectAll()
		elseif k == Enum.KeyCode.I and ctrl then Tools.invert()
		elseif k == Enum.KeyCode.G then startTransform("G")
		elseif k == Enum.KeyCode.S and not ctrl then startTransform("S")
		elseif k == Enum.KeyCode.R and ctrl then Tools.loopCut()
		elseif k == Enum.KeyCode.R then startTransform("R")
		elseif k == Enum.KeyCode.E then Tools.extrude()
		elseif k == Enum.KeyCode.I then Tools.inset()
		elseif k == Enum.KeyCode.X or k == Enum.KeyCode.Delete then Tools.delete()
		elseif k == Enum.KeyCode.M then Tools.merge()
		elseif k == Enum.KeyCode.F then Tools.fill()
		elseif k == Enum.KeyCode.Z and alt then xray = not xray worldTris = nil dirtyCage = true setStatus("X-ray " .. (xray and "on" or "off"))
		end
	end)
	if not ok then warn(NAME .. ": " .. tostring(err)) setStatus("Error: " .. tostring(err)) end
end)

-- ===== keep the look up to date (mesh rebuilt at most ~20 times a second while dragging) =====
local lastCam = nil
local lastUI = 0
RunService.Heartbeat:Connect(function()
	if uiOn and os.clock() - lastUI > 0.1 then
		lastUI = os.clock()
		local ok, err = pcall(function() ui:refresh() end)
		if not ok then warn(NAME .. " UI: " .. tostring(err)) end
	end
	if not editing or not obj then return end
	if not obj.Parent then exitEdit() return end
	local now = os.clock()
	if dirtyMesh and now - lastBuild > 0.05 then
		dirtyMesh = false
		lastBuild = now
		local ok, err, np = applyMesh(obj, bm, true)
		if np then obj = np end
		if ok then origin = originOf(obj) else setStatus("Mesh: " .. tostring(err)) end
		worldTris = nil
		dirtyCage = true
	end
	local cf = camera().CFrame
	if dirtyCage or cf ~= lastCam then
		lastCam = cf
		dirtyCage = false
		drawCage()
	end
end)

print(NAME .. " " .. VERSION .. " loaded - free + open source (GPL-2.0-or-later). Mesh engine converted from Blender's BMesh.")
