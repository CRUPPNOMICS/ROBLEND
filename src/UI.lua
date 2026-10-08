--[[
	ROBLENDER - the Blender-style window: top bar, 3D view header + tool strip + navigation gizmo,
	Outliner, Properties editor and status bar.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).
	Converted from Blender's UI definitions (GPL-2.0-or-later, Blender Authors):
	  release/datafiles/userdef/userdef_default_theme.c   (every colour below)
	  scripts/startup/bl_ui/space_view3d.py              (header menus, Add menu, context menus)
	  scripts/startup/bl_ui/space_toolsystem_toolbar.py  (tool strip names, tooltips, shortcuts)
	  scripts/startup/bl_ui/space_topbar.py, space_outliner.py, properties_object.py, space_statusbar.py
	Icons are drawn from simple shapes (Blender's icon images aren't included).
	Not made or endorsed by the Blender Foundation.
]]

local UI = {}
UI.__index = UI

local function rgb(hex) return Color3.fromRGB(bit32.rshift(hex, 16) % 256, bit32.rshift(hex, 8) % 256, hex % 256) end
-- Blender default theme
local T = {
	border = rgb(0x161616),
	topbar = rgb(0x181818),
	header = rgb(0x303030),
	props = rgb(0x303030),
	outliner = rgb(0x282828),
	status = rgb(0x303030),
	statusText = rgb(0x838383),
	text = rgb(0xe6e6e6),
	textMenu = rgb(0xdddddd),
	textDim = rgb(0x999999),
	textTab = rgb(0x989898),
	panel = rgb(0x3d3d3d),
	panelSub = rgb(0x353535),
	num = rgb(0x545454),
	regular = rgb(0x545454),
	textField = rgb(0x1d1d1d),
	toolItem = rgb(0x282828),
	tabInner = rgb(0x1d1d1d),
	tabSel = rgb(0x303030),
	menuBack = rgb(0x181818),
	menuOutline = rgb(0x242424),
	blue = rgb(0x4772b3),
	tooltip = rgb(0x1d1d1d),
	tooltipText = rgb(0xd9d9d9),
	outSel = rgb(0x1d314d),
	outActive = rgb(0x334d80),
	activeObj = rgb(0xffaf29),
	selObj = rgb(0xe96a00),
	xaxis = rgb(0xff3352), yaxis = rgb(0x8bdc00), zaxis = rgb(0x2890ff),
	iconObject = rgb(0xe19658), iconData = rgb(0x00d4a3), iconShading = rgb(0xcc6670), iconModifier = rgb(0x74a2ff),
	white = Color3.new(1, 1, 1),
	orange = rgb(0xff8c1a),
}
UI.THEME = T
local FONT, FONT_B = Enum.Font.Gotham, Enum.Font.GothamMedium
local TOP_H, HDR_H, STATUS_H, RIGHT_W = 26, 26, 22, 300

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) make("UICorner", { CornerRadius = UDim.new(0, r or 4) }, o) return o end
local function stroke(o, c, th) make("UIStroke", { Color = c, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o) return o end
local function label(parent, props)
	local t = make("TextLabel", { BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left }, parent)
	for k, v in pairs(props or {}) do t[k] = v end
	return t
end
local function hlist(parent, pad, align)
	return make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, pad or 2), VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = align or Enum.HorizontalAlignment.Left, SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end
local function vlist(parent, pad)
	return make("UIListLayout", { Padding = UDim.new(0, pad or 0), SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end

-- ===== icons, drawn from frames in a 16x16 box =====
local function seg(box, x1, y1, x2, y2, col, w)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2), Size = UDim2.fromOffset(len + (w or 1.5) * 0.5, w or 1.5),
		Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = col, BorderSizePixel = 0 }, box)
end
local function ring(box, cx, cy, r, col, filled)
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(r * 2, r * 2), BackgroundColor3 = col, BackgroundTransparency = filled and 0 or 1, BorderSizePixel = 0 }, box)
	corner(f, 99)
	if not filled then stroke(f, col, 1.3) end
	return f
end
local function rect(box, x, y, w, h, col, filled, alpha)
	local f = make("Frame", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = col, BackgroundTransparency = filled and (alpha or 0) or 1, BorderSizePixel = 0 }, box)
	if not filled then stroke(f, col, 1.2) end
	return f
end
local function icon(parent, kind, col, size)
	col = col or T.text
	local box = make("Frame", { Name = "Icon", BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, parent)
	if size then make("UIScale", { Scale = size / 16 }, box) end
	if kind == "select" then
		rect(box, 1, 1, 11, 11, col, false)
		seg(box, 8, 7, 8, 15, col) seg(box, 8, 7, 14, 12, col) seg(box, 8, 15, 10, 12, col) seg(box, 10, 12, 14, 12, col)
	elseif kind == "move" then
		seg(box, 8, 1, 8, 15, col) seg(box, 1, 8, 15, 8, col)
		seg(box, 8, 1, 6, 3.5, col) seg(box, 8, 1, 10, 3.5, col) seg(box, 8, 15, 6, 12.5, col) seg(box, 8, 15, 10, 12.5, col)
		seg(box, 1, 8, 3.5, 6, col) seg(box, 1, 8, 3.5, 10, col) seg(box, 15, 8, 12.5, 6, col) seg(box, 15, 8, 12.5, 10, col)
	elseif kind == "rotate" then
		ring(box, 8, 8, 6, col, false) ring(box, 8, 8, 1.5, col, true)
		seg(box, 14, 6, 12, 8.5, col) seg(box, 14, 6, 15.5, 8.5, col)
	elseif kind == "scale" then
		rect(box, 1, 6, 9, 9, col, false) seg(box, 6, 10, 14, 2, col) seg(box, 14, 2, 10, 2, col) seg(box, 14, 2, 14, 6, col)
	elseif kind == "cube" then
		rect(box, 2, 5, 9, 9, col, false) seg(box, 2, 5, 5, 2, col) seg(box, 11, 5, 14, 2, col) seg(box, 5, 2, 14, 2, col) seg(box, 14, 2, 14, 11, col) seg(box, 11, 14, 14, 11, col)
	elseif kind == "extrude" then
		rect(box, 2, 9, 12, 6, col, true, 0.5) seg(box, 8, 9, 8, 1, col) seg(box, 8, 1, 5.5, 3.5, col) seg(box, 8, 1, 10.5, 3.5, col)
	elseif kind == "inset" then
		rect(box, 1, 1, 14, 14, col, false) rect(box, 5, 5, 6, 6, col, true, 0.3)
	elseif kind == "loopcut" then
		rect(box, 1, 1, 14, 14, col, false) seg(box, 1, 8, 15, 8, rgb(0xffd800), 2)
	elseif kind == "vert" then
		rect(box, 3, 3, 11, 11, col, false) rect(box, 1, 1, 5, 5, col, true)
	elseif kind == "edge" then
		rect(box, 3, 3, 11, 11, col, false) seg(box, 3, 1, 3, 15, col, 3)
	elseif kind == "face" then
		rect(box, 3, 3, 11, 11, col, true, 0.35) rect(box, 3, 3, 11, 11, col, false)
	elseif kind == "object" then
		rect(box, 3, 3, 10, 10, T.iconObject, true)
	elseif kind == "mesh" then
		seg(box, 8, 2, 2, 14, T.iconObject, 2) seg(box, 8, 2, 14, 14, T.iconObject, 2) seg(box, 2, 14, 14, 14, T.iconObject, 2)
	elseif kind == "meshdata" then
		seg(box, 8, 2, 2, 14, T.iconData, 1.5) seg(box, 8, 2, 14, 14, T.iconData, 1.5) seg(box, 2, 14, 14, 14, T.iconData, 1.5)
		ring(box, 8, 2, 1.8, T.iconData, true) ring(box, 2, 14, 1.8, T.iconData, true) ring(box, 14, 14, 1.8, T.iconData, true)
	elseif kind == "material" then
		ring(box, 8, 8, 6, T.iconShading, true) ring(box, 6, 6, 1.6, T.white, true)
	elseif kind == "export" then
		rect(box, 2, 6, 12, 9, T.iconModifier, false) seg(box, 8, 1, 8, 10, T.iconModifier) seg(box, 8, 1, 5.5, 3.5, T.iconModifier) seg(box, 8, 1, 10.5, 3.5, T.iconModifier)
	elseif kind == "collection" then
		rect(box, 2, 4, 12, 9, T.white, false) seg(box, 2, 4, 6, 1.5, T.white) seg(box, 6, 1.5, 14, 1.5, T.white)
	elseif kind == "scene" then
		ring(box, 8, 8, 6, rgb(0xcccccc), false) ring(box, 8, 8, 2, rgb(0xcccccc), true)
	elseif kind == "eye" then
		ring(box, 8, 8, 6, col, false) ring(box, 8, 8, 2.2, col, true)
	elseif kind == "eyeoff" then
		seg(box, 2, 8, 14, 8, col)
	elseif kind == "zoom" then
		ring(box, 7, 7, 4.5, col, false) seg(box, 10, 10, 15, 15, col, 2)
	elseif kind == "hand" then
		rect(box, 4, 6, 9, 9, col, false) seg(box, 5, 6, 5, 2, col) seg(box, 8, 6, 8, 1, col) seg(box, 11, 6, 11, 2, col)
	elseif kind == "frame" then
		seg(box, 1, 1, 5, 1, col) seg(box, 1, 1, 1, 5, col) seg(box, 15, 1, 11, 1, col) seg(box, 15, 1, 15, 5, col)
		seg(box, 1, 15, 5, 15, col) seg(box, 1, 15, 1, 11, col) seg(box, 15, 15, 11, 15, col) seg(box, 15, 15, 15, 11, col) ring(box, 8, 8, 2, col, true)
	elseif kind == "xray" then
		rect(box, 1, 4, 9, 9, col, false) rect(box, 6, 1, 9, 9, col, true, 0.6)
	elseif kind == "wire" then
		ring(box, 8, 8, 6.5, col, false) seg(box, 1.5, 8, 14.5, 8, col, 1) seg(box, 8, 1.5, 8, 14.5, col, 1)
	elseif kind == "solid" then
		ring(box, 8, 8, 6.5, col, true)
	elseif kind == "editor" then
		rect(box, 1, 3, 14, 10, col, false) seg(box, 4, 10, 8, 6, col) seg(box, 8, 6, 12, 10, col)
	elseif kind == "check" then
		seg(box, 3, 8, 6.5, 12, col, 2) seg(box, 6.5, 12, 13, 4, col, 2)
	elseif kind == "logo" then
		local f = rect(box, 0, 0, 16, 16, T.orange, true) corner(f, 4)
		label(box, { Size = UDim2.fromScale(1, 1), Text = "R", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = T.white, TextXAlignment = Enum.TextXAlignment.Center })
	end
	return box
end
UI.icon = icon

-- ===== construction =====
function UI.new(api, parentGui)
	local self = setmetatable({ api = api, on = false, menuOpen = nil, subOpen = nil, sidebar = false, toolbar = true,
		hover = {}, report = "", drag = nil, propTab = "object", panelsOpen = { transform = true, vis = false, mesh = true, surface = true, keep = true },
		fields = {}, outRows = {}, version = api.version or "" }, UI)
	local gui = make("ScreenGui", { Name = "ROBLENDER_UI", Enabled = false, IgnoreGuiInset = true, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ResetOnSpawn = false }, parentGui)
	self.gui = gui
	self:buildTopBar()
	self:buildView()
	self:buildOutliner()
	self:buildProperties()
	self:buildStatus()
	-- tooltip + menu catcher
	self.tipFrame = make("Frame", { Visible = false, ZIndex = 40, BackgroundColor3 = T.tooltip, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0) }, gui)
	corner(stroke(self.tipFrame, T.menuOutline), 4)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, self.tipFrame)
	self.tipText = label(self.tipFrame, { ZIndex = 41, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), TextColor3 = T.tooltipText, RichText = true, TextYAlignment = Enum.TextYAlignment.Top })
	self.catcher = make("TextButton", { Visible = false, ZIndex = 18, BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1) }, gui)
	self.catcher.Activated:Connect(function() self:closeMenu() end)
	self.catcher.MouseButton2Click:Connect(function() self:closeMenu() end)
	self:refresh(true)
	return self
end

function UI:safe(fn, ...)
	if not fn then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("ROBLENDER UI: " .. tostring(err)) end
	self:refresh(true)
end

-- a button that lightens on hover (Blender pulldown / regular widget)
function UI:btn(parent, props, fn, style)
	local b = make("TextButton", { AutoButtonColor = false, BorderSizePixel = 0, Font = FONT, TextSize = 12, TextColor3 = T.text, Text = "" }, parent)
	for k, v in pairs(props) do b[k] = v end
	style = style or "pulldown"
	b:SetAttribute("rbStyle", style)
	if style == "pulldown" then b.BackgroundColor3 = T.white b.BackgroundTransparency = 1 end
	self.base = self.base or {}
	self.base[b] = b.BackgroundColor3
	b.MouseEnter:Connect(function()
		self.hover[b] = true
		if style == "pulldown" then b.BackgroundTransparency = 0.9
		elseif not b:GetAttribute("rbOn") then b.BackgroundColor3 = Color3.new(math.min(1, b.BackgroundColor3.R + 0.07), math.min(1, b.BackgroundColor3.G + 0.07), math.min(1, b.BackgroundColor3.B + 0.07)) end
	end)
	b.MouseLeave:Connect(function()
		self.hover[b] = nil
		if style == "pulldown" then b.BackgroundTransparency = 1
		elseif not b:GetAttribute("rbOn") then b.BackgroundColor3 = self.base[b] end
		self:refresh(true)
	end)
	if fn then b.Activated:Connect(function() self:safe(fn, b) end) end
	return b
end
function UI:setOnStyle(b, on, offCol)
	b:SetAttribute("rbOn", on)
	self.base[b] = offCol or T.regular
	if not self.hover[b] or on then b.BackgroundColor3 = on and T.blue or self.base[b] end
end

function UI:tip(b, title, desc, shortcut)
	b.MouseEnter:Connect(function()
		local s = "<b>" .. title .. "</b>"
		if desc and desc ~= "" then s ..= "\n" .. desc end
		if shortcut and shortcut ~= "" then s ..= "\n<font color=\"#999999\">Shortcut: " .. shortcut .. "</font>" end
		self.tipText.Text = s
		local p, sz = b.AbsolutePosition, b.AbsoluteSize
		if p and sz then
			if b:GetAttribute("rbTipRight") then self.tipFrame.Position = UDim2.fromOffset(p.X + sz.X + 10, p.Y)
			else self.tipFrame.Position = UDim2.fromOffset(p.X, p.Y + sz.Y + 6) end
		end
		self.tipFrame.Visible = true
	end)
	b.MouseLeave:Connect(function() self.tipFrame.Visible = false end)
end

-- ===== top bar: logo, File / Edit / Help, workspace tabs =====
function UI:buildTopBar()
	local api = self.api
	local bar = make("Frame", { Name = "TopBar", BackgroundColor3 = T.topbar, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, TOP_H) }, self.gui)
	self.topBar = bar
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -200, 1, 0) }, bar)
	hlist(row, 2)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, row)
	local logo = make("Frame", { LayoutOrder = 0, BackgroundTransparency = 1, Size = UDim2.fromOffset(26, 20) }, row)
	icon(logo, "logo")
	local n = 0
	local function menu(text, items)
		n += 1
		local b = self:btn(row, { LayoutOrder = n, Size = UDim2.fromOffset(#text * 7 + 16, 20), Text = text, TextColor3 = rgb(0xd9d9d9) }, function(btn) self:openMenu(items(), btn) end)
		corner(b, 4)
		return b
	end
	menu("File", function() return {
		{ "Bake to Parts", "", function() api.tool("Bake") end },
		{ "Export .obj", "", function() api.tool("Export") end },
		"-",
		{ "Close ROBLENDER", "", function() api.close() end },
	} end)
	menu("Edit", function() return {
		{ "Undo", "Ctrl Z", function() api.undo() end },
		{ "Redo", "Ctrl Y", function() api.redo() end },
		"-",
		{ "Use Studio's 3D View", "", function() api.setStudioView(not api.state().studioView) end, check = api.state().studioView },
	} end)
	menu("Help", function() return self:helpItems() end)
	-- workspace tabs (Layout = Object Mode, Modeling = Edit Mode)
	n += 1
	make("Frame", { LayoutOrder = n, BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 1) }, row)
	self.tabs = {}
	for _, t in ipairs({ { "Layout", false }, { "Modeling", true } }) do
		n += 1
		local b = self:btn(row, { LayoutOrder = n, Size = UDim2.fromOffset(#t[1] * 7 + 20, 22), Text = t[1], BackgroundColor3 = T.topbar }, function()
			if api.state().editing ~= t[2] then api.toggleEdit() end
		end, "tab")
		corner(b, 4)
		self.tabs[t[1]] = { b = b, edit = t[2] }
	end
	-- scene name on the right
	local right = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromOffset(190, TOP_H) }, bar)
	hlist(right, 4, Enum.HorizontalAlignment.Right)
	local sc = make("Frame", { LayoutOrder = 1, BackgroundColor3 = T.textField, BorderSizePixel = 0, Size = UDim2.fromOffset(150, 20) }, right)
	corner(sc, 4)
	local ic = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 20) }, sc)
	icon(ic, "scene")
	label(sc, { Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 1, 0), Text = "Scene" })
end

-- ===== 3D view area =====
function UI:buildView()
	local api = self.api
	local area = make("Frame", { Name = "ViewArea", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, TOP_H + 2), Size = UDim2.new(1, -RIGHT_W - 2, 1, -(TOP_H + 2) - STATUS_H - 2) }, self.gui)
	self.viewArea = area
	-- header
	local hdr = make("Frame", { Name = "Header", BackgroundColor3 = T.header, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, HDR_H) }, area)
	self.header = hdr
	local left = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -150, 1, 0) }, hdr)
	hlist(left, 2)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, left)
	local n = 0
	local function nx() n += 1 return n end
	local ed = self:btn(left, { LayoutOrder = nx(), Size = UDim2.fromOffset(32, 20), BackgroundColor3 = T.textField }, nil, "regular")
	corner(ed, 4) icon(ed, "editor")
	self:tip(ed, "Editor Type", "3D Viewport")
	local mode = self:btn(left, { LayoutOrder = nx(), Size = UDim2.fromOffset(118, 20), BackgroundColor3 = T.textField, Text = "      Object Mode   v", TextXAlignment = Enum.TextXAlignment.Left }, function(b)
		self:openMenu({
			{ "Object Mode", "Tab", function() if api.state().editing then api.toggleEdit() end end, icon = "object" },
			{ "Edit Mode", "Tab", function() if not api.state().editing then api.toggleEdit() end end, icon = "mesh" },
		}, b)
	end, "regular")
	corner(mode, 4)
	local mi = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(22, 20) }, mode)
	self.modeIcon = icon(mi, "object")
	self.modeBtn = mode
	self:tip(mode, "Interaction Mode", "Sets the object interaction mode", "Tab")
	-- select mode buttons (edit mode, in the header like Blender 4/5)
	local grp = make("Frame", { LayoutOrder = nx(), BackgroundTransparency = 1, Size = UDim2.fromOffset(84, 20) }, left)
	hlist(grp, 0)
	make("UIPadding", { PaddingLeft = UDim.new(0, 4) }, grp)
	self.selGroup, self.selBtns = grp, {}
	for i, m in ipairs({ "vert", "edge", "face" }) do
		local b = self:btn(grp, { LayoutOrder = i, Size = UDim2.fromOffset(26, 20), BackgroundColor3 = T.regular }, function() api.setMode(m) end, "toggle")
		corner(b, 3)
		icon(b, m)
		self:tip(b, ({ vert = "Vertex", edge = "Edge", face = "Face" })[m], ({ vert = "Vertex select mode", edge = "Edge select mode", face = "Face select mode" })[m], ({ vert = "1", edge = "2", face = "3" })[m])
		self.selBtns[m] = b
	end
	local function pd(text, items)
		local b = self:btn(left, { LayoutOrder = nx(), Size = UDim2.fromOffset(#text * 7 + 14, 20), Text = text, TextColor3 = rgb(0xd9d9d9) }, function(btn) self:openMenu(items(), btn) end)
		corner(b, 4)
		return b
	end
	pd("View", function() return self:viewMenu() end)
	pd("Select", function() return self:selectMenu() end)
	pd("Add", function() return self:addMeshItems() end)
	self.objMenuBtn = pd("Object", function() return api.state().editing and self:meshMenu() or self:objectMenu() end)
	self.vertMenuBtn = pd("Vertex", function() return self:vertexMenu() end)
	self.edgeMenuBtn = pd("Edge", function() return self:edgeMenu() end)
	self.faceMenuBtn = pd("Face", function() return self:faceMenu() end)
	-- right side: X-ray + shading
	local right = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromOffset(140, HDR_H) }, hdr)
	hlist(right, 1, Enum.HorizontalAlignment.Right)
	self.xrayBtn = self:btn(right, { LayoutOrder = 1, Size = UDim2.fromOffset(26, 20), BackgroundColor3 = T.regular }, function() api.toggleXray() end, "toggle")
	corner(self.xrayBtn, 4) icon(self.xrayBtn, "xray")
	self:tip(self.xrayBtn, "Toggle X-Ray", "Transparent scene display. Allow selecting through items", "Alt Z")
	make("Frame", { LayoutOrder = 2, BackgroundTransparency = 1, Size = UDim2.fromOffset(8, 1) }, right)
	self.shadeBtns = {}
	for i, s in ipairs({ { "wire", "Wireframe", "Display the object as wire edges" }, { "solid", "Solid", "Display in solid mode" } }) do
		local b = self:btn(right, { LayoutOrder = 2 + i, Size = UDim2.fromOffset(26, 20), BackgroundColor3 = T.regular }, function() api.setShading(s[1]) end, "toggle")
		corner(b, 4) icon(b, s[1])
		self:tip(b, s[2], s[3], "Shift Z")
		self.shadeBtns[s[1]] = b
	end
	-- operator header (shows over the header while G / R / S / inset / loop cut run, like Blender)
	self.opHeader = make("Frame", { Visible = false, BackgroundColor3 = T.header, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, HDR_H), ZIndex = 6 }, area)
	self.opText = label(self.opHeader, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), ZIndex = 6, TextColor3 = T.text })

	-- the canvas (View.lua puts the ViewportFrame in here)
	local canvas = make("Frame", { Name = "Canvas", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, HDR_H), Size = UDim2.new(1, 0, 1, -HDR_H), ClipsDescendants = true }, area)
	self.canvas = canvas
	self.overlay = make("Frame", { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2 }, canvas)
	local ov = self.overlay
	-- info text (top left)
	self.info = label(ov, { ZIndex = 3, Position = UDim2.fromOffset(56, 8), Size = UDim2.fromOffset(420, 110), TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, RichText = true, TextStrokeTransparency = 0.75, TextStrokeColor3 = Color3.new(0, 0, 0) })
	-- tool strip (left), from space_toolsystem_toolbar.py
	local tb = make("Frame", { Name = "Toolbar", ZIndex = 3, Position = UDim2.fromOffset(6, 8), Size = UDim2.fromOffset(40, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.header, BackgroundTransparency = 0.15, BorderSizePixel = 0 }, ov)
	corner(tb, 6)
	vlist(tb, 2).HorizontalAlignment = Enum.HorizontalAlignment.Center
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, tb)
	self.toolbarFrame = tb
	self.toolBtns = {}
	local TOOLS = {
		{ "Select", "select", "Select Box", "Select items using box selection", "W", "both" },
		"-",
		{ "Move", "move", "Move", "Move selected items", "G", "both" },
		{ "Rotate", "rotate", "Rotate", "Rotate selected items", "R", "both" },
		{ "Scale", "scale", "Scale", "Scale (resize) selected items", "S", "both" },
		"-",
		{ "AddCube", "cube", "Add Cube", "Add cube to mesh interactively", "", "both" },
		"=",
		{ "Extrude", "extrude", "Extrude Region", "Extrude region together along the average normal", "E", "edit" },
		{ "Inset", "inset", "Inset Faces", "Inset new faces into selected faces", "I", "edit" },
		{ "LoopCut", "loopcut", "Loop Cut", "Add a new loop between existing loops", "Ctrl R", "edit" },
	}
	self.toolSeps = {}
	for i, t in ipairs(TOOLS) do
		if t == "-" or t == "=" then
			local s = make("Frame", { LayoutOrder = i, ZIndex = 3, Size = UDim2.fromOffset(26, 1), BackgroundColor3 = rgb(0x4a4a4a), BorderSizePixel = 0 }, tb)
			if t == "=" then self.toolSeps[#self.toolSeps + 1] = s end
		else
			local b = self:btn(tb, { LayoutOrder = i, ZIndex = 3, Size = UDim2.fromOffset(32, 32), BackgroundColor3 = T.toolItem }, function()
				if t[1] == "AddCube" then api.add("Cube") elseif t[1] ~= "Select" then api.tool(t[1]) end
			end, "tool")
			corner(b, 5)
			local ic = icon(b, t[2], nil, 18)
			ic.ZIndex = 3
			b:SetAttribute("rbTipRight", true)
			self:tip(b, t[3], t[4], t[5])
			self.toolBtns[t[1]] = { b = b, scope = t[6] }
		end
	end
	-- navigation gizmo (top right) + zoom / pan / frame buttons
	local gz = make("Frame", { Name = "Gizmo", ZIndex = 3, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(90, 90), BackgroundColor3 = T.white, BackgroundTransparency = 1 }, ov)
	corner(gz, 99)
	self.gizmo = gz
	local gzBtn = make("TextButton", { ZIndex = 3, BackgroundTransparency = 1, Text = "", Size = UDim2.fromScale(1, 1), AutoButtonColor = false }, gz)
	gzBtn.MouseEnter:Connect(function() gz.BackgroundTransparency = 0.88 end)
	gzBtn.MouseLeave:Connect(function() gz.BackgroundTransparency = 1 end)
	gzBtn.MouseButton1Down:Connect(function() self:startDrag("orbit") end)
	self.gzLines, self.gzBalls = {}, {}
	for _, a in ipairs({ { "X", T.xaxis }, { "Y", T.yaxis }, { "Z", T.zaxis } }) do
		self.gzLines[a[1]] = make("Frame", { ZIndex = 4, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = a[2], BorderSizePixel = 0, Size = UDim2.fromOffset(10, 2) }, gz)
		for _, sgn in ipairs({ 1, -1 }) do
			local key = (sgn > 0 and "+" or "-") .. a[1]
			local ball = make("TextButton", { ZIndex = 5, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(sgn > 0 and 18 or 15, sgn > 0 and 18 or 15), BackgroundColor3 = a[2],
				BackgroundTransparency = sgn > 0 and 0 or 0.55, BorderSizePixel = 0, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(0, 0, 0), Text = sgn > 0 and a[1] or "" }, gz)
			corner(ball, 99)
			if sgn < 0 then stroke(ball, a[2], 1.5) end
			ball.MouseButton1Down:Connect(function() self:startDrag("orbit", key) end)
			ball.MouseEnter:Connect(function() gz.BackgroundTransparency = 0.88 ball.TextColor3 = T.white end)
			ball.MouseLeave:Connect(function() ball.TextColor3 = Color3.new(0, 0, 0) end)
			self.gzBalls[key] = { b = ball, axis = a[1], sgn = sgn }
		end
	end
	local nav = make("Frame", { Name = "Nav", ZIndex = 3, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -41, 0, 104), Size = UDim2.fromOffset(28, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, ov)
	vlist(nav, 4)
	self.navFrame = nav
	for i, k in ipairs({ { "zoom", "Zoom", "Zoom in and out of the view (drag)", "Ctrl MMB / Wheel" }, { "hand", "Move", "Pan the view (drag)", "Shift MMB" }, { "frame", "Frame All", "View all objects in the scene", "Home" } }) do
		local b = make("TextButton", { LayoutOrder = i, ZIndex = 3, Size = UDim2.fromOffset(28, 28), BackgroundColor3 = T.header, BackgroundTransparency = 0.3, BorderSizePixel = 0, AutoButtonColor = false, Text = "" }, nav)
		corner(b, 99)
		local ic = icon(b, k[1])
		ic.ZIndex = 3
		b.MouseEnter:Connect(function() b.BackgroundTransparency = 0 end)
		b.MouseLeave:Connect(function() b.BackgroundTransparency = 0.3 end)
		b:SetAttribute("rbTipRight", false)
		self:tip(b, k[2], k[3], k[4])
		if k[1] == "frame" then b.Activated:Connect(function() self:safe(function() api.frameAll() end) end)
		else b.MouseButton1Down:Connect(function() self:startDrag(k[1] == "zoom" and "zoom" or "pan") end) end
	end
	-- N sidebar (Item), hidden by default like Blender
	local sb = make("Frame", { Name = "Sidebar", ZIndex = 3, Visible = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -50, 0, 8), Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.header, BackgroundTransparency = 0.05, BorderSizePixel = 0 }, ov)
	corner(sb, 6)
	vlist(sb, 3)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, sb)
	self.sidebarFrame = sb
	label(sb, { LayoutOrder = 1, ZIndex = 3, Size = UDim2.new(1, 0, 0, 18), Text = "Item", Font = FONT_B })
	self.sbTitle = label(sb, { LayoutOrder = 2, ZIndex = 3, Size = UDim2.new(1, 0, 0, 16), Text = "Median:", TextColor3 = T.textDim })
	for i, ax in ipairs({ "X", "Y", "Z" }) do self:numField(sb, 2 + i, ax, "n_loc" .. ax, function(s) return s.loc and s.loc[ax] end, function(v) api.setField("loc", ax, v) end, 3) end
end

-- ===== Outliner =====
function UI:buildOutliner()
	local col = make("Frame", { Name = "RightColumn", BackgroundColor3 = T.border, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, TOP_H), Size = UDim2.new(0, RIGHT_W + 2, 1, -TOP_H - STATUS_H) }, self.gui)
	self.rightCol = col
	local out = make("Frame", { Name = "Outliner", BackgroundColor3 = T.outliner, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -2, 0, 210) }, col)
	local hdr = make("Frame", { BackgroundColor3 = T.outliner, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, HDR_H) }, out)
	make("Frame", { BackgroundColor3 = T.border, BorderSizePixel = 0, Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1) }, hdr)
	local e = make("Frame", { BackgroundColor3 = T.textField, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(32, 20) }, hdr)
	corner(e, 4)
	local ei = icon(e, "collection")
	ei.Position = UDim2.fromScale(0.5, 0.5)
	local search = make("Frame", { BackgroundColor3 = T.textField, BorderSizePixel = 0, Position = UDim2.fromOffset(44, 3), Size = UDim2.new(1, -52, 0, 20) }, hdr)
	corner(search, 4)
	label(search, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -8, 1, 0), Text = "Search", TextColor3 = rgb(0x707070) })
	local list = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, HDR_H), Size = UDim2.new(1, 0, 1, -HDR_H), ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, out)
	vlist(list, 0)
	self.outList = list
	self.outliner = out
end

local function outRow(self, order, indent, ic, text, alt)
	local r = make("TextButton", { LayoutOrder = order, AutoButtonColor = false, BorderSizePixel = 0, Text = "", Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = T.white, BackgroundTransparency = alt and 0.985 or 1 }, self.outList)
	local icf = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8 + indent * 18, 2), Size = UDim2.fromOffset(16, 16) }, r)
	icon(icf, ic)
	local l = label(r, { Position = UDim2.fromOffset(30 + indent * 18, 0), Size = UDim2.new(1, -(60 + indent * 18), 1, 0), Text = text, TextColor3 = rgb(0xc3c3c3) })
	return r, l
end

function UI:refreshOutliner(s)
	local api = self.api
	local objs = api.outliner and api.outliner() or {}
	local sig = {}
	for _, o in ipairs(objs) do sig[#sig + 1] = o.name .. (o.selected and "*" or "") .. (o.active and "!" or "") .. (o.hidden and "h" or "") end
	local key = table.concat(sig, "|")
	if key == self.outKey then return end
	self.outKey = key
	for _, c in ipairs(self.outList:GetChildren()) do if c:IsA("GuiObject") then c.Parent = nil end end
	outRow(self, 1, 0, "scene", "Scene Collection", false)
	outRow(self, 2, 1, "collection", "Collection", true)
	for i, o in ipairs(objs) do
		local r, l = outRow(self, 2 + i, 2, "mesh", o.name, i % 2 == 0)
		if o.active then r.BackgroundColor3, r.BackgroundTransparency = T.outActive, 0 l.TextColor3 = T.activeObj
		elseif o.selected then r.BackgroundColor3, r.BackgroundTransparency = T.outSel, 0 l.TextColor3 = T.selObj end
		local data = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 2), Size = UDim2.fromOffset(16, 16) }, r)
		icon(data, "meshdata")
		local eye = make("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 2), Size = UDim2.fromOffset(18, 16), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, r)
		icon(eye, o.hidden and "eyeoff" or "eye", rgb(0xcccccc))
		eye.Activated:Connect(function() self:safe(function() api.toggleHidden(o.key) end) self.outKey = nil end)
		r.Activated:Connect(function()
			self:safe(function() api.selectObject(o.key, api.shiftDown and api.shiftDown()) end)
			self.outKey = nil
		end)
	end
end

-- ===== Properties editor (Object / Data / Material / Output tabs) =====
function UI:buildProperties()
	local col = self.rightCol
	local pr = make("Frame", { Name = "Properties", BackgroundColor3 = T.props, BorderSizePixel = 0, Position = UDim2.fromOffset(2, 214), Size = UDim2.new(1, -2, 1, -214) }, col)
	self.properties = pr
	local hdr = make("Frame", { BackgroundColor3 = T.header, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, HDR_H) }, pr)
	local search = make("Frame", { BackgroundColor3 = T.textField, BorderSizePixel = 0, Position = UDim2.fromOffset(44, 3), Size = UDim2.new(1, -52, 0, 20) }, hdr)
	corner(search, 4)
	label(search, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -8, 1, 0), Text = "Search", TextColor3 = rgb(0x707070) })
	-- tab column
	local tabs = make("Frame", { BackgroundColor3 = T.tabInner, BorderSizePixel = 0, Position = UDim2.fromOffset(0, HDR_H), Size = UDim2.new(0, 30, 1, -HDR_H) }, pr)
	vlist(tabs, 2)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 3) }, tabs)
	self.propTabs = {}
	for i, t in ipairs({ { "object", "object", "Object", "Object properties" }, { "data", "meshdata", "Data", "Mesh data" }, { "material", "material", "Material", "Material properties" }, { "export", "export", "Output", "Bake / export" } }) do
		local b = self:btn(tabs, { LayoutOrder = i, Size = UDim2.fromOffset(25, 25), BackgroundColor3 = T.tabInner }, function() self.propTab = t[1] self:buildPropContent() end, "tab")
		corner(b, 4)
		icon(b, t[2])
		b:SetAttribute("rbTipRight", true)
		self:tip(b, t[3], t[4])
		self.propTabs[t[1]] = b
	end
	self.propScroll = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(32, HDR_H), Size = UDim2.new(1, -34, 1, -HDR_H), ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, pr)
	vlist(self.propScroll, 6)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 12) }, self.propScroll)
	self:buildPropContent()
end

-- a number field like Blender's (label on the left, value box on the right). get(state) -> number or nil
function UI:numField(parent, order, text, id, get, set, z)
	local row = make("Frame", { LayoutOrder = order, ZIndex = z, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20) }, parent)
	label(row, { ZIndex = z, Size = UDim2.new(0.38, -6, 1, 0), Text = text, TextXAlignment = Enum.TextXAlignment.Right })
	local box = make("TextBox", { ZIndex = z, Position = UDim2.new(0.38, 0, 0, 0), Size = UDim2.new(0.62, 0, 1, 0), BackgroundColor3 = T.num, BorderSizePixel = 0, Font = FONT, TextSize = 12, TextColor3 = T.text, Text = "", ClearTextOnFocus = false }, row)
	corner(box, 4)
	box.FocusLost:Connect(function()
		local v = tonumber((box.Text:gsub("[^%d%.%-eE]", "")))
		if v then self:safe(function() set(v) end) end
		self.fieldsDirty = true
		self:refresh(true)
	end)
	self.fields[id] = { box = box, get = get, row = row }
	return row
end

-- collapsible panel; build(body) fills it
function UI:panel(order, key, title, build)
	local p = make("Frame", { LayoutOrder = order, BackgroundColor3 = T.panel, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, self.propScroll)
	corner(p, 5)
	vlist(p, 0)
	local open = self.panelsOpen[key]
	local h = make("TextButton", { LayoutOrder = 0, AutoButtonColor = false, BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 0, 24) }, p)
	label(h, { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(14, 24), Text = open and "v" or ">", TextColor3 = T.textDim, TextSize = 11 })
	label(h, { Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 1, 0), Text = title, TextColor3 = T.text })
	h.Activated:Connect(function() self.panelsOpen[key] = not self.panelsOpen[key] self:buildPropContent() end)
	if open then
		local body = make("Frame", { LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, p)
		vlist(body, 3)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingTop = UDim.new(0, 2) }, body)
		build(body)
	end
	return p
end

function UI:wideButton(parent, order, text, fn, col)
	local b = self:btn(parent, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = col or T.regular, Text = text }, fn, "regular")
	corner(b, 4)
	return b
end

local MATERIALS = { "SmoothPlastic", "Plastic", "Metal", "DiamondPlate", "Foil", "CorrodedMetal", "Wood", "WoodPlanks", "Concrete", "Brick", "Cobblestone",
	"Granite", "Marble", "Slate", "Pebble", "Sand", "Grass", "Ice", "Glass", "Neon", "Fabric" }
local SWATCHES = { 0xcccccc, 0xffffff, 0x6e6e6e, 0x1e1e1e, 0xc42b2b, 0xe8822e, 0xf2cd37, 0x5ba84a, 0x2b86c4, 0x6a4bc4, 0xd96ab8, 0x8a5a36 }

function UI:buildPropContent()
	local api = self.api
	for _, c in ipairs(self.propScroll:GetChildren()) do if c:IsA("GuiObject") then c.Parent = nil end end
	for id in pairs(self.fields) do if id:sub(1, 2) == "p_" then self.fields[id] = nil end end
	local s = api.state()
	local tab = self.propTab
	-- name row
	local top = make("Frame", { LayoutOrder = 0, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) }, self.propScroll)
	local icf = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 22) }, top)
	icon(icf, tab == "object" and "object" or tab == "data" and "meshdata" or tab == "material" and "material" or "export")
	if tab == "object" and s.objName then
		local nb = make("TextBox", { Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 1, 0), BackgroundColor3 = T.textField, BorderSizePixel = 0, Font = FONT, TextSize = 12, TextColor3 = T.text, Text = s.objName, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, top)
		corner(nb, 4)
		make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, nb)
		nb.FocusLost:Connect(function() if nb.Text ~= "" then self:safe(function() api.rename(nb.Text) end) end end)
	else
		label(top, { Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 1, 0), Text = s.objName or "No object selected", TextColor3 = s.objName and T.text or T.textDim })
	end
	if not s.objName and tab ~= "export" then return end
	if tab == "object" then
		self:panel(1, "transform", "Transform", function(b)
			for i, ax in ipairs({ "X", "Y", "Z" }) do self:numField(b, i, i == 1 and "Location X" or ax, "p_loc" .. ax, function(st) return st.objLoc and st.objLoc[ax] end, function(v) api.setProp("loc", ax, v) end) end
			make("Frame", { LayoutOrder = 4, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 4) }, b)
			for i, ax in ipairs({ "X", "Y", "Z" }) do self:numField(b, 4 + i, i == 1 and "Rotation X" or ax, "p_rot" .. ax, function(st) return st.objRot and st.objRot[ax] end, function(v) api.setProp("rot", ax, v) end) end
			local m = make("Frame", { LayoutOrder = 8, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20) }, b)
			label(m, { Size = UDim2.new(0.38, -6, 1, 0), Text = "Mode", TextXAlignment = Enum.TextXAlignment.Right })
			local mb = make("Frame", { Position = UDim2.new(0.38, 0, 0, 0), Size = UDim2.new(0.62, 0, 1, 0), BackgroundColor3 = T.textField, BorderSizePixel = 0 }, m)
			corner(mb, 4)
			label(mb, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -8, 1, 0), Text = "YXZ Euler (Roblox)" })
			make("Frame", { LayoutOrder = 9, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 4) }, b)
			for i, ax in ipairs({ "X", "Y", "Z" }) do self:numField(b, 9 + i, i == 1 and "Dimensions X" or ax, "p_dim" .. ax, function(st) return st.objDim and st.objDim[ax] end, function(v) api.setProp("dim", ax, v) end) end
		end)
		self:panel(2, "vis", "Visibility", function(b)
			self:wideButton(b, 1, s.hidden and "Show in Viewports" or "Hide in Viewports", function() api.toggleHidden(nil) self:buildPropContent() end)
		end)
	elseif tab == "data" then
		self:panel(1, "mesh", "Mesh", function(b)
			local st = s.meshInfo or {}
			for i, k in ipairs({ { "Vertices", st.v }, { "Edges", st.e }, { "Faces", st.f }, { "Triangles", st.t } }) do
				local r = make("Frame", { LayoutOrder = i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18) }, b)
				label(r, { Size = UDim2.new(0.5, -6, 1, 0), Text = k[1], TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.textDim })
				label(r, { Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), Text = tostring(k[2] or "-") })
			end
			self:wideButton(b, 10, "Merge by Distance", function() api.tool("MergeDist") end)
			self:wideButton(b, 11, "Flip Normals", function() api.tool("Flip") end)
			label(b, { LayoutOrder = 12, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim, Text = "These work in Edit Mode (Tab)." })
		end)
	elseif tab == "material" then
		self:panel(1, "surface", "Surface", function(b)
			label(b, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 16), Text = "Base Color", TextColor3 = T.textDim })
			local g = make("Frame", { LayoutOrder = 2, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) }, b)
			make("UIGridLayout", { CellSize = UDim2.fromOffset(34, 20), CellPadding = UDim2.fromOffset(4, 4) }, g)
			for _, hex in ipairs(SWATCHES) do
				local sw = make("TextButton", { AutoButtonColor = true, BackgroundColor3 = rgb(hex), BorderSizePixel = 0, Text = "" }, g)
				corner(sw, 3)
				if s.color and math.abs(s.color.R - rgb(hex).R) + math.abs(s.color.G - rgb(hex).G) + math.abs(s.color.B - rgb(hex).B) < 0.02 then stroke(sw, T.white, 2) end
				sw.Activated:Connect(function() self:safe(function() api.setLook("Color", rgb(hex)) end) self:buildPropContent() end)
			end
			local m = make("Frame", { LayoutOrder = 3, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) }, b)
			label(m, { Size = UDim2.new(0.38, -6, 1, 0), Text = "Material", TextXAlignment = Enum.TextXAlignment.Right })
			local mb = self:btn(m, { Position = UDim2.new(0.38, 0, 0, 0), Size = UDim2.new(0.62, 0, 1, 0), BackgroundColor3 = T.textField, Text = "  " .. (s.material or "") .. "", TextXAlignment = Enum.TextXAlignment.Left }, function(btn)
				local items = {}
				for _, name in ipairs(MATERIALS) do items[#items + 1] = { name, "", function() api.setLook("Material", name) self:buildPropContent() end, check = s.material == name } end
				self:openMenu(items, btn)
			end, "regular")
			corner(mb, 4)
		end)
	else
		self:panel(1, "keep", "Keep It", function(b)
			label(b, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim,
				Text = "The mesh is stored on the part and comes back when you edit it. Roblox doesn't save plugin-made meshes into the place yet, so to keep one for good:" })
			self:wideButton(b, 2, "Bake to Parts", function() api.tool("Bake") end, rgb(0x2f6f46))
			self:wideButton(b, 3, "Export .obj (for the 3D Importer)", function() api.tool("Export") end)
		end)
	end
	self.fieldsDirty = true
end

-- ===== status bar =====
function UI:buildStatus()
	local st = make("Frame", { Name = "Status", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, STATUS_H), BackgroundColor3 = T.status, BorderSizePixel = 0 }, self.gui)
	self.statusFrame = st
	self.hints = label(st, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.6, -10, 1, 0), TextColor3 = T.statusText, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd })
	self.reportLbl = label(st, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.4, -10, 1, 0), TextColor3 = T.statusText, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
end

-- ===== menus (Blender: back #181818, outline #242424, hover #4772b3) =====
function UI:closeMenu()
	if self.subOpen then self.subOpen.Parent = nil self.subOpen = nil end
	if self.menuOpen then self.menuOpen.Parent = nil self.menuOpen = nil end
	self.catcher.Visible = false
end

-- items: { {label, shortcut, fn, sub = fn() -> items, check = bool, icon = kind}, "-", {header = "Vertex"} }
-- at: a button (drops below it) or a Vector2 (pops up there)
function UI:openMenu(items, at, title, isSub)
	if not isSub then self:closeMenu() elseif self.subOpen then self.subOpen.Parent = nil self.subOpen = nil end
	self.tipFrame.Visible = false
	local x, y = 100, 30
	if typeof(at) == "Vector2" then x, y = at.X, at.Y
	elseif at and at.AbsolutePosition and at.AbsoluteSize then
		if isSub then x, y = at.AbsolutePosition.X + at.AbsoluteSize.X + 2, at.AbsolutePosition.Y - 4
		else x, y = at.AbsolutePosition.X, at.AbsolutePosition.Y + at.AbsoluteSize.Y + 2 end
	end
	local W = 230
	local m = make("Frame", { ZIndex = isSub and 24 or 20, BackgroundColor3 = T.menuBack, BorderSizePixel = 0, Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y }, nil)
	corner(stroke(m, T.menuOutline), 5)
	vlist(m, 0)
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, m)
	local z = m.ZIndex
	local h = 8
	if title then
		label(m, { LayoutOrder = 0, ZIndex = z + 1, Size = UDim2.new(1, 0, 0, 22), Text = "  " .. title, Font = FONT_B, TextColor3 = T.textDim })
		h += 22
	end
	for i, it in ipairs(items) do
		if it == "-" then
			local sep = make("Frame", { LayoutOrder = i, ZIndex = z + 1, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 7) }, m)
			make("Frame", { ZIndex = z + 1, Position = UDim2.new(0, 6, 0, 3), Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = rgb(0x2d2d2d), BorderSizePixel = 0 }, sep)
			h += 7
		elseif it.header then
			local r = make("Frame", { LayoutOrder = i, ZIndex = z + 1, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) }, m)
			if it.icon then local f = make("Frame", { ZIndex = z + 1, BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(16, 16) }, r) icon(f, it.icon, T.textDim) end
			label(r, { ZIndex = z + 1, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -26, 1, 0), Text = it.header, TextColor3 = T.textDim })
			h += 22
		else
			local enabled = it[3] ~= nil or it.sub ~= nil
			local b = make("TextButton", { LayoutOrder = i, ZIndex = z + 1, Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = T.blue, BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "" }, m)
			corner(b, 3)
			if it.icon or it.check ~= nil then
				local f = make("Frame", { ZIndex = z + 2, BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(16, 16) }, b)
				if it.icon then icon(f, it.icon, enabled and T.textMenu or T.textDim)
				elseif it.check then icon(f, "check", T.textMenu) end
			end
			label(b, { ZIndex = z + 2, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -36, 1, 0), Text = it[1], TextColor3 = enabled and T.textMenu or rgb(0x6a6a6a) })
			label(b, { ZIndex = z + 2, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -36, 1, 0), Text = it.sub and ">" or (it[2] or ""), TextColor3 = T.textDim, TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11 })
			if enabled then
				b.MouseEnter:Connect(function()
					b.BackgroundTransparency = 0
					if it.sub then self:openMenu(it.sub(), b, nil, true)
					elseif not isSub and self.subOpen then self.subOpen.Parent = nil self.subOpen = nil end
				end)
				b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
				b.Activated:Connect(function()
					if it.sub then self:openMenu(it.sub(), b, nil, true) return end
					self:closeMenu()
					self:safe(it[3])
				end)
			end
			h += 22
		end
	end
	local scr = self.gui.AbsoluteSize
	if scr and scr.X > 0 then
		x = math.clamp(x, 0, math.max(0, scr.X - W))
		y = math.clamp(y, 0, math.max(0, scr.Y - h))
	end
	m.Position = UDim2.fromOffset(x, y)
	m.Parent = self.gui
	if isSub then self.subOpen = m else self.menuOpen = m end
	self.catcher.Visible = true
	return m
end

-- ===== menu contents (from space_view3d.py, only what ROBLENDER can do) =====
function UI:addMeshItems()
	local api = self.api
	local items = {}
	for _, k in ipairs({ { "Plane", "Plane" }, { "Cube", "Cube" }, { "Circle", "Circle" }, { "UV Sphere", "Sphere" }, { "Cylinder", "Cylinder" }, "-", { "Grid", "Grid" } }) do
		if k == "-" then items[#items + 1] = "-" else items[#items + 1] = { k[1], "", function() api.add(k[2]) end, icon = "mesh" } end
	end
	return items
end
function UI:openAddMenu(at)
	local api = self.api
	if api.state().editing then return self:openMenu(self:addMeshItems(), at, "Add Mesh") end
	return self:openMenu({ { "Mesh", "", nil, sub = function() return self:addMeshItems() end, icon = "mesh" } }, at, "Add")
end
function UI:viewMenu()
	local api = self.api
	return {
		{ "Toolbar", "T", function() self:toggleToolbar() end, check = self.toolbar },
		{ "Sidebar", "N", function() self:toggleSidebar() end, check = self.sidebar },
		"-",
		{ "Frame Selected", "Numpad .", function() api.frameSelected() end },
		{ "Frame All", "Home", function() api.frameAll() end },
		"-",
		{ "Viewpoint", "", nil, sub = function() return {
			{ "Top", "Numpad 7", function() api.viewAxis("top") end },
			{ "Bottom", "Ctrl Numpad 7", function() api.viewAxis("bottom") end },
			"-",
			{ "Front", "Numpad 1", function() api.viewAxis("front") end },
			{ "Back", "Ctrl Numpad 1", function() api.viewAxis("back") end },
			"-",
			{ "Right", "Numpad 3", function() api.viewAxis("right") end },
			{ "Left", "Ctrl Numpad 3", function() api.viewAxis("left") end },
		} end },
		"-",
		{ "Use Studio's 3D View", "", function() api.setStudioView(not api.state().studioView) end, check = api.state().studioView },
	}
end
function UI:selectMenu()
	local api = self.api
	return {
		{ "All", "A", function() api.tool("SelectAll") end },
		{ "None", "Alt A", function() api.tool("SelectNone") end },
		{ "Invert", "Ctrl I", function() api.tool("Invert") end },
		"-",
		{ "Box Select", "B / Drag", nil },
		{ "Select Loops", "Alt Click", nil },
	}
end
function UI:objectMenu()
	local api = self.api
	return {
		{ "Transform", "", nil, sub = function() return {
			{ "Move", "G", function() api.tool("G") end }, { "Rotate", "R", function() api.tool("R") end }, { "Scale", "S", function() api.tool("S") end },
		} end },
		"-",
		{ "Duplicate Objects", "Shift D", function() api.tool("Duplicate") end },
		"-",
		{ "Bake to Parts", "", function() api.tool("Bake") end },
		{ "Export .obj", "", function() api.tool("Export") end },
		"-",
		{ "Delete", "X", function() api.tool("DeleteObjects") end, icon = nil },
	}
end
function UI:meshMenu()
	local api = self.api
	return {
		{ "Transform", "", nil, sub = function() return {
			{ "Move", "G", function() api.tool("G") end }, { "Rotate", "R", function() api.tool("R") end }, { "Scale", "S", function() api.tool("S") end },
		} end },
		"-",
		{ "Extrude", "E", function() api.tool("Extrude") end },
		"-",
		{ "Merge", "M", nil, sub = function() return {
			{ "At Center", "", function() api.tool("Merge") end },
			{ "By Distance", "", function() api.tool("MergeDist") end },
		} end },
		"-",
		{ "Normals", "", nil, sub = function() return { { "Flip", "", function() api.tool("Flip") end } } end },
		"-",
		{ "Delete", "X", function() api.tool("Delete") end },
	}
end
function UI:vertexMenu()
	local api = self.api
	return {
		{ "Extrude Vertices", "E", function() api.setMode("vert") api.tool("Extrude") end },
		"-",
		{ "New Edge/Face from Vertices", "F", function() api.tool("Fill") end },
		"-",
		{ "Merge at Center", "M", function() api.tool("Merge") end },
	}
end
function UI:edgeMenu()
	local api = self.api
	return {
		{ "Extrude Edges", "E", function() api.setMode("edge") api.tool("Extrude") end },
		"-",
		{ "Subdivide", "", function() api.tool("Subdivide") end },
		"-",
		{ "Loop Cut and Slide", "Ctrl R", function() api.tool("LoopCut") end },
	}
end
function UI:faceMenu()
	local api = self.api
	return {
		{ "Extrude Faces", "E", function() api.setMode("face") api.tool("Extrude") end },
		"-",
		{ "Inset Faces", "I", function() api.tool("Inset") end },
		"-",
		{ "Fill", "F", function() api.tool("Fill") end },
		"-",
		{ "Subdivide", "", function() api.tool("Subdivide") end },
	}
end
-- right-click menus (VIEW3D_MT_edit_mesh_context_menu / VIEW3D_MT_object_context_menu)
function UI:openContextMenu(at)
	local api = self.api
	local s = api.state()
	if s.editing then
		local items = { { "Add", "", nil, sub = function() return self:addMeshItems() end } }
		if s.mode == "vert" then
			items[#items + 1] = { header = "Vertex", icon = "vert" }
			items[#items + 1] = { "Subdivide", "", function() api.tool("Subdivide") end }
			items[#items + 1] = { "Extrude Vertices", "", function() api.tool("Extrude") end }
			items[#items + 1] = { "New Edge/Face from Vertices", "", function() api.tool("Fill") end }
			items[#items + 1] = { "Merge Vertices", "", function() api.tool("Merge") end }
			items[#items + 1] = "-"
			items[#items + 1] = { "Delete Vertices", "", function() api.tool("Delete") end }
		elseif s.mode == "edge" then
			items[#items + 1] = { header = "Edge", icon = "edge" }
			items[#items + 1] = { "Subdivide", "", function() api.tool("Subdivide") end }
			items[#items + 1] = { "Extrude Edges", "", function() api.tool("Extrude") end }
			items[#items + 1] = { "New Face from Edges", "", function() api.tool("Fill") end }
			items[#items + 1] = "-"
			items[#items + 1] = { "Delete Edges", "", function() api.tool("Delete") end }
		else
			items[#items + 1] = { header = "Face", icon = "face" }
			items[#items + 1] = { "Subdivide", "", function() api.tool("Subdivide") end }
			items[#items + 1] = { "Extrude Faces", "", function() api.tool("Extrude") end }
			items[#items + 1] = { "Inset Faces", "", function() api.tool("Inset") end }
			items[#items + 1] = "-"
			items[#items + 1] = { "Delete Faces", "", function() api.tool("Delete") end }
		end
		return self:openMenu(items, at)
	end
	return self:openMenu({
		{ "Add", "", nil, sub = function() return self:addMeshItems() end },
		"-",
		{ "Duplicate Objects", "Shift D", function() api.tool("Duplicate") end },
		"-",
		{ "Delete", "X", function() api.tool("DeleteObjects") end },
	}, at, "Object")
end
function UI:helpItems()
	local items = {}
	for _, k in ipairs({
		{ "Edit / Object Mode", "Tab" }, { "Vertex / Edge / Face", "1  2  3" }, { "Select / Extend / Box", "Click  Shift  Drag" },
		{ "Select Loop", "Alt Click" }, { "All / None / Invert", "A  Alt A  Ctrl I" }, { "Move / Rotate / Scale", "G  R  S" },
		{ "Axis / Snap / Value", "X Y Z  Ctrl  0-9" }, { "Extrude / Inset", "E  I" }, { "Loop Cut", "Ctrl R" },
		{ "Delete / Merge / Fill", "X  M  F" }, { "Add", "Shift A" }, { "Duplicate", "Shift D" },
		{ "Orbit / Pan / Zoom", "MMB / RMB, Shift, Wheel" }, { "Views", "Numpad 1 3 7, Home, ." },
		{ "Toolbar / Sidebar", "T  N" }, { "X-Ray", "Alt Z" }, { "Undo", "Ctrl Z" },
	}) do items[#items + 1] = { k[1], k[2], nil } end
	return items
end

-- ===== drags on the gizmo / zoom / hand buttons =====
function UI:startDrag(kind, ballKey)
	local api = self.api
	self.drag = { kind = kind, last = api.mousePos(), moved = 0, ball = ballKey }
end
function UI:step(mp)
	local d = self.drag
	if not d then return end
	local dx, dy = mp.X - d.last.X, mp.Y - d.last.Y
	d.last = mp
	d.moved += math.abs(dx) + math.abs(dy)
	if dx ~= 0 or dy ~= 0 then self.api.navDrag(d.kind, dx, dy) end
end
function UI:mouseUp()
	local d = self.drag
	self.drag = nil
	if d and d.ball and d.moved < 4 then
		local b = self.gzBalls[d.ball]
		local name = ({ ["+X"] = "right", ["-X"] = "left", ["+Y"] = "top", ["-Y"] = "bottom", ["+Z"] = "back", ["-Z"] = "front" })[d.ball]
		if b and name then self:safe(function() self.api.viewAxis(name) end) end
	end
end

-- ===== show / hide =====
function UI:toggleSidebar() self.sidebar = not self.sidebar self:refresh(true) end
function UI:toggleToolbar() self.toolbar = not self.toolbar self:refresh(true) end
function UI:setOn(on)
	self.on = on
	self.gui.Enabled = on
	if not on then self:closeMenu() self.tipFrame.Visible = false self.drag = nil end
	self:refresh(true)
end
function UI:setReport(s) self.report = s or "" if self.reportLbl then self.reportLbl.Text = self.report end end

local function inside(f, p)
	if not f or f.Visible == false then return false end
	local a, s = f.AbsolutePosition, f.AbsoluteSize
	return a ~= nil and s ~= nil and p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end
-- is a screen point in the 3D view itself (not on a panel / button / menu)?
function UI:inCanvas(p)
	if not self.on then return true end
	if self.menuOpen then return false end
	local c = self.canvas
	if c.AbsolutePosition and c.AbsoluteSize and not inside(c, p) then return false end
	for _, f in ipairs({ self.toolbarFrame, self.gizmo, self.navFrame, self.sidebarFrame, self.opHeader }) do
		if inside(f, p) then return false end
	end
	return true
end
function UI:overUI(p) return not self:inCanvas(p) end

local function fmt(x)
	local s = string.format("%.3f", x)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	if s == "-0" then s = "0" end
	return s
end

function UI:refresh(force)
	if not self.on and not force then return end
	local api = self.api
	local s = api.state()
	-- top bar tabs
	for _, t in pairs(self.tabs) do
		t.b:SetAttribute("rbOn", t.edit == s.editing)
		self.base[t.b] = (t.edit == s.editing) and T.tabSel or T.topbar
		if not self.hover[t.b] then t.b.BackgroundColor3 = self.base[t.b] end
		t.b.TextColor3 = (t.edit == s.editing) and T.white or T.textTab
	end
	-- 3D header
	self.modeBtn.Text = "      " .. (s.editing and "Edit Mode" or "Object Mode") .. "   v"
	if self.lastModeIcon ~= s.editing then
		self.lastModeIcon = s.editing
		local parent = self.modeIcon.Parent
		self.modeIcon.Parent = nil
		self.modeIcon = icon(parent, s.editing and "mesh" or "object")
	end
	self.selGroup.Visible = s.editing
	for m, b in pairs(self.selBtns) do self:setOnStyle(b, s.mode == m) end
	self.objMenuBtn.Text = s.editing and "Mesh" or "Object"
	self.objMenuBtn.Size = UDim2.fromOffset(s.editing and 42 or 56, 20)
	self.vertMenuBtn.Visible, self.edgeMenuBtn.Visible, self.faceMenuBtn.Visible = s.editing, s.editing, s.editing
	self:setOnStyle(self.xrayBtn, s.xray)
	for k, b in pairs(self.shadeBtns) do self:setOnStyle(b, (s.shading or "solid") == k) end
	self.opHeader.Visible = s.modal ~= nil
	if s.modal then self.opText.Text = s.modalText or "" end
	-- canvas: hide our 3D view when Studio's own is used
	self.toolbarFrame.Visible = self.toolbar
	local active = ({ G = "Move", R = "Rotate", S = "Scale", inset = "Inset", loopcut = "LoopCut" })[s.modal or ""] or (s.modal == nil and "Select" or nil)
	if s.modal == "G" and s.modalWhat == "Extrude" then active = "Extrude" end
	for key, t in pairs(self.toolBtns) do
		t.b.Visible = t.scope == "both" or s.editing
		self:setOnStyle(t.b, key == active, T.toolItem)
	end
	for _, sep in ipairs(self.toolSeps) do sep.Visible = s.editing end
	-- info text (Blender: "User Perspective" + "(1) Collection | Cube")
	local lines = { s.viewName or "User Perspective", "(1) Collection" .. (s.objName and (" | " .. s.objName) or "") }
	if s.editing and s.stats then
		local st = s.stats
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("Vertices  %d/%d"):format(st.vs, st.v)
		lines[#lines + 1] = ("Edges  %d/%d"):format(st.es, st.e)
		lines[#lines + 1] = ("Faces  %d/%d"):format(st.fs, st.f)
		lines[#lines + 1] = ("Triangles  %d"):format(st.t)
	end
	self.info.Text = table.concat(lines, "\n")
	self.info.Position = UDim2.fromOffset(self.toolbar and 56 or 12, 8)
	-- navigation gizmo
	local cf = s.camCF
	if cf then
		local R = 31
		local order = {}
		for key, g in pairs(self.gzBalls) do
			local axis = ({ X = Vector3.new(1, 0, 0), Y = Vector3.new(0, 1, 0), Z = Vector3.new(0, 0, 1) })[g.axis] * g.sgn
			local v = cf:VectorToObjectSpace(axis)
			g.b.Position = UDim2.fromOffset(45 + v.X * R, 45 - v.Y * R)
			order[#order + 1] = { g = g, z = v.Z }
			if g.sgn > 0 then
				local ln = self.gzLines[g.axis]
				local ex, ey = v.X * R, -v.Y * R
				ln.Position = UDim2.fromOffset(45 + ex / 2, 45 + ey / 2)
				ln.Size = UDim2.fromOffset(math.sqrt(ex * ex + ey * ey), 2)
				ln.Rotation = math.deg(math.atan2(ey, ex))
			end
		end
		table.sort(order, function(a, b) return a.z < b.z end)
		for i, o in ipairs(order) do o.g.b.ZIndex = 4 + i end
	end
	self.gizmo.Visible = not s.studioView
	self.navFrame.Visible = not s.studioView
	-- sidebar
	self.sidebarFrame.Visible = self.sidebar
	self.sbTitle.Text = s.editing and "Median:" or "Location:"
	-- outliner + properties
	self:refreshOutliner(s)
	for t, b in pairs(self.propTabs) do
		self.base[b] = (t == self.propTab) and T.tabSel or T.tabInner
		if not self.hover[b] then b.BackgroundColor3 = self.base[b] end
	end
	if s.objName ~= self.lastPropObj then self.lastPropObj = s.objName self:buildPropContent() end
	for _, f in pairs(self.fields) do
		if not f.box:IsFocused() then
			local v = f.get(s)
			f.box.Text = v and fmt(v) or "-"
		end
	end
	-- status bar (Blender 5 style mouse hints)
	if s.modal then
		self.hints.Text = "<b>LMB</b> Confirm      <b>RMB</b> Cancel      <b>X Y Z</b> Axis      <b>Ctrl</b> Snap      <b>0-9</b> Value"
	elseif s.editing then
		self.hints.Text = "<b>LMB</b> Select      <b>MMB</b> Rotate View      <b>RMB</b> Mesh Context Menu      <b>Tab</b> Object Mode"
	else
		self.hints.Text = "<b>LMB</b> Select      <b>MMB</b> Rotate View      <b>RMB</b> Object Context Menu      <b>Shift A</b> Add"
	end
	self.reportLbl.Text = (self.report ~= "" and (self.report .. "      ") or "") .. "ROBLENDER " .. self.version
end

function UI:destroy() self.gui.Parent = nil end

return UI
