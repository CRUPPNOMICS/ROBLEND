--[[
	ROBLENDER - the Blender-style screen: header + menus, tool strip, N sidebar, stats, status bar
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27). Layout follows Blender's 3D viewport (header, toolbar,
	sidebar, status bar). Not made or endorsed by the Blender Foundation.
]]

local UI = {}
UI.__index = UI

-- Blender's default dark theme (close enough)
local C = {
	header = Color3.fromRGB(48, 48, 48),
	widget = Color3.fromRGB(40, 40, 40),
	hover = Color3.fromRGB(70, 70, 70),
	blue = Color3.fromRGB(71, 114, 179),
	menu = Color3.fromRGB(24, 24, 24),
	text = Color3.fromRGB(230, 230, 230),
	dim = Color3.fromRGB(150, 150, 150),
	orange = Color3.fromRGB(255, 160, 60),
	line = Color3.fromRGB(80, 80, 80),
}
local FONT = Enum.Font.Gotham
local FONT_B = Enum.Font.GothamMedium

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function corner(o, r) make("UICorner", { CornerRadius = UDim.new(0, r or 4) }, o) end
local function text(parent, props)
	local t = make("TextLabel", {
		BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props or {}) do t[k] = v end
	return t
end

function UI.new(api, parentGui)
	local self = setmetatable({ api = api, on = false, menuOpen = nil, sidebar = true, toolbar = true, hoverBtns = {}, report = "" }, UI)
	local gui = make("ScreenGui", { Name = "ROBLENDER_UI", Enabled = false, IgnoreGuiInset = true, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ResetOnSpawn = false }, parentGui)
	self.gui = gui

	-- ===== header =====
	local header = make("Frame", { Name = "Header", BackgroundColor3 = C.header, BackgroundTransparency = 0.05, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30) }, gui)
	self.header = header
	local left = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -230, 1, 0) }, header)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, left)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, left)
	local n = 0
	local function hbtn(label, w, fn, flat)
		n += 1
		local b = make("TextButton", {
			LayoutOrder = n, Size = UDim2.new(0, w, 0, 22), BackgroundColor3 = C.widget, BackgroundTransparency = flat and 1 or 0,
			BorderSizePixel = 0, AutoButtonColor = false, Font = FONT, TextSize = 13, TextColor3 = C.text, Text = label,
		}, left)
		corner(b, 4)
		self:hoverable(b, flat)
		b.Activated:Connect(function() self:safe(fn, b) end)
		return b
	end
	self.modeBtn = hbtn("Object Mode", 112, function(b)
		self:openMenu({
			{ "Object Mode", "Tab", function() if api.state().editing then api.toggleEdit() end end },
			{ "Edit Mode", "Tab", function() if not api.state().editing then api.toggleEdit() end end },
		}, b)
	end)
	hbtn("View", 44, function(b)
		self:openMenu({
			{ "Toolbar", "T", function() self:toggleToolbar() end },
			{ "Sidebar", "N", function() self:toggleSidebar() end },
			{ "X-Ray", "Alt Z", function() api.toggleXray() end },
			"-",
			{ "Classic panel", "", function() api.togglePanel() end },
		}, b)
	end, true)
	hbtn("Select", 50, function(b)
		self:openMenu({
			{ "All", "A", function() api.tool("SelectAll") end },
			{ "None", "Alt A", function() api.tool("SelectNone") end },
			{ "Invert", "Ctrl I", function() api.tool("Invert") end },
			"-",
			{ "Select Loop", "Alt Click", nil },
			{ "Box Select", "Drag", nil },
		}, b)
	end, true)
	hbtn("Add", 40, function(b) self:openAddMenu(b) end, true)
	self.meshBtn = hbtn("Mesh", 50, function(b)
		if api.state().editing then
			self:openMenu({
				{ "Extrude", "E", function() api.tool("Extrude") end },
				{ "Inset Faces", "I", function() api.tool("Inset") end },
				{ "Loop Cut", "Ctrl R", function() api.tool("LoopCut") end },
				{ "Subdivide", "", function() api.tool("Subdivide") end },
				"-",
				{ "Merge at Center", "M", function() api.tool("Merge") end },
				{ "Merge by Distance", "", function() api.tool("MergeDist") end },
				{ "Fill", "F", function() api.tool("Fill") end },
				{ "Delete", "X", function() api.tool("Delete") end },
				{ "Flip Normals", "", function() api.tool("Flip") end },
				"-",
				{ "Bake to Parts", "", function() api.tool("Bake") end },
				{ "Export .obj", "", function() api.tool("Export") end },
			}, b)
		else
			self:openMenu({
				{ "Edit Mode", "Tab", function() api.toggleEdit() end },
				"-",
				{ "Bake to Parts", "", function() api.tool("Bake") end },
				{ "Export .obj", "", function() api.tool("Export") end },
			}, b)
		end
	end, true)

	-- vertex / edge / face select mode (little drawn icons like Blender's)
	n += 1
	local grp = make("Frame", { LayoutOrder = n, BackgroundTransparency = 1, Size = UDim2.new(0, 92, 0, 22) }, left)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 1) }, grp)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, grp)
	self.selGroup = grp
	self.selBtns = {}
	for i, m in ipairs({ "vert", "edge", "face" }) do
		local b = make("TextButton", { LayoutOrder = i, Size = UDim2.new(0, 27, 1, 0), BackgroundColor3 = C.widget, BorderSizePixel = 0, AutoButtonColor = false, Text = "" }, grp)
		corner(b, 3)
		local box = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = C.text, BackgroundTransparency = m == "face" and 0.35 or 1, BorderSizePixel = 0 }, b)
		make("UIStroke", { Color = C.text, Thickness = 1 }, box)
		if m == "vert" then
			make("Frame", { Position = UDim2.fromOffset(-3, -3), Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.text, BorderSizePixel = 0 }, box)
		elseif m == "edge" then
			make("Frame", { Position = UDim2.fromOffset(-2, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = C.text, BorderSizePixel = 0 }, box)
		end
		b.Activated:Connect(function() self:safe(function() api.setMode(m) end) end)
		self:tip(b, ({ vert = "Vertex select  1", edge = "Edge select  2", face = "Face select  3" })[m])
		self.selBtns[m] = b
	end

	-- right side of the header
	local right = make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), BackgroundTransparency = 1, Size = UDim2.new(0, 220, 1, 0) }, header)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center, HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, right)
	local function rbtn(order, label, w, tipText, fn)
		local b = make("TextButton", { LayoutOrder = order, Size = UDim2.new(0, w, 0, 22), BackgroundColor3 = C.widget, BorderSizePixel = 0, AutoButtonColor = false, Font = FONT, TextSize = 12, TextColor3 = C.text, Text = label }, right)
		corner(b, 4)
		self:hoverable(b)
		self:tip(b, tipText)
		b.Activated:Connect(function() self:safe(fn, b) end)
		return b
	end
	self.xrayBtn = rbtn(1, "X-Ray", 48, "Toggle X-Ray  Alt Z", function() api.toggleXray() end)
	self.sideBtn = rbtn(2, "N", 24, "Sidebar  N", function() self:toggleSidebar() end)
	rbtn(3, "?", 24, "Keys", function(b) self:openHelp(b) end)
	text(right, { LayoutOrder = 4, Size = UDim2.new(0, 84, 1, 0), Text = "ROBLENDER", Font = FONT_B, TextColor3 = C.orange, TextXAlignment = Enum.TextXAlignment.Right })

	-- operator header (replaces the header while G / S / R / inset / loop cut runs, like Blender)
	self.opHeader = make("Frame", { Visible = false, BackgroundColor3 = C.header, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30), ZIndex = 5 }, gui)
	self.opText = text(self.opHeader, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), ZIndex = 5, Font = FONT_B })

	-- ===== tool strip (left) =====
	local tb = make("Frame", { Name = "Toolbar", Position = UDim2.fromOffset(6, 38), Size = UDim2.fromOffset(52, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.header, BackgroundTransparency = 0.1, BorderSizePixel = 0 }, gui)
	corner(tb, 6)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, tb)
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, tb)
	self.toolbarFrame = tb
	self.toolBtns = {}
	local tools = {
		{ "Select", "Select", "Select (click, drag a box)" },
		{ "Move", "G", "Move  G" },
		{ "Rotate", "R", "Rotate  R" },
		{ "Scale", "S", "Scale  S" },
		"-",
		{ "Extrude", "Extrude", "Extrude  E" },
		{ "Inset", "Inset", "Inset Faces  I" },
		{ "Loop Cut", "LoopCut", "Loop Cut  Ctrl R" },
		"-",
		{ "Subdiv", "Subdivide", "Subdivide" },
		{ "Merge", "Merge", "Merge at Center  M" },
		{ "Delete", "Delete", "Delete  X" },
	}
	for i, t in ipairs(tools) do
		if t == "-" then
			make("Frame", { LayoutOrder = i, Size = UDim2.new(0, 36, 0, 1), BackgroundColor3 = C.line, BorderSizePixel = 0 }, tb)
		else
			local b = make("TextButton", { LayoutOrder = i, Size = UDim2.fromOffset(44, 30), BackgroundColor3 = C.widget, BorderSizePixel = 0, AutoButtonColor = false, Font = FONT, TextSize = 10, TextColor3 = C.text, Text = t[1], TextWrapped = true }, tb)
			corner(b, 4)
			self:hoverable(b)
			self:tip(b, t[3])
			b.Activated:Connect(function() self:safe(function() if t[2] ~= "Select" then api.tool(t[2]) end end) end)
			self.toolBtns[t[2]] = b
		end
	end

	-- ===== info text (top left, like Blender's overlay text) =====
	self.info = text(gui, { Position = UDim2.fromOffset(66, 38), Size = UDim2.fromOffset(400, 90), TextYAlignment = Enum.TextYAlignment.Top, TextSize = 13, TextStrokeTransparency = 0.6, RichText = true })

	-- ===== sidebar (N) =====
	local sb = make("Frame", { Name = "Sidebar", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 38), Size = UDim2.fromOffset(210, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.header, BackgroundTransparency = 0.05, BorderSizePixel = 0 }, gui)
	corner(sb, 6)
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, sb)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, sb)
	self.sidebarFrame = sb
	text(sb, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), Text = "Item", Font = FONT_B })
	self.sec1 = text(sb, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 16), Text = "Location", TextColor3 = C.dim, TextSize = 12 })
	self.fields = {}
	local function field(order, key, axis)
		local row = make("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) }, sb)
		text(row, { Size = UDim2.new(0, 18, 1, 0), Text = axis, TextColor3 = ({ X = Color3.fromRGB(255, 90, 90), Y = Color3.fromRGB(130, 220, 80), Z = Color3.fromRGB(90, 150, 255) })[axis], Font = FONT_B })
		local box = make("TextBox", { Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -20, 1, 0), BackgroundColor3 = Color3.fromRGB(84, 84, 84), BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = C.text, Text = "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Center }, row)
		corner(box, 4)
		box.FocusLost:Connect(function(enter)
			local v = tonumber(box.Text)
			if v then self:safe(function() api.setField(key, axis, v) end) end
			self:refresh(true)
		end)
		self.fields[key .. axis] = { row = row, box = box }
	end
	field(3, "loc", "X") field(4, "loc", "Y") field(5, "loc", "Z")
	self.sec2 = text(sb, { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 16), Text = "Dimensions", TextColor3 = C.dim, TextSize = 12 })
	field(7, "dim", "X") field(8, "dim", "Y") field(9, "dim", "Z")
	self.sbNote = text(sb, { LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = C.dim, Text = "" })

	-- ===== status bar (bottom) =====
	local st = make("Frame", { Name = "Status", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = C.header, BackgroundTransparency = 0.05, BorderSizePixel = 0 }, gui)
	self.statusFrame = st
	self.hints = text(st, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.62, -10, 1, 0), TextSize = 12, TextColor3 = C.dim, TextTruncate = Enum.TextTruncate.AtEnd })
	self.reportLbl = text(st, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.38, -10, 1, 0), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })

	-- ===== tooltip + menu layer =====
	self.tipLbl = make("TextLabel", { Visible = false, ZIndex = 30, BackgroundColor3 = C.menu, BorderSizePixel = 0, Font = FONT, TextSize = 12, TextColor3 = C.text, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22) }, gui)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, self.tipLbl)
	corner(self.tipLbl, 4)
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

function UI:hoverable(b, flat)
	b.MouseEnter:Connect(function() if not self.hoverBtns[b] then self.hoverBtns[b] = true b.BackgroundTransparency = 0 b.BackgroundColor3 = C.hover end end)
	b.MouseLeave:Connect(function() self.hoverBtns[b] = nil if flat then b.BackgroundTransparency = 1 end self:refresh(true) end)
end

function UI:tip(b, s)
	b.MouseEnter:Connect(function()
		self.tipLbl.Text = s
		local p, sz = b.AbsolutePosition, b.AbsoluteSize
		if p and sz then
			if b.Parent == self.toolbarFrame then
				self.tipLbl.Position = UDim2.fromOffset(p.X + sz.X + 8, p.Y + 4)
			else
				self.tipLbl.Position = UDim2.fromOffset(p.X, p.Y + sz.Y + 6)
			end
		end
		self.tipLbl.Visible = true
	end)
	b.MouseLeave:Connect(function() self.tipLbl.Visible = false end)
end

-- ===== menus =====
function UI:closeMenu()
	if self.menuOpen then self.menuOpen.Parent = nil self.menuOpen = nil end
	self.catcher.Visible = false
end

-- items: { {label, shortcut, fn}, "-", ... }; at = a button (drops below it) or a Vector2 (pops at the mouse)
function UI:openMenu(items, at, title)
	self:closeMenu()
	self.tipLbl.Visible = false
	local x, y = 100, 30
	if typeof(at) == "Vector2" then x, y = at.X, at.Y
	elseif at and at.AbsolutePosition and at.AbsoluteSize then x, y = at.AbsolutePosition.X, at.AbsolutePosition.Y + at.AbsoluteSize.Y + 2 end
	local W = 210
	local m = make("Frame", { ZIndex = 20, BackgroundColor3 = C.menu, BackgroundTransparency = 0.03, BorderSizePixel = 0, Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y }, nil)
	corner(m, 5)
	make("UIStroke", { Color = Color3.fromRGB(60, 60, 60), Thickness = 1 }, m)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, m)
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, m)
	local h = 8
	if title then
		text(m, { LayoutOrder = 0, ZIndex = 21, Size = UDim2.new(1, 0, 0, 22), Text = "   " .. title, Font = FONT_B, TextColor3 = C.dim })
		h += 22
	end
	for i, it in ipairs(items) do
		if it == "-" then
			local sep = make("Frame", { LayoutOrder = i, ZIndex = 21, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 7) }, m)
			make("Frame", { ZIndex = 21, Position = UDim2.new(0, 8, 0, 3), Size = UDim2.new(1, -16, 0, 1), BackgroundColor3 = C.line, BorderSizePixel = 0 }, sep)
			h += 7
		else
			local b = make("TextButton", { LayoutOrder = i, ZIndex = 21, Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = C.blue, BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "" }, m)
			text(b, { ZIndex = 22, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Text = it[1], TextColor3 = it[3] and C.text or C.dim })
			text(b, { ZIndex = 22, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Text = it[2] or "", TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, TextSize = 12 })
			if it[3] then
				b.MouseEnter:Connect(function() b.BackgroundTransparency = 0 end)
				b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
				b.Activated:Connect(function()
					self:closeMenu()
					self:safe(it[3])
				end)
			end
			h += 22
		end
	end
	-- keep it on screen
	local scr = self.gui.AbsoluteSize
	if scr and scr.X > 0 then
		x = math.clamp(x, 0, math.max(0, scr.X - W))
		y = math.clamp(y, 0, math.max(0, scr.Y - h))
	end
	m.Position = UDim2.fromOffset(x, y)
	m.Parent = self.gui
	self.menuOpen = m
	self.catcher.Visible = true
	return m
end

function UI:openAddMenu(at)
	local api = self.api
	local items = {}
	for _, k in ipairs({ { "Plane", "Plane" }, { "Cube", "Cube" }, { "Circle", "Circle" }, { "UV Sphere", "Sphere" }, { "Cylinder", "Cylinder" }, { "Grid", "Grid" } }) do
		items[#items + 1] = { k[1], "", function() api.add(k[2]) end }
	end
	return self:openMenu(items, at, "Add Mesh")
end

function UI:openHelp(at)
	local items = {}
	for _, k in ipairs({
		{ "Edit / Object Mode", "Tab" }, { "Vertex / Edge / Face", "1  2  3" }, { "Select / Extend / Box", "Click  Shift  Drag" },
		{ "Select Loop", "Alt Click" }, { "All / None / Invert", "A  Alt A  Ctrl I" }, { "Move / Rotate / Scale", "G  R  S" },
		{ "Lock axis / Snap / Number", "X Y Z  Ctrl  0-9" }, { "Extrude / Inset", "E  I" }, { "Loop Cut", "Ctrl R" },
		{ "Delete / Merge / Fill", "X  M  F" }, { "Add", "Shift A" }, { "Toolbar / Sidebar", "T  N" }, { "X-Ray", "Alt Z" }, { "Undo", "Ctrl Z" },
	}) do items[#items + 1] = { k[1], k[2], nil } end
	return self:openMenu(items, at, "Keys")
end

-- ===== panels =====
function UI:toggleSidebar() self.sidebar = not self.sidebar self:refresh(true) end
function UI:toggleToolbar() self.toolbar = not self.toolbar self:refresh(true) end
function UI:setOn(on)
	self.on = on
	self.gui.Enabled = on
	if not on then self:closeMenu() self.tipLbl.Visible = false end
	self:refresh(true)
end
function UI:setReport(s) self.report = s or "" self.reportLbl.Text = self.report end

-- is a screen point over any of our panels? (so viewport clicks there are ignored)
function UI:overUI(p)
	if not self.on then return false end
	if self.menuOpen then return true end
	for _, f in ipairs({ self.header, self.opHeader, self.toolbarFrame, self.sidebarFrame, self.statusFrame }) do
		if f.Visible ~= false then
			local a, s = f.AbsolutePosition, f.AbsoluteSize
			if a and s and p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y then return true end
		end
	end
	return false
end

local function fmt(x) return string.format("%.3f", x):gsub("%.?0+$", "") end

function UI:refresh(force)
	if not self.on and not force then return end
	local s = self.api.state()
	-- header
	self.modeBtn.Text = (s.editing and "Edit Mode" or "Object Mode") .. "  v"
	self.meshBtn.Text = s.editing and "Mesh" or "Object"
	self.selGroup.Visible = s.editing
	for m, b in pairs(self.selBtns) do b.BackgroundColor3 = (s.mode == m) and C.blue or C.widget end
	if not self.hoverBtns[self.xrayBtn] then self.xrayBtn.BackgroundColor3 = s.xray and C.blue or C.widget end
	if not self.hoverBtns[self.sideBtn] then self.sideBtn.BackgroundColor3 = self.sidebar and C.blue or C.widget end
	-- operator header
	self.opHeader.Visible = s.modal ~= nil
	if s.modal then self.opText.Text = s.modalText or "" end
	-- tool strip
	self.toolbarFrame.Visible = self.toolbar and s.editing
	local active = ({ G = "Move", R = "Rotate", S = "Scale", inset = "Inset", loopcut = "LoopCut" })[s.modal or ""] or (s.modal == nil and "Select" or nil)
	if s.modal == "G" and s.modalWhat == "Extrude" then active = "Extrude" end
	for key, b in pairs(self.toolBtns) do
		if not self.hoverBtns[b] then b.BackgroundColor3 = (key == active) and C.blue or C.widget end
	end
	-- info text
	local lines = {}
	if s.editing then
		local st = s.stats
		lines[1] = "<b>Edit Mode</b>   (" .. (s.objName or "") .. ")"
		lines[2] = ("Vertices  %d/%d"):format(st.vs, st.v)
		lines[3] = ("Edges  %d/%d"):format(st.es, st.e)
		lines[4] = ("Faces  %d/%d"):format(st.fs, st.f)
		lines[5] = ("Triangles  %d"):format(st.t)
	else
		lines[1] = "<b>Object Mode</b>" .. (s.objName and ("   (" .. s.objName .. ")") or "")
		lines[2] = s.objName and (s.isRB and "Tab = edit this mesh" or "Not a ROBLENDER mesh - Shift A to add one") or "Shift A to add a mesh"
	end
	self.info.Text = table.concat(lines, "\n")
	self.info.Position = UDim2.fromOffset((self.toolbar and s.editing) and 66 or 12, 38)
	-- sidebar
	self.sidebarFrame.Visible = self.sidebar
	self.sec1.Text = s.editing and "Median (Global)" or "Location"
	self.sec2.Visible = not s.editing
	local loc, dim = s.loc, (not s.editing) and s.dim or nil
	for key, f in pairs(self.fields) do
		local isDim = key:sub(1, 3) == "dim"
		f.row.Visible = not isDim or not s.editing
		local v = isDim and dim or loc
		local focused = f.box:IsFocused()
		if not focused then
			local axis = key:sub(4, 4)
			f.box.Text = v and fmt(v[axis]) or "-"
		end
	end
	self.sbNote.Text = s.editing and (loc and "Type a number to move the selection." or "Nothing selected.")
		or (s.dim and "Type to move / resize the part." or "Select a part.")
	-- status bar
	if s.modal then
		self.hints.Text = "LMB / Enter  Confirm      RMB / Esc  Cancel      X Y Z  Axis      Ctrl  Snap      0-9  Type a value"
	elseif s.editing then
		self.hints.Text = "LMB  Select   Shift  Extend   Drag  Box   Alt  Loop      G R S  Move Rotate Scale      E  Extrude   I  Inset   Ctrl R  Loop Cut      Tab  Object Mode"
	else
		self.hints.Text = "Tab  Edit Mode      Shift A  Add      N  Sidebar      Click the ROBLENDER button to close"
	end
	self.reportLbl.Text = self.report
end

function UI:destroy() self.gui.Parent = nil end

return UI
