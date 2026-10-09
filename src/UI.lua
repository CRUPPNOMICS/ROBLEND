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
	elseif kind == "cursor" then
		ring(box, 8, 8, 5, rgb(0xff4040), false) seg(box, 8, 0, 8, 4, col) seg(box, 8, 12, 8, 16, col) seg(box, 0, 8, 4, 8, col) seg(box, 12, 8, 16, 8, col)
	elseif kind == "transform" then
		ring(box, 8, 8, 6.5, col, false) seg(box, 8, 3, 8, 13, col) seg(box, 3, 8, 13, 8, col) rect(box, 11, 11, 4, 4, col, true)
	elseif kind == "annotate" then
		seg(box, 3, 13, 12, 4, col, 2) seg(box, 12, 4, 14, 2, rgb(0x00c8b4), 2) seg(box, 2, 15, 8, 15, rgb(0x00c8b4), 1.5)
	elseif kind == "measure" then
		seg(box, 2, 13, 13, 2, col, 4) seg(box, 5, 10, 6.5, 11.5, T.header, 1) seg(box, 8, 7, 9.5, 8.5, T.header, 1) seg(box, 11, 4, 12.5, 5.5, T.header, 1)
	elseif kind == "bevel" then
		seg(box, 2, 14, 2, 6, col) seg(box, 2, 6, 6, 2, rgb(0xffa030), 2) seg(box, 6, 2, 14, 2, col) seg(box, 2, 14, 14, 14, col) seg(box, 14, 14, 14, 2, col)
	elseif kind == "knife" then
		seg(box, 3, 13, 13, 3, col, 2) seg(box, 3, 13, 6, 13, col, 2) rect(box, 10, 1, 5, 4, col, true)
	elseif kind == "bisect" then
		rect(box, 2, 2, 12, 12, col, false) seg(box, 0, 15, 16, 1, rgb(0xffd800), 1.5)
	elseif kind == "polybuild" then
		seg(box, 2, 14, 8, 3, col) seg(box, 8, 3, 13, 14, col) seg(box, 2, 14, 13, 14, col) seg(box, 13, 2, 13, 8, rgb(0x80ff80), 1.5) seg(box, 10, 5, 16, 5, rgb(0x80ff80), 1.5)
	elseif kind == "spin" then
		ring(box, 8, 8, 6, col, false) rect(box, 5, 1, 6, 4, T.header, true) seg(box, 11, 2, 14, 4, col) ring(box, 8, 8, 1.5, rgb(0xff4040), true)
	elseif kind == "smooth" then
		seg(box, 1, 10, 5, 6, col) seg(box, 5, 6, 9, 10, col) seg(box, 9, 10, 13, 6, col) seg(box, 13, 6, 15, 8, col)
	elseif kind == "randomize" then
		ring(box, 3, 4, 1.5, col, true) ring(box, 11, 3, 1.5, col, true) ring(box, 7, 9, 1.5, col, true) ring(box, 13, 12, 1.5, col, true) ring(box, 3, 13, 1.5, col, true)
	elseif kind == "edgeslide" then
		seg(box, 2, 4, 14, 4, col) seg(box, 2, 12, 14, 12, col) seg(box, 4, 8, 12, 8, rgb(0xffa030), 2) seg(box, 12, 8, 10, 6, rgb(0xffa030)) seg(box, 12, 8, 10, 10, rgb(0xffa030))
	elseif kind == "vertexslide" then
		seg(box, 2, 12, 14, 12, col) ring(box, 6, 12, 2, rgb(0xffa030), true) seg(box, 8, 8, 13, 8, rgb(0xffa030)) seg(box, 13, 8, 11, 6, rgb(0xffa030))
	elseif kind == "shrinkfatten" then
		ring(box, 8, 8, 4, col, false) seg(box, 8, 4, 8, 0, col) seg(box, 8, 12, 8, 16, col) seg(box, 4, 8, 0, 8, col) seg(box, 12, 8, 16, 8, col)
	elseif kind == "pushpull" then
		ring(box, 8, 8, 2, col, true) seg(box, 2, 2, 5, 5, col) seg(box, 14, 2, 11, 5, col) seg(box, 2, 14, 5, 11, col) seg(box, 14, 14, 11, 11, col)
	elseif kind == "shear" then
		seg(box, 5, 3, 15, 3, col) seg(box, 1, 13, 11, 13, col) seg(box, 5, 3, 1, 13, col) seg(box, 15, 3, 11, 13, col)
	elseif kind == "tosphere" then
		rect(box, 1, 1, 14, 14, col, false) ring(box, 8, 8, 5, rgb(0xffa030), false)
	elseif kind == "rip" then
		seg(box, 2, 2, 8, 9, col) seg(box, 14, 2, 8, 9, col) seg(box, 8, 9, 8, 15, col) seg(box, 4, 2, 9, 7, rgb(0xffa030))
	elseif kind == "ripedge" then
		seg(box, 2, 14, 8, 8, col) seg(box, 8, 8, 14, 14, col) seg(box, 8, 8, 8, 2, rgb(0xffa030), 2)
	elseif kind == "boxset" then
		rect(box, 2, 2, 12, 12, col, true, 0.35) rect(box, 2, 2, 12, 12, col, false)
	elseif kind == "boxadd" then
		rect(box, 1, 1, 9, 9, col, true, 0.35) rect(box, 6, 6, 9, 9, col, true, 0.35)
	elseif kind == "boxsub" then
		rect(box, 1, 1, 9, 9, col, true, 0.35) rect(box, 6, 6, 9, 9, col, false)
	elseif kind == "boxxor" then
		rect(box, 1, 1, 9, 9, col, true, 0.35) rect(box, 6, 6, 9, 9, col, true, 0.35) rect(box, 6, 6, 4, 4, T.header or rgb(0x303030), true)
	elseif kind == "boxand" then
		rect(box, 1, 1, 9, 9, col, false) rect(box, 6, 6, 9, 9, col, false) rect(box, 6, 6, 4, 4, col, true)
	elseif kind == "wrench" then
		seg(box, 2.5, 13.5, 9, 7, T.iconModifier, 3) ring(box, 11, 5, 3.5, T.iconModifier, false) rect(box, 11, 1, 4, 4, T.props or rgb(0x303030), true)
	elseif kind == "automerge" then
		ring(box, 4, 8, 2.5, col, true) ring(box, 12, 8, 2.5, col, false) seg(box, 6.5, 8, 9.5, 8, col) seg(box, 9.5, 8, 8, 6.5, col) seg(box, 9.5, 8, 8, 9.5, col)
	elseif kind == "magnet" then
		seg(box, 4, 3, 4, 10, col, 3) seg(box, 12, 3, 12, 10, col, 3) ring(box, 8, 10, 4, col, false) rect(box, 2, 2, 4, 3, rgb(0xff4040), true) rect(box, 10, 2, 4, 3, rgb(0xff4040), true)
	elseif kind == "prop" then
		ring(box, 8, 8, 6.5, col, false) ring(box, 8, 8, 2, col, true)
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
		hover = {}, report = "", drag = nil, propTab = "object", panelsOpen = { transform = true, vis = false, mesh = true, surface = true, save = true, keep = false },
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
		{ "Save Mesh to Roblox", "", function() api.tool("Save") end },
		{ "Save All Meshes", "", function() api.tool("SaveAll") end },
		{ "Auto Save (leaving Edit Mode)", "", function() api.setAutoSave(not api.state().autoSave) end, check = api.state().autoSave },
		"-",
		{ "Bake to Parts", "", function() api.tool("Bake") end },
		{ "Export .obj", "", function() api.tool("Export") end },
		"-",
		{ "Close ROBLENDER", "", function() api.close() end },
	} end)
	menu("Edit", function() return {
		{ "Undo", "Ctrl Z", function() api.undo() end },
		{ "Redo", "Ctrl Y", function() api.redo() end },
		"-",
		(function()
			local st = api.state()
			return { "Repeat Last" .. (st.lastOp and (": " .. st.lastOp:gsub("(%l)(%u)", "%1 %2")) or ""), "Shift R", (st.editing and st.lastOp) and function() api.repeatLast() end or nil }
		end)(),
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
	pd("Select", function() return api.state().editing and self:selectMenuEdit() or self:selectMenu() end)
	pd("Add", function() return self:addMeshItems() end)
	self.objMenuBtn = pd("Object", function() return api.state().editing and self:meshMenu() or self:objectMenu() end)
	self.vertMenuBtn = pd("Vertex", function() return self:vertexMenu() end)
	self.edgeMenuBtn = pd("Edge", function() return self:edgeMenu() end)
	self.faceMenuBtn = pd("Face", function() return self:faceMenu() end)
	self.uvMenuBtn = pd("UV", function() return self:uvItems() end)
	-- right side: X-ray + shading
	local right = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromOffset(470, HDR_H) }, hdr)
	hlist(right, 1, Enum.HorizontalAlignment.Right)
	self.toggleBtns = {}
	for i, tg in ipairs({ { "snap", "magnet", "Snap", "Snap during transform (Ctrl does the opposite)", "" },
		{ "prop", "prop", "Proportional Editing", "Nearby geometry follows the selection (mouse wheel = size while moving)", "O" },
		{ "mirrorX", nil, "Mirror X", "Edit both sides of the mesh at once (its own X axis)", "" },
		{ "autoMerge", "automerge", "Auto Merge Vertices", "After moving, vertices that end up on top of each other are welded", "" } }) do
		local b = self:btn(right, { LayoutOrder = -20 + i * 2, Size = UDim2.fromOffset(26, 20), BackgroundColor3 = T.regular, Text = tg[2] and "" or "X", Font = FONT_B }, function() api.toggleEdit2(tg[1]) end, "toggle")
		corner(b, 4)
		if tg[2] then icon(b, tg[2]) end
		self:tip(b, tg[3], tg[4], tg[5])
		self.toggleBtns[tg[1]] = b
	end
	-- pivot point dropdown (Blender's . menu)
	self.pivotBtn = self:btn(right, { LayoutOrder = -25, Size = UDim2.fromOffset(44, 20), BackgroundColor3 = T.regular, Text = "Pivot v", TextSize = 11 }, function(b)
		self:openMenu(self:pivotItems(), b, "Pivot Point")
	end, "toggle")
	corner(self.pivotBtn, 4)
	self:tip(self.pivotBtn, "Transform Pivot Point", "What Rotate and Scale turn round: Median Point, 3D Cursor or Individual Origins", ".")
	-- snap target dropdown (just after the snap button)
	self.snapTargetBtn = self:btn(right, { LayoutOrder = -20 + 1 * 2 + 1, Size = UDim2.fromOffset(16, 20), BackgroundColor3 = T.regular, Text = "v", TextSize = 10 }, function(b)
		local st = api.state()
		local items = { { header = "Snap To" } }
		for _, n in ipairs({ "Increment", "Vertex", "Face" }) do items[#items + 1] = { n, "", function() api.setSnapTarget(n) end, check = st.snapTarget == n } end
		self:openMenu(items, b)
	end, "toggle")
	corner(self.snapTargetBtn, 4)
	self:tip(self.snapTargetBtn, "Snap To", "Increment (whole studs), Vertex or Face. Shift Tab turns snapping on / off")
	-- proportional falloff dropdown (just after the proportional button)
	self.falloffBtn = self:btn(right, { LayoutOrder = -20 + 2 * 2 + 1, Size = UDim2.fromOffset(16, 20), BackgroundColor3 = T.regular, Text = "v", TextSize = 10 }, function(b)
		local st = api.state()
		local items = { { header = "Proportional Falloff" } }
		for _, n in ipairs(api.falloffs) do items[#items + 1] = { n, "", function() api.setFalloff(n) end, check = st.propFalloff == n } end
		self:openMenu(items, b)
	end, "toggle")
	corner(self.falloffBtn, 4)
	self:tip(self.falloffBtn, "Proportional Editing Falloff", "How nearby geometry follows: Smooth, Sphere, Root, Sharp, Linear, Constant...")
	-- Select Box modes (the tool header in Blender): Set, Extend, Subtract, Difference, Intersect
	self.boxModeBtns = {}
	for i, bm in ipairs({ { "set", "boxset", "Set", "Set a new selection" }, { "add", "boxadd", "Extend", "Extend the existing selection (Shift)" },
		{ "sub", "boxsub", "Subtract", "Subtract from the existing selection (Ctrl)" }, { "xor", "boxxor", "Difference", "Invert the existing selection" },
		{ "and", "boxand", "Intersect", "Intersect the existing selection" } }) do
		local b = self:btn(right, { LayoutOrder = -40 + i, Size = UDim2.fromOffset(22, 20), BackgroundColor3 = T.regular }, function() api.setBoxMode(bm[1]) end, "toggle")
		corner(b, 4)
		icon(b, bm[2])
		self:tip(b, bm[3], bm[4])
		self.boxModeBtns[bm[1]] = b
	end
	make("Frame", { LayoutOrder = -30, BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 1) }, right)
	make("Frame", { LayoutOrder = -5, BackgroundTransparency = 1, Size = UDim2.fromOffset(8, 1) }, right)
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
	-- from space_toolsystem_toolbar.py (VIEW3D_PT_tools_active, object + edit mesh); a list = a flyout group
	local TOOLS = {
		{ { "select", "select", "Select Box", "Select items using box selection", "W" },
			{ "circle", "select", "Select Circle", "Select items using circle selection (drag to paint, wheel = size)", "C" } },
		{ { "cursor", "cursor", "Cursor", "Set the cursor location (also Shift Right Click)", "Shift RMB" } },
		"-",
		{ { "move", "move", "Move", "Move selected items (drag on them)", "G" } },
		{ { "rotate", "rotate", "Rotate", "Rotate selected items", "R" } },
		{ { "scale", "scale", "Scale", "Scale (resize) selected items", "S" } },
		{ { "transform", "transform", "Transform", "Supports any combination of grab, rotate, and scale at once", "" } },
		"-",
		{ { "annotate", "annotate", "Annotate", "Draw free-hand annotation", "" } },
		{ { "measure", "measure", "Measure", "Measure distance and angles", "" } },
		"-",
		{ { "addcube", "cube", "Add Cube", "Add cube to mesh interactively", "" } },
		"=",
		{ { "extrude", "extrude", "Extrude Region", "Extrude region together along the average normal", "E" },
			{ "extrudeNormals", "extrude", "Extrude Along Normals", "Extrude region together along local normals", "Alt E" },
			{ "extrudeIndividual", "extrude", "Extrude Individual", "Extrude individual elements along their normals", "Alt E" } },
		{ { "inset", "inset", "Inset Faces", "Inset new faces into selected faces", "I" } },
		{ { "bevel", "bevel", "Bevel", "Cut into selected items at an angle to create bevel or chamfer", "Ctrl B" } },
		{ { "loopcut", "loopcut", "Loop Cut", "Add a new loop between existing loops", "Ctrl R" } },
		{ { "knife", "knife", "Knife", "Cut new topology (click points, Enter to cut)", "K" },
			{ "bisect", "bisect", "Bisect", "Cut geometry along a plane (click-drag to define plane)", "" } },
		{ { "polybuild", "polybuild", "Poly Build", "Ctrl click: extrude to the mouse, Shift click: delete, drag: move a vert", "" } },
		{ { "spin", "spin", "Spin", "Extrude around the 3D cursor (drag round)", "" } },
		{ { "smooth", "smooth", "Smooth", "Flatten angles of selected vertices", "" },
			{ "randomize", "randomize", "Randomize", "Randomize vertices", "" } },
		{ { "edgeslide", "edgeslide", "Edge Slide", "Slide edge along a face", "G G" },
			{ "vertexslide", "vertexslide", "Vertex Slide", "Slide a vertex along a mesh", "" } },
		{ { "shrinkfatten", "shrinkfatten", "Shrink/Fatten", "Shrink/fatten selected vertices along normals", "Alt S" },
			{ "pushpull", "pushpull", "Push/Pull", "Push/Pull selected items", "" } },
		{ { "shear", "shear", "Shear", "Shear selected items along the horizontal screen axis", "Shift Ctrl Alt S" },
			{ "tosphere", "tosphere", "To Sphere", "Move selected items outward in a spherical shape around the selected center", "Shift Alt S" } },
		{ { "rip", "rip", "Rip Region", "Disconnect vertex or edges from connected geometry", "V" },
			{ "ripedge", "ripedge", "Rip Edge", "Extend vertices along the edge closest to the cursor", "Alt D" } },
	}
	local EDIT_ONLY = { extrude = true, inset = true, bevel = true, loopcut = true, knife = true, polybuild = true, spin = true, smooth = true, edgeslide = true, shrinkfatten = true, shear = true, rip = true }
	self.toolSeps = {}
	self.toolGroups = {}
	local editSep = false
	for i, g in ipairs(TOOLS) do
		if g == "-" or g == "=" then
			local sp = make("Frame", { LayoutOrder = i, ZIndex = 3, Size = UDim2.fromOffset(24, 1), BackgroundColor3 = rgb(0x4a4a4a), BorderSizePixel = 0 }, tb)
			if g == "=" then editSep = true end
			if editSep then self.toolSeps[#self.toolSeps + 1] = sp end
		else
			local grp = { list = g, current = 1, edit = EDIT_ONLY[g[1][1]] == true }
			local b = self:btn(tb, { LayoutOrder = i, ZIndex = 3, Size = UDim2.fromOffset(30, 30), BackgroundColor3 = T.toolItem }, function()
				api.setTool(grp.list[grp.current][1])
			end, "tool")
			corner(b, 5)
			grp.b = b
			local function setIcon()
				if grp.ic then grp.ic.Parent = nil end
				grp.ic = icon(b, grp.list[grp.current][2], nil, 17)
				grp.ic.ZIndex = 3
				for _, d in ipairs(grp.ic:GetDescendants()) do if d:IsA("GuiObject") then d.ZIndex = 3 end end
			end
			setIcon()
			b:SetAttribute("rbTipRight", true)
			local function tipNow()
				local t = grp.list[grp.current]
				return t[3], t[4] .. (#grp.list > 1 and "\n(right-click for more tools)" or ""), t[5]
			end
			b.MouseEnter:Connect(function()
				local a, d, k = tipNow()
				self.tipText.Text = "<b>" .. a .. "</b>\n" .. d .. (k ~= "" and ("\n<font color=\"#999999\">Shortcut: " .. k .. "</font>") or "")
				local p, sz = b.AbsolutePosition, b.AbsoluteSize
				if p and sz then self.tipFrame.Position = UDim2.fromOffset(p.X + sz.X + 10, p.Y) end
				self.tipFrame.Visible = true
			end)
			b.MouseLeave:Connect(function() self.tipFrame.Visible = false end)
			if #g > 1 then
				-- little corner triangle like Blender's, right-click opens the group
				make("Frame", { ZIndex = 4, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 1, -2), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = rgb(0xaaaaaa), BorderSizePixel = 0 }, b)
				b.MouseButton2Click:Connect(function()
					local items = {}
					for k, t in ipairs(grp.list) do
						items[#items + 1] = { t[3], t[5], function() grp.current = k setIcon() api.setTool(t[1]) end, icon = t[2], check = (k == grp.current) or nil }
					end
					self:openMenu(items, b, nil, false)
				end)
			end
			self.toolGroups[#self.toolGroups + 1] = grp
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
	for _, o in ipairs(objs) do sig[#sig + 1] = o.name .. (o.selected and "*" or "") .. (o.active and "!" or "") .. (o.hidden and "h" or "") .. (o.unsaved and "u" or "") end
	local key = table.concat(sig, "|")
	if key == self.outKey then return end
	self.outKey = key
	for _, c in ipairs(self.outList:GetChildren()) do if c:IsA("GuiObject") then c.Parent = nil end end
	outRow(self, 1, 0, "scene", "Scene Collection", false)
	outRow(self, 2, 1, "collection", "Collection", true)
	for i, o in ipairs(objs) do
		local r, l = outRow(self, 2 + i, 2, "mesh", o.name .. (o.unsaved and " *" or ""), i % 2 == 0)
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
	for i, t in ipairs({ { "object", "object", "Object", "Object properties" }, { "modifiers", "wrench", "Modifiers", "Modifier properties: non-destructive mirror, subdivision, array..." }, { "data", "meshdata", "Data", "Mesh data" }, { "material", "material", "Material", "Material properties" }, { "export", "export", "Output", "Bake / export" } }) do
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

-- ===== Properties > Modifiers (Blender's modifier stack panels) =====
-- a row of small toggle buttons: items = { {text, on, fn, tip}, ... }
function UI:toggleRow(parent, order, text, items)
	local row = make("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20) }, parent)
	label(row, { Size = UDim2.new(0.38, -6, 1, 0), Text = text, TextXAlignment = Enum.TextXAlignment.Right })
	local box = make("Frame", { Position = UDim2.new(0.38, 0, 0, 0), Size = UDim2.new(0.62, 0, 1, 0), BackgroundTransparency = 1 }, row)
	hlist(box, 1)
	for i, it in ipairs(items) do
		local b = self:btn(box, { LayoutOrder = i, Size = UDim2.new(1 / #items, -1, 1, 0), BackgroundColor3 = it[2] and T.blue or T.regular, Text = it[1] }, function() self:safe(it[3]) end, "regular")
		corner(b, 4)
		if it[4] then self:tip(b, it[1], it[4]) end
	end
	return row
end

local MOD_FIELDS = {
	mirror = function(self, b, i, m, api, num)
		self:toggleRow(b, 2, "Axis", {
			{ "X", m.x == true, function() api.modToggle(i, "x") end }, { "Y", m.y == true, function() api.modToggle(i, "y") end }, { "Z", m.z == true, function() api.modToggle(i, "z") end } })
		self:toggleRow(b, 3, "Merge", { { m.merge ~= false and "On" or "Off", m.merge ~= false, function() api.modToggle(i, "merge") end, "Weld the vertices that sit on the mirror plane" } })
		self:toggleRow(b, 5, "Bisect", { { m.bisect and "On" or "Off", m.bisect == true, function() api.modToggle(i, "bisect") end, "Cut off whatever crosses to the other side first" } })
		num(4, "Distance", "mergeDist", 0, 10)
	end,
	subsurf = function(self, b, i, m, api, num)
		num(2, "Levels Viewport", "levels", 0, 4, true)
		label(b, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim, Text = "Catmull-Clark. Each level = 4x the faces (Roblox limit: 20,000 triangles)." })
	end,
	solidify = function(self, b, i, m, api, num)
		num(2, "Thickness", "thickness", -100, 100)
		num(3, "Offset", "offset", -1, 1)
	end,
	array = function(self, b, i, m, api, num)
		num(2, "Count", "count", 1, 64, true)
		local ax = m.axis or "X"
		self:toggleRow(b, 3, "Axis", {
			{ "X", ax == "X", function() api.modSet(i, "axis", "X") end }, { "Y", ax == "Y", function() api.modSet(i, "axis", "Y") end }, { "Z", ax == "Z", function() api.modSet(i, "axis", "Z") end } })
		num(4, "Relative Offset", "relative", -100, 100)
		num(5, "Constant Offset", "constant", -10000, 10000)
		self:toggleRow(b, 6, "Merge", { { m.merge and "On" or "Off", m.merge == true, function() api.modToggle(i, "merge") end, "Weld the copies where they touch" } })
	end,
	bevel = function(self, b, i, m, api, num)
		num(2, "Amount", "amount", 0, 100)
		num(3, "Segments", "segments", 1, 32, true)
		num(4, "Angle", "angle", 0, 180)
	end,
	wireframe = function(self, b, i, m, api, num)
		num(2, "Thickness", "thickness", 0.001, 100)
	end,
	weld = function(self, b, i, m, api, num)
		num(2, "Distance", "distance", 0, 100)
	end,
	triangulate = function(self, b)
		label(b, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextColor3 = T.textDim, Text = "Splits every face into triangles." })
	end,
	decimate = function(self, b, i, m, api, num)
		self:toggleRow(b, 2, "Mode", { { "Planar", true, function() end, "Joins faces that are flatter than the angle limit" } })
		num(3, "Angle Limit", "angle", 0, 180)
	end,
	screw = function(self, b, i, m, api, num)
		num(2, "Angle", "angle", -3600, 3600)
		num(3, "Screw", "screw", -1000, 1000)
		num(4, "Steps Viewport", "steps", 1, 256, true)
		local ax = m.axis or "Y"
		self:toggleRow(b, 5, "Axis", {
			{ "X", ax == "X", function() api.modSet(i, "axis", "X") end }, { "Y", ax == "Y", function() api.modSet(i, "axis", "Y") end }, { "Z", ax == "Z", function() api.modSet(i, "axis", "Z") end } })
		label(b, { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim, Text = "Spins the mesh's open edges (a profile line) round the axis through the origin." })
	end,
	simpledeform = function(self, b, i, m, api, num)
		local me = m.method or "Twist"
		self:toggleRow(b, 2, "Method", {
			{ "Twist", me == "Twist", function() api.modSet(i, "method", "Twist") end }, { "Bend", me == "Bend", function() api.modSet(i, "method", "Bend") end },
			{ "Taper", me == "Taper", function() api.modSet(i, "method", "Taper") end }, { "Stretch", me == "Stretch", function() api.modSet(i, "method", "Stretch") end } })
		if me == "Twist" or me == "Bend" then num(3, "Angle", "angle", -3600, 3600) else num(3, "Factor", "factor", -10, 10) end
		local ax = m.axis or "Y"
		self:toggleRow(b, 4, "Axis", {
			{ "X", ax == "X", function() api.modSet(i, "axis", "X") end }, { "Y", ax == "Y", function() api.modSet(i, "axis", "Y") end }, { "Z", ax == "Z", function() api.modSet(i, "axis", "Z") end } })
	end,
	cast = function(self, b, i, m, api, num)
		self:toggleRow(b, 2, "Shape", { { "Sphere", true, function() end } })
		num(3, "Factor", "factor", -10, 10)
	end,
	wave = function(self, b, i, m, api, num)
		self:toggleRow(b, 2, "Motion", { { "Radial", m.radial ~= false, function() api.modSet(i, "radial", true) end }, { "Along X", m.radial == false, function() api.modSet(i, "radial", false) end } })
		num(3, "Height", "height", -100, 100)
		num(4, "Width", "width", 0.001, 1000)
		num(5, "Offset", "offset", -1000, 1000)
	end,
	displace = function(self, b, i, m, api, num)
		num(2, "Strength", "strength", -100, 100)
		num(3, "Texture Size", "size", 0.001, 1000)
		num(4, "Seed", "seed", -100000, 100000, true)
	end,
	smooth = function(self, b, i, m, api, num)
		num(2, "Factor", "factor", -2, 2)
		num(3, "Repeat", "repeat", 0, 50, true)
	end,
}

function UI:modifierItems()
	local api = self.api
	local items, group = {}, nil
	for _, ty in ipairs(api.modTypes or {}) do
		if ty.group ~= group then
			group = ty.group
			if #items > 0 then items[#items + 1] = "-" end
			items[#items + 1] = { header = group }
		end
		items[#items + 1] = { ty.name, "", function() api.modAdd(ty.id) self:buildPropContent() end, icon = "wrench" }
	end
	return items
end

function UI:buildModifiers(s)
	local api = self.api
	if not s.isRB then
		label(self.propScroll, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim, Text = "Modifiers work on ROBLENDER meshes. Add one with Shift A." })
		return
	end
	self:wideButton(self.propScroll, 1, "Add Modifier   v", function(btn) self:openMenu(self:modifierItems(), btn, "Add Modifier") end)
	local list = s.mods or {}
	if #list == 0 then
		label(self.propScroll, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim,
			Text = "No modifiers. They change how the mesh looks without touching your edits: Mirror one half, Subdivide to smooth it, Array to repeat it. Apply one to make it real geometry." })
	end
	for i, m in ipairs(list) do
		local key = "mod" .. i .. (m.type or "")
		if self.panelsOpen[key] == nil then self.panelsOpen[key] = true end
		self:panel(1 + i, key, (m.name or m.type or "?") .. (m.on == false and "   (off)" or ""), function(b)
			-- control row: show in viewport, show in edit mode, move up / down, apply, remove
			local ctl = make("Frame", { LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) }, b)
			hlist(ctl, 2)
			local function small(order, text, w, on, fn, tipT, tipD, ic)
				local bt = self:btn(ctl, { LayoutOrder = order, Size = UDim2.fromOffset(w, 20), BackgroundColor3 = on and T.blue or T.regular, Text = ic and "" or text }, function() self:safe(fn) end, "regular")
				corner(bt, 4)
				if ic then icon(bt, ic) end
				if tipT then self:tip(bt, tipT, tipD) end
				return bt
			end
			small(1, "", 24, m.on ~= false, function() api.modToggle(i, "on") end, "Realtime", "Show the modifier (in the view, the part and saves)", m.on ~= false and "eye" or "eyeoff")
			small(2, "", 24, m.edit ~= false, function() api.modToggle(i, "edit") end, "Edit Mode", "Show the modifier while in Edit Mode", "mesh")
			small(3, "^", 20, false, function() api.modMove(i, -1) end, "Move Up", "Run this modifier earlier")
			small(4, "v", 20, false, function() api.modMove(i, 1) end, "Move Down", "Run this modifier later")
			small(5, "Apply", 46, false, function() api.modApply(i) end, "Apply", "Make the modifier's result real geometry (Ctrl A)")
			small(6, "X", 22, false, function() api.modRemove(i) end, "Delete", "Remove the modifier")
			local function num(order, text, field, lo, hi, int)
				self:numField(b, order, text, "p_m" .. i .. field, function(st)
					local mm = st.mods and st.mods[i]
					return mm and tonumber(mm[field])
				end, function(v)
					v = math.clamp(v, lo, hi)
					if int then v = math.floor(v + 0.5) end
					api.modSet(i, field, v)
				end)
			end
			local f = MOD_FIELDS[m.type]
			if f then f(self, b, i, m, api, num) end
		end)
	end
end

function UI:buildPropContent()
	local api = self.api
	for _, c in ipairs(self.propScroll:GetChildren()) do if c:IsA("GuiObject") then c.Parent = nil end end
	for id in pairs(self.fields) do if id:sub(1, 2) == "p_" then self.fields[id] = nil end end
	local s = api.state()
	local tab = self.propTab
	-- name row
	local top = make("Frame", { LayoutOrder = 0, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) }, self.propScroll)
	local icf = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 22) }, top)
	icon(icf, tab == "object" and "object" or tab == "modifiers" and "wrench" or tab == "data" and "meshdata" or tab == "material" and "material" or "export")
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
	elseif tab == "modifiers" then
		self:buildModifiers(s)
	elseif tab == "data" then
		self:panel(1, "mesh", "Mesh", function(b)
			local st = s.meshInfo or {}
			for i, k in ipairs({ { "Vertices", st.v }, { "Edges", st.e }, { "Faces", st.f }, { "Triangles", st.t } }) do
				local r = make("Frame", { LayoutOrder = i, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18) }, b)
				label(r, { Size = UDim2.new(0.5, -6, 1, 0), Text = k[1], TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.textDim })
				label(r, { Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), Text = tostring(k[2] or "-") })
			end
			if s.mods and #s.mods > 0 and not s.editing then
				label(b, { LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextColor3 = T.textDim, Text = "Counts include the modifiers." })
			end
			self:wideButton(b, 10, "Merge by Distance", function() api.tool("MergeDist") end)
			self:wideButton(b, 11, "Flip Normals", function() api.tool("Flip") end)
			label(b, { LayoutOrder = 12, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim, Text = "These work in Edit Mode (Tab)." })
		end)
	elseif tab == "material" then
		if self.panelsOpen.texture == nil then self.panelsOpen.texture = true end
		self:panel(2, "texture", "Texture", function(b)
			local r = make("Frame", { LayoutOrder = 1, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) }, b)
			label(r, { Size = UDim2.new(0.38, -6, 1, 0), Text = "Image", TextXAlignment = Enum.TextXAlignment.Right })
			local tb = make("TextBox", { Name = "RB_Texture", Position = UDim2.new(0.38, 0, 0, 0), Size = UDim2.new(0.62, 0, 1, 0), BackgroundColor3 = T.textField, BorderSizePixel = 0, Font = FONT, TextSize = 11,
				TextColor3 = T.text, Text = s.texture or "", PlaceholderText = "rbxassetid://... or the number", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, r)
			corner(tb, 4)
			make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, tb)
			tb.FocusLost:Connect(function() self:safe(function() api.setTexture(tb.Text) end) self:buildPropContent() end)
			local cur = s.uv and s.uv.mode or ""
			local items = {}
			for _, m in ipairs({ { "box", "Box" }, { "boxfit", "Fit" }, { "cylinder", "Cyl" }, { "sphere", "Sph" }, { "top", "Top" } }) do
				items[#items + 1] = { m[2], cur == m[1], function() api.setUV(m[1]) end }
			end
			self:toggleRow(b, 2, "UV", items)
			if cur == "box" then
				self:numField(b, 3, "Tile Size", "p_uvscale", function(st) return st.uv and st.uv.scale end, function(v) api.setUV(nil, v) end)
			end
			label(b, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim,
				Text = "UVs are worked out from the shape every time it changes. Box = repeats every Tile Size studs, Fit = one image per side. Upload an image (Asset Manager) and paste its id." })
		end)
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
		self:panel(1, "save", "Save to Roblox", function(b)
			local txt
			if s.saving then txt = "Saving..."
			elseif s.saved then txt = "Saved as rbxassetid://" .. tostring(s.assetId) .. " - it stays in the place and publishes."
			elseif s.objName then txt = "Not saved yet. Saving uploads the mesh as a real Roblox Mesh asset."
			else txt = "Select a mesh." end
			label(b, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = s.saved and rgb(0x8bdc00) or T.textDim, Text = txt })
			self:wideButton(b, 2, "Save Mesh to Roblox", function() api.tool("Save") end, T.blue)
			self:wideButton(b, 3, "Save All Meshes", function() api.tool("SaveAll") end)
			self:wideButton(b, 4, (s.autoSave and "[x]" or "[  ]") .. "  Auto save when leaving Edit Mode", function() api.setAutoSave(not s.autoSave) self:buildPropContent() end, T.textField)
			label(b, { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.textDim,
				Text = "Needs Studio's beta \"CreateAssetAsync Luau API\" (File > Beta Features)." })
		end)
		self:panel(2, "keep", "Other Ways", function(b)
			self:wideButton(b, 1, "Bake to Parts", function() api.tool("Bake") end, rgb(0x2f6f46))
			self:wideButton(b, 2, "Export .obj (for the 3D Importer)", function() api.tool("Export") end)
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
	if self.searchFrame then self.searchFrame.Parent = nil self.searchFrame = nil end
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
	for _, k in ipairs({ { "Plane", "Plane" }, { "Cube", "Cube" }, { "Circle", "Circle" }, { "UV Sphere", "Sphere" }, { "Ico Sphere", "IcoSphere" }, { "Cylinder", "Cylinder" }, { "Cone", "Cone" }, { "Torus", "Torus" }, "-", { "Grid", "Grid" } }) do
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
		{ "Clear Annotations", "", function() api.tool("ClearAnnotations") end },
		{ "Frame All", "Home", function() api.frameAll() end },
		{ "Local View", "Numpad /", function() api.tool("LocalView") end },
		{ "Perspective/Orthographic", "Numpad 5", function() api.toggleOrtho() end, check = api.state().viewName ~= nil and api.state().viewName:find("Ortho") ~= nil },
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
		{ "Box Select", "Drag", nil },
	}
end
-- VIEW3D_MT_select_edit_mesh
function UI:selectMenuEdit()
	local api = self.api
	local t = function(n) return function() api.tool(n) end end
	return {
		{ "All", "A", t("SelectAll") }, { "None", "Alt A", t("SelectNone") }, { "Invert", "Ctrl I", t("Invert") },
		"-",
		{ "Box Select", "Drag", nil }, { "Circle Select", "C", t("CircleSelect") },
		{ "Select Mirror", "Shift Ctrl M", t("SelectMirror") },
		{ "Edge Rings", "Ctrl Alt Click", t("SelectRing") },
		"-",
		{ "Select Similar", "Shift G", nil, sub = function() return self:similarItems() end },
		"-",
		{ "Select Random", "", t("SelectRandom") }, { "Checker Deselect", "", t("Checker") },
		"-",
		{ "More/Less", "", nil, sub = function() return { { "More", "Ctrl +", t("SelectMore") }, { "Less", "Ctrl -", t("SelectLess") } } end },
		"-",
		{ "Select Linked", "", nil, sub = function() return { { "Linked", "Ctrl L", t("SelectLinked") }, { "Pick Linked", "L", t("PickLinked") } } end },
		{ "Select Loops", "", nil, sub = function() return { { "Edge Loops", "Alt Click", nil }, { "Edge Rings", "", t("SelectRing") } } end },
		"-",
		{ "Sharp Edges", "", t("SharpEdges") },
		"-",
		{ "Select All by Trait", "", nil, sub = function() return {
			{ "Non Manifold", "", t("NonManifold") }, { "Loose Geometry", "", t("Loose") }, { "Faces by Sides", "", t("FacesBySides") },
		} end },
	}
end
function UI:objectMenu()
	local api = self.api
	return {
		{ "Transform", "", nil, sub = function() return {
			{ "Move", "G", function() api.tool("G") end }, { "Rotate", "R", function() api.tool("R") end }, { "Scale", "S", function() api.tool("S") end },
		} end },
		{ "Snap", "Shift S", nil, sub = function() return self:snapItems() end },
		"-",
		{ "Duplicate Objects", "Shift D", function() api.tool("Duplicate") end },
		{ "Join", "Ctrl J", function() api.tool("Join") end },
		"-",
		{ "Set Origin", "", nil, sub = function() return {
			{ "Geometry to Origin", "", function() api.tool("GeometryToOrigin") end },
			{ "Origin to Geometry", "", function() api.tool("OriginToGeometry") end },
			{ "Origin to 3D Cursor", "", function() api.tool("OriginToCursor") end },
		} end },
		{ "Apply", "Ctrl A", nil, sub = function() return { { "Rotation", "", function() api.tool("ApplyRotation") end } } end },
		"-",
		{ "Show/Hide", "", nil, sub = function() return {
			{ "Show Hidden Objects", "Alt H", function() api.tool("RevealObj") end },
			{ "Hide Selected", "H", function() api.tool("HideSelected") end },
			{ "Hide Unselected", "Shift H", function() api.tool("HideUnselectedObj") end },
		} end },
		{ "Clear", "", nil, sub = function() return {
			{ "Location", "Alt G", function() api.tool("ClearLocation") end },
			{ "Rotation", "Alt R", function() api.tool("ClearRotation") end },
		} end },
		"-",
		{ "Shade Smooth", "", function() api.tool("ObjShadeSmooth") end },
		{ "Shade Auto Smooth", "", function() api.tool("ObjShadeAuto") end },
		{ "Shade Flat", "", function() api.tool("ObjShadeFlat") end },
		"-",
		{ "Subdivision", "", nil, sub = function()
			local items = {}
			for lv = 0, 4 do items[#items + 1] = { "Level " .. lv, "Ctrl " .. lv, function() api.subdivSet(lv) end } end
			return items
		end },
		"-",
		{ "Bake to Parts", "", function() api.tool("Bake") end },
		{ "Export .obj", "", function() api.tool("Export") end },
		"-",
		{ "Delete", "X", function() api.tool("DeleteObjects") end },
	}
end
function UI:pivotItems()
	local api = self.api
	local cur = api.state().pivot
	local items = {}
	for _, p in ipairs({ { "median", "Median Point" }, { "cursor", "3D Cursor" }, { "individual", "Individual Origins" } }) do
		items[#items + 1] = { p[2], "", function() api.setPivot(p[1]) end, check = cur == p[1] }
	end
	return items
end
function UI:uvItems()
	local api = self.api
	local s = api.state()
	local cur = s.uv and s.uv.mode
	local items = { { header = "Unwrap (follows your edits)" } }
	for _, m in ipairs(api.uvModes or {}) do items[#items + 1] = { m[2], "", function() api.setUV(m[1]) end, check = cur == m[1] } end
	items[#items + 1] = "-"
	items[#items + 1] = { "Clear UVs", "", function() api.setUV("") end }
	items[#items + 1] = { "Texture and tile size: Properties > Material", "", nil }
	return items
end
function UI:shadingItems()
	local api = self.api
	local s = api.state()
	return {
		{ "Wireframe", "Shift Z", function() api.setShading("wire") end, check = s.shading == "wire" },
		{ "Solid", "", function() api.setShading("solid") end, check = (s.shading or "solid") == "solid" },
		"-",
		{ "Toggle X-Ray", "Alt Z", function() api.toggleXray() end, check = s.xray },
	}
end
function UI:applyItems()
	return { { "Rotation", "", function() self.api.tool("ApplyRotation") end } }
end
function UI:originItems()
	local t = function(n) return function() self.api.tool(n) end end
	return { { "Geometry to Origin", "", t("GeometryToOrigin") }, { "Origin to Geometry", "", t("OriginToGeometry") }, { "Origin to 3D Cursor", "", t("OriginToCursor") } }
end
function UI:normalsItems()
	local t = function(n) return function() self.api.tool(n) end end
	return { { "Flip", "", t("Flip") }, { "Recalculate Outside", "Shift N", t("RecalcOutside") }, { "Recalculate Inside", "Shift Ctrl N", t("RecalcInside") } }
end
-- F3 (Blender's Menu Search): every menu item, filtered as you type; Enter runs the top one
function UI:searchItems()
	local s = self.api.state()
	local roots
	if s.editing then
		roots = { { "Mesh", self:meshMenu() }, { "Vertex", self:vertexMenu() }, { "Edge", self:edgeMenu() }, { "Face", self:faceMenu() },
			{ "Select", self:selectMenuEdit() }, { "Add", self:addMeshItems() }, { "View", self:viewMenu() } }
	else
		roots = { { "Object", self:objectMenu() }, { "Select", self:selectMenu() }, { "Add", self:addMeshItems() }, { "View", self:viewMenu() } }
	end
	local out, seen = {}, {}
	local function walk(prefix, items, depth)
		for _, it in ipairs(items or {}) do
			if type(it) == "table" and not it.header and it[1] then
				local lbl = prefix .. " > " .. it[1]
				if it.sub and depth < 3 then
					local ok, sub = pcall(it.sub)
					if ok then walk(lbl, sub, depth + 1) end
				elseif it[3] and not seen[lbl] then
					seen[lbl] = true
					out[#out + 1] = { label = lbl, key = it[2] or "", fn = it[3] }
				end
			end
		end
	end
	for _, r in ipairs(roots) do walk(r[1], r[2], 0) end
	return out
end
function UI:openSearch()
	self:closeMenu()
	local all = self:searchItems()
	local mp = self.api.mousePos()
	local W = 380
	local fr = make("Frame", { ZIndex = 40, BackgroundColor3 = T.menuBack, BorderSizePixel = 0, Position = UDim2.fromOffset(math.max(4, mp.X - W / 2), math.max(4, mp.Y - 14)), Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y }, self.gui)
	corner(stroke(fr, T.menuOutline), 5)
	vlist(fr, 0)
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, fr)
	local box = make("TextBox", { Name = "RB_Search", LayoutOrder = 0, ZIndex = 41, Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = T.textField, BorderSizePixel = 0, Font = FONT, TextSize = 12,
		TextColor3 = T.text, Text = "", PlaceholderText = "Search menus...  (Enter runs the top one)", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, fr)
	corner(box, 4)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, box)
	local rows, matches = {}, {}
	local function close() fr.Parent = nil if self.searchFrame == fr then self.searchFrame = nil end self.catcher.Visible = false end
	local function run(it) close() self:safe(it.fn) end
	local function refresh()
		for _, r in ipairs(rows) do r.Parent = nil end
		rows, matches = {}, {}
		local q = (box.Text or ""):lower()
		for _, it in ipairs(all) do
			local ok = true
			for word in q:gmatch("%S+") do if not it.label:lower():find(word, 1, true) then ok = false break end end
			if ok then matches[#matches + 1] = it end
			if #matches >= 14 then break end
		end
		for i, it in ipairs(matches) do
			local b = make("TextButton", { LayoutOrder = i, ZIndex = 41, Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = T.blue, BackgroundTransparency = i == 1 and 0.5 or 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "" }, fr)
			corner(b, 3)
			label(b, { ZIndex = 42, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -96, 1, 0), Text = it.label, TextColor3 = T.textMenu, TextTruncate = Enum.TextTruncate.AtEnd })
			label(b, { ZIndex = 42, Position = UDim2.new(1, -88, 0, 0), Size = UDim2.fromOffset(82, 22), Text = it.key, TextColor3 = T.textDim, TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11 })
			b.MouseEnter:Connect(function() b.BackgroundTransparency = 0 end)
			b.MouseLeave:Connect(function() b.BackgroundTransparency = i == 1 and 0.5 or 1 end)
			b.Activated:Connect(function() run(it) end)
			rows[#rows + 1] = b
		end
	end
	box:GetPropertyChangedSignal("Text"):Connect(refresh)
	box.FocusLost:Connect(function(enter)
		if not enter then return end
		refresh()
		if matches[1] then run(matches[1]) else close() end
	end)
	self.searchFrame = fr
	self.catcher.Visible = true
	refresh()
	pcall(function() box:CaptureFocus() end)
	return fr
end
function UI:similarItems()
	local items = {}
	for _, k in ipairs(self.api.similarList()) do items[#items + 1] = { k[2], "", function() self.api.selectSimilar(k[1]) end } end
	return items
end
function UI:separateItems()
	local t = function(n) return function() self.api.tool(n) end end
	return { { "Selection", "", t("Separate") }, { "By Loose Parts", "", t("SeparateLoose") } }
end
function UI:snapItems()
	local t = function(n) return function() self.api.tool(n) end end
	return {
		{ "Selection to Cursor", "", t("SelToCursor") }, { "Selection to Grid", "", t("SelToGrid") },
		"-",
		{ "Cursor to Selected", "", t("CursorToSel") }, { "Cursor to World Origin", "", t("CursorToOrigin") }, { "Cursor to Grid", "", t("CursorToGrid") },
	}
end
function UI:deleteItems()
	local t = function(n) return function() self.api.tool(n) end end
	return {
		{ "Vertices", "", t("DeleteVerts") }, { "Edges", "", t("DeleteEdges") }, { "Faces", "", t("DeleteFaces") },
		{ "Only Edges & Faces", "", t("DeleteEdgesFaces") }, { "Only Faces", "", t("DeleteOnlyFaces") },
		"-",
		{ "Dissolve Vertices", "", t("DissolveVerts") }, { "Dissolve Edges", "", t("DissolveEdges") }, { "Dissolve Faces", "", t("DissolveFaces") },
		"-",
		{ "Collapse Edges & Faces", "", t("EdgeCollapse") }, { "Edge Loops", "", t("DeleteEdgeLoops") },
	}
end
function UI:mergeItems()
	local t = function(n) return function() self.api.tool(n) end end
	return { { "At Center", "", t("MergeCenter") }, { "At Cursor", "", t("MergeCursor") }, { "Collapse", "", t("MergeCollapse") }, "-", { "By Distance", "", t("MergeDistance") } }
end
function UI:extrudeItems()
	local t = function(n) return function() self.api.tool(n) end end
	return { { "Extrude Faces", "", t("Extrude") }, { "Extrude Faces Along Normals", "", t("ExtrudeNormals") }, { "Extrude Individual Faces", "", t("ExtrudeIndividual") },
		"-", { "Extrude Edges", "", t("ExtrudeEdges") }, { "Extrude Vertices", "", t("ExtrudeVerts") } }
end
-- VIEW3D_MT_edit_mesh
function UI:meshMenu()
	local api = self.api
	local t = function(n) return function() api.tool(n) end end
	return {
		{ "Transform", "", nil, sub = function() return {
			{ "Move", "G", t("G") }, { "Rotate", "R", t("R") }, { "Scale", "S", t("S") }, "-",
			{ "To Sphere", "Shift Alt S", t("ToSphere") }, { "Shear", "Shift Ctrl Alt S", t("Shear") }, { "Push/Pull", "", t("PushPull") },
			{ "Shrink/Fatten", "Alt S", t("ShrinkFatten") }, "-", { "Randomize", "", t("Randomize") },
		} end },
		{ "Mirror", "", nil, sub = function() return { { "X Global", "", t("MirrorX") }, { "Y Global", "", t("MirrorY") }, { "Z Global", "", t("MirrorZ") } } end },
		{ "Snap", "Shift S", nil, sub = function() return self:snapItems() end },
		"-",
		{ "Duplicate", "Shift D", t("Duplicate") },
		{ "Extrude", "Alt E", nil, sub = function() return self:extrudeItems() end },
		"-",
		{ "Merge", "M", nil, sub = function() return self:mergeItems() end },
		{ "Split", "", nil, sub = function() return { { "Selection", "Y", t("Split") } } end },
		{ "Separate", "P", nil, sub = function() return self:separateItems() end },
		"-",
		{ "Bisect", "", function() api.setTool("bisect") end },
		{ "Knife Tool", "K", t("Knife") },
		{ "Convex Hull", "", t("ConvexHull") },
		"-",
		{ "Symmetrize", "", t("SymmetrizeX") },
		"-",
		{ "Normals", "", nil, sub = function() return {
			{ "Flip", "", t("Flip") }, { "Recalculate Outside", "Shift N", t("RecalcOutside") }, { "Recalculate Inside", "", t("RecalcInside") },
		} end },
		{ "Shading", "", nil, sub = function() return { { "Smooth Faces", "", t("ShadeSmooth") }, { "Flat Faces", "", t("ShadeFlat") }, { "Auto Smooth (30 degrees)", "", t("ShadeAutoSmooth") } } end },
		"-",
		{ "Show/Hide", "", nil, sub = function() return {
			{ "Reveal Hidden", "Alt H", t("Reveal") }, { "Hide Selected", "H", t("Hide") }, { "Hide Unselected", "Shift H", t("HideUnselected") },
		} end },
		{ "Clean Up", "", nil, sub = function() return {
			{ "Delete Loose", "", t("DeleteLoose") }, { "Degenerate Dissolve", "", t("DegenerateDissolve") }, { "Limited Dissolve", "", t("LimitedDissolve") },
			"-", { "Fill Holes", "", t("FillHoles") }, "-", { "Merge by Distance", "", t("MergeDistance") },
		} end },
		"-",
		{ "Delete", "X", nil, sub = function() return self:deleteItems() end },
		"-",
		{ "Bake to Parts", "", t("Bake") }, { "Export .obj", "", t("Export") },
	}
end
-- VIEW3D_MT_edit_mesh_vertices
function UI:vertexMenu()
	local api = self.api
	local t = function(n) return function() api.tool(n) end end
	return {
		{ "Extrude Vertices", "E", t("ExtrudeVerts") },
		{ "Bevel Vertices", "Shift Ctrl B", t("BevelVerts") },
		"-",
		{ "New Edge/Face from Vertices", "F", t("Fill") },
		{ "Connect Vertex Pairs", "J", t("Connect") },
		"-",
		{ "Rip Vertices", "V", t("Rip") },
		{ "Rip Vertices and Extend", "Alt D", t("RipEdge") },
		"-",
		{ "Slide Vertices", "", t("VertexSlide") },
		{ "Smooth Vertices", "", t("Smooth") },
		"-",
		{ "Merge Vertices", "M", nil, sub = function() return self:mergeItems() end },
	}
end
-- VIEW3D_MT_edit_mesh_edges
function UI:edgeMenu()
	local api = self.api
	local t = function(n) return function() api.tool(n) end end
	return {
		{ "Extrude Edges", "", t("ExtrudeEdges") },
		{ "Bevel Edges", "Ctrl B", t("Bevel") },
		{ "Bridge Edge Loops", "", t("Bridge") },
		"-",
		{ "Subdivide", "", t("Subdivide") },
		{ "Subdivide Edge-Ring", "", t("SubdivideRing") },
		"-",
		{ "Rotate Edge CW", "", t("RotateCW") },
		{ "Rotate Edge CCW", "", t("RotateCCW") },
		"-",
		{ "Edge Slide", "G G", t("EdgeSlide") },
		{ "Loop Cut and Slide", "Ctrl R", t("LoopCut") }, { "Offset Edge Slide", "Shift Ctrl R", t("OffsetEdgeLoops") },
		"-",
		{ "Mark Seam", "", t("MarkSeam") }, { "Clear Seam", "", t("ClearSeam") },
		"-",
		{ "Mark Sharp", "", t("MarkSharp") }, { "Clear Sharp", "", t("ClearSharp") },
		"-",
		{ "Edge Crease (toggle)", "Shift E", t("Crease") },
	}
end
-- VIEW3D_MT_edit_mesh_faces
function UI:faceMenu()
	local api = self.api
	local t = function(n) return function() api.tool(n) end end
	return {
		{ "Extrude Faces", "E", t("Extrude") },
		{ "Extrude Faces Along Normals", "", t("ExtrudeNormals") },
		{ "Extrude Individual Faces", "", t("ExtrudeIndividual") },
		"-",
		{ "Inset Faces", "I", t("Inset") },
		{ "Poke Faces", "", t("Poke") },
		{ "Triangulate Faces", "Ctrl T", t("Triangulate") },
		{ "Tris to Quads", "Alt J", t("TrisToQuads") },
		{ "Solidify Faces", "", t("Solidify") },
		{ "Wireframe", "", t("Wireframe") },
		"-",
		{ "Fill", "F", t("Fill") },
		{ "Beautify Faces", "Alt F", t("BeautyFill") },
		"-",
		{ "Shade Smooth", "", t("ShadeSmooth") },
		{ "Shade Flat", "", t("ShadeFlat") },
	}
end
-- X / M / Shift S / Alt E / Ctrl V E F popups
function UI:openNamedMenu(name, at)
	local lists = {
		delete = function() return self:deleteItems(), "Delete" end,
		merge = function() return self:mergeItems(), "Merge" end,
		snap = function() return self:snapItems(), "Snap" end,
		separate = function() return self:separateItems(), "Separate" end,
		similar = function() return self:similarItems(), "Select Similar" end,
		uv = function() return self:uvItems(), "UV Mapping" end,
		pivot = function() return self:pivotItems(), "Pivot Point" end,
		shading = function() return self:shadingItems(), "Shading" end,
		apply = function() return self:applyItems(), "Apply" end,
		origin = function() return self:originItems(), "Set Origin" end,
		split = function() return { { "Selection", "Y", function() self.api.tool("Split") end } }, "Split" end,
		normals = function() return self:normalsItems(), "Normals" end,
		extrude = function() return self:extrudeItems(), "Extrude" end,
		vertex = function() return self:vertexMenu(), "Vertex" end,
		edge = function() return self:edgeMenu(), "Edge" end,
		face = function() return self:faceMenu(), "Face" end,
	}
	local f = lists[name]
	if not f then return end
	local items, title = f()
	return self:openMenu(items, at, title)
end
-- floating labels in the 3D view (measure tool)
function UI:setLabel(id, pos, text)
	self.labels = self.labels or {}
	local l = self.labels[id]
	if not pos then if l then l.Visible = false end return end
	if not l then
		l = label(self.overlay, { ZIndex = 4, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Font = FONT_B, TextSize = 13,
			TextStrokeTransparency = 0.3, TextStrokeColor3 = Color3.new(0, 0, 0), AnchorPoint = Vector2.new(0.5, 1) })
		self.labels[id] = l
	end
	local off = self.canvas.AbsolutePosition or Vector2.new()
	l.Position = UDim2.fromOffset(pos.X - off.X, pos.Y - off.Y - 6)
	l.Text = text
	l.Visible = true
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
			items[#items + 1] = { "Bevel Vertices", "", function() api.tool("BevelVerts") end }
			items[#items + 1] = { "Connect Vertex Pairs", "", function() api.tool("Connect") end }
			items[#items + 1] = { "Push/Pull", "", function() api.tool("PushPull") end }
			items[#items + 1] = { "Shrink/Fatten", "", function() api.tool("ShrinkFatten") end }
			items[#items + 1] = { "Shear", "", function() api.tool("Shear") end }
			items[#items + 1] = { "Slide Vertices", "", function() api.tool("VertexSlide") end }
			items[#items + 1] = { "Smooth Vertices", "", function() api.tool("Smooth") end }
			items[#items + 1] = { "Mirror Vertices", "", nil, sub = function() return { { "X", "", function() api.tool("MirrorX") end }, { "Y", "", function() api.tool("MirrorY") end }, { "Z", "", function() api.tool("MirrorZ") end } } end }
			items[#items + 1] = { "Snap Vertices", "", nil, sub = function() return self:snapItems() end }
			items[#items + 1] = { "New Edge/Face from Vertices", "", function() api.tool("Fill") end }
			items[#items + 1] = { "Merge Vertices", "", function() api.tool("Merge") end }
			items[#items + 1] = "-"
			items[#items + 1] = { "Delete Vertices", "", function() api.tool("Delete") end }
		elseif s.mode == "edge" then
			items[#items + 1] = { header = "Edge", icon = "edge" }
			items[#items + 1] = { "Subdivide", "", function() api.tool("Subdivide") end }
			items[#items + 1] = { "Extrude Edges", "", function() api.tool("Extrude") end }
			items[#items + 1] = { "Bevel Edges", "", function() api.tool("Bevel") end }
			items[#items + 1] = { "Bridge Edge Loops", "", function() api.tool("Bridge") end }
			items[#items + 1] = { "Rotate Edge CW", "", function() api.tool("RotateCW") end }
			items[#items + 1] = { "Edge Slide", "", function() api.tool("EdgeSlide") end }
			items[#items + 1] = { "Loop Cut and Slide", "", function() api.tool("LoopCut") end }
			items[#items + 1] = { "Mark Sharp", "", function() api.tool("MarkSharp") end }
			items[#items + 1] = { "Clear Sharp", "", function() api.tool("ClearSharp") end }
			items[#items + 1] = { "New Face from Edges", "", function() api.tool("Fill") end }
			items[#items + 1] = "-"
			items[#items + 1] = { "Delete Edges", "", function() api.tool("Delete") end }
		else
			items[#items + 1] = { header = "Face", icon = "face" }
			items[#items + 1] = { "Subdivide", "", function() api.tool("Subdivide") end }
			items[#items + 1] = { "Extrude Faces", "", function() api.tool("Extrude") end }
			items[#items + 1] = { "Inset Faces", "", function() api.tool("Inset") end }
			items[#items + 1] = { "Extrude Faces Along Normals", "", function() api.tool("ExtrudeNormals") end }
			items[#items + 1] = { "Extrude Individual Faces", "", function() api.tool("ExtrudeIndividual") end }
			items[#items + 1] = { "Poke Faces", "", function() api.tool("Poke") end }
			items[#items + 1] = { "Triangulate Faces", "", function() api.tool("Triangulate") end }
			items[#items + 1] = { "Shade Smooth", "", function() api.tool("ShadeSmooth") end }
			items[#items + 1] = { "Shade Flat", "", function() api.tool("ShadeFlat") end }
			items[#items + 1] = "-"
			items[#items + 1] = { "Delete Faces", "", function() api.tool("Delete") end }
		end
		return self:openMenu(items, at)
	end
	return self:openMenu({
		{ "Add", "", nil, sub = function() return self:addMeshItems() end },
		"-",
		{ "Duplicate Objects", "Shift D", function() api.tool("Duplicate") end },
		{ "Join", "Ctrl J", function() api.tool("Join") end },
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
		{ "Extrude to Mouse", "Ctrl RMB" }, { "Repeat Last", "Shift R" }, { "Circle Select", "C" },
		{ "Inset: individual / depth", "I then I / Ctrl" }, { "Subdivision level", "Ctrl 0-4" }, { "Join / Separate", "Ctrl J  /  P" },
		{ "Search every menu", "F3" }, { "Loop / Ring select", "Double click / Ctrl Alt click" }, { "Edge Crease", "Shift E" },
		{ "Select Similar / Mirror", "Shift G / Shift Ctrl M" }, { "Perspective / Ortho, Local View", "Numpad 5, Numpad /" },
		{ "Hide / Clear (objects)", "H Shift H Alt H, Alt G Alt R" }, { "Shading menu", "Z" },
		{ "Lasso select / deselect", "Ctrl RMB drag / Shift Ctrl RMB drag" }, { "Snapping on / off", "Shift Tab" }, { "UV menu", "U" },
		{ "Pivot point menu", "." }, { "Local axis (G / R / S)", "X X, Y Y, Z Z" }, { "Offset Edge Loops", "Shift Ctrl R" },
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
	local active = s.activeTool or "select"
	for _, g in ipairs(self.toolGroups) do
		g.b.Visible = (not g.edit) or s.editing
		local on = false
		for k, t in ipairs(g.list) do if t[1] == active then on = true if g.current ~= k then g.current = k end end end
		self:setOnStyle(g.b, on, T.toolItem)
	end
	for _, sep in ipairs(self.toolSeps) do sep.Visible = s.editing end
	for k, b in pairs(self.toggleBtns) do
		self:setOnStyle(b, s[k] == true)
		b.Visible = s.editing or k == "snap"
	end
	self.falloffBtn.Visible = s.editing == true
	self.pivotBtn.Visible = s.editing == true
	for k, b in pairs(self.boxModeBtns) do
		self:setOnStyle(b, (s.boxMode or "set") == k)
		b.Visible = s.editing == true and (s.activeTool or "select") == "select"
	end
	self.uvMenuBtn.Visible = s.editing
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
	local propKey = tostring(s.objName) .. "|" .. tostring(s.modsKey) .. "|" .. tostring(s.editing) .. "|" .. tostring(s.saved) .. tostring(s.saving) .. tostring(s.assetId) .. tostring(s.autoSave)
	if propKey ~= self.lastPropKey then self.lastPropKey = propKey self:buildPropContent() end
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
