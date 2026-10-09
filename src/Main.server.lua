--[[
	ROBLEND - a free, open-source mesh editor for Roblox Studio
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

local NAME = "ROBLEND"
local VERSION = "0.16.0"

local BMesh = require(script.BMesh)
local Ops = require(script.Ops)
local Display = require(script.Display)
local UI = require(script.UI)
local View = require(script.View)
local MT = require(script.MeshTools)
local Icon = require(script.Icon)
local ObjectTools = require(script.ObjectTools)
local ModStack = require(script.ModStack)
local Sculpt = require(script.Sculpt)
local Paint = require(script.Paint)
local Font = require(script.Font)
local Mods = require(script.Modifiers)

local Selection = game:GetService("Selection")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CHS = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
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
local paintMode = nil    -- nil = Edit Mode, "sculpt" = Sculpt Mode (both edit the mesh in `bm`)
local paintHooks = {}    -- exit() set by the Sculpt controller
local xray = false
local modal = nil        -- the running G / S / R / inset / loop cut
local hover = nil
local lastWritten = nil
local dirtyMesh, dirtyCage, lastBuild = false, false, 0
local worldTris = nil    -- cache for picking
local dataConn = nil
local ui = nil            -- the Blender-style screen (UI.lua)
local view = nil          -- our own 3D view (View.lua), used while the screen is open
local uiOn = false
local useStudio = false   -- true = edit in Studio's own 3D view instead of ours
local shading = "solid"   -- solid / wire
local navDrag = nil       -- orbit / pan / zoom drag in our 3D view
local scene = {}          -- ROBLEND parts shown in our 3D view: part -> record
local activeObj = nil     -- Blender's "active object"
local CURSOR = Vector3.new(0, 2, 0) -- new shapes go here (Blender's 3D cursor)
local EDIT = { prop = false, propR = 4, mirrorX = false, snap = false, autoMerge = false, propFalloff = "Smooth", boxMode = "set", snapTarget = "Increment", pivot = "median" }
-- proportional editing falloffs (Blender's PROP_SMOOTH, PROP_SPHERE, ...): t = 1 at the selection, 0 at the edge of the circle
local FALLOFF = {
	Smooth = function(t) return t * t * (3 - 2 * t) end,
	Sphere = function(t) return math.sqrt(math.max(0, 2 * t - t * t)) end,
	Root = function(t) return math.sqrt(t) end,
	["Inverse Square"] = function(t) return t * (2 - t) end,
	Sharp = function(t) return t * t end,
	Linear = function(t) return t end,
	Constant = function() return 1 end,
	Random = function(t) return t * math.random() end,
}
local snapTargetLocal
local FALLOFF_ORDER = { "Smooth", "Sphere", "Root", "Inverse Square", "Sharp", "Linear", "Constant", "Random" } -- header toggles: proportional, X mirror, snapping

-- ===== UI =====
local toolbar = plugin:CreateToolbar(NAME)
local btnMain = toolbar:CreateButton(NAME, "Open " .. NAME .. " - free, open-source 3D modelling for Roblox Studio", "rbxassetid://0", NAME)
btnMain.ClickableWhenViewportHidden = true
-- the ROBLEND logo: shown in the window straight from the plugin (an EditableImage), and uploaded once as an
-- Image asset for the toolbar button (needs the same "CreateAssetAsync" beta as saving meshes; the id is remembered)
local logoImage = Icon.image(AssetService)
local function setButtonIcon(id) pcall(function() btnMain.Icon = "rbxassetid://" .. tostring(id) end) end
do
	local saved
	pcall(function() saved = plugin:GetSetting("RB_IconId") end)
	if saved then
		setButtonIcon(saved)
	elseif logoImage then
		task.spawn(function()
			local lastTry
			pcall(function() lastTry = plugin:GetSetting("RB_IconTry") end)
			if lastTry and os.time() - lastTry < 3600 then return end
			pcall(function() plugin:SetSetting("RB_IconTry", os.time()) end)
			local ok, result, id = pcall(function()
				return AssetService:CreateAssetAsync(logoImage, Enum.AssetType.Image, { Name = "ROBLEND icon", Description = "ROBLEND plugin icon (Cruppnomics)" })
			end)
			if ok and result == Enum.CreateAssetResult.Success and id then
				pcall(function() plugin:SetSetting("RB_IconId", id) end)
				setButtonIcon(id)
			end
		end)
	end
end
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
label("ROBLEND - free, open-source modelling (GPL) by Cruppnomics. Portions derived from Blender; not affiliated with or endorsed by the Blender Foundation.", 10, Color3.fromRGB(150, 155, 170))
local status = label("Add a shape, or click a " .. NAME .. " part and press Tab.", 12, Color3.fromRGB(140, 220, 255))
local lastStatus = ""
local function setStatus(t) status.Text = t lastStatus = t if ui then ui:setReport(t) end end

-- ===== saving on the part =====
local function isRB(p) return p and p:IsA("MeshPart") and p:FindFirstChild("RB_Data") ~= nil end
local function dataOf(p) return p:FindFirstChild("RB_Data") end

local function encode(b) return HttpService:JSONEncode(b:toData()) end

-- ===== modifier stack (StringValue RB_Mods = JSON list, see Modifiers.lua) =====
local function modsStr(p) local s = p and p:FindFirstChild("RB_Mods") return s and s:IsA("StringValue") and s.Value or "" end
local function modsOf(p)
	local s = modsStr(p)
	if s == "" then return {} end
	local ok, l = pcall(function() return HttpService:JSONDecode(s) end)
	return (ok and type(l) == "table") and l or {}
end
local function setMods(p, list)
	local s = p:FindFirstChild("RB_Mods")
	if #list == 0 then if s then s.Parent = nil end return end
	if not s then
		s = Instance.new("StringValue")
		s.Name = "RB_Mods"
		s.Parent = p
	end
	s.Value = HttpService:JSONEncode(list)
end
-- the mesh as it looks with its modifiers (inEdit: only the ones shown in Edit Mode)
local function evaluated(p, m, inEdit)
	local list = modsOf(p)
	if #list == 0 then return m end
	if inEdit then
		local l2 = {}
		for _, md in ipairs(list) do if md.edit ~= false then l2[#l2 + 1] = md end end
		list = l2
	end
	local ok, r = pcall(Mods.evaluate, m, list)
	return ok and r or m
end
-- UVs (U menu): worked out at build time from the part's RB_UVMode / RB_UVScale
local function uvOf(p)
	local m = p and p:GetAttribute("RB_UVMode")
	if not m or m == "" then return nil end
	return { mode = m, scale = p:GetAttribute("RB_UVScale") or 4 }
end
local function uvKey(p)
	local u = uvOf(p)
	return u and (u.mode .. ":" .. tostring(u.scale)) or ""
end
-- what a save covers: the mesh + its modifiers + its UVs
local function saveKey(p)
	local d, s = p.RB_Data.Value, modsStr(p)
	local u = uvKey(p)
	if s == "" and u == "" then return d end
	return d .. "|" .. s .. (u ~= "" and ("|uv:" .. u) or "")
end

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
local function ownView() return uiOn and view ~= nil and not useStudio end
local applyBuilt
local function applyMesh(p, b, tint)
	local mp, c, err = Display.build(evaluated(p, b, tint), tint and SEL_COL or nil, tint, uvOf(p))
	if not mp then return false, err end
	return applyBuilt(p, mp, c)
end
-- put an already-built MeshPart's mesh on the part (keeps the part where its origin is)
applyBuilt = function(p, mp, c)
	local o = originOf(p)
	local ok = pcall(function() p:ApplyMesh(mp) end)
	if not ok then
		-- older Studio: swap the part out for the new one
		mp.Name, mp.Color, mp.Material, mp.Anchored = p.Name, p.Color, p.Material, p.Anchored
		pcall(function() mp.TextureID = p.TextureID end)
		for _, ch in ipairs(p:GetChildren()) do ch.Parent = mp end
		for k, v in pairs(p:GetAttributes()) do mp:SetAttribute(k, v) end
		mp.Parent = p.Parent
		p.Parent = nil
		if obj == p then obj = mp end
		p = mp
	else
		p.Size = mp.Size
		Display.adopt(p, Display.emOf[mp])
		Display.emOf[mp] = nil
		mp:Destroy()
	end
	p.CFrame = o * CFrame.new(c)
	p:SetAttribute("RB_Center", c)
	p:SetAttribute("RB_Size", p.Size)
	return true, nil, p
end

-- ===== saving to Roblox (real Mesh assets, so the mesh stays in the place and publishes) =====
local BETA_MSG = "Saving needs Studio's beta: File > Beta Features > turn on \"CreateAssetAsync Luau API\", then restart Studio."
local autoSave = true
pcall(function() local v = plugin:GetSetting("RB_AutoSave") if v ~= nil then autoSave = v == true end end)
local saving = {}
local function dataHash(str)
	local h = 2166136261
	for i = 1, #str do h = bit32.band(bit32.bxor(h, string.byte(str, i)) * 16777619, 0xFFFFFFFF) end
	return string.format("%08x:%d", h, #str)
end
local function isSaved(p)
	local d = p and p:FindFirstChild("RB_Data")
	return d ~= nil and p:GetAttribute("RB_AssetId") ~= nil and p:GetAttribute("RB_SavedHash") == dataHash(saveKey(p))
end
local function saveMesh(p, quiet, silent)
	if not (p and p:IsA("MeshPart") and p:FindFirstChild("RB_Data")) or saving[p] then return end
	saving[p] = true
	task.spawn(function()
		local ok, err = pcall(function()
			if not silent then setStatus("Saving " .. p.Name .. " to Roblox...") end
			local data = saveKey(p)
			local m = evaluated(p, (loadFrom(p)))
			local params = { Name = p.Name, Description = "Made with ROBLEND (free, open source mesh editor)" }
			pcall(function()
				if game.CreatorType == Enum.CreatorType.Group and game.CreatorId > 0 then
					params.CreatorId = game.CreatorId
					params.CreatorType = Enum.AssetCreatorType.Group
				end
			end)
			local id, uerr, kind, c = Display.upload(m, params, uvOf(p))
			if not id then
				setStatus(kind == "api" and BETA_MSG or ("Couldn't save " .. p.Name .. ": " .. tostring(uerr)))
				return
			end
			p:SetAttribute("RB_AssetId", id)
			local real, lerr = Display.fromAsset(id)
			if not real then
				setStatus(("Uploaded %s as rbxassetid://%s but Roblox hasn't made it ready yet (%s). Save again in a minute."):format(p.Name, tostring(id), tostring(lerr)))
				return
			end
			if p.Parent and not (editing and p == obj and not ownView()) and saveKey(p) == data then
				local rec
				pcall(function() rec = CHS:TryBeginRecording("ROBLEND", "ROBLEND save") end)
				applyBuilt(p, real, c)
				p:SetAttribute("RB_SavedHash", dataHash(data))
				if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
				setStatus(("Saved %s to Roblox (rbxassetid://%s). It stays in the place and publishes."):format(p.Name, tostring(id)))
			else
				real:Destroy()
				if not silent then setStatus(p.Name .. " changed while saving - it will save again when you leave Edit Mode.") end
			end
		end)
		saving[p] = nil
		if not ok then setStatus("Couldn't save " .. p.Name .. ": " .. tostring(err)) end
	end)
end
-- a ROBLEND part that was never saved shows nothing / Roblox's checker after Studio restarts: rebuild its look
-- from RB_Data (only once per session, and only for parts not saved to Roblox)
local fixedLook = setmetatable({}, { __mode = "k" })
local function fixUnsaved(p)
	if fixedLook[p] or not (p and p:IsA("MeshPart") and p:FindFirstChild("RB_Data")) then return end
	fixedLook[p] = true
	if isSaved(p) or Display.partEm[p] then return end
	pcall(function() applyMesh(p, loadFrom(p), false) end)
end
-- the part has a saved mesh and nothing changed: put the saved one back (edit mode swaps in a temporary one)
local function restoreSaved(p)
	local id = p:GetAttribute("RB_AssetId")
	if not id then return end
	task.spawn(function()
		local real = Display.fromAsset(id)
		if real and p.Parent and not (editing and p == obj) and isSaved(p) then
			local c = Display.bounds(evaluated(p, (loadFrom(p))))
			applyBuilt(p, real, c)
		elseif real then
			real:Destroy()
		end
	end)
end

-- ===== world helpers =====
local function W(co) return origin * co end
local function camera() if ownView() then return view end return workspace.CurrentCamera end
local function toScreen(wp)
	local sp, vis = camera():WorldToViewportPoint(wp)
	return Vector2.new(sp.X, sp.Y), vis and sp.Z > 0, sp.Z
end
local mouse = plugin:GetMouse()
local function mousePos() return Vector2.new(mouse.X, mouse.Y) end
local function getRay() if ownView() then return view:ray(mousePos()) end return mouse.UnitRay end

local function buildWorldTris()
	worldTris = {}
	for _, t in ipairs(Display.triangles(bm, true)) do
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
	if ownView() then view:line(a, b, col, 1.4 * (w or 1)) return end
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
	if ownView() then view:dot(p, col, 7 * (s or 1)) return end
	local x = pGet(pool("SphereHandleAdornment"))
	x.CFrame = CFrame.new(p)
	x.Radius = (camera().CFrame.Position - p).Magnitude * 0.0045 * (s or 1)
	x.Color3 = col
	x.Transparency = 0
end

local drawObjects -- object-mode outlines (set below)
local drawExtras  -- 3D cursor, knife, measure, annotations, tool previews (set below)
local SEAM_COL, SHARP_COL, CREASE_COL = Color3.fromRGB(219, 37, 18), Color3.fromRGB(0, 255, 255), Color3.fromRGB(204, 0, 153)
local function drawCage()
	pBegin()
	if view then view:beginCage() end
	if editing and bm and not paintMode then
		local many = bm.ne > 6000
		for e in pairs(bm.edges) do
			local on = e.sel
			if (on or not many) and not e.hide then
				-- Blender's theme: seam red, sharp cyan, crease magenta
				local col = (hover == e) and ACT_COL or (on and SEL_COL or (e.seam and SEAM_COL or e.sharp and SHARP_COL or e.crease and CREASE_COL or WIRE_COL))
				line(W(e.v1.co), W(e.v2.co), col, (mode == "edge" and (on or hover == e)) and 2.2 or 1)
			end
		end
		if mode == "vert" and bm.nv < 6000 then
			for v in pairs(bm.verts) do
				if not v.hide then dot(W(v.co), (hover == v) and ACT_COL or (v.sel and SEL_COL or WIRE_COL), (v.sel or hover == v) and 1.2 or 0.8) end
			end
		elseif mode == "face" and bm.nf < 6000 then
			for f in pairs(bm.faces) do
				if not f.hide then dot(W(BMesh.faceCenter(f)), (hover == f) and ACT_COL or (f.sel and SEL_COL or WIRE_COL), 0.7) end
			end
		end
		-- loop cut preview
		if modal and modal.kind == "loopcut" and modal.preview then
			for _, seg in ipairs(modal.preview) do line(seg[1], seg[2], Color3.fromRGB(255, 220, 60), 2) end
		end
	end
	if ownView() and drawObjects then drawObjects() end
	if ownView() and drawExtras then drawExtras() end
	pEnd()
	if view then view:endCage() end
end

-- the mesh being edited, shown in our 3D view (selected faces tinted) - the real part is updated on commit
local function lookOf(p)
	local tr = 0
	if xray then tr = 0.5 end
	if shading == "wire" then tr = 1 end
	local tex
	pcall(function() tex = p.TextureID end)
	return { Color = p.Color, Material = p.Material, Transparency = tr, TextureID = tex }
end
local function showEdit()
	if not (ownView() and obj and bm) then return false end
	local mp, c, err = Display.build(evaluated(obj, bm, true), SEL_COL, true, uvOf(obj))
	if not mp then
		view:removeObject(obj)
		return true, err
	end
	view:setObject(obj, mp, origin * CFrame.new(c), lookOf(obj))
	return true
end

-- ===== saving + undo (each change = one Studio undo step; Ctrl+Z reloads the mesh) =====
local function commit(what)
	if not (obj and bm) then return end
	local rec
	pcall(function() rec = CHS:TryBeginRecording("ROBLEND", "ROBLEND " .. what) end)
	local val = encode(bm)
	lastWritten = val
	dataOf(obj).Value = val
	if not ownView() then
		local _, _, np = applyMesh(obj, bm, editing)
		if np then obj = np end
		origin = originOf(obj)
	end
	worldTris = nil
	showEdit()
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else CHS:SetWaypoint("ROBLEND " .. what) end
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
	-- a curve (only line paths, no faces): edit its points
	if m.nf == 0 and m.nv > 0 then mode = "vert" end
	worldTris = nil
	lastWritten = dataOf(p).Value
	clearSel()
	Selection:Set({})
	activeObj = p
	plugin:Activate(true)
	watchData()
	setMode(mode)
	dirtyMesh, dirtyCage = true, true
	setStatus("EDIT: " .. p.Name .. ". 1/2/3 = vertex/edge/face, G S R E I, Ctrl+R loop cut, Tab = done.")
	if buttons["Edit (Tab)"] then buttons["Edit (Tab)"].BackgroundColor3 = Color3.fromRGB(0, 150, 90) end
end

local function exitEdit()
	if not editing then return end
	paintMode = nil
	if paintHooks.exit then pcall(paintHooks.exit) end
	modal = nil
	if obj and bm then
		editing = false
		local ok, _, np = applyMesh(obj, bm, false)
		if np then obj = np end
		local done = obj
		task.defer(function() if isSaved(done) then restoreSaved(done) elseif autoSave then saveMesh(done, true) end end)
		Selection:Set({ obj })
		activeObj = obj
		if scene[obj] then scene[obj].data = nil end -- redraw it untinted
	end
	editing = false
	if dataConn then dataConn:Disconnect() dataConn = nil end
	bm = nil
	obj = nil
	worldTris = nil
	hover = nil
	pBegin() pEnd()
	if view then view:beginCage() view:endCage() end
	if not ownView() then plugin:Deactivate() end
	dirtyCage = true
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
	elseif kind == "Sphere" then Ops.uvSphere(m, 24, 12, 2)
	elseif kind == "IcoSphere" then Ops.icoSphere(m, 2, 2)
	elseif kind == "Cone" then Ops.cone(m, 32, 2, 4)
	elseif kind == "Torus" then Ops.torus(m, 48, 12, 2, 0.5)
	-- curves (Add > Curve): line paths that the Tube modifier turns into pipes
	elseif kind == "CurveBezier" or kind == "CurvePath" or kind == "CurveCircle" then
		local pts = {}
		if kind == "CurveBezier" then pts = { V3(-3, 0, 0), V3(-1, 1.5, 0), V3(1, -1.5, 0), V3(3, 0, 0) }
		elseif kind == "CurvePath" then for i = 0, 4 do pts[#pts + 1] = V3(-4 + i * 2, 0, 0) end
		else for i = 0, 15 do local a = i / 16 * 2 * math.pi pts[#pts + 1] = V3(math.cos(a) * 2, 0, math.sin(a) * 2) end end
		local vs = {}
		for i, p in ipairs(pts) do vs[i] = m:vertCreate(p) end
		for i = 1, #vs - 1 do m:edgeCreate(vs[i], vs[i + 1]) end
		if kind == "CurveCircle" then m:edgeCreate(vs[#vs], vs[1]) end
	elseif kind == "Text" then
		Font.build(m, "Text", { pixel = 0.5, depth = 1 })
	end
end
local CURVE_KINDS = { CurveBezier = "Bezier Curve", CurvePath = "Path", CurveCircle = "Curve Circle" }
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
	-- a curve comes with a Tube modifier (so it shows as a pipe); edit its path in Edit Mode
	local mods
	if CURVE_KINDS[kind] then
		local tube = Mods.new("tube")
		tube.name = Mods.BY_ID.tube.name
		mods = { tube }
	end
	local mp, c, err = Display.build(mods and Mods.evaluate(m, mods) or m)
	if not mp then
		setStatus("Couldn't make the mesh: " .. tostring(err) .. "  (Game Settings > Security > allow Mesh / Image APIs, then try again)")
		return
	end
	local rec
	pcall(function() rec = CHS:TryBeginRecording("ROBLEND", "ROBLEND add " .. kind) end)
	mp.Name = NAME .. " " .. (CURVE_KINDS[kind] or kind)
	mp.Anchored = true
	mp.Color = Color3.fromRGB(200, 200, 205)
	mp.Material = Enum.Material.SmoothPlastic
	local base = ownView() and (CURSOR - V3(0, 2, 0)) or spawnPoint()
	base += V3(0, 2, 0)
	mp.CFrame = CFrame.new(base + c)
	local sv = Instance.new("StringValue")
	sv.Name = "RB_Data"
	sv.Value = encode(m)
	sv.Parent = mp
	mp:SetAttribute("RB_Center", c)
	mp:SetAttribute("RB_Size", mp.Size)
	mp:SetAttribute("ROBLEND", VERSION)
	if mods then setMods(mp, mods) end
	if kind == "Text" then
		mp:SetAttribute("RB_Text", "Text")
		mp:SetAttribute("RB_TextPixel", 0.5)
		mp:SetAttribute("RB_TextDepth", 1)
	end
	mp.Parent = workspace
	Display.adopt(mp, Display.emOf[mp])
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else CHS:SetWaypoint("ROBLEND add") end
	Selection:Set({ mp })
	activeObj = mp
	if CURVE_KINDS[kind] then
		setStatus("Added a " .. CURVE_KINDS[kind] .. ". Tab = edit its points (Ctrl + right click extends it); pipe size in Properties > Modifiers.")
	elseif kind == "Text" then
		setStatus("Added Text. Change the words in Properties > Data > Text.")
	else
		setStatus("Added a " .. kind .. ". Press Tab (or Edit) to edit it.")
	end
end

-- ===== picking =====
local PICK_PX = 14
local function pickVert(mp)
	local best, bd, bz = nil, PICK_PX, math.huge
	for v in pairs(bm.verts) do
		if v.hide then continue end
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
		if e.hide then continue end
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
	local r = getRay()
	local _, f = rayMesh(r.Origin, r.Direction)
	if f then return f end
	-- x-ray: nearest face dot on screen
	local mp = mousePos()
	local best, bd = nil, PICK_PX
	for g in pairs(bm.faces) do
		if g.hide then continue end
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
	-- Pivot Point (Blender's . menu): Median Point, 3D Cursor or Individual Origins
	if EDIT.pivot == "cursor" then cLocal = origin:PointToObjectSpace(CURSOR) end
	local ic
	if EDIT.pivot == "individual" and kind ~= "G" then
		-- each connected island of the selection turns / scales round its own middle
		local sel, parent = {}, {}
		for _, v in ipairs(vs) do sel[v] = true parent[v] = v end
		local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]] x = parent[x] end return x end
		for e in pairs(bm.edges) do
			if sel[e.v1] and sel[e.v2] then
				local a, b = find(e.v1), find(e.v2)
				if a ~= b then parent[a] = b end
			end
		end
		local sum, cnt = {}, {}
		for _, v in ipairs(vs) do local r = find(v) sum[r] = (sum[r] or V3()) + v.co cnt[r] = (cnt[r] or 0) + 1 end
		ic = {}
		for _, v in ipairs(vs) do local r = find(v) ic[v] = sum[r] / cnt[r] end
	end
	local m = mousePos()
	modal = {
		ic = ic,
		kind = kind, verts = vs, orig = orig, c = cLocal, cw = W(cLocal), m0 = m, ray0 = getRay(),
		axis = opts and opts.axis or nil, axisWorld = opts and opts.axisWorld or nil, num = "", what = opts and opts.what or nil,
	}
	local sc = toScreen(modal.cw)
	modal.cs = sc
	modal.releaseConfirm = opts and opts.releaseConfirm or nil
	if EDIT.prop then
		-- proportional editing: unselected verts near the selection follow, smooth falloff (Blender's default)
		local sel = {}
		for _, v in ipairs(vs) do sel[v] = true end
		modal.propWeights = function()
			modal.prop = {}
			for v in pairs(bm.verts) do
				if not sel[v] and not v.hide then
					local best = math.huge
					local co = orig[v] or v.co
					for _, s in ipairs(vs) do local d = (co - orig[s]).Magnitude if d < best then best = d end end
					if best < EDIT.propR then
						local t = 1 - best / EDIT.propR
						modal.prop[v] = (FALLOFF[EDIT.propFalloff] or FALLOFF.Smooth)(t)
						orig[v] = co
					end
				end
			end
		end
		modal.propWeights()
	end
	if EDIT.mirrorX then
		-- X mirror: the vert on the other side of X = 0 follows (the mesh's own X)
		modal.mirror, modal.center = {}, {}
		local sel = {}
		for _, v in ipairs(vs) do sel[v] = true end
		for _, v in ipairs(vs) do
			if math.abs(v.co.X) < 1e-4 then modal.center[v] = true
			else
				local target = V3(-v.co.X, v.co.Y, v.co.Z)
				for u in pairs(bm.verts) do
					if not sel[u] and (u.co - target).Magnitude < 1e-3 then modal.mirror[v] = u orig[u] = u.co break end
				end
			end
		end
	end
	setStatus(({ G = "MOVE", S = "SCALE", R = "ROTATE" })[kind] .. ": move the mouse. X / Y / Z = lock to an axis, type a number, Ctrl = snap. Click / Enter = done, Esc = cancel.")
end

-- ===== object mode: G / R / S on whole parts (our 3D view) =====
local function selectedParts()
	local out = {}
	for _, p in ipairs(Selection:Get()) do if p:IsA("BasePart") then out[#out + 1] = p end end
	return out
end
local function startObjTransform(kind)
	local ps = selectedParts()
	if #ps == 0 then setStatus("Nothing selected.") return end
	local orig, c = {}, V3()
	for _, p in ipairs(ps) do orig[p] = { cf = p.CFrame, size = p.Size } c += p.CFrame.Position end
	c = c / #ps
	local rec
	pcall(function() rec = CHS:TryBeginRecording("ROBLEND", "ROBLEND " .. kind) end)
	modal = { kind = kind, obj = true, parts = ps, orig = orig, cw = c, cs = toScreen(c), m0 = mousePos(), ray0 = getRay(), num = "", rec = rec }
	setStatus(({ G = "Move", S = "Resize", R = "Rotate" })[kind] .. ": move the mouse. X / Y / Z = axis, type a number, Ctrl = snap. Click / Enter = done, Esc = cancel.")
end
local function applyObjTransform()
	local M = modal
	local mp = mousePos()
	local num = tonumber(M.num)
	local snap = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local axisW = M.axis and AXES[M.axis]
	local cam = camera()
	if M.kind == "G" then
		local dW
		if axisW then
			local t = num
			if not t then
				local t1, t0 = axisParam(getRay(), M.cw, axisW), axisParam(M.ray0, M.cw, axisW)
				t = (t1 and t0) and (t1 - t0) or 0
				if snap then t = math.floor(t + 0.5) end
			end
			dW = axisW * t
		else
			local n = cam.CFrame.LookVector
			local p1, p0 = planeHit(getRay(), M.cw, n), planeHit(M.ray0, M.cw, n)
			dW = (p1 and p0) and (p1 - p0) or V3()
			if num then dW = cam.CFrame.RightVector * num end
			if snap then dW = V3(math.floor(dW.X + 0.5), math.floor(dW.Y + 0.5), math.floor(dW.Z + 0.5)) end
		end
		for p, o in pairs(M.orig) do p.CFrame = o.cf + dW end
		M.info = ("D: %.2f  %.2f  %.2f"):format(dW.X, dW.Y, dW.Z)
	elseif M.kind == "S" then
		local d0 = (M.m0 - M.cs).Magnitude
		local f = num or (d0 > 1 and (mp - M.cs).Magnitude / d0 or 1)
		if snap and not num then f = math.floor(f * 10 + 0.5) / 10 end
		for p, o in pairs(M.orig) do
			local pos = o.cf.Position
			local k = V3(f, f, f)
			if axisW then
				local la = o.cf:VectorToObjectSpace(axisW)
				k = V3(1, 1, 1) + V3(math.abs(la.X), math.abs(la.Y), math.abs(la.Z)) * (f - 1)
				pos = M.cw + (pos - M.cw) + axisW * ((pos - M.cw):Dot(axisW) * (f - 1))
			else
				pos = M.cw + (pos - M.cw) * f
			end
			p.Size = V3(math.max(0.001, o.size.X * math.abs(k.X)), math.max(0.001, o.size.Y * math.abs(k.Y)), math.max(0.001, o.size.Z * math.abs(k.Z)))
			p.CFrame = o.cf.Rotation + pos
		end
		M.info = ("Scale %.3f"):format(f)
	else
		local a0 = math.atan2(M.m0.Y - M.cs.Y, M.m0.X - M.cs.X)
		local a1 = math.atan2(mp.Y - M.cs.Y, mp.X - M.cs.X)
		local ang = num and math.rad(num) or -(a1 - a0)
		if snap and not num then ang = math.rad(math.floor(math.deg(ang) / 15 + 0.5) * 15) end
		local ax = axisW or -cam.CFrame.LookVector
		local rot = CFrame.fromAxisAngle(ax, ang)
		for p, o in pairs(M.orig) do p.CFrame = CFrame.new(M.cw) * rot * CFrame.new(-M.cw) * o.cf end
		M.info = ("Rot %.1f"):format(math.deg(ang))
	end
	dirtyCage = true
	setStatus((M.info or "") .. (M.axis and ("  along " .. M.axis .. (M.axisLocal and " (Local)" or "")) or "") .. (M.num ~= "" and ("  [" .. M.num .. "]") or "") .. "   click / Enter = done, Esc = cancel")
end
local function finishObjModal(M, cancel)
	if cancel then for p, o in pairs(M.orig) do p.CFrame = o.cf p.Size = o.size end end
	if M.rec then
		CHS:FinishRecording(M.rec, cancel and Enum.FinishRecordingOperation.Cancel or Enum.FinishRecordingOperation.Commit)
	elseif not cancel then
		CHS:SetWaypoint("ROBLEND " .. M.kind)
	end
	setStatus(cancel and "Cancelled." or "Done.")
	dirtyCage = true
end

-- Snap to Vertex / Face (Blender's snap targets): where the selection's middle goes, in mesh space, or nil
snapTargetLocal = function(M)
	local moving = {}
	for _, v in ipairs(M.verts) do moving[v] = true end
	local mp = mousePos()
	if EDIT.snapTarget == "Vertex" then
		local best, bd = nil, 30
		for v in pairs(bm.verts) do
			if not moving[v] and not v.hide then
				local sp, vis = toScreen(W(v.co))
				if vis then
					local d = (sp - mp).Magnitude
					if d < bd then best, bd = v, d end
				end
			end
		end
		return best and best.co or nil
	elseif EDIT.snapTarget == "Face" then
		local ray = getRay()
		local bt, bp
		for f in pairs(bm.faces) do
			if not f.hide then
				local vs = BMesh.faceVerts(f)
				local still = true
				for _, v in ipairs(vs) do if moving[v] then still = false break end end
				if still then
					for _, tri in ipairs(Display.triangulate(vs, f.no)) do
						local a, b, c = W(vs[tri[1]].co), W(vs[tri[2]].co), W(vs[tri[3]].co)
						local hit = rayTri(ray.Origin, ray.Direction, a, b, c)
						if hit and (not bt or hit < bt) then bt, bp = hit, ray.Origin + ray.Direction * hit end
					end
				end
			end
		end
		return bp and origin:PointToObjectSpace(bp) or nil
	end
	return nil
end
local function applyTransform()
	local M = modal
	if M.obj then applyObjTransform() return end
	local mp = mousePos()
	local num = tonumber(M.num)
	local snap = (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) ~= EDIT.snap
	local axisW = M.axisWorld or (M.axis and (M.axisLocal and origin:VectorToWorldSpace(AXES[M.axis]) or AXES[M.axis]))
	local axisL = axisW and origin:VectorToObjectSpace(axisW).Unit
	if M.kind == "G" then
		local dL
		if axisW then
			local t
			if num then t = num else
				local t1, t0 = axisParam(getRay(), M.cw, axisW), axisParam(M.ray0, M.cw, axisW)
				t = (t1 and t0) and (t1 - t0) or 0
				if snap then t = math.floor(t + 0.5) end
			end
			dL = axisL * t
		else
			local n = camera().CFrame.LookVector
			local p1, p0 = planeHit(getRay(), M.cw, n), planeHit(M.ray0, M.cw, n)
			local dW = (p1 and p0) and (p1 - p0) or V3()
			if num then dW = camera().CFrame.RightVector * num end
			local target = (snap and not num and EDIT.snapTarget ~= "Increment") and snapTargetLocal(M) or nil
			if target then
				dL = target - M.c
			else
				if snap then dW = V3(math.floor(dW.X + 0.5), math.floor(dW.Y + 0.5), math.floor(dW.Z + 0.5)) end
				dL = origin:VectorToObjectSpace(dW)
			end
		end
		for _, v in ipairs(M.verts) do v.co = M.orig[v] + dL end
		for v, w in pairs(M.prop or {}) do v.co = M.orig[v] + dL * w end
		M.info = ("Move %.2f"):format(dL.Magnitude)
	elseif M.kind == "S" then
		local d0 = (M.m0 - M.cs).Magnitude
		local f = num or (d0 > 1 and (mp - M.cs).Magnitude / d0 or 1)
		if snap and not num then f = math.floor(f * 10 + 0.5) / 10 end
		for _, v in ipairs(M.verts) do
			local pc = M.ic and M.ic[v] or M.c
			local r = M.orig[v] - pc
			if axisL then
				local along = axisL * r:Dot(axisL)
				v.co = pc + (r - along) + along * f
			else
				v.co = pc + r * f
			end
		end
		for v, w in pairs(M.prop or {}) do
			local r = M.orig[v] - M.c
			local fw = 1 + (f - 1) * w
			if axisL then
				local along = axisL * r:Dot(axisL)
				v.co = M.c + (r - along) + along * fw
			else
				v.co = M.c + r * fw
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
		for _, v in ipairs(M.verts) do local pc = M.ic and M.ic[v] or M.c v.co = pc + rot * (M.orig[v] - pc) end
		for v, w in pairs(M.prop or {}) do v.co = M.c + CFrame.fromAxisAngle(axL, ang * w) * (M.orig[v] - M.c) end
		M.info = ("Rotate %.1f deg"):format(math.deg(ang))
	end
	if M.mirror then
		for v, u in pairs(M.mirror) do u.co = V3(-v.co.X, v.co.Y, v.co.Z) end
		for v in pairs(M.center) do v.co = V3(0, v.co.Y, v.co.Z) end
	end
	if M.prop then M.info ..= ("   Proportional size %.2f (wheel)"):format(EDIT.propR) end
	bm:normalsUpdate()
	worldTris = nil
	dirtyMesh, dirtyCage = true, true
	setStatus((M.info or "") .. (M.axis and ("  along " .. M.axis .. (M.axisLocal and " (Local)" or "")) or "") .. (M.num ~= "" and ("  [" .. M.num .. "]") or "") .. "   click / Enter = done, Esc = cancel")
end

local function finishModal(cancel)
	local M = modal
	if not M then return end
	modal = nil
	if M.obj then finishObjModal(M, cancel) return end
	if M.finish then M.finish(cancel) dirtyCage = true return end
	if M.kind == "G" or M.kind == "S" or M.kind == "R" then
		if cancel then
			for v, co in pairs(M.orig) do v.co = co end
			bm:normalsUpdate()
			if M.what then commit(M.what) setStatus(M.what .. " (not moved).") else dirtyMesh, dirtyCage = true, true setStatus("Cancelled.") end
		else
			local merged = 0
			if EDIT.autoMerge then
				local nb, n = Mods.mergeDoubles(bm, 0.001)
				if n > 0 then bm, merged = nb, n worldTris = nil hover = nil dirtyMesh = true end
			end
			commit(M.what or ({ G = "Move", S = "Scale", R = "Rotate" })[M.kind])
			setStatus((M.what or "Done") .. (merged > 0 and (" - Auto Merge welded " .. merged .. " vert" .. (merged == 1 and "" or "s")) or "") .. ".")
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
	local thick, depth
	if M.depthMode then
		thick = M.thickFixed or 0
		depth = tonumber(M.num) or ((M.depth0 or 0) + (M.dm0.Y - mousePos().Y) * wpp)
	else
		thick = tonumber(M.num) or math.abs((mousePos() - M.cs).Magnitude - (M.m0 - M.cs).Magnitude) * wpp
		depth = M.depth or 0
	end
	M.thick, M.depth = thick, depth
	local nb, _, fl = BMesh.fromData(M.snap)
	local set = {}
	for _, i in ipairs(M.picked) do if fl[i] then set[fl[i]] = true end end
	local _, nf = (M.individual and Ops.insetIndividual or Ops.insetRegion)(nb, set, thick, depth)
	bm = nb
	clearSel()
	for f in pairs(nf) do f.sel = true end
	flush()
	worldTris = nil
	dirtyMesh, dirtyCage = true, true
	setStatus(("INSET %.3f  depth %.3f%s   I = individual, Ctrl = depth, click / Enter = done, Esc = cancel"):format(thick, depth, M.individual and "  (individual)" or ""))
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
-- A = select all (Blender 2.8+ keymap; Alt A deselects)
function Tools.selectAll()
	clearSel()
	for v in pairs(bm.verts) do v.sel = not v.hide end
	for e in pairs(bm.edges) do e.sel = not e.hide end
	for f in pairs(bm.faces) do f.sel = not f.hide end
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
	local m = evaluated(p, (p == obj and bm) or (loadFrom(p)))
	local o = (p == obj) and origin or originOf(p)
	setStatus("Baking to parts...")
	local rec
	pcall(function() rec = CHS:TryBeginRecording("ROBLEND", "ROBLEND bake") end)
	local model = Display.bake(m, o, p, true)
	model.Name = p.Name .. " (baked)"
	model.Parent = p.Parent
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) end
	setStatus("Baked: a copy made of normal parts (saves + publishes). The mesh part is still there.")
end
function Tools.exportOBJ()
	local p = (editing and obj) or Selection:Get()[1]
	if not isRB(p) then setStatus("Pick a " .. NAME .. " part to export.") return end
	local m = evaluated(p, (p == obj and bm) or (loadFrom(p)))
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
label("SAVING: leaving Edit Mode uploads the mesh as a real Roblox Mesh asset (needs the Studio beta \"CreateAssetAsync Luau API\"), so it stays in the place and publishes. Bake to parts / Export .obj still work too.", 10, Color3.fromRGB(255, 200, 120))

-- ===== the Blender-style window (UI.lua + View.lua) =====
-- (in its own function: Luau allows 200 locals per function)
local function window()
local function shiftDown() return UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) end
local function selectedPart()
	if editing and obj then return obj end
	if activeObj and activeObj.Parent and table.find(Selection:Get(), activeObj) then return activeObj end
	local p = Selection:Get()[1]
	if p and p:IsA("BasePart") then return p end
	return nil
end
local function record(what, fn)
	local rec
	pcall(function() rec = CHS:TryBeginRecording("ROBLEND", "ROBLEND " .. what) end)
	local ok, err = pcall(fn)
	if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else CHS:SetWaypoint("ROBLEND " .. what) end
	if not ok then warn(NAME .. ": " .. tostring(err)) end
end

-- ----- the scene: every ROBLEND part, shown in our 3D view -----
local function sceneAdd(p)
	if p and p:IsA("MeshPart") and p:FindFirstChild("RB_Data") and not scene[p] then scene[p] = { part = p } end
end
local function sceneScan()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("MeshPart") and d:FindFirstChild("RB_Data") then sceneAdd(d) end
	end
end
pcall(function()
	workspace.DescendantAdded:Connect(function(d)
		if not uiOn then return end
		if d.Name == "RB_Data" and d.Parent then sceneAdd(d.Parent) elseif d:IsA("MeshPart") then sceneAdd(d) end
	end)
end)
local function featureEdges(m, all)
	local out = {}
	for e in pairs(m.edges) do
		local keep = all
		if not keep then
			local fs = BMesh.edgeFaces(e)
			keep = #fs ~= 2 or fs[1].no:Dot(fs[2].no) < 0.87
		end
		if keep then out[#out + 1] = { e.v1.co, e.v2.co } end
	end
	return out
end
local function syncScene()
	if not ownView() then return false end
	local changed = false
	for p, r in pairs(scene) do
		if not p.Parent or not p:FindFirstChild("RB_Data") then
			view:removeObject(p)
			scene[p] = nil
			changed = true
		elseif not (editing and p == obj) then
			local data, ms = p.RB_Data.Value, modsStr(p) .. uvKey(p)
			local look = lookOf(p)
			if r.hidden or r.localOut then
				if r.shown then view:removeObject(p) r.shown = false changed = true end
			elseif data ~= r.data or ms ~= r.mods or p.Size ~= r.size or not r.shown then
				local ok, m = pcall(function() return evaluated(p, (loadFrom(p))) end)
				if ok and m then
					local mp, c = Display.build(m, nil, nil, uvOf(p))
					if mp then
						view:setObject(p, mp, originOf(p) * CFrame.new(c), look)
						r.c, r.bm, r.feat, r.all, r.tris, r.shown = c, m, nil, nil, nil, true
					else
						view:removeObject(p)
						r.bm, r.shown = m, false
					end
				end
				r.data, r.mods, r.size, r.cf, r.col, r.mat, r.tr = data, ms, p.Size, p.CFrame, p.Color, p.Material, look.Transparency
				changed = true
			else
				if p.CFrame ~= r.cf then
					view:moveObject(p, originOf(p) * CFrame.new(r.c))
					r.cf, r.tris = p.CFrame, nil
					changed = true
				end
				if p.Color ~= r.col or p.Material ~= r.mat or look.Transparency ~= r.tr or look.TextureID ~= r.tex then
					local d = view.objects[p]
					if d then
						d.Color, d.Material, d.Transparency = p.Color, p.Material, look.Transparency
						pcall(function() d.TextureID = look.TextureID or "" end)
					end
					r.col, r.mat, r.tr, r.tex = p.Color, p.Material, look.Transparency, look.TextureID
					changed = true
				end
			end
		end
	end
	-- the mesh being edited follows colour / x-ray / shading changes too
	if editing and obj and view.objects[obj] then
		local d, look = view.objects[obj], lookOf(obj)
		d.Color, d.Material, d.Transparency = obj.Color, obj.Material, look.Transparency
	end
	return changed
end
local function objTris(r)
	if not r.tris then
		local o = originOf(r.part)
		r.tris = {}
		for _, t in ipairs(Display.triangles(r.bm)) do r.tris[#r.tris + 1] = { o * t[1], o * t[2], o * t[3] } end
	end
	return r.tris
end
local function pickObject(sp)
	local ray = view:ray(sp)
	local best, bt = nil, math.huge
	for p, r in pairs(scene) do
		if r.shown and r.bm and not (editing and p == obj) then
			for _, t in ipairs(objTris(r)) do
				local hit = rayTri(ray.Origin, ray.Direction, t[1], t[2], t[3])
				if hit and hit < bt then best, bt = p, hit end
			end
		end
	end
	return best
end
local function selectObject(p, add)
	if add and p then
		local cur = Selection:Get()
		local i = table.find(cur, p)
		if i and activeObj == p then table.remove(cur, i) activeObj = cur[#cur]
		elseif i then activeObj = p
		else cur[#cur + 1] = p activeObj = p end
		Selection:Set(cur)
	else
		Selection:Set(p and { p } or {})
		activeObj = p
	end
	dirtyCage = true
end
-- selected objects get Blender's orange outline (active one lighter); wireframe shading shows every edge
drawObjects = function()
	local sel = {}
	for _, p in ipairs(Selection:Get()) do sel[p] = true end
	local budget = 5000
	for p, r in pairs(scene) do
		if r.shown and r.bm and not (editing and p == obj) then
			local isSel = sel[p] and not editing
			local list
			if shading == "wire" then r.all = r.all or featureEdges(r.bm, true) list = r.all
			elseif isSel then r.feat = r.feat or featureEdges(r.bm, false) list = r.feat end
			if list then
				local o = originOf(p)
				local col = isSel and (p == activeObj and View.THEME.active or View.THEME.select) or Color3.new(0, 0, 0)
				for _, e in ipairs(list) do
					if budget <= 0 then break end
					budget -= 1
					line(o * e[1], o * e[2], col, isSel and 1.3 or 0.7)
				end
			end
		end
	end
end
local function boundsOf(points)
	local lo, hi = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, q in ipairs(points) do
		lo = V3(math.min(lo.X, q.X), math.min(lo.Y, q.Y), math.min(lo.Z, q.Z))
		hi = V3(math.max(hi.X, q.X), math.max(hi.Y, q.Y), math.max(hi.Z, q.Z))
	end
	return lo, hi
end
local function partCorners(p, out)
	local h = p.Size / 2
	for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
		out[#out + 1] = p.CFrame * V3(h.X * sx, h.Y * sy, h.Z * sz)
	end end end
end
local function frameAll()
	if not view then return end
	local pts = {}
	for p, r in pairs(scene) do if p.Parent and not r.hidden then partCorners(p, pts) end end
	if #pts == 0 then view.focus, view.dist = CURSOR, 30 view:update() else view:frameBox(boundsOf(pts)) end
	view.viewName = nil
	dirtyCage = true
end
local function frameSelected()
	if not view then return end
	local pts = {}
	if editing and bm then
		for v in pairs(bm.verts) do if v.sel then pts[#pts + 1] = W(v.co) end end
		if #pts == 0 then for v in pairs(bm.verts) do pts[#pts + 1] = W(v.co) end end
	else
		for _, p in ipairs(selectedParts()) do partCorners(p, pts) end
	end
	if #pts == 0 then frameAll() return end
	view:frameBox(boundsOf(pts))
	dirtyCage = true
end
local function deleteObjects()
	local ps = selectedParts()
	if #ps == 0 then setStatus("Nothing selected.") return end
	record("Delete", function() for _, p in ipairs(ps) do p.Parent = nil end end)
	Selection:Set({})
	activeObj = nil
	dirtyCage = true
	setStatus(("Deleted %d object%s."):format(#ps, #ps == 1 and "" or "s"))
end
local function duplicateObjects()
	local ps = selectedParts()
	if #ps == 0 then setStatus("Nothing selected.") return end
	local copies = {}
	record("Duplicate", function()
		for _, p in ipairs(ps) do
			local c = p:Clone()
			c.Parent = p.Parent
			copies[#copies + 1] = c
			sceneAdd(c)
		end
	end)
	Selection:Set(copies)
	activeObj = copies[#copies]
	startObjTransform("G")
end
-- ===== shared context for the split-out modules (ObjectTools.lua, Sculpt.lua, Paint.lua, ...) =====
local ctx = {
	NAME = NAME, Selection = Selection, CHS = CHS, HttpService = HttpService, UIS = UIS, MT = MT, Display = Display, BMesh = BMesh, Ops = Ops, Mods = Mods,
	setStatus = setStatus, loadFrom = loadFrom, originOf = originOf, encode = encode, applyMesh = applyMesh, dataOf = dataOf, isRB = isRB,
	record = record, selectedParts = selectedParts, commit = commit, scene = scene, flush = flush, clearSel = clearSel,
	toScreen = toScreen, getRay = getRay, mousePos = mousePos, W = W, planeHit = planeHit, rayTri = rayTri, shiftDown = shiftDown,
}
function ctx.get()
	return { editing = editing, obj = obj, bm = bm, mode = mode, modal = modal, origin = origin, cursor = CURSOR, activeObj = activeObj, xray = xray, view = view, ui = ui }
end
function ctx.setActive(p) activeObj = p end
function ctx.setBm(m) bm = m worldTris = nil end
function ctx.setModal(M) modal = M end
function ctx.dirtyCage() dirtyCage = true end
function ctx.dirtyMesh() dirtyMesh = true dirtyCage = true worldTris = nil end
local OT = ObjectTools.new(ctx)
ctx.rayMesh, ctx.camera = rayMesh, camera
function ctx.ctrlDown() return UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl) end
local SCULPT = Sculpt.new(ctx)
local PAINT = Paint.new(ctx)
-- the brush controller for the current mode (Sculpt Mode / Vertex Paint)
local function brushCtl() return paintMode == "paint" and PAINT or SCULPT end
paintHooks.exit = function() SCULPT.exit() PAINT.exit() end

-- ===== the Modeling tab: Blender's Edit Mode tools (own function: Luau's 200-local limit) =====
local function modelingTools()
	local MOD = { tool = "select", strokes = {}, measure = nil, preview = nil }
	local THEME = View.THEME

	-- ----- snapshots: undo a live tool back to where it started (selection carried by index) -----
	local function snapshot()
		local data, vi, fOrder = bm:toData()
		local sn = { data = data, sv = {}, sf = {}, se = {}, hv = {}, hf = {} }
		for v, i in pairs(vi) do
			if v.sel then sn.sv[#sn.sv + 1] = i end
			if v.hide then sn.hv[#sn.hv + 1] = i end
		end
		for i, f in ipairs(fOrder) do
			if f.sel then sn.sf[#sn.sf + 1] = i end
			if f.hide then sn.hf[#sn.hf + 1] = i end
		end
		for e in pairs(bm.edges) do if e.sel then sn.se[#sn.se + 1] = { vi[e.v1], vi[e.v2] } end end
		return sn
	end
	local function restore(sn)
		local nb, vs, fl = BMesh.fromData(sn.data)
		for _, i in ipairs(sn.sv) do if vs[i] then vs[i].sel = true end end
		for _, i in ipairs(sn.sf) do if fl[i] then fl[i].sel = true end end
		for _, p in ipairs(sn.se) do
			local e = vs[p[1]] and vs[p[2]] and BMesh.edgeExists(vs[p[1]], vs[p[2]])
			if e then e.sel = true end
		end
		for _, i in ipairs(sn.hv) do if vs[i] then vs[i].hide = true end end
		for _, i in ipairs(sn.hf) do if fl[i] then fl[i].hide = true end end
		for e in pairs(nb.edges) do if e.v1.hide or e.v2.hide then e.hide = true end end
		return nb
	end
	MOD.snapshot, MOD.restore = snapshot, restore
	local function changed(what)
		worldTris = nil
		dirtyMesh, dirtyCage = true, true
		if what then commit(what) end
	end
	local function wpp(at)
		local cam = camera()
		local depth = (cam.CFrame.Position - at).Magnitude
		return 2 * depth * math.tan(math.rad(cam.FieldOfView) / 2) / math.max(1, cam.ViewportSize.Y)
	end
	local function selCenterLocal()
		local vs = selectedVertsList()
		return #vs > 0 and centerOf(vs) or V3()
	end
	local function cursorLocal() return origin:PointToObjectSpace(CURSOR) end
	local function viewLocal(vec) return origin:VectorToObjectSpace(vec) end

	-- ----- "live" tools: drag the mouse (or type a number) and the operator re-runs from the snapshot -----
	-- mode: dist (>= 0, away from the selection), signed, x (left / right), angle (round the selection), drag (distance moved)
	local function startParam(opts)
		if not editing or modal then return end
		local sn = snapshot()
		local cLocal = opts.center or selCenterLocal()
		local cw = W(cLocal)
		local M = { kind = "param", name = opts.name, what = opts.what, cw = cw, cs = toScreen(cw), m0 = mousePos(), num = "", releaseConfirm = opts.releaseConfirm, acc = 0,
			onWheel = opts.onWheel, onKey = opts.onKey }
		local lastA = nil
		M.update = function()
			local mp = mousePos()
			local num = tonumber(M.num)
			local v
			if num then
				v = opts.mode == "angle" and math.rad(num) or num
			elseif opts.mode == "dist" or opts.mode == "signed" then
				v = ((mp - M.cs).Magnitude - (M.m0 - M.cs).Magnitude) * wpp(M.cw)
				if opts.mode == "dist" then v = math.max(0, v) end
			elseif opts.mode == "x" then
				v = (mp.X - M.m0.X) / 200
			elseif opts.mode == "drag" then
				v = (mp - M.m0).Magnitude * wpp(M.cw)
			elseif opts.mode == "angle" then
				local a = math.atan2(mp.Y - M.cs.Y, mp.X - M.cs.X)
				if lastA then
					local d = a - lastA
					if d > math.pi then d -= 2 * math.pi elseif d < -math.pi then d += 2 * math.pi end
					M.acc -= d
				end
				lastA = a
				v = M.acc
			elseif opts.mode == "vec" then
				v = mp - M.m0
			end
			M.value = v
			bm = restore(sn)
			local ok, err = pcall(opts.fn, v)
			if not ok then setStatus(opts.name .. ": " .. tostring(err)) end
			worldTris = nil
			dirtyMesh, dirtyCage = true, true
			local shown = (typeof(v) == "number") and (opts.mode == "angle" and ("%.1f deg"):format(math.deg(v)) or ("%.3f"):format(v)) or ""
			setStatus(("%s  %s%s%s   drag / type a value, click or Enter = done, Esc = cancel"):format(opts.name, shown, M.num ~= "" and ("  [" .. M.num .. "]") or "", opts.info and ("   " .. opts.info()) or ""))
		end
		M.finish = function(cancel)
			if cancel and not opts.commitOnCancel then
				bm = restore(sn)
				changed()
				setStatus(opts.name .. " cancelled.")
				return
			end
			if cancel then bm = restore(sn) end
			if M.value == nil and not cancel then M.update() end
			flush()
			changed(opts.name)
			setStatus(opts.name .. " done.")
		end
		modal = M
		lastA = nil
		M.update()
	end
	MOD.startParam = startParam

	local function selVertsSet() return MT.selVerts(bm) end
	local function origOf(vs) local o = {} for v in pairs(vs) do o[v] = v.co end return o end
	local function regionNormals(vs)
		local n = {}
		for v in pairs(vs) do
			local s = V3()
			for _, f in ipairs(BMesh.vertFaces(v)) do if f.sel then s += f.no end end
			if s.Magnitude < 1e-9 then s = MT.vertNormal(v) end
			n[v] = s.Magnitude > 1e-9 and s.Unit or V3(0, 1, 0)
		end
		return n
	end

	local T = {}
	-- bevel (Ctrl B edges, Ctrl Shift B verts)
	function T.bevel(opts)
		local vertexOnly = (opts and opts.vertex) or mode == "vert"
		if not vertexOnly and not next(MT.selEdges(bm)) then setStatus("Pick edges to bevel.") return end
		if vertexOnly and not next(MT.selVerts(bm)) then setStatus("Pick verts to bevel.") return end
		MOD.bevelSegs = MOD.bevelSegs or 1
		local function seg(stepsUp)
			MOD.bevelSegs = math.clamp(MOD.bevelSegs + stepsUp, 1, 32)
			return true
		end
		startParam({ name = vertexOnly and "Bevel Vertices" or "Bevel", mode = "dist", releaseConfirm = opts and opts.release,
			info = function() return vertexOnly and "" or ("Segments %d (wheel / PageUp / PageDown)"):format(MOD.bevelSegs) end,
			onWheel = function(steps) if not vertexOnly then seg(steps > 0 and 1 or -1) end end,
			onKey = function(k)
				if vertexOnly then return false end
				if k == Enum.KeyCode.PageUp then return seg(1) end
				if k == Enum.KeyCode.PageDown then return seg(-1) end
				return false
			end,
			fn = function(d)
				if d < 1e-3 then return end
				local nb = MT.bevel(bm, d, vertexOnly, MOD.bevelSegs)
				if nb then bm = nb setMode("face") end
			end })
	end
	function T.spin(opts)
		local c, ax = cursorLocal(), viewLocal(camera().CFrame.LookVector)
		startParam({ name = "Spin", mode = "angle", center = c, releaseConfirm = opts and opts.release, fn = function(a)
			if math.abs(a) < 1e-3 then return end
			MT.spin(bm, c, ax, a, 12)
		end })
	end
	function T.smooth(opts)
		startParam({ name = "Smooth Vertices", mode = "x", releaseConfirm = opts and opts.release, fn = function(x)
			local f = math.clamp(x, 0, 1)
			if f > 0 then MT.smooth(bm, selVertsSet(), f, 1 + math.floor(math.max(0, x - 1) * 4)) end
		end })
	end
	function T.randomize(opts)
		startParam({ name = "Randomize", mode = "drag", releaseConfirm = opts and opts.release, fn = function(d) MT.randomize(bm, selVertsSet(), d * 0.25, 1) end })
	end
	function T.shrinkFatten(opts)
		startParam({ name = opts and opts.name or "Shrink/Fatten", mode = "signed", releaseConfirm = opts and opts.release, commitOnCancel = opts and opts.commitOnCancel, fn = function(d)
			local vs = selVertsSet()
			MT.shrinkFatten(vs, origOf(vs), regionNormals(vs), d)
			bm:normalsUpdate()
		end })
	end
	function T.pushPull(opts)
		startParam({ name = "Push/Pull", mode = "signed", releaseConfirm = opts and opts.release, fn = function(d)
			local vs = selVertsSet()
			local c = V3() local n = 0
			for v in pairs(vs) do c += v.co n += 1 end
			if n > 0 then MT.pushPull(vs, origOf(vs), c / n, d) bm:normalsUpdate() end
		end })
	end
	function T.shear(opts)
		local r, u = viewLocal(camera().CFrame.RightVector), viewLocal(camera().CFrame.UpVector)
		startParam({ name = "Shear", mode = "x", releaseConfirm = opts and opts.release, fn = function(x)
			local vs = selVertsSet()
			local c = V3() local n = 0
			for v in pairs(vs) do c += v.co n += 1 end
			if n > 0 then MT.shear(vs, origOf(vs), c / n, r, u, x) bm:normalsUpdate() end
		end })
	end
	function T.toSphere(opts)
		startParam({ name = "To Sphere", mode = "x", releaseConfirm = opts and opts.release, fn = function(x)
			local vs = selVertsSet()
			local c = V3() local n = 0
			for v in pairs(vs) do c += v.co n += 1 end
			if n > 0 then MT.toSphere(vs, origOf(vs), c / n, x) bm:normalsUpdate() end
		end })
	end
	-- edge / vertex slide: every selected vert runs along the un-selected edge that best matches the drag
	function T.slide(opts)
		local single = opts and opts.vertex
		startParam({ name = (opts and opts.name) or (single and "Vertex Slide" or "Edge Slide"), mode = "vec", releaseConfirm = opts and opts.release, commitOnCancel = opts and opts.commitOnCancel, fn = function(D)
			if D.Magnitude < 3 then return end
			local dir = D.Unit
			for v in pairs(selVertsSet()) do
				local best, bestDot, bestLen
				local sp = toScreen(W(v.co))
				for _, e in ipairs(BMesh.vertEdges(v)) do
					local o = BMesh.otherVert(e, v)
					if not e.hide and not (o.sel and not single) then
						local so = toScreen(W(o.co))
						local sd = so - sp
						if sd.Magnitude > 1 then
							local d = sd.Unit:Dot(dir)
							if not bestDot or d > bestDot then best, bestDot, bestLen = o, d, sd.Magnitude end
						end
					end
				end
				if best and bestDot > 0 then
					local t = math.clamp(D:Dot((toScreen(W(best.co)) - sp).Unit) / bestLen, 0, 1)
					v.co = v.co:Lerp(best.co, t)
				end
			end
			bm:normalsUpdate()
		end })
	end
	-- extrude variants (Alt E)
	function T.extrudeNormals(opts)
		local fs = MT.selFaces(bm)
		if not next(fs) then Tools.extrude() return end
		Ops.extrudeFaceRegion(bm, fs)
		bm:normalsUpdate()
		flush()
		T.shrinkFatten({ name = "Extrude Along Normals", release = opts and opts.release, commitOnCancel = true })
	end
	function T.extrudeIndividual(opts)
		local fs = MT.selFaces(bm)
		if not next(fs) then setStatus("Pick faces to extrude.") return end
		MT.extrudeIndividual(bm, fs)
		flush()
		T.shrinkFatten({ name = "Extrude Individual Faces", release = opts and opts.release, commitOnCancel = true })
	end
	-- rip (V): faces on the mouse's side get their own copies of the selected verts, which then move
	function T.rip(opts)
		local sv = selVertsSet()
		if not next(sv) then setStatus("Pick verts or edges to rip.") return end
		local mp = mousePos()
		local pts = {}
		local c2 = Vector2.new()
		for v in pairs(sv) do local p = toScreen(W(v.co)) pts[#pts + 1] = p c2 += p end
		c2 = c2 / #pts
		local lineDir
		if #pts >= 2 then
			local far, fd = pts[1], 0
			for _, p in ipairs(pts) do local d = (p - pts[1]).Magnitude if d > fd then far, fd = p, d end end
			lineDir = fd > 1 and (far - pts[1]).Unit or nil
		end
		local function side(p)
			if lineDir then return lineDir.X * (p.Y - c2.Y) - lineDir.Y * (p.X - c2.X) end
			return (p - c2):Dot(mp - c2)
		end
		local want = side(mp) >= 0
		local nb = MT.rip(bm, function(f)
			local touches = false
			for _, v in ipairs(BMesh.faceVerts(f)) do if sv[v] then touches = true end end
			if not touches then return false end
			return (side(toScreen(W(BMesh.faceCenter(f)))) >= 0) == want
		end)
		if not nb then setStatus("Nothing to rip here.") return end
		bm = nb
		setMode("vert")
		changed()
		startTransform("G", { what = "Rip", releaseConfirm = opts and opts.release })
	end
	function T.ripEdge(opts)
		local sv = selVertsSet()
		if not next(sv) then setStatus("Pick verts to extend.") return end
		local nv = Ops.extrudeVerts(bm, sv)
		MT.clearSel(bm)
		for v in pairs(nv) do v.sel = true end
		setMode("vert")
		changed()
		startTransform("G", { what = "Rip Edge", releaseConfirm = opts and opts.release })
	end

	-- ----- knife (K) -----
	local function knifeSnap(mp)
		local v = pickVert(mp)
		if v then return { v = v, pos = W(v.co) } end
		local e = pickEdge(mp)
		local function onEdge(ed)
			local sa, sb = toScreen(W(ed.v1.co)), toScreen(W(ed.v2.co))
			local _, t = segDist2(mp, sa, sb)
			t = math.clamp(t, 0.02, 0.98)
			return { e = ed, t = t, pos = W(ed.v1.co:Lerp(ed.v2.co, t)) }
		end
		if e then return onEdge(e) end
		local f = pickFace()
		if f then
			local best, bd
			for _, l in ipairs(BMesh.faceLoops(f)) do
				local d = segDist2(mp, toScreen(W(l.e.v1.co)), toScreen(W(l.e.v2.co)))
				if not bd or d < bd then best, bd = l.e, d end
			end
			if best then return onEdge(best) end
		end
		return nil
	end
	-- the edges a screen segment crosses (so a long cut goes through every face on the way)
	local function crossings(p, q)
		local sp, sq = toScreen(p.pos), toScreen(q.pos)
		local out = {}
		local skip = {}
		for _, x in ipairs({ p, q }) do
			if x.e then skip[x.e] = true end
			if x.v then for _, e in ipairs(BMesh.vertEdges(x.v)) do skip[e] = true end end
		end
		local r = sq - sp
		for e in pairs(bm.edges) do
			if not skip[e] and not e.hide then
				local a, b = toScreen(W(e.v1.co)), toScreen(W(e.v2.co))
				local s = b - a
				local den = r.X * s.Y - r.Y * s.X
				if math.abs(den) > 1e-6 then
					local w = a - sp
					local u = (w.X * s.Y - w.Y * s.X) / den
					local t = (w.X * r.Y - w.Y * r.X) / den
					if u > 0.001 and u < 0.999 and t > 0.001 and t < 0.999 then
						local wp = W(e.v1.co:Lerp(e.v2.co, t))
						if xray or not occluded(wp, faceSetOfEdge(e)) then out[#out + 1] = { e = e, t = t, u = u, pos = wp } end
					end
				end
			end
		end
		table.sort(out, function(x, y) return x.u < y.u end)
		return out
	end
	function T.knife()
		if not editing or modal then return end
		local M = { kind = "knife", pts = {}, num = "" }
		M.update = function() M.hover = knifeSnap(mousePos()) dirtyCage = true end
		M.click = function()
			M.update()
			if M.hover then M.pts[#M.pts + 1] = M.hover end
			setStatus(("Knife: %d point%s. Click to add, Enter = cut, Esc = cancel."):format(#M.pts, #M.pts == 1 and "" or "s"))
		end
		M.finish = function(cancel)
			if cancel or #M.pts < 2 then setStatus("Knife cancelled.") return end
			local chain = { M.pts[1] }
			for i = 2, #M.pts do
				for _, x in ipairs(crossings(M.pts[i - 1], M.pts[i])) do chain[#chain + 1] = x end
				chain[#chain + 1] = M.pts[i]
			end
			local cut = MT.knife(bm, chain)
			MT.clearSel(bm)
			for e in pairs(cut) do e.sel = true e.v1.sel = true e.v2.sel = true end
			setMode("edge")
			changed("Knife")
			setStatus("Knife cut.")
			if MOD.tool == "knife" then task.defer(function() if editing and not modal and MOD.tool == "knife" then T.knife() end end) end
		end
		modal = M
		setStatus("Knife: click points on edges / faces, Enter = cut, Esc = cancel.")
	end
	-- bisect: a cut along a line dragged on the screen (through the view)
	function T.bisect(a, b)
		local ra, rb = view and view:ray(a) or nil, view and view:ray(b) or nil
		if not (ra and rb) then return end
		local c = W(selCenterLocal())
		local depth = (c - ra.Origin).Magnitude
		local pa, pb = ra.Origin + ra.Direction * depth, rb.Origin + rb.Direction * depth
		local n = (pb - pa):Cross(camera().CFrame.LookVector)
		if n.Magnitude < 1e-6 then return end
		local fs = MT.selFaces(bm)
		local cut = MT.bisect(bm, origin:PointToObjectSpace(pa), viewLocal(n), next(fs) and fs or nil)
		MT.clearSel(bm)
		for e in pairs(cut) do e.sel = true e.v1.sel = true e.v2.sel = true end
		setMode("edge")
		changed("Bisect")
	end

	-- ----- 3D cursor, measure, annotate -----
	local function surfacePoint(mp)
		local ray = view and view:ray(mp) or getRay()
		local best
		if editing and bm then
			local t = rayMesh(ray.Origin, ray.Direction)
			if t then best = t end
		end
		for p, r in pairs(scene) do
			if r.shown and r.bm and not (editing and p == obj) then
				local o = originOf(p)
				for _, t in ipairs(Display.triangles(r.bm)) do
					local hit = rayTri(ray.Origin, ray.Direction, o * t[1], o * t[2], o * t[3])
					if hit and (not best or hit < best) then best = hit end
				end
			end
		end
		if best then return ray.Origin + ray.Direction * best, true end
		if ray.Direction.Y < -1e-3 then
			local t = -ray.Origin.Y / ray.Direction.Y
			if t > 0 then return ray.Origin + ray.Direction * t, false end
		end
		local n = camera().CFrame.LookVector
		return planeHit(ray, CURSOR, n) or CURSOR, false
	end
	function MOD.placeCursor(mp)
		CURSOR = surfacePoint(mp)
		dirtyCage = true
		setStatus(("3D cursor: %.2f, %.2f, %.2f"):format(CURSOR.X, CURSOR.Y, CURSOR.Z))
	end
	local function snapPoint(mp)
		if editing and bm then
			local v = pickVert(mp)
			if v then return W(v.co) end
		end
		return (surfacePoint(mp))
	end

	-- ----- add cube (drag the base, then the height) -----
	local function boxCorners(lo, hi)
		local c = {}
		for _, x in ipairs({ lo.X, hi.X }) do for _, y in ipairs({ lo.Y, hi.Y }) do for _, z in ipairs({ lo.Z, hi.Z }) do c[#c + 1] = V3(x, y, z) end end end
		return c
	end
	local BOX_EDGES = { { 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 }, { 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 }, { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 } }
	local function makeBox(lo, hi)
		local size = hi - lo
		if math.abs(size.X) < 0.05 or math.abs(size.Z) < 0.05 then setStatus(("Too small (%.2f x %.2f) - drag a bigger base."):format(math.abs(size.X), math.abs(size.Z))) return end
		local a = V3(math.min(lo.X, hi.X), math.min(lo.Y, hi.Y), math.min(lo.Z, hi.Z))
		local b = V3(math.max(lo.X, hi.X), math.max(lo.Y, hi.Y), math.max(lo.Z, hi.Z))
		if b.Y - a.Y < 0.05 then b = V3(b.X, a.Y + math.max(b.X - a.X, b.Z - a.Z), b.Z) end
		local mid, sz = (a + b) / 2, b - a
		if editing and bm then
			local old = {}
			for v in pairs(bm.verts) do old[v] = true end
			Ops.cube(bm, 2)
			MT.clearSel(bm)
			local lmid = origin:PointToObjectSpace(mid)
			for v in pairs(bm.verts) do
				if not old[v] then
					local w = mid + V3(v.co.X * sz.X / 2, v.co.Y * sz.Y / 2, v.co.Z * sz.Z / 2)
					v.co = origin:PointToObjectSpace(w)
					v.sel = true
				end
			end
			bm:normalsUpdate()
			flush()
			changed("Add Cube")
			local _ = lmid
		else
			local m = BMesh.new()
			Ops.cube(m, 2)
			for v in pairs(m.verts) do v.co = V3(v.co.X * sz.X / 2, v.co.Y * sz.Y / 2, v.co.Z * sz.Z / 2) end
			m:normalsUpdate()
			MOD.createPart(m, NAME .. " Cube", CFrame.new(mid))
		end
	end
	function MOD.createPart(m, name, originCF)
		local mp, c, err = Display.build(m)
		if not mp then setStatus("Couldn't make the mesh: " .. tostring(err)) return end
		local rec
		pcall(function() rec = CHS:TryBeginRecording("ROBLEND", "ROBLEND add") end)
		mp.Name = name
		mp.Anchored = true
		mp.Color = Color3.fromRGB(200, 200, 205)
		mp.Material = Enum.Material.SmoothPlastic
		mp.CFrame = originCF * CFrame.new(c)
		local sv = Instance.new("StringValue")
		sv.Name = "RB_Data"
		sv.Value = HttpService:JSONEncode(m:toData())
		sv.Parent = mp
		mp:SetAttribute("RB_Center", c)
		mp:SetAttribute("RB_Size", mp.Size)
		mp:SetAttribute("ROBLEND", VERSION)
		mp.Parent = workspace
		Display.adopt(mp, Display.emOf[mp])
		if rec then CHS:FinishRecording(rec, Enum.FinishRecordingOperation.Commit) else CHS:SetWaypoint("ROBLEND add") end
		sceneAdd(mp)
		return mp
	end
	function T.addCube(a)
		local p0, hitSurface = surfacePoint(a)
		local h = p0.Y
		local M = { kind = "addcube", num = "", phase = "base", base0 = p0, base1 = p0 }
		local function onPlane(mp)
			local ray = view and view:ray(mp) or getRay()
			if math.abs(ray.Direction.Y) < 1e-4 then return M.base1 end
			local t = (h - ray.Origin.Y) / ray.Direction.Y
			return t > 0 and (ray.Origin + ray.Direction * t) or M.base1
		end
		M.update = function()
			local mp = mousePos()
			if M.phase == "base" then
				M.base1 = onPlane(mp)
				M.height = math.max(math.abs(M.base1.X - M.base0.X), math.abs(M.base1.Z - M.base0.Z))
			else
				M.height = math.max(0.05, (M.mUp.Y - mp.Y) * wpp(M.base1) + (M.h0 or 0))
				if tonumber(M.num) then M.height = tonumber(M.num) end
			end
			dirtyCage = true
		end
		M.release = function()
			if M.phase == "base" then M.phase = "height" M.mUp = mousePos() M.h0 = M.height setStatus("Add Cube: move up / down for the height, click = done.") return true end
			return false
		end
		M.click = function() modal = nil makeBox(M.base0, M.base1 + V3(0, M.height or 1, 0)) dirtyCage = true end
		M.finish = function(cancel) if not cancel then makeBox(M.base0, M.base1 + V3(0, M.height or 1, 0)) end end
		M.box = function()
			local lo = M.base0
			local hi = M.base1 + V3(0, M.height or 0, 0)
			return lo, hi
		end
		modal = M
		local _ = hitSurface
		setStatus("Add Cube: drag the base, let go, then set the height.")
	end

	-- ----- poly build -----
	function T.polyBuild(mp, ctrl, shift)
		if shift then
			local x = pickAny()
			if not x then return end
			if mode == "face" and x.len then Ops.deleteFaces(bm, { [x] = true })
			elseif x.co then Ops.deleteVerts(bm, { [x] = true })
			elseif x.v1 then Ops.deleteEdges(bm, { [x] = true }) end
			changed("Poly Build")
			return
		end
		if ctrl then
			local vs = selectedVertsList()
			if #vs == 0 or #vs > 2 then setStatus("Poly Build: pick 1 vert (or an edge), then Ctrl-click.") return end
			local c = W(centerOf(vs))
			local p = planeHit(view and view:ray(mp) or getRay(), c, camera().CFrame.LookVector)
			if not p then return end
			local nv = bm:vertCreate(origin:PointToObjectSpace(p))
			if #vs == 1 then
				bm:edgeCreate(vs[1], nv)
				MT.clearSel(bm)
				nv.sel = true
			else
				local a, b = vs[1], vs[2]
				local e = BMesh.edgeExists(a, b)
				if e and e.l and e.l.v == a then a, b = b, a end
				bm:faceCreate({ a, b, nv })
				local keep = ((a.co - nv.co).Magnitude < (b.co - nv.co).Magnitude) and a or b
				MT.clearSel(bm)
				nv.sel, keep.sel = true, true
			end
			setMode("vert")
			bm:normalsUpdate()
			flush()
			changed("Poly Build")
			return
		end
		local v = pickVert(mp)
		if v then
			if not v.sel then MT.clearSel(bm) v.sel = true setMode("vert") flush() end
			startTransform("G", { what = "Poly Build", releaseConfirm = true })
		end
	end

	-- ----- loop cut and slide (Ctrl R / the Loop Cut tool): wheel = number of cuts, then slide -----
	MOD.loopCuts = 1
	local function ringLines(e)
		local out = {}
		for _, seg in ipairs(MT.ringCuts(bm, e, MOD.loopCuts)) do out[#out + 1] = { W(seg[1]), W(seg[2]) } end
		return out
	end
	local function cutAndSlide(e, release)
		local made = MT.loopCutN(bm, e, MOD.loopCuts)
		MT.clearSel(bm)
		setMode("edge")
		for x in pairs(made) do if bm.edges[x] then x.sel = true x.v1.sel = true x.v2.sel = true end end
		flush()
		changed()
		MOD.preview = nil
		T.slide({ name = "Loop Cut and Slide", release = release, commitOnCancel = true })
	end
	function T.loopCutModal()
		if not editing or modal then return end
		local M = { kind = "loopcut2", num = "" }
		M.update = function()
			M.edge = pickEdge(mousePos())
			M.lines = M.edge and ringLines(M.edge) or nil
			dirtyCage = true
			setStatus(("Loop Cut: %d cut%s (wheel / PageUp / PageDown), click = cut + slide, Esc = cancel"):format(MOD.loopCuts, MOD.loopCuts == 1 and "" or "s"))
		end
		M.onWheel = function(steps) MOD.loopCuts = math.clamp(MOD.loopCuts + (steps > 0 and 1 or -1), 1, 64) end
		M.onKey = function(k)
			if k == Enum.KeyCode.PageUp then MOD.loopCuts = math.min(64, MOD.loopCuts + 1) return true end
			if k == Enum.KeyCode.PageDown then MOD.loopCuts = math.max(1, MOD.loopCuts - 1) return true end
			return false
		end
		M.click = function()
			M.update()
			local e = M.edge
			modal = nil
			if e then cutAndSlide(e, false) else setStatus("Loop Cut: point at an edge.") end
		end
		M.finish = function(cancel) setStatus(cancel and "Loop cut cancelled." or "Loop cut: point at an edge and click.") end
		modal = M
		M.update()
	end
	MOD.cutAndSlide = cutAndSlide

	-- ----- loop cut tool preview -----
	local function ringPreview(e)
		local ring = Ops.edgeRing(bm, e)
		local mids, lines = {}, {}
		for i, r in ipairs(ring) do mids[i] = W((r.v1.co + r.v2.co) / 2) end
		for i = 1, #mids - 1 do lines[#lines + 1] = { mids[i], mids[i + 1] } end
		if #ring > 2 and BMesh.edgeFaceCount(ring[1]) == 2 then
			local fs1 = faceSetOfEdge(ring[1])
			for _, f in ipairs(BMesh.edgeFaces(ring[#ring])) do if fs1[f] then lines[#lines + 1] = { mids[#mids], mids[1] } break end end
		end
		return lines
	end

	-- ----- the active tool (toolbar) -----
	local EDIT_ONLY = { extrude = true, extrudeNormals = true, extrudeIndividual = true, inset = true, bevel = true, loopcut = true, knife = true, bisect = true,
		polybuild = true, spin = true, smooth = true, randomize = true, edgeslide = true, vertexslide = true, shrinkfatten = true, pushpull = true,
		shear = true, tosphere = true, rip = true, ripedge = true }
	function MOD.setTool(name)
		if name == "circle" then
			-- Select Circle runs as a mode (like pressing C); the tool stays Select Box
			if editing and not modal then T.circleSelect() else setStatus("Select Circle works in Edit Mode (Tab).") end
			return
		end
		MOD.tool = name
		MOD.preview = nil
		if modal and modal.kind == "knife" and name ~= "knife" then finishModal(true) end
		if name == "knife" and editing and not modal then T.knife() end
		dirtyCage = true
		setStatus("Tool: " .. name)
	end
	function MOD.effectiveTool()
		local t = MOD.tool
		if EDIT_ONLY[t] and not editing then return "select" end
		return t
	end
	-- LMB pressed in the 3D view with no modal running: returns true when the tool used it
	function MOD.press(mp, shift, ctrl)
		local t = MOD.effectiveTool()
		if t == "select" then return false end
		if t == "cursor" then MOD.pendingCursor = true return true end
		if t == "measure" then
			local p = snapPoint(mp)
			MOD.measure = { a = p, b = p, dragging = true }
			return true
		end
		if t == "annotate" then
			MOD.strokes[#MOD.strokes + 1] = { surfacePoint(mp) }
			MOD.drawing = true
			MOD.lastAnn = mp
			return true
		end
		if t == "addcube" then T.addCube(mp) return true end
		if t == "bisect" then MOD.bisectFrom = mp MOD.bisectTo = mp return true end
		if t == "polybuild" then T.polyBuild(mp, ctrl, shift) return true end
		if t == "loopcut" then
			local e = pickEdge(mp)
			if e then cutAndSlide(e, true) end
			return true
		end
		if t == "knife" then
			if not modal then T.knife() end
			if modal and modal.click then modal.click() end
			return true
		end
		-- drag tools (like Blender): a plain click still selects; a DRAG that starts on the selection uses the tool
		-- (Move / Transform also grab whatever is under the mouse). A drag that starts anywhere else box-selects.
		local hit
		if editing then hit = pickAny() else hit = pickObject(mp) end
		local onSel
		if editing then onSel = hit ~= nil and hit.sel == true
		else onSel = hit ~= nil and table.find(Selection:Get(), hit) ~= nil end
		if t == "move" or t == "transform" then
			if hit then MOD.pending = { tool = t, mp = mp, hit = hit, onSel = onSel } end
		elseif onSel then
			MOD.pending = { tool = t, mp = mp, hit = hit, onSel = true }
		end
		return false
	end
	-- the drag passed the threshold: run the pending tool (confirms when the mouse is let go)
	local function startPending(pd)
		local t = pd.tool
		if t == "move" or t == "transform" then
			if editing then
				if not pd.onSel then clearSel() toggle(pd.hit, true) flush() end
				startTransform("G", { releaseConfirm = true })
			else
				if not pd.onSel then selectObject(pd.hit, false) end
				startObjTransform("G")
				if modal then modal.releaseConfirm = true end
			end
			return
		end
		if t == "rotate" or t == "scale" then
			local k = t == "rotate" and "R" or "S"
			if editing then startTransform(k, { releaseConfirm = true }) else startObjTransform(k) if modal then modal.releaseConfirm = true end end
			return
		end
		local rel = { release = true }
		if t == "extrude" then Tools.extrude() if modal then modal.releaseConfirm = true end
		elseif t == "extrudeNormals" then T.extrudeNormals(rel)
		elseif t == "extrudeIndividual" then T.extrudeIndividual(rel)
		elseif t == "inset" then Tools.inset() if modal then modal.releaseConfirm = true end
		elseif t == "bevel" then T.bevel(rel)
		elseif t == "spin" then T.spin(rel)
		elseif t == "smooth" then T.smooth(rel)
		elseif t == "randomize" then T.randomize(rel)
		elseif t == "edgeslide" then T.slide(rel)
		elseif t == "vertexslide" then T.slide({ release = true, vertex = true })
		elseif t == "shrinkfatten" then T.shrinkFatten(rel)
		elseif t == "pushpull" then T.pushPull(rel)
		elseif t == "shear" then T.shear(rel)
		elseif t == "tosphere" then T.toSphere(rel)
		elseif t == "rip" then T.rip(rel)
		elseif t == "ripedge" then T.ripEdge(rel)
		end
	end
	function MOD.move(mp)
		local t = MOD.effectiveTool()
		if MOD.pending and (mp - MOD.pending.mp).Magnitude > 5 then
			local pd = MOD.pending
			MOD.pending = nil
			startPending(pd)
			if modal and modal.update then modal.update() elseif modal and (modal.kind == "G" or modal.kind == "R" or modal.kind == "S") then applyTransform() end
			return "drag"
		end
		if MOD.measure and MOD.measure.dragging then MOD.measure.b = snapPoint(mp) dirtyCage = true return true end
		if MOD.drawing then
			if (mp - MOD.lastAnn).Magnitude > 4 then
				local s = MOD.strokes[#MOD.strokes]
				s[#s + 1] = surfacePoint(mp)
				MOD.lastAnn = mp
				dirtyCage = true
			end
			return true
		end
		if MOD.bisectFrom then MOD.bisectTo = mp dirtyCage = true return true end
		if t == "loopcut" and editing and not modal then
			local e = pickEdge(mp)
			MOD.preview = e and ringLines(e) or nil
			MOD.previewEdge = e
			dirtyCage = true
		end
		return false
	end
	function MOD.release(mp)
		MOD.pending = nil
		if MOD.pendingCursor then MOD.pendingCursor = nil MOD.placeCursor(mp) return true end
		if MOD.measure and MOD.measure.dragging then
			MOD.measure.dragging = false
			local d = (MOD.measure.b - MOD.measure.a).Magnitude
			setStatus(("Measure: %.3f studs  (Esc clears)"):format(d))
			return true
		end
		if MOD.drawing then MOD.drawing = nil return true end
		if MOD.bisectFrom then
			local a, b = MOD.bisectFrom, mp
			MOD.bisectFrom, MOD.bisectTo = nil, nil
			if (b - a).Magnitude > 6 then T.bisect(a, b) end
			dirtyCage = true
			return true
		end
		return false
	end

	-- ----- extra drawing: cursor, knife, measure, annotations, previews -----
	local function px(at, n) return n end
	drawExtras = function()
		if not view then return end
		-- 3D cursor: red / white ring + cross (like Blender's)
		local cf = view.CFrame
		local r = view:pixel(CURSOR) * 11
		local right, up = cf.RightVector, cf.UpVector
		for i = 0, 11 do
			local a0, a1 = i / 12 * math.pi * 2, (i + 1) / 12 * math.pi * 2
			local p0 = CURSOR + (right * math.cos(a0) + up * math.sin(a0)) * r
			local p1 = CURSOR + (right * math.cos(a1) + up * math.sin(a1)) * r
			line(p0, p1, (i % 2 == 0) and Color3.fromRGB(255, 50, 50) or Color3.new(1, 1, 1), 1.3)
		end
		line(CURSOR - right * r * 1.6, CURSOR - right * r * 0.6, Color3.new(0, 0, 0), 1)
		line(CURSOR + right * r * 0.6, CURSOR + right * r * 1.6, Color3.new(0, 0, 0), 1)
		line(CURSOR - up * r * 1.6, CURSOR - up * r * 0.6, Color3.new(0, 0, 0), 1)
		line(CURSOR + up * r * 0.6, CURSOR + up * r * 1.6, Color3.new(0, 0, 0), 1)
		-- annotations
		for _, s in ipairs(MOD.strokes) do
			for i = 2, #s do line(s[i - 1], s[i], Color3.fromRGB(0, 200, 180), 2) end
		end
		-- measure
		local m = MOD.measure
		if m then
			line(m.a, m.b, Color3.new(1, 1, 1), 1.6)
			view:dot(m.a, Color3.new(1, 1, 1), 6) view:dot(m.b, Color3.new(1, 1, 1), 6)
			ui:setLabel("measure", toScreen((m.a + m.b) / 2), ("%.3f"):format((m.b - m.a).Magnitude))
		else
			ui:setLabel("measure", nil)
		end
		-- knife
		if modal and modal.kind == "knife" then
			local pts = modal.pts
			for i, p in ipairs(pts) do
				view:dot(p.pos, Color3.fromRGB(80, 255, 80), 7)
				if i > 1 then line(pts[i - 1].pos, p.pos, Color3.fromRGB(80, 255, 80), 1.8) end
			end
			if modal.hover then
				view:dot(modal.hover.pos, Color3.fromRGB(255, 80, 80), 7)
				if #pts > 0 then line(pts[#pts].pos, modal.hover.pos, Color3.fromRGB(255, 80, 80), 1.4) end
			end
		end
		-- add cube box
		if modal and modal.kind == "addcube" then
			local lo, hi = modal.box()
			local c = boxCorners(lo, hi)
			for _, e in ipairs(BOX_EDGES) do line(c[e[1]], c[e[2]], Color3.new(1, 1, 1), 1.4) end
		end
		if modal and modal.kind == "loopcut2" and modal.lines then
			for _, sg in ipairs(modal.lines) do line(sg[1], sg[2], Color3.fromRGB(255, 220, 60), 2) end
		end
		-- loop cut tool preview
		if MOD.preview and not modal then
			for _, s in ipairs(MOD.preview) do line(s[1], s[2], Color3.fromRGB(255, 220, 60), 2) end
		end
		-- bisect line
		if MOD.bisectFrom and MOD.bisectTo then
			local ra, rb = view:ray(MOD.bisectFrom), view:ray(MOD.bisectTo)
			local d = (W(selCenterLocal()) - ra.Origin).Magnitude
			line(ra.Origin + ra.Direction * d, rb.Origin + rb.Direction * d, Color3.new(1, 1, 1), 1.6)
		end
		local _ = px
	end

	-- ----- menu operators -----
	local function need(sel, msg) if not sel then setStatus(msg) return false end return true end
	local O = {}
	O.Duplicate = function()
		bm = MT.duplicate(bm)
		changed()
		startTransform("G", { what = "Duplicate" })
	end
	O.Split = function() local nb = MT.split(bm) if need(nb, "Pick faces to split.") then bm = nb changed("Split") end end
	O.Separate = function()
		local fs = MT.selFaces(bm)
		if not need(next(fs), "Pick faces to separate.") then return end
		local spec = MT.toSpec(bm)
		local keepFaces = {}
		for _, f in ipairs(spec.faces) do if f.sel then keepFaces[#keepFaces + 1] = f end end
		spec.faces = keepFaces
		spec.edges = {}
		for _, sv in ipairs(spec.verts) do sv.loose = false end
		local part = MT.fromSpec(spec)
		Ops.deleteFaces(bm, fs)
		changed("Separate")
		local np = MOD.createPart(part, obj.Name .. ".001", origin)
		if np then np.Color, np.Material = obj.Color, obj.Material end
		setStatus("Separated into " .. (np and np.Name or "a new part") .. ".")
	end
	-- P > By Loose Parts: every unconnected piece becomes its own part (the biggest stays)
	O.SeparateLoose = function()
		local comps, seen = {}, {}
		for v in pairs(bm.verts) do
			if not seen[v] then
				local set, n, stack = {}, 0, { v }
				seen[v] = true
				while #stack > 0 do
					local x = table.remove(stack)
					set[x] = true
					n += 1
					for _, e in ipairs(BMesh.vertEdges(x)) do
						local o = BMesh.otherVert(e, x)
						if not seen[o] then seen[o] = true stack[#stack + 1] = o end
					end
				end
				comps[#comps + 1] = { set = set, n = n }
			end
		end
		if #comps < 2 then setStatus("The mesh is one piece - nothing to separate.") return end
		table.sort(comps, function(a, b) return a.n > b.n end)
		local made = 0
		local gone = {}
		for i = 2, #comps do
			local spec = MT.toSpec(bm)
			local inSet = {}
			for v, k in pairs(spec.vi) do if comps[i].set[v] then inSet[k] = true end end
			local fs = {}
			for _, f in ipairs(spec.faces) do
				local all = true
				for _, k in ipairs(f.v) do if not inSet[k] then all = false break end end
				if all then fs[#fs + 1] = f end
			end
			spec.faces = fs
			local es = {}
			for _, e in ipairs(spec.edges) do if inSet[e[1]] and inSet[e[2]] then es[#es + 1] = e end end
			spec.edges = es
			for k, sv in ipairs(spec.verts) do sv.loose = sv.loose and inSet[k] == true end
			local piece = MT.fromSpec(spec)
			local np = MOD.createPart(piece, obj.Name .. "." .. string.format("%03d", i - 1), origin)
			if np then np.Color, np.Material = obj.Color, obj.Material made += 1 end
			for v in pairs(comps[i].set) do gone[v] = true end
		end
		Ops.deleteVerts(bm, gone)
		changed("Separate")
		setStatus(("Separated %d loose part%s."):format(made, made == 1 and "" or "s"))
	end
	O.MergeCenter = function() Tools.merge() end
	O.MergeCursor = function()
		local vs = MT.selVerts(bm)
		if not need(next(vs), "Pick verts.") then return end
		local c = cursorLocal()
		for v in pairs(vs) do v.co = c end
		local nb = Ops.mergeByDistance(bm, vs, 1e-4)
		bm = nb
		changed("Merge at Cursor")
	end
	O.MergeCollapse = function()
		local es = MT.selEdges(bm)
		if not need(next(es), "Pick edges / faces to collapse.") then return end
		bm = MT.edgeCollapse(bm, es)
		changed("Collapse")
	end
	O.MergeDistance = function() Tools.mergeDist() end
	O.DeleteVerts = function() Ops.deleteVerts(bm, MT.selVerts(bm)) changed("Delete") end
	O.DeleteEdges = function() Ops.deleteEdges(bm, MT.selEdges(bm)) changed("Delete") end
	O.DeleteFaces = function() Ops.deleteFaces(bm, MT.selFaces(bm)) changed("Delete") end
	O.DeleteEdgesFaces = function() MT.deleteEdgesFaces(bm, MT.selEdges(bm), MT.selFaces(bm)) changed("Delete") end
	O.DeleteOnlyFaces = function() MT.deleteOnlyFaces(bm, MT.selFaces(bm)) changed("Delete") end
	O.DissolveVerts = function() local n = MT.dissolveVerts(bm, MT.selVerts(bm)) changed("Dissolve Vertices") setStatus(("Dissolved %d verts."):format(n)) end
	O.DissolveEdges = function()
		local n, ends = MT.dissolveEdges(bm, MT.selEdges(bm))
		local ok, nb = MT.dissolveDeg2(bm, ends)
		if ok and nb then bm = nb end
		changed("Dissolve Edges")
		setStatus(("Dissolved %d edges."):format(n))
	end
	O.DissolveFaces = function() MT.dissolveFaces(bm, MT.selFaces(bm)) changed("Dissolve Faces") end
	O.Dissolve = function()
		if mode == "vert" then O.DissolveVerts() elseif mode == "edge" then O.DissolveEdges() else O.DissolveFaces() end
	end
	O.EdgeCollapse = O.MergeCollapse
	O.DeleteEdgeLoops = O.DissolveEdges
	O.DeleteLoose = function() local n = MT.deleteLoose(bm) changed("Delete Loose") setStatus(("Removed %d loose bits."):format(n)) end
	O.RotateCW = function() for e in pairs(MT.selEdges(bm)) do MT.rotateEdge(bm, e, false) end changed("Rotate Edge") end
	O.RotateCCW = function() for e in pairs(MT.selEdges(bm)) do MT.rotateEdge(bm, e, true) end changed("Rotate Edge") end
	O.Bridge = function() local out, err = MT.bridge(bm) if not out then setStatus(err) return end flush() changed("Bridge Edge Loops") end
	O.SubdivideRing = function()
		local e = next(MT.selEdges(bm))
		if not need(e, "Pick an edge of the ring.") then return end
		local ne = Ops.loopCut(bm, e, 0.5)
		MT.clearSel(bm)
		for x in pairs(ne) do x.sel = true end
		setMode("edge")
		changed("Subdivide Edge-Ring")
	end
	O.Poke = function() MT.poke(bm, MT.selFaces(bm)) setMode("face") changed("Poke Faces") end
	O.Triangulate = function() MT.triangulate(bm, MT.selFaces(bm), Display.triangulate) setMode("face") changed("Triangulate Faces") end
	O.TrisToQuads = function() local n = MT.trisToQuads(bm, MT.selFaces(bm)) flush() changed("Tris to Quads") setStatus(("Joined %d pairs."):format(n)) end
	O.Solidify = function()
		local fs = MT.selFaces(bm)
		if not need(next(fs), "Pick faces to solidify.") then return end
		startParam({ name = "Solidify Faces", mode = "dist", fn = function(d)
			if d > 1e-3 then MT.solidify(bm, MT.selFaces(bm), d) end
		end })
	end
	O.Wireframe = function()
		local fs = MT.selFaces(bm)
		if not need(next(fs), "Pick faces for Wireframe.") then return end
		startParam({ name = "Wireframe", mode = "dist", fn = function(d)
			if d > 1e-3 then
				local frame = Mods.wireframeFaces(bm, MT.selFaces(bm), d)
				MT.solidify(bm, frame, d)
			end
		end })
	end
	O.Connect = function()
		local made = MT.connectVerts(bm, MT.selVerts(bm))
		for e in pairs(made) do e.sel = true end
		changed("Connect Vertex Pairs")
	end
	O.Fill = function() Tools.fill() end
	O.BeautyFill = function() MT.triangulate(bm, MT.selFaces(bm), Display.triangulate) changed("Beautify Faces") end
	O.ConvexHull = function()
		local out, err = MT.convexHull(bm, MT.selVerts(bm))
		if not out then setStatus(err) return end
		setMode("face")
		changed("Convex Hull")
	end
	O.SymmetrizeX = function() bm = MT.symmetrize(bm, "X") changed("Symmetrize") end
	O.RecalcOutside = function()
		local fs = MT.selFaces(bm)
		bm = MT.recalcNormals(bm, next(fs) and fs or nil, false)
		changed("Recalculate Outside")
	end
	O.RecalcInside = function()
		local fs = MT.selFaces(bm)
		bm = MT.recalcNormals(bm, next(fs) and fs or nil, true)
		changed("Recalculate Inside")
	end
	O.ShadeSmooth = function()
		local fs = MT.selFaces(bm)
		for f in pairs(next(fs) and fs or bm.faces) do f.smooth = true end
		changed("Shade Smooth")
	end
	O.ShadeFlat = function()
		local fs = MT.selFaces(bm)
		for f in pairs(next(fs) and fs or bm.faces) do f.smooth = nil end
		changed("Shade Flat")
	end
	-- Shift E (edge crease): toggles a full crease on the selected edges; Subdivision Surface keeps them sharp
	O.Crease = function()
		local es = MT.selEdges(bm)
		if not need(next(es), "Pick edges to crease.") then return end
		local all = true
		for e in pairs(es) do if not e.crease then all = false end end
		for e in pairs(es) do e.crease = (not all) or nil end
		changed(all and "Clear Crease" or "Crease")
		setStatus(all and "Crease cleared." or "Creased: Subdivision Surface keeps these edges sharp.")
	end
	O.ShadeAutoSmooth = function()
		local fs = MT.selFaces(bm)
		local n = MT.smoothByAngle(bm, next(fs) and fs or nil, 30)
		changed("Shade Auto Smooth")
		setStatus(("Shade Auto Smooth: smooth, with %d edges sharper than 30 degrees kept sharp."):format(n))
	end
	O.FillHoles = function()
		local n = MT.fillHoles(bm, 0)
		changed("Fill Holes")
		setStatus(("Filled %d hole%s."):format(n, n == 1 and "" or "s"))
	end
	O.LimitedDissolve = function()
		local before = bm.nf
		local nb = Mods.decimate(bm, { angle = 5 })
		if nb ~= bm then bm = nb end
		changed("Limited Dissolve")
		setStatus(("Limited Dissolve: %d faces -> %d."):format(before, bm.nf))
	end
	O.DegenerateDissolve = function()
		local nb, n = Mods.mergeDoubles(bm, 1e-4)
		bm = nb
		changed("Degenerate Dissolve")
		setStatus(("Degenerate Dissolve: %d zero-length bits removed."):format(n))
	end
	-- Ctrl Shift R (Offset Edge Loops): two loops either side of the selected one = a flat 1-segment bevel
	O.OffsetEdgeLoops = function()
		if mode == "vert" then setMode("edge") end
		MOD.bevelSegs = 1
		T.bevel()
	end
	O.SelectMirror = function()
		local n = MT.selectMirror(bm, "X", false)
		flush()
		changed()
		setStatus(n > 0 and ("Selected the mirror (X) of %d verts."):format(n) or "No mirrored verts found (the mesh isn't symmetrical on X).")
	end
	O.DeselectLinked = function()
		local x = pickAny()
		if not x then return end
		local seed = {}
		if x.co then seed[x] = true elseif x.v1 then seed[x.v1] = true else for _, v in ipairs(BMesh.faceVerts(x)) do seed[v] = true end end
		-- select linked from the seed on a scratch copy of the flags, then turn those off
		local was = {}
		for v in pairs(bm.verts) do was[v] = v.sel v.sel = false end
		MT.selectLinked(bm, seed)
		local hit = {}
		for v in pairs(bm.verts) do if v.sel then hit[v] = true end end
		for v in pairs(bm.verts) do v.sel = was[v] and not hit[v] end
		for e in pairs(bm.edges) do e.sel = e.v1.sel and e.v2.sel end
		for f in pairs(bm.faces) do
			local all = true
			for _, v in ipairs(BMesh.faceVerts(f)) do if not v.sel then all = false break end end
			f.sel = all
		end
		flush()
		changed()
	end
	-- Alt F (Blender's mesh.fill): fill the selected edge loop with triangles
	O.FillTris = function()
		local before = {}
		for f in pairs(bm.faces) do before[f] = true end
		Tools.fill()
		local new = {}
		for f in pairs(bm.faces) do if not before[f] then new[f] = true end end
		if next(new) then MT.triangulate(bm, new, Display.triangulate) changed("Fill") end
	end
	for _, k in ipairs({ "sharp", "seam" }) do
		local K = k:sub(1, 1):upper() .. k:sub(2)
		O["Mark" .. K] = function() for e in pairs(MT.selEdges(bm)) do e[k] = true end changed("Mark " .. K) end
		O["Clear" .. K] = function() for e in pairs(MT.selEdges(bm)) do e[k] = nil end changed("Clear " .. K) end
	end
	O.SelectMore = function() MT.selectMore(bm, mode) flush() changed() end
	O.SelectLess = function() MT.selectLess(bm, mode) flush() changed() end
	O.SelectLinked = function() MT.selectLinked(bm, MT.selVerts(bm)) flush() changed() end
	O.PickLinked = function()
		local x = pickAny()
		if not x then return end
		local seed = {}
		if x.co then seed[x] = true elseif x.v1 then seed[x.v1] = true else for _, v in ipairs(BMesh.faceVerts(x)) do seed[v] = true end end
		MT.selectLinked(bm, seed)
		flush()
		changed()
	end
	O.SelectRandom = function() MT.selectRandom(bm, mode, 0.5, math.floor(os.clock() * 1000) % 997) flush() changed() end
	O.Checker = function() MT.checkerDeselect(bm, mode) flush() changed() end
	O.NonManifold = function() setMode("vert") MT.selectNonManifold(bm) flush() changed() end
	O.Loose = function() setMode("vert") MT.selectLoose(bm) flush() changed() end
	O.SharpEdges = function() setMode("edge") MT.selectSharp(bm) flush() changed() end
	O.FacesBySides = function() setMode("face") MT.selectBySides(bm, 4) flush() changed() end
	O.SelectRing = function()
		local e = pickEdge(mousePos()) or next(MT.selEdges(bm))
		if e then setMode("edge") MT.selectRing(bm, e, shiftDown()) flush() changed() end
	end
	O.Hide = function() MT.hide(bm, mode, false) changed() end
	O.HideUnselected = function() MT.hide(bm, mode, true) changed() end
	O.Reveal = function() MT.reveal(bm) flush() changed() end
	for _, a in ipairs({ "X", "Y", "Z" }) do
		O["Mirror" .. a] = function()
			local vs = MT.selVerts(bm)
			if not need(next(vs), "Pick something to mirror.") then return end
			local c = V3()
			local n = 0
			for v in pairs(vs) do c += v.co n += 1 end
			bm = MT.mirror(bm, vs, c / n, ({ X = V3(1, 0, 0), Y = V3(0, 1, 0), Z = V3(0, 0, 1) })[a])
			changed("Mirror " .. a)
		end
	end
	O.SelToCursor = function()
		local vs = selectedVertsList()
		if #vs == 0 then return end
		local d = cursorLocal() - centerOf(vs)
		for _, v in ipairs(vs) do v.co += d end
		bm:normalsUpdate()
		changed("Selection to Cursor")
	end
	O.SelToGrid = function()
		for _, v in ipairs(selectedVertsList()) do
			local w = W(v.co)
			v.co = origin:PointToObjectSpace(V3(math.floor(w.X + 0.5), math.floor(w.Y + 0.5), math.floor(w.Z + 0.5)))
		end
		bm:normalsUpdate()
		changed("Selection to Grid")
	end
	O.CursorToSel = function()
		if editing and bm then
			local vs = selectedVertsList()
			if #vs > 0 then CURSOR = W(centerOf(vs)) end
		else
			local ps = selectedParts()
			if #ps > 0 then local c = V3() for _, p in ipairs(ps) do c += p.CFrame.Position end CURSOR = c / #ps end
		end
		dirtyCage = true
	end
	O.CursorToOrigin = function() CURSOR = V3() dirtyCage = true end
	O.CursorToGrid = function() CURSOR = V3(math.floor(CURSOR.X + 0.5), math.floor(CURSOR.Y + 0.5), math.floor(CURSOR.Z + 0.5)) dirtyCage = true end
	O.ClearAnnotations = function() MOD.strokes = {} dirtyCage = true end
	-- modal tools from menus / keys
	O.Bevel = function() T.bevel() end
	O.BevelVerts = function() T.bevel({ vertex = true }) end
	O.Knife = function() T.knife() end
	O.Spin = function() T.spin() end
	O.Smooth = function() T.smooth() end
	O.Randomize = function() T.randomize() end
	O.EdgeSlide = function() T.slide() end
	O.VertexSlide = function() T.slide({ vertex = true }) end
	O.ShrinkFatten = function() T.shrinkFatten() end
	O.PushPull = function() T.pushPull() end
	O.Shear = function() T.shear() end
	O.ToSphere = function() T.toSphere() end
	O.Rip = function() T.rip() end
	O.RipEdge = function() T.ripEdge() end
	O.ExtrudeNormals = function() T.extrudeNormals() end
	O.ExtrudeIndividual = function() T.extrudeIndividual() end
	O.ExtrudeEdges = function() setMode("edge") Tools.extrude() end
	O.ExtrudeVerts = function() setMode("vert") Tools.extrude() end
	-- C (Blender's Circle Select): LMB paints a selection, Shift + LMB deselects, wheel = size, RMB / Esc / Enter = done
	function T.circleSelect()
		if modal or not editing then return end
		local ring = Instance.new("Frame")
		ring.Name = "RB_Circle"
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.ZIndex = 50
		local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0.5, 0) uc.Parent = ring
		local us = Instance.new("UIStroke") us.Color = Color3.fromRGB(235, 235, 235) us.Thickness = 1 us.Parent = ring
		ring.Parent = ui and ui.gui or nil
		local M = { kind = "circle", num = "", r = MOD.circleR or 25 }
		local function place()
			local mp = mousePos()
			ring.Position = UDim2.fromOffset(mp.X, mp.Y)
			ring.Size = UDim2.fromOffset(M.r * 2, M.r * 2)
		end
		local function paint()
			local mp = mousePos()
			local on = M.painting ~= "sub"
			local function inside(wp)
				local sp, vis = toScreen(wp)
				return vis and (sp - mp).Magnitude <= M.r
			end
			if mode == "vert" then
				for v in pairs(bm.verts) do
					if not v.hide then
						local wp = W(v.co)
						if inside(wp) and (xray or not occluded(wp, faceSetOfVert(v))) then v.sel = on end
					end
				end
			elseif mode == "edge" then
				for e in pairs(bm.edges) do
					local a, b = W(e.v1.co), W(e.v2.co)
					local mid = (a + b) / 2
					if inside(mid) and (xray or not occluded(mid, faceSetOfEdge(e))) then e.sel = on e.v1.sel = on e.v2.sel = on end
				end
			else
				for f in pairs(bm.faces) do
					local c = W(BMesh.faceCenter(f))
					if inside(c) and (xray or not occluded(c, { [f] = true })) then f.sel = on end
				end
			end
			flush()
			dirtyCage, dirtyMesh = true, true
		end
		M.update = function() place() if M.painting then paint() end end
		M.click = function() M.painting = shiftDown() and "sub" or "add" paint() end
		M.release = function() M.painting = nil return true end
		M.onWheel = function(steps) M.r = math.clamp(M.r * (steps > 0 and 0.85 or 1.18), 4, 400) place() end
		M.onKey = function(k)
			if k == Enum.KeyCode.Equals or k == Enum.KeyCode.KeypadPlus then M.r = math.min(400, M.r * 1.18) place() return true end
			if k == Enum.KeyCode.Minus or k == Enum.KeyCode.KeypadMinus then M.r = math.max(4, M.r * 0.85) place() return true end
			return false
		end
		M.finish = function()
			MOD.circleR = M.r
			ring.Parent = nil
			setStatus("Circle select done.")
		end
		modal = M
		place()
		setStatus("CIRCLE SELECT: drag = select, Shift drag = deselect, wheel = size. Right click / Esc = done.")
	end
	-- Ctrl + right click (Blender's Extrude to Mouse): extrude the selection to the mouse, or add a vertex there
	O.ExtrudeToMouse = function()
		local ray = getRay()
		local look = camera().CFrame.LookVector
		local vs = MT.selVerts(bm)
		if next(vs) then
			local cw = W(selCenterLocal())
			local hit = planeHit(ray, cw, look)
			if not hit then return end
			local delta = origin:VectorToObjectSpace(hit - cw)
			local fs, nfs = selSet("face")
			local es, nes = selSet("edge")
			if mode == "face" and nfs > 0 then
				local _, nf = Ops.extrudeFaceRegion(bm, fs)
				clearSel()
				for f in pairs(nf) do f.sel = true end
				flush()
			elseif mode ~= "vert" and nes > 0 then
				local nv = Ops.extrudeEdges(bm, es)
				clearSel()
				for v in pairs(nv) do v.sel = true end
				for e in pairs(bm.edges) do e.sel = e.v1.sel and e.v2.sel end
			else
				local nv = Ops.extrudeVerts(bm, vs)
				clearSel()
				for v in pairs(nv) do v.sel = true end
				for e in pairs(bm.edges) do e.sel = e.v1.sel and e.v2.sel end
			end
			for v in pairs(MT.selVerts(bm)) do v.co += delta end
			bm:normalsUpdate()
			changed("Extrude to Mouse")
			setStatus("Extruded to the mouse (Ctrl + right click).")
		else
			local hit = planeHit(ray, CURSOR, look)
			if not hit then return end
			local v = bm:vertCreate(origin:PointToObjectSpace(hit))
			v.sel = true
			changed("Add Vertex")
			setStatus("Added a vertex. Ctrl + right click again to extrude to the mouse.")
		end
	end
	O.CircleSelect = function() T.circleSelect() end
	-- remember the last operator for Shift R (Repeat Last)
	MOD.opDepth = 0
	for name, fn in pairs(O) do
		local wrapped
		wrapped = function(...)
			if MOD.opDepth == 0 then MOD.lastOp = { name = name, fn = wrapped } end
			MOD.opDepth += 1
			local r = table.pack(pcall(fn, ...))
			MOD.opDepth -= 1
			if not r[1] then error(r[2], 0) end
			return table.unpack(r, 2, r.n)
		end
		O[name] = wrapped
	end
	function MOD.repeatLast()
		local op = MOD.lastOp
		if not op then setStatus("Nothing to repeat yet.") return end
		op.fn()
		setStatus("Repeat Last: " .. op.name:gsub("(%l)(%u)", "%1 %2") .. ".")
	end
	function MOD.remember(name, fn) MOD.lastOp = { name = name, fn = fn } end
	MOD.ops = O
	MOD.T = T

	-- ----- Blender's Edit Mode shortcuts (the ones not handled elsewhere) -----
	function MOD.editKey(k, shift, ctrl, alt)
		local K = Enum.KeyCode
		local function menu(name) ui:openNamedMenu(name, mousePos()) return true end
		if k == K.R and ctrl and shift then O.OffsetEdgeLoops() return true end
		if k == K.R and ctrl then T.loopCutModal() return true end
		if k == K.R and shift and not alt then MOD.repeatLast() return true end
		if k == K.C and not ctrl and not shift and not alt then T.circleSelect() return true end
		if k == K.G and shift and not ctrl and not alt then return menu("similar") end
		if k == K.M and shift and ctrl then O.SelectMirror() return true end
		if k == K.M and alt then return menu("split") end
		if k == K.N and alt then return menu("normals") end
		if k == K.N and shift and ctrl then O.RecalcInside() return true end
		if k == K.L and shift and not ctrl then O.DeselectLinked() return true end
		if k == K.E and shift and not ctrl and not alt then O.Crease() return true end
		if k == K.F and shift and alt then O.BeautyFill() return true end
		if k == K.P and alt then O.Poke() return true end
		if k == K.V and shift and not ctrl and not alt then O.VertexSlide() return true end
		if k == K.Delete and ctrl then O.Dissolve() return true end
		if k == K.Z and not ctrl and not shift and not alt then return menu("shading") end
		if k == K.U and not ctrl and not shift and not alt then return menu("uv") end
		if k == K.Period and not ctrl and not shift and not alt then return menu("pivot") end
		if k == K.P and not ctrl then return menu("separate") end
		local LEVEL = { [K.Zero] = 0, [K.One] = 1, [K.Two] = 2, [K.Three] = 3, [K.Four] = 4, [K.Five] = 5 }
		if ctrl and LEVEL[k] then MOD.subdivSet(LEVEL[k]) return true end
		if k == K.B and ctrl and shift then O.BevelVerts() return true end
		if k == K.B and ctrl then O.Bevel() return true end
		if k == K.K and not ctrl then O.Knife() return true end
		if k == K.S and ctrl and alt and shift then O.Shear() return true end
		if k == K.S and alt and shift then O.ToSphere() return true end
		if k == K.S and alt then O.ShrinkFatten() return true end
		if k == K.S and shift then return menu("snap") end
		if k == K.V and ctrl then return menu("vertex") end
		if k == K.V and not ctrl and not alt then O.Rip() return true end
		if k == K.D and alt then O.RipEdge() return true end
		if k == K.D and shift then O.Duplicate() return true end
		if k == K.Y and not ctrl then O.Split() return true end
		if k == K.X and ctrl then O.Dissolve() return true end
		if k == K.X or k == K.Delete then return menu("delete") end
		if k == K.M and not ctrl then return menu("merge") end
		if k == K.J and alt then O.TrisToQuads() return true end
		if k == K.J and not ctrl then O.Connect() return true end
		if k == K.T and ctrl then O.Triangulate() return true end
		if k == K.N and shift then O.RecalcOutside() return true end
		if k == K.H and alt then O.Reveal() return true end
		if k == K.H and shift then O.HideUnselected() return true end
		if k == K.H then O.Hide() return true end
		if k == K.L and ctrl then O.SelectLinked() return true end
		if k == K.L then O.PickLinked() return true end
		if k == K.E and alt then return menu("extrude") end
		if k == K.E and ctrl then return menu("edge") end
		if k == K.F and ctrl then return menu("face") end
		if k == K.F and alt then O.FillTris() return true end
		if k == K.O and not ctrl then EDIT.prop = not EDIT.prop setStatus("Proportional editing " .. (EDIT.prop and "on (wheel = size while moving)" or "off")) return true end
		if (k == K.KeypadPlus or k == K.Equals) and ctrl then O.SelectMore() return true end
		if (k == K.KeypadMinus or k == K.Minus) and ctrl then O.SelectLess() return true end
		return false
	end
	-- keys inside a running G (GG = edge slide) and the wheel (proportional size)
	function MOD.modalKey(k)
		if modal and modal.kind == "inset" then
			local K = Enum.KeyCode
			if k == K.I then modal.individual = not modal.individual updateInset() return true end
			if k == K.LeftControl or k == K.RightControl then
				modal.depthMode = not modal.depthMode
				modal.dm0 = mousePos()
				modal.depth0 = modal.depth or 0
				modal.thickFixed = modal.thick
				updateInset()
				return true
			end
		end
		if modal and modal.onKey and modal.onKey(k) then
			if modal.update then modal.update() end
			return true
		end
		if k == Enum.KeyCode.G and modal and modal.kind == "G" and not modal.obj and not modal.axis and modal.num == "" then
			finishModal(true)
			T.slide()
			return true
		end
		return false
	end
	function MOD.wheel(steps)
		if modal and modal.onWheel then
			modal.onWheel(steps)
			if modal.update then modal.update() end
			return true
		end
		if not modal and editing and MOD.effectiveTool() == "loopcut" then
			MOD.loopCuts = math.clamp(MOD.loopCuts + (steps > 0 and 1 or -1), 1, 64)
			if MOD.previewEdge and bm.edges[MOD.previewEdge] then MOD.preview = ringLines(MOD.previewEdge) end
			setStatus(("Loop Cut: %d cut%s"):format(MOD.loopCuts, MOD.loopCuts == 1 and "" or "s"))
			dirtyCage = true
			return true
		end
		if modal and modal.propWeights then
			EDIT.propR = math.clamp(EDIT.propR * (steps > 0 and 0.9 or 1.1), 0.05, 1000)
			modal.propWeights()
			applyTransform()
			return true
		end
		return false
	end
	return MOD
end
local MOD = modelingTools()

local function toggleXray() xray = not xray worldTris = nil dirtyCage = true setStatus("X-ray " .. (xray and "on" or "off")) end
local function toggleEdit()
	if editing then exitEdit() return end
	local p = selectedPart()
	if not isRB(p) and uiOn then
		-- like Blender's Modeling tab: use the active / last mesh, else the first one, else make a cube
		if isRB(activeObj) and activeObj.Parent then p = activeObj end
		if not isRB(p) then
			local names = {}
			for q, r in pairs(scene) do if q.Parent and not r.hidden then names[#names + 1] = q end end
			table.sort(names, function(a, b) return a.Name < b.Name end)
			p = names[1]
		end
		if not isRB(p) then
			addShape("Cube")
			sceneAdd(Selection:Get()[1])
			p = Selection:Get()[1]
		end
		if isRB(p) then Selection:Set({ p }) activeObj = p end
	end
	if not isRB(p) then setStatus("Select a " .. NAME .. " mesh first (Shift A adds one).") return end
	enterEdit(p)
end
local function needEdit(fn)
	return function()
		if not editing then setStatus("Tab into Edit Mode on a " .. NAME .. " part first.") return end
		if modal then return end
		fn()
	end
end
local function transformTool(kind)
	return function()
		if modal then return end
		if editing then startTransform(kind)
		elseif uiOn then startObjTransform(kind)
		else setStatus("Tab into Edit Mode on a " .. NAME .. " part first.") end
	end
end
local TOOL = {
	G = transformTool("G"), R = transformTool("R"), S = transformTool("S"),
	Extrude = needEdit(Tools.extrude), Inset = needEdit(Tools.inset), LoopCut = needEdit(Tools.loopCut),
	Subdivide = needEdit(Tools.subdivide), Merge = needEdit(Tools.merge), MergeDist = needEdit(Tools.mergeDist),
	Fill = needEdit(Tools.fill), Delete = needEdit(Tools.delete), Flip = needEdit(Tools.flip),
	SelectAll = function()
		if editing then clearSel() for v in pairs(bm.verts) do v.sel = true end for e in pairs(bm.edges) do e.sel = true end for f in pairs(bm.faces) do f.sel = true end flush() dirtyCage, dirtyMesh = true, true
		else local all = {} for p, r in pairs(scene) do if p.Parent and not r.hidden then all[#all + 1] = p end end Selection:Set(all) activeObj = all[1] dirtyCage = true end
	end,
	SelectNone = function()
		if editing then clearSel() flush() dirtyCage, dirtyMesh = true, true else selectObject(nil) end
	end,
	Invert = function()
		if editing then Tools.invert()
		else
			local cur, out = {}, {}
			for _, p in ipairs(Selection:Get()) do cur[p] = true end
			for p, r in pairs(scene) do if p.Parent and not r.hidden and not cur[p] then out[#out + 1] = p end end
			Selection:Set(out) activeObj = out[1] dirtyCage = true
		end
	end,
	Bake = Tools.bake, Export = Tools.exportOBJ,
	Save = function()
		local p = selectedPart()
		if not isRB(p) then setStatus("Select a " .. NAME .. " mesh to save.") return end
		if editing and p == obj then exitEdit() end
		if isSaved(p) then setStatus(p.Name .. " is already saved (rbxassetid://" .. tostring(p:GetAttribute("RB_AssetId")) .. ").") return end
		saveMesh(p)
	end,
	SaveAll = function()
		if editing then exitEdit() end
		local n = 0
		for q in pairs(scene) do if q.Parent and not isSaved(q) then saveMesh(q) n += 1 end end
		if n == 0 then setStatus("Everything is saved.") end
	end,
	DeleteObjects = function() if not editing and not modal then deleteObjects() end end,
	Duplicate = function() if not editing and not modal then duplicateObjects() end end,
}
TOOL.Move, TOOL.Rotate, TOOL.Scale = TOOL.G, TOOL.R, TOOL.S
TOOL.Join = function() if not editing and not modal then OT.join() end end
TOOL.OriginToGeometry = function() OT.setOrigin("geometry") end
TOOL.OriginToCursor = function() OT.setOrigin("cursor") end
TOOL.GeometryToOrigin = function() OT.setOrigin("origin") end
TOOL.ApplyRotation = OT.applyRotation
TOOL.HideSelected = function() if not editing then OT.hide("selected") end end
TOOL.HideUnselectedObj = function() if not editing then OT.hide("unselected") end end
TOOL.RevealObj = function() if not editing then OT.hide("reveal") end end
TOOL.ClearLocation = function() if not editing then OT.clearTransform("loc") end end
TOOL.ClearRotation = function() if not editing then OT.clearTransform("rot") end end
TOOL.LocalView = OT.toggleLocalView
TOOL.ObjShadeSmooth = function() if not editing then OT.shade(true) end end
TOOL.ObjShadeFlat = function() if not editing then OT.shade(false) end end
TOOL.ObjShadeAuto = function() if not editing then OT.shade(true, 30) end end
TOOL.LoopCut = needEdit(function() MOD.T.loopCutModal() end)
local ANY_MODE = { CursorToSel = true, CursorToOrigin = true, CursorToGrid = true, ClearAnnotations = true }
for name, fn in pairs(MOD.ops) do
	if not TOOL[name] or name == "Duplicate" then
		if ANY_MODE[name] then TOOL[name] = fn
		elseif name == "Duplicate" then
			local objDup = TOOL.Duplicate
			TOOL.Duplicate = function() if editing then if not modal then fn() end else objDup() end end
		else TOOL[name] = needEdit(fn) end
	end
end

local api = { version = VERSION, logoImage = logoImage }
local setUIOn, setStudioView
function api.state()
	local st = { editing = editing, mode = mode, xray = xray, shading = shading, studioView = useStudio, autoSave = autoSave,
		modal = modal and modal.kind or nil, modalWhat = modal and modal.what or nil, modalText = lastStatus,
		camCF = camera().CFrame,
		viewName = view and ((view.viewName or "User") .. (view.ortho and " Orthographic" or " Perspective")) or nil,
		activeTool = MOD.tool, snap = EDIT.snap, prop = EDIT.prop, mirrorX = EDIT.mirrorX, autoMerge = EDIT.autoMerge,
		paintMode = paintMode, brush = SCULPT and brushCtl().brush, brushRadius = SCULPT and brushCtl().radius, brushStrength = SCULPT and brushCtl().strength, symmetryX = SCULPT and brushCtl().symmetryX,
		paintColor = PAINT and Paint.hex(PAINT.color),
		propFalloff = EDIT.propFalloff, boxMode = EDIT.boxMode, snapTarget = EDIT.snapTarget, pivot = EDIT.pivot,
		lastOp = MOD.lastOp and MOD.lastOp.name or nil }
	local p = selectedPart()
	if p then
		st.objName, st.isRB = p.Name, isRB(p)
		st.objLoc, st.objDim = p.CFrame.Position, p.Size
		local rx, ry, rz = p.CFrame:ToOrientation()
		st.objRot = V3(math.deg(rx), math.deg(ry), math.deg(rz))
		st.color, st.material = p.Color, p.Material and p.Material.Name
		st.hidden = scene[p] ~= nil and scene[p].hidden == true
		if isRB(p) then
			st.text = p:GetAttribute("RB_Text")
			st.textPixel, st.textDepth = p:GetAttribute("RB_TextPixel"), p:GetAttribute("RB_TextDepth")
			st.uv = uvOf(p)
			pcall(function() st.texture = p.TextureID end)
			st.modsKey = modsStr(p) .. uvKey(p) .. tostring(st.texture) .. tostring(st.text)
			st.mods = modsOf(p)
			st.saved = isSaved(p)
			st.assetId = p:GetAttribute("RB_AssetId")
			st.saving = saving[p] == true
		end
	end
	local m = (editing and bm) or (p and scene[p] and scene[p].bm)
	if m then
		local t = 0
		for f in pairs(m.faces) do t += f.len - 2 end
		st.meshInfo = { v = m.nv, e = m.ne, f = m.nf, t = t }
	end
	if editing and bm then
		local s = { v = bm.nv, e = bm.ne, f = bm.nf, vs = 0, es = 0, fs = 0, t = st.meshInfo and st.meshInfo.t or 0 }
		local sum, n = V3(), 0
		for v in pairs(bm.verts) do if v.sel then s.vs += 1 sum += v.co n += 1 end end
		for e in pairs(bm.edges) do if e.sel then s.es += 1 end end
		for f in pairs(bm.faces) do if f.sel then s.fs += 1 end end
		st.stats = s
		if n > 0 then st.loc = W(sum / n) end
	elseif p then
		st.loc = p.CFrame.Position
	end
	return st
end
function api.outliner()
	local list = {}
	local sel = {}
	for _, p in ipairs(Selection:Get()) do sel[p] = true end
	for p, r in pairs(scene) do
		if p.Parent then list[#list + 1] = { key = p, name = p.Name, unsaved = not isSaved(p), selected = sel[p] == true or (editing and p == obj), active = p == activeObj or (editing and p == obj), hidden = r.hidden == true } end
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end
api.toggleEdit = toggleEdit
api.setTool = function(name) MOD.setTool(name) end
api.toggleEdit2 = function(key)
	EDIT[key] = not EDIT[key]
	setStatus(({ snap = "Snapping", prop = "Proportional editing", mirrorX = "X mirror", autoMerge = "Auto Merge Vertices" })[key] .. (EDIT[key] and " on." or " off."))
end
api.toggleXray = toggleXray

-- ----- modifiers (Properties > Modifiers) -----
local function modTarget() local p = selectedPart() if isRB(p) then return p end return nil end
-- the real part / our view catch up with a modifier change
local function modsChanged(p)
	if editing and p == obj then
		dirtyMesh = true
		if not ownView() then
			local _, _, np = applyMesh(obj, bm, true)
			if np then obj = np end
			origin = originOf(obj)
		end
	else
		local ok, m = pcall(loadFrom, p)
		if ok and m then applyMesh(p, m, false) end
		if scene[p] then scene[p].data = nil end
		-- save it a few seconds after the last change (not on every click: uploads are rate limited)
		if autoSave then MOD.modSave = MOD.modSave or {} MOD.modSave[p] = os.clock() end
	end
	dirtyCage = true
end
ctx.modTarget, ctx.modsChanged, ctx.modsOf, ctx.setMods, ctx.uvOf = modTarget, modsChanged, modsOf, setMods, uvOf
function ctx.replaceEdited(m, val) bm = m lastWritten = val worldTris = nil end
ModStack.install(api, ctx)
api.repeatLast = function() if editing and not modal then MOD.repeatLast() end end
MOD.subdivSet = api.subdivSet
api.similarList = function()
	local out = {}
	for _, k in ipairs(MT.SIMILAR[mode] or {}) do out[#out + 1] = { k[1], k[2] } end
	return out
end
api.selectSimilar = function(kind)
	if not editing or modal then return end
	local n = MT.selectSimilar(bm, mode, kind, 0)
	flush()
	dirtyCage, dirtyMesh = true, true
	setStatus(("Select Similar: %d more selected."):format(n))
end
api.falloffs = FALLOFF_ORDER
api.setFalloff = function(name)
	if FALLOFF[name] then EDIT.propFalloff = name EDIT.prop = true setStatus("Proportional falloff: " .. name .. " (proportional editing on).") end
end
api.setBoxMode = function(m) EDIT.boxMode = m end
api.setPivot = function(m) EDIT.pivot = m setStatus("Pivot: " .. ({ median = "Median Point", cursor = "3D Cursor", individual = "Individual Origins" })[m] .. ".") end
api.setSnapTarget = function(m) EDIT.snapTarget = m EDIT.snap = true setStatus("Snap to " .. m .. " (snapping on).") end
api.toggleOrtho = function() if view then view:toggleOrtho() dirtyCage = true end end
api.join = OT.join
-- Sculpt Mode (mode menu / Ctrl Tab)
api.setPaintMode = function(m)
	if modal then return end
	if not m then
		paintMode = nil
		SCULPT.exit() PAINT.exit()
		dirtyCage, dirtyMesh = true, true
		if editing then setStatus("Edit Mode.") end
		return
	end
	if not editing then toggleEdit() end
	if not editing then return end
	SCULPT.exit() PAINT.exit()
	paintMode = m
	clearSel()
	flush()
	worldTris = nil
	dirtyCage, dirtyMesh = true, true
	if m == "paint" then
		PAINT.setBrush(PAINT.brush)
		local c = obj and obj.Color
		if c and (c.R < 0.9 or c.G < 0.9 or c.B < 0.9) then
			setStatus("Vertex Paint. The part's colour tints the paint - Paint > White Base Colour shows the true colours.")
		elseif bm.nv < 100 then
			setStatus(("Vertex Paint. Colour goes on the points (%d here) and blends across faces - Subdivide for finer painting."):format(bm.nv))
		end
		return
	end
	SCULPT.setBrush(SCULPT.brush)
	if bm.nv < 300 then
		setStatus(("Sculpt Mode. This mesh only has %d points - use Sculpt > Subdivide (or Ctrl 2 on it first) for detail to sculpt."):format(bm.nv))
	end
end
api.brushes = Sculpt.BRUSHES
api.paintBrushes = Paint.BRUSHES
api.palette = Paint.PALETTE
api.setBrush = function(id) brushCtl().setBrush(id) end
api.sculptSet = function(key, value)
	local B = brushCtl()
	if key == "radius" then B.radius = math.clamp(value, 4, 500)
	elseif key == "strength" then B.strength = math.clamp(value, 0.01, 1)
	elseif key == "symmetryX" then B.symmetryX = value == true end
end
-- Text objects (Add > Text): change the words / block size / depth, the mesh is rebuilt
api.setText = function(key, value)
	local p = modTarget()
	if not (p and p:GetAttribute("RB_Text")) then return end
	if editing and p == obj then setStatus("Leave Edit Mode (Tab) to change the text.") return end
	local text = p:GetAttribute("RB_Text")
	local px = p:GetAttribute("RB_TextPixel") or 0.5
	local depth = p:GetAttribute("RB_TextDepth") or 1
	if key == "text" then text = tostring(value) ~= "" and tostring(value) or text
	elseif key == "pixel" then px = math.clamp(tonumber(value) or px, 0.05, 20)
	elseif key == "depth" then depth = math.clamp(tonumber(value) or depth, 0.05, 50) end
	local m = BMesh.new()
	Font.build(m, text, { pixel = px, depth = depth })
	if m.nf == 0 then setStatus("No letters to build.") return end
	record("Text", function()
		p:SetAttribute("RB_Text", text)
		p:SetAttribute("RB_TextPixel", px)
		p:SetAttribute("RB_TextDepth", depth)
		dataOf(p).Value = encode(m)
		modsChanged(p)
	end)
	setStatus(("Text: \"%s\"."):format(text))
end
-- Vertex Paint: colour, fill, white base
api.setPaintColor = function(c)
	if type(c) == "string" then c = Paint.fromHex(c) elseif type(c) == "number" then c = Paint.fromInt(c) end
	if c then PAINT.setColor(c) else setStatus("Colour: type 6 hex digits, like FF8800.") end
end
api.paintFill = function() if editing and paintMode == "paint" then PAINT.fill() end end
api.paintWhiteBase = function()
	if obj then record("White Base Colour", function() obj.Color = Color3.new(1, 1, 1) end) setStatus("Part colour set to white: the paint shows as painted.") end
end
api.paintClear = function()
	if not (editing and bm) then return end
	for v in pairs(bm.verts) do v.col = nil end
	dirtyMesh = true
	commit("Clear Colours")
	setStatus("Colours cleared.")
end
-- Sculpt > Subdivide: one Catmull-Clark level for the whole mesh (more points to sculpt), smooth shaded
api.sculptSubdivide = function()
	if not (editing and bm) or modal then return end
	local tris = 0
	for f in pairs(bm.faces) do tris += f.len - 2 end
	if tris * 4 > 20000 then setStatus(("Too dense to subdivide again (%d triangles now; Roblox allows 20,000)."):format(tris)) return end
	local nb = Mods.subsurf(bm, { levels = 1 })
	for f in pairs(nb.faces) do f.smooth = true f.sel = false end
	for v in pairs(nb.verts) do v.sel = false end
	for e in pairs(nb.edges) do e.sel = false end
	bm = nb
	worldTris = nil
	commit("Subdivide")
	setStatus(("Subdivided: %d points, %d faces."):format(bm.nv, bm.nf))
end
api.sculptSmooth = function(on)
	if not (editing and bm) then return end
	for f in pairs(bm.faces) do f.smooth = on or nil end
	commit(on and "Shade Smooth" or "Shade Flat")
end
api.togglePanel = function() widget.Enabled = not widget.Enabled end
api.setMode = function(m) if editing and not modal then setMode(m) end end
api.add = function(kind) addShape(kind) sceneAdd(Selection:Get()[1]) end
api.tool = function(name) local f = TOOL[name] if f then f() end end
api.mousePos = mousePos
api.shiftDown = shiftDown
api.selectObject = function(p, add) if editing or modal then return end selectObject(p, add) end
api.toggleHidden = function(p)
	p = p or selectedPart()
	if not p or not scene[p] then return end
	scene[p].hidden = not scene[p].hidden
	dirtyCage = true
end
api.navDrag = function(kind, dx, dy)
	if not view then return end
	if kind == "orbit" then view:orbit(dx, dy) view.viewName = nil
	elseif kind == "pan" then view:pan(dx, dy)
	else view:zoom(-dy / 30) end
	dirtyCage = true
end
api.viewAxis = function(name)
	if not view then return end
	view:viewAxis(name)
	view.viewName = name:sub(1, 1):upper() .. name:sub(2)
	dirtyCage = true
end
api.frameAll = frameAll
api.frameSelected = frameSelected
api.setShading = function(s) shading = s dirtyCage = true dirtyMesh = editing end
api.undo = function() pcall(function() CHS:Undo() end) end
api.redo = function() pcall(function() CHS:Redo() end) end
api.close = function() setUIOn(false) end
api.setStudioView = function(b) setStudioView(b) end
api.setAutoSave = function(b)
	autoSave = b
	pcall(function() plugin:SetSetting("RB_AutoSave", b) end)
	setStatus(b and "Meshes save to Roblox when you leave Edit Mode." or "Auto save off - use File > Save Mesh.")
end
api.rename = function(name)
	local p = selectedPart()
	if p then record("Rename", function() p.Name = name end) end
end
api.setLook = function(prop, value)
	local p = selectedPart()
	if not p then return end
	record(prop, function()
		if prop == "Material" then p.Material = Enum.Material[value] else p[prop] = value end
	end)
	dirtyMesh = editing
end
function api.setProp(key, axis, value)
	local p = selectedPart()
	if not p or modal then return end
	local function with(v3) return V3(axis == "X" and value or v3.X, axis == "Y" and value or v3.Y, axis == "Z" and value or v3.Z) end
	record(key, function()
		if key == "loc" then
			p.CFrame = p.CFrame.Rotation + with(p.CFrame.Position)
		elseif key == "rot" then
			local rx, ry, rz = p.CFrame:ToOrientation()
			local r = with(V3(math.deg(rx), math.deg(ry), math.deg(rz)))
			p.CFrame = CFrame.new(p.CFrame.Position) * CFrame.fromOrientation(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
		elseif key == "dim" and value > 0 then
			p.Size = with(p.Size)
		end
	end)
	if editing and p == obj then
		-- the edited part moved / resized: carry on from its new place
		exitEdit()
		enterEdit(p)
	end
	dirtyCage = true
end
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
		api.setProp("loc", axis, value)
	end
end

ui = UI.new(api, CoreGui)
pcall(function() useStudio = plugin:GetSetting("RB_StudioView") == true end)

-- Studio's own camera: saved when ROBLEND opens, held still while our 3D view covers it, put back on close
local function saveStudioCam()
	local cam = workspace.CurrentCamera
	if cam then MOD.savedCam = { cf = cam.CFrame, focus = cam.Focus } end
end
local function restoreStudioCam()
	local cam, sc = workspace.CurrentCamera, MOD.savedCam
	if cam and sc then
		pcall(function()
			cam.CFrame = sc.cf
			if sc.focus then cam.Focus = sc.focus end
		end)
	end
end
MOD.holdStudioCam = function()
	local cam, sc = workspace.CurrentCamera, MOD.savedCam
	if cam and sc and cam.CFrame ~= sc.cf then restoreStudioCam() end
end
setStudioView = function(b)
	if editing then exitEdit() end
	if b then restoreStudioCam() MOD.savedCam = nil else saveStudioCam() end
	if modal then finishModal(true) end
	useStudio = b
	pcall(function() plugin:SetSetting("RB_StudioView", b) end)
	if view then
		view.frame.Visible = not b
		view:beginCage() view:endCage()
	end
	if uiOn then
		if b then plugin:Deactivate() else plugin:Activate(true) end
	end
	dirtyCage = true
	setStatus(b and "Using Studio's 3D view (Edit > Use Studio's 3D View to switch back)." or "Using the ROBLEND 3D view.")
end
setUIOn = function(on)
	if not on then
		if modal then pcall(finishModal, true) end
		if editing then exitEdit() end
	end
	uiOn = on
	ui:setOn(on)
	pcall(function() btnMain:SetActive(on) end)
	if on then
		if not useStudio then saveStudioCam() end
		if not view then
			view = View.new(ui.canvas)
			view.frame.ZIndex = 1
			view.discard = function(part) Display.free(part) end
			local had = false
			sceneScan()
			for _ in pairs(scene) do had = true break end
			if had then syncScene() frameAll() end
		end
		sceneScan()
		for q in pairs(scene) do if not (editing and q == obj) then fixUnsaved(q) end end
		view.frame.Visible = not useStudio
		if ownView() then plugin:Activate(true) end
		local hasApi = pcall(function() assert(AssetService.CreateAssetAsync) end)
		setStatus(hasApi and ("Welcome to " .. NAME .. ". Shift A = add, click a mesh + Tab = edit, MMB / RMB drag = orbit, wheel = zoom.") or BETA_MSG)
	else
		if view then view:beginCage() view:endCage() end
		plugin:Deactivate()
		restoreStudioCam()
		MOD.savedCam = nil
		local n = 0
		for q in pairs(scene) do if q.Parent and not isSaved(q) then n += 1 end end
		if n > 0 then setStatus(("%d mesh%s not saved to Roblox yet - open ROBLEND and use File > Save All Meshes."):format(n, n == 1 and "" or "es")) end
	end
	dirtyCage = true
end
btnMain.Click:Connect(function() setUIOn(not uiOn) end)
plugin.Unloading:Connect(function()
	pcall(function() if editing then exitEdit() end end)
	ui:destroy()
	if view then view:destroy() end
	cageFolder.Parent = nil
end)

-- ===== mouse =====
local boxGui = Instance.new("ScreenGui")
boxGui.Name = NAME .. "_Box"
boxGui.IgnoreGuiInset = true
boxGui.DisplayOrder = 60
boxGui.Parent = CoreGui
plugin.Unloading:Connect(function() boxGui.Parent = nil end)
local boxFrame = Instance.new("Frame")
boxFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
boxFrame.BackgroundTransparency = 0.92
boxFrame.BorderSizePixel = 0
boxFrame.Visible = false
local st = Instance.new("UIStroke") st.Color = Color3.fromRGB(230, 230, 230) st.Parent = boxFrame
boxFrame.Parent = boxGui
local down = nil

-- select what's inside a screen region (box or lasso): inScreen(sp) -> bool
local function regionSelect(inScreen, add, sub)
	local function inside(wp)
		local sp, vis = toScreen(wp)
		return vis and inScreen(sp)
	end
	if not editing then
		-- object mode: objects whose middle is in the box
		local cur = (add or sub) and Selection:Get() or {}
		local set = {}
		for _, p in ipairs(cur) do set[p] = true end
		for p, r in pairs(scene) do
			if r.shown and inside(p.CFrame.Position) then set[p] = not sub or nil end
		end
		local out = {}
		for p in pairs(set) do out[#out + 1] = p end
		Selection:Set(out)
		if not set[activeObj] then activeObj = out[1] end
		dirtyCage = true
		return
	end
	-- Shift / Ctrl override the header's box mode (Set, Extend, Subtract, Difference, Intersect)
	local bmode = sub and "sub" or add and "add" or EDIT.boxMode or "set"
	if bmode == "set" then clearSel() end
	local function apply(x, hit)
		if bmode == "set" or bmode == "add" then if hit then x.sel = true end
		elseif bmode == "sub" then if hit then x.sel = false end
		elseif bmode == "xor" then if hit then x.sel = not x.sel end
		elseif bmode == "and" then x.sel = x.sel and hit end
	end
	if mode == "vert" then
		for v in pairs(bm.verts) do
			local wp = W(v.co)
			apply(v, inside(wp) and not occluded(wp, faceSetOfVert(v)))
		end
	elseif mode == "edge" then
		for e in pairs(bm.edges) do
			local a2, b2 = W(e.v1.co), W(e.v2.co)
			apply(e, inside(a2) and inside(b2) and not occluded((a2 + b2) / 2, faceSetOfEdge(e)))
		end
		if bmode ~= "set" and bmode ~= "add" then for v in pairs(bm.verts) do v.sel = false end for e in pairs(bm.edges) do if e.sel then e.v1.sel = true e.v2.sel = true end end end
	else
		for f in pairs(bm.faces) do
			local c = W(BMesh.faceCenter(f))
			apply(f, inside(c) and not occluded(c, { [f] = true }))
		end
		if bmode ~= "set" and bmode ~= "add" then
			for v in pairs(bm.verts) do v.sel = false end
			for e in pairs(bm.edges) do e.sel = false end
			for f in pairs(bm.faces) do if f.sel then for _, v in ipairs(BMesh.faceVerts(f)) do v.sel = true end end end
		end
	end
	flush()
	dirtyCage, dirtyMesh = true, true
end
local function boxSelect(a, b, add, sub)
	local lo = Vector2.new(math.min(a.X, b.X), math.min(a.Y, b.Y))
	local hi = Vector2.new(math.max(a.X, b.X), math.max(a.Y, b.Y))
	regionSelect(function(sp) return sp.X >= lo.X and sp.X <= hi.X and sp.Y >= lo.Y and sp.Y <= hi.Y end, add, sub)
end
-- Ctrl + right drag (Blender's Lasso Select; Shift Ctrl + right drag deselects). A Ctrl + right click still extrudes to the mouse.
local lasso = nil
local lassoLines = {}
local function drawLasso()
	local pts = lasso and lasso.pts or {}
	for i = 1, math.max(#pts, #lassoLines) do
		local a, b = pts[i], pts[i % #pts + 1]
		local ln = lassoLines[i]
		if a and b and #pts > 1 then
			if not ln then
				ln = Instance.new("Frame")
				ln.BorderSizePixel = 0
				ln.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
				ln.AnchorPoint = Vector2.new(0.5, 0.5)
				ln.Parent = boxGui
				lassoLines[i] = ln
			end
			local d = b - a
			ln.Visible = true
			ln.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			ln.Size = UDim2.fromOffset(d.Magnitude, 1)
			ln.Rotation = math.deg(math.atan2(d.Y, d.X))
		elseif ln then
			ln.Visible = false
		end
	end
end
local function inPolygon(pts, p)
	local inside = false
	local j = #pts
	for i = 1, #pts do
		local a, b = pts[i], pts[j]
		if (a.Y > p.Y) ~= (b.Y > p.Y) and p.X < (b.X - a.X) * (p.Y - a.Y) / (b.Y - a.Y) + a.X then inside = not inside end
		j = i
	end
	return inside
end
local function finishLasso()
	local L = lasso
	lasso = nil
	drawLasso()
	if not L then return end
	if L.len < 8 or #L.pts < 3 then
		if editing then
			local ok, err = pcall(MOD.ops.ExtrudeToMouse)
			if not ok then warn(NAME .. ": " .. tostring(err)) end
		end
		return
	end
	local ok, err = pcall(regionSelect, function(sp) return inPolygon(L.pts, sp) end, false, L.sub)
	if not ok then warn(NAME .. ": " .. tostring(err)) end
	setStatus(L.sub and "Lasso: deselected." or "Lasso: selected.")
end

mouse.Button1Down:Connect(function()
	local mp = mousePos()
	if ui:overUI(mp) then return end
	if paintMode and editing and ownView() and not modal and ui:inCanvas(mp) then
		local ok, err = pcall(brushCtl().press, mp)
		if not ok then warn(NAME .. ": " .. tostring(err)) end
		return
	end
	if modal and modal.click then
		local ok, err = pcall(modal.click)
		if not ok then warn(NAME .. ": " .. tostring(err)) end
		return
	end
	if modal and modal.releaseConfirm then return end
	if not modal and (editing or ownView()) then
		local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		local ok, used = pcall(MOD.press, mp, shiftDown(), ctrl)
		if not ok then warn(NAME .. ": " .. tostring(used)) return end
		if used then return end
	end
	if modal then
		if modal.kind == "loopcut" then pcall(updateLoopCut) end
		local ok, err = pcall(finishModal, false)
		if not ok then warn(NAME .. ": " .. tostring(err)) end
		return
	end
	if not editing and not ownView() then return end
	down = mp
end)
mouse.Button1Up:Connect(function()
	if uiOn then ui:mouseUp() end
	if paintMode and editing then
		local ok, err = pcall(brushCtl().release)
		if not ok then warn(NAME .. ": " .. tostring(err)) end
		return
	end
	if modal and modal.release then
		local ok, used = pcall(modal.release)
		if ok and used then return end
	end
	if modal and modal.releaseConfirm then
		local ok, err = pcall(finishModal, false)
		if not ok then warn(NAME .. ": " .. tostring(err)) end
		return
	end
	do
		local ok, used = pcall(MOD.release, mousePos())
		if not ok then warn(NAME .. ": " .. tostring(used)) elseif used then down = nil return end
	end
	if not down then return end
	local a, b = down, mousePos()
	down = nil
	boxFrame.Visible = false
	local shift = shiftDown()
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local alt = UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
	local ok, err = pcall(function()
		if (b - a).Magnitude > 6 then boxSelect(a, b, shift, ctrl) return end
		if not editing then
			selectObject(pickObject(b), shift)
			return
		end
		-- double click = loop select (Blender 4), like Alt click
		local now = os.clock()
		if not alt and not ctrl and MOD.lastClick and now - MOD.lastClick.t < 0.3 and (b - MOD.lastClick.at).Magnitude < 5 then alt = true end
		MOD.lastClick = { t = now, at = b }
		if alt and ctrl then
			-- Ctrl Alt click: edge ring select
			local e = pickEdge(b)
			if e then
				if not shift then clearSel() end
				local ring, quads = Ops.edgeRing(bm, e)
				if mode == "face" then for _, f in ipairs(quads or {}) do f.sel = true end
				else for _, re in ipairs(ring) do re.sel = true re.v1.sel = true re.v2.sel = true end end
				flush()
			end
		elseif alt then
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
			if x and ctrl and MOD.lastPick and MOD.lastPick ~= x and (MOD.lastPick.co ~= nil) == (x.co ~= nil) and (MOD.lastPick.len ~= nil) == (x.len ~= nil) then
				-- Ctrl click: the shortest path from the last picked element (Blender's Pick Shortest Path)
				if not MT.shortestPath(bm, MOD.lastPick, x, mode) then setStatus("No path between those.") end
			elseif x then
				if shift then toggle(x) else clearSel() toggle(x, true) end
			elseif not shift then clearSel() end
			if x then MOD.lastPick = x end
			flush()
		end
		dirtyCage, dirtyMesh = true, true
	end)
	if not ok then warn(NAME .. ": " .. tostring(err)) end
end)
mouse.Button2Down:Connect(function()
	if modal then pcall(finishModal, true) return end
	if paintMode and brushCtl().adjust then brushCtl().finishAdjust(true) return end
	local mp = mousePos()
	if ownView() and ui:inCanvas(mp) and (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
		lasso = { pts = { mp }, len = 0, sub = shiftDown() }
		return
	end
	if ownView() and ui:inCanvas(mp) then navDrag = { kind = shiftDown() and "pan" or "orbit", last = mp, moved = 0, rmb = true } end
end)
pcall(function()
	mouse.Button2Up:Connect(function()
		if lasso then finishLasso() return end
		local nd = navDrag
		if not (nd and nd.rmb) then return end
		navDrag = nil
		if nd.moved < 4 then
			local ok, err = pcall(function()
				if nd.kind == "pan" then MOD.placeCursor(mousePos()) else ui:openContextMenu(mousePos()) end
			end)
			if not ok then warn(NAME .. ": " .. tostring(err)) end
		end
	end)
end)
local wheelFromMouse = false
local function wheel(steps)
	if (editing or modal) and MOD.wheel(steps) then return end
	if not ownView() or ui.menuOpen or not ui:inCanvas(mousePos()) then return end
	view:zoom(steps)
	dirtyCage = true
end
pcall(function()
	mouse.WheelForward:Connect(function() wheelFromMouse = true wheel(1) end)
	mouse.WheelBackward:Connect(function() wheelFromMouse = true wheel(-1) end)
end)
mouse.Move:Connect(function()
	local mp = mousePos()
	if uiOn then pcall(function() ui:step(mp) end) end
	if lasso then
		local last = lasso.pts[#lasso.pts]
		local d = (mp - last).Magnitude
		if d >= 3 then lasso.pts[#lasso.pts + 1] = mp lasso.len += d drawLasso() end
		return
	end
	if navDrag then
		local dx, dy = mp.X - navDrag.last.X, mp.Y - navDrag.last.Y
		navDrag.last = mp
		navDrag.moved += math.abs(dx) + math.abs(dy)
		if dx ~= 0 or dy ~= 0 then api.navDrag(navDrag.kind, dx, dy) end
		return
	end
	if paintMode and editing and ownView() and not modal then
		if ui:inCanvas(mp) and not ui:overUI(mp) then
			local ok, err = pcall(brushCtl().move, mp)
			if not ok then warn(NAME .. ": " .. tostring(err)) end
		else
			brushCtl().hideRing()
		end
		return
	end
	if modal and modal.update then
		local ok, err = pcall(modal.update)
		if not ok then warn(NAME .. ": " .. tostring(err)) end
		return
	end
	do
		local ok, used = pcall(MOD.move, mp)
		if not ok then warn(NAME .. ": " .. tostring(used))
		elseif used == "drag" then down = nil boxFrame.Visible = false return
		elseif used then return end
	end
	if not editing and not (modal and modal.obj) then
		if down and ownView() then
			local a = down
			if (mp - a).Magnitude > 6 then
				boxFrame.Visible = true
				boxFrame.Position = UDim2.fromOffset(math.min(a.X, mp.X), math.min(a.Y, mp.Y))
				boxFrame.Size = UDim2.fromOffset(math.abs(a.X - mp.X), math.abs(a.Y - mp.Y))
			end
		end
		return
	end
	local ok, err = pcall(function()
		if modal then
			if modal.kind == "G" or modal.kind == "S" or modal.kind == "R" then applyTransform()
			elseif modal.kind == "inset" then updateInset()
			elseif modal.kind == "loopcut" then updateLoopCut() end
			return
		end
		if not down and ui:overUI(mp) then
			if hover then hover = nil dirtyCage = true end
			return
		end
		if down then
			local a = down
			if (mp - a).Magnitude > 6 then
				boxFrame.Visible = true
				boxFrame.Position = UDim2.fromOffset(math.min(a.X, mp.X), math.min(a.Y, mp.Y))
				boxFrame.Size = UDim2.fromOffset(math.abs(a.X - mp.X), math.abs(a.Y - mp.Y))
			end
			return
		end
		local h = pickAny()
		if h ~= hover then hover = h dirtyCage = true end
	end)
	if not ok then warn(NAME .. ": " .. tostring(err)) end
end)

-- ===== keys =====
local DIGITS = { Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	KeypadZero = "0", KeypadOne = "1", KeypadTwo = "2", KeypadThree = "3", KeypadFour = "4", KeypadFive = "5", KeypadSix = "6", KeypadSeven = "7", KeypadEight = "8", KeypadNine = "9",
	Period = ".", KeypadPeriod = ".", Minus = "-", KeypadMinus = "-" }
local function modalKey(k)
	if k == Enum.KeyCode.Escape then finishModal(true) return end
	if k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter then
		if modal.kind == "loopcut" then updateLoopCut() end
		finishModal(false)
		return
	end
	if modal.kind == "G" or modal.kind == "S" or modal.kind == "R" then
		if k == Enum.KeyCode.X or k == Enum.KeyCode.Y or k == Enum.KeyCode.Z then
			local a = k.Name
			modal.axisWorld = nil
			-- X = global X, X again = the mesh's own (local) X, again = off (Blender)
			if modal.axis == a and not modal.axisLocal and not modal.obj then modal.axisLocal = true
			elseif modal.axis == a then modal.axis, modal.axisLocal = nil, nil
			else modal.axis, modal.axisLocal = a, nil end
			applyTransform()
			return
		end
	end
	if k == Enum.KeyCode.Space and modal.kind == "knife" then finishModal(false) return end
	local ch = DIGITS[k.Name]
	if ch then modal.num = (modal.num or "") .. ch
	elseif k == Enum.KeyCode.Backspace then modal.num = (modal.num or ""):sub(1, -2)
	else return end
	if modal.update then modal.update() elseif modal.kind == "inset" then updateInset() elseif modal.kind ~= "loopcut" then applyTransform() end
end
local function navKey(k, ctrl)
	if not ownView() then return false end
	local n = k.Name
	if n == "KeypadOne" then api.viewAxis(ctrl and "back" or "front")
	elseif n == "KeypadThree" then api.viewAxis(ctrl and "left" or "right")
	elseif n == "KeypadSeven" then api.viewAxis(ctrl and "bottom" or "top")
	elseif n == "KeypadPeriod" then frameSelected()
	elseif n == "Home" then frameAll()
	elseif n == "KeypadPlus" then view:zoom(1) dirtyCage = true
	elseif n == "KeypadMinus" then view:zoom(-1) dirtyCage = true
	elseif n == "KeypadFive" then view:toggleOrtho() dirtyCage = true
	elseif n == "KeypadFour" then if ctrl then view:pan(-40, 0) else view:step(math.rad(15), 0) view.viewName = nil end dirtyCage = true
	elseif n == "KeypadSix" then if ctrl then view:pan(40, 0) else view:step(math.rad(-15), 0) view.viewName = nil end dirtyCage = true
	elseif n == "KeypadEight" then if ctrl then view:pan(0, -40) else view:step(0, math.rad(15)) view.viewName = nil end dirtyCage = true
	elseif n == "KeypadTwo" then if ctrl then view:pan(0, 40) else view:step(0, math.rad(-15)) view.viewName = nil end dirtyCage = true
	elseif n == "KeypadNine" then view:step(math.pi, -2 * view.pitch) view.viewName = nil dirtyCage = true
	elseif n == "KeypadDivide" then OT.toggleLocalView() frameSelected()
	else return false end
	return true
end
local function objectKey(k, shift, ctrl, alt)
	if not ownView() then return end
	if k == Enum.KeyCode.S and shift and not ctrl and not alt then ui:openNamedMenu("snap", mousePos()) return end
	if k == Enum.KeyCode.C and shift and ctrl and alt then ui:openNamedMenu("origin", mousePos()) return end
	if k == Enum.KeyCode.A and ctrl and not shift and not alt then ui:openNamedMenu("apply", mousePos()) return end
	if k == Enum.KeyCode.Z and not ctrl and not shift and not alt then ui:openNamedMenu("shading", mousePos()) return end
	if k == Enum.KeyCode.C and shift and not ctrl and not alt then CURSOR = V3() frameAll() setStatus("3D cursor to the world origin, view all.") return end
	if k == Enum.KeyCode.H and alt then OT.hide("reveal") return end
	if k == Enum.KeyCode.H and shift then OT.hide("unselected") return end
	if k == Enum.KeyCode.H then OT.hide("selected") return end
	if k == Enum.KeyCode.G and alt then OT.clearTransform("loc") return end
	if k == Enum.KeyCode.R and alt then OT.clearTransform("rot") return end
	if k == Enum.KeyCode.G and not ctrl then startObjTransform("G")
	elseif k == Enum.KeyCode.R and not ctrl then startObjTransform("R")
	elseif k == Enum.KeyCode.S and not ctrl then startObjTransform("S")
	elseif (k == Enum.KeyCode.X or k == Enum.KeyCode.Delete) and not ctrl then deleteObjects()
	elseif k == Enum.KeyCode.D and shift then duplicateObjects()
	elseif k == Enum.KeyCode.A and alt then TOOL.SelectNone()
	elseif k == Enum.KeyCode.A and not ctrl then TOOL.SelectAll()
	elseif k == Enum.KeyCode.I and ctrl then TOOL.Invert()
	elseif k == Enum.KeyCode.J and ctrl then OT.join()
	elseif ctrl and ({ Zero = 0, One = 1, Two = 2, Three = 3, Four = 4, Five = 5 })[k.Name] then MOD.subdivSet(({ Zero = 0, One = 1, Two = 2, Three = 3, Four = 4, Five = 5 })[k.Name])
	elseif k == Enum.KeyCode.Z and alt then toggleXray()
	elseif k == Enum.KeyCode.Z and shift then api.setShading(shading == "wire" and "solid" or "wire")
	end
end
UIS.InputBegan:Connect(function(input, gp)
	if UIS:GetFocusedTextBox() then return end
	local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
	local shift = shiftDown()
	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		local mp = mousePos()
		if ownView() and not modal and ui:inCanvas(mp) then navDrag = { kind = shift and "pan" or (ctrl and "zoom" or "orbit"), last = mp, moved = 0 } end
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local k = input.KeyCode
	local alt = UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
	if uiOn and ui.menuOpen then
		if k == Enum.KeyCode.Escape then ui:closeMenu() end
		return
	end
	if k == Enum.KeyCode.F3 and uiOn and not modal then ui:openSearch() return end
	if k == Enum.KeyCode.Tab and ctrl and uiOn and not modal then ui:openNamedMenu("mode", mousePos()) return end
	if k == Enum.KeyCode.Tab and shift and not ctrl and not alt and uiOn then
		EDIT.snap = not EDIT.snap
		setStatus("Snapping " .. (EDIT.snap and ("on (" .. EDIT.snapTarget .. ")") or "off") .. ".")
		return
	end
	if k == Enum.KeyCode.Tab and not ctrl and not alt then
		if modal then return end
		if editing then exitEdit()
		elseif uiOn then toggleEdit()
		elseif isRB(Selection:Get()[1]) then enterEdit(Selection:Get()[1]) end
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
	local ok, err = pcall(function()
		if modal then
			if MOD.modalKey(k) then return end
			modalKey(k)
			return
		end
		if navKey(k, ctrl) then return end
		if paintMode and editing then
			-- Sculpt Mode: brush keys only (no mesh-editing tools)
			if brushCtl().key(k, shift, ctrl, alt) then return end
			if k == Enum.KeyCode.Z and alt then toggleXray()
			elseif k == Enum.KeyCode.Z and shift then api.setShading(shading == "wire" and "solid" or "wire")
			elseif k == Enum.KeyCode.Z then ui:openNamedMenu("shading", mousePos()) end
			return
		end
		if k == Enum.KeyCode.Escape and MOD.measure then MOD.measure = nil dirtyCage = true return end
		if not editing then
			if uiOn then objectKey(k, shift, ctrl, alt) end
			return
		end
		if uiOn and MOD.editKey(k, shift, ctrl, alt) then return end
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
		elseif k == Enum.KeyCode.E then Tools.extrude() MOD.remember("Extrude", Tools.extrude)
		elseif k == Enum.KeyCode.I then Tools.inset() MOD.remember("Inset", Tools.inset)
		elseif k == Enum.KeyCode.X or k == Enum.KeyCode.Delete then Tools.delete()
		elseif k == Enum.KeyCode.M then Tools.merge()
		elseif k == Enum.KeyCode.F then Tools.fill()
		elseif k == Enum.KeyCode.Z and alt then toggleXray()
		elseif k == Enum.KeyCode.Z and shift and uiOn then api.setShading(shading == "wire" and "solid" or "wire")
		end
	end)
	if not ok then warn(NAME .. ": " .. tostring(err)) setStatus("Error: " .. tostring(err)) end
end)
pcall(function()
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			if navDrag and not navDrag.rmb then navDrag = nil end
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if uiOn then ui:mouseUp() end
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not wheelFromMouse then
			wheel(input.Position.Z > 0 and 1 or -1)
		end
	end)
end)

-- ===== keep everything up to date (the edited mesh is rebuilt at most ~20 times a second) =====
local lastCam = nil
local lastUI, lastSync = 0, 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if uiOn and now - lastUI > 0.1 then
		lastUI = now
		local ok, err = pcall(function() ui:refresh() end)
		if not ok then warn(NAME .. " UI: " .. tostring(err)) end
	end
	if ownView() then
		pcall(function() if not plugin:IsActivated() then plugin:Activate(true) end end)
		MOD.holdStudioCam()
		if now - lastSync > 0.2 then
			lastSync = now
			local ok, changed = pcall(syncScene)
			if ok and changed then dirtyCage = true elseif not ok then warn(NAME .. ": " .. tostring(changed)) end
		end
	end
	-- timed save while editing in our view, so a crash loses little
	if editing and obj and ownView() and autoSave then
		MOD.lastAuto = MOD.lastAuto or now
		if now - MOD.lastAuto > 90 then
			MOD.lastAuto = now
			if not isSaved(obj) and not saving[obj] then saveMesh(obj, true, true) end
		end
	else
		MOD.lastAuto = nil
	end
	if MOD.modSave then
		for p, t0 in pairs(MOD.modSave) do
			if now - t0 > 4 then
				MOD.modSave[p] = nil
				if p.Parent and not (editing and p == obj) and isRB(p) and not isSaved(p) then saveMesh(p, true, true) end
			end
		end
	end
	if editing and obj then
		if not obj.Parent then exitEdit() return end
		local ms = modsStr(obj)
		if ms ~= MOD.modsSeen then MOD.modsSeen = ms dirtyMesh = true end
		if dirtyMesh and now - lastBuild > 0.05 then
			dirtyMesh = false
			lastBuild = now
			if ownView() then
				local _, err = showEdit()
				if err then setStatus("Mesh: " .. tostring(err)) end
			else
				local ok, err, np = applyMesh(obj, bm, true)
				if np then obj = np end
				if ok then origin = originOf(obj) else setStatus("Mesh: " .. tostring(err)) end
			end
			worldTris = nil
			dirtyCage = true
		end
	end
	if editing or ownView() then
		local cf = camera().CFrame
		if dirtyCage or cf ~= lastCam then
			lastCam = cf
			dirtyCage = false
			drawCage()
		end
	end
end)

end
window()

-- after Studio opens a place: rebuild the look of ROBLEND meshes that were never saved to Roblox
task.delay(3, function()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("MeshPart") and d:FindFirstChild("RB_Data") then fixUnsaved(d) end
	end
end)

print(NAME .. " " .. VERSION .. " loaded - free, open-source modelling by Cruppnomics (GPL-2.0-or-later). Portions derived from Blender; not affiliated with or endorsed by the Blender Foundation.")
