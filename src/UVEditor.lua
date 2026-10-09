--[[
	ROBLEND - the UV Editor: a 2D window showing the UVs of the faces being edited over the texture,
	where UV points are selected and moved (Blender's UV Editor, cut down).
	Converted to Luau from Blender's UV editor behaviour:
	  source/blender/editors/uvedit/uvedit_select.cc (pick / box / linked select), uvedit_ops.cc (align, pack call),
	  scripts/startup/bl_ui/space_image.py (the UV menu layout)
	SPDX-License-Identifier: GPL-2.0-or-later
	Original: Copyright (C) Blender Authors. Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27).

	UVEditor.new(C) -> E. Works on the mesh in Edit Mode (C.get().bm): the selected faces, or all of them.
	Mouse: click a point to select it (Shift adds / removes), drag a selected point to move, drag on empty
	space to box select. Keys while the mouse is over it: G / S / R (move, scale, rotate - click or Enter to
	finish, Esc or right click to cancel), A all, Alt A none, L the island under the mouse.
]]
local UVEditor = {}
local V2 = Vector2.new

function UVEditor.new(C)
	local E = { open = false, sel = {}, hover = false, modal = nil, drag = nil, box = nil, points = {}, edges = {}, sig = nil }
	local BMesh, UVT = C.BMesh, C.UVTools
	local SIZE = 360
	local frame, canvas, image, info, boxFrame
	local linePool, dotPool = {}, {}

	local function mesh() local st = C.get() return st.editing and st.bm or nil end
	local function shownFaces()
		local m = mesh()
		if not m then return {} end
		local any = false
		for f in pairs(m.faces) do if f.sel and not f.hide then any = true break end end
		local out = {}
		for f in pairs(m.faces) do if not f.hide and (not any or f.sel) then out[#out + 1] = f end end
		return out
	end
	local function hasUV(f) for _, l in ipairs(BMesh.faceLoops(f)) do if not l.uv then return false end end return true end
	local function key(l) return tostring(l.v) .. ":" .. math.floor(l.uv.X * 100000 + 0.5) .. "," .. math.floor(l.uv.Y * 100000 + 0.5) end

	-- ===== screen <-> UV =====
	local function rect()
		local p, s = canvas.AbsolutePosition, canvas.AbsoluteSize
		if not p or not s or s.X < 1 then return V2(0, 0), V2(SIZE, SIZE) end
		return p, s
	end
	local function toUV(mp) local p, s = rect() return V2((mp.X - p.X) / s.X, 1 - (mp.Y - p.Y) / s.Y) end
	local function toPx(uv) return V2(uv.X * SIZE, (1 - uv.Y) * SIZE) end
	local function inside(mp)
		if not (E.open and canvas) then return false end
		local p, s = rect()
		return mp.X >= p.X and mp.Y >= p.Y and mp.X <= p.X + s.X and mp.Y <= p.Y + s.Y
	end
	E.inside = inside

	-- ===== the window =====
	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = parent
		return o
	end
	local function button(parent, text, w, fn)
		local b = mk("TextButton", { Size = UDim2.fromOffset(w, 20), BackgroundColor3 = Color3.fromRGB(84, 84, 84), BorderSizePixel = 0, Text = text,
			Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Color3.fromRGB(230, 230, 230), AutoButtonColor = true }, parent)
		b.Activated:Connect(function() local ok, err = pcall(fn) if not ok then C.setStatus("UV Editor: " .. tostring(err)) end end)
		return b
	end
	local function build()
		local st = C.get()
		local gui = st.ui and st.ui.gui
		if not gui then return false end
		frame = mk("Frame", { Name = "RB_UVEditor", Size = UDim2.fromOffset(SIZE + 16, SIZE + 84), Position = UDim2.fromOffset(70, 70), BackgroundColor3 = Color3.fromRGB(48, 48, 48),
			BorderSizePixel = 0, ZIndex = 40, Active = true }, gui)
		mk("UICorner", { CornerRadius = UDim.new(0, 6) }, frame)
		mk("UIStroke", { Color = Color3.fromRGB(20, 20, 20), Thickness = 1 }, frame)
		local title = mk("TextLabel", { Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1, Text = "UV Editor", Font = Enum.Font.GothamMedium,
			TextSize = 12, TextColor3 = Color3.fromRGB(230, 230, 230), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41 }, frame)
		local close = button(frame, "X", 22, function() E.close() end)
		close.Position = UDim2.new(1, -26, 0, 1)
		close.ZIndex = 41
		local bar = mk("Frame", { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 24), BackgroundTransparency = 1, ZIndex = 41 }, frame)
		mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3) }, bar)
		for _, b in ipairs({
			{ "Unwrap", 54, function() C.api.uvUnwrap("unwrap") end },
			{ "Smart", 46, function() C.api.uvUnwrap("smart") end },
			{ "Pack", 40, function() E.pack() end },
			{ "Flip", 36, function() E.flip() end },
			{ "Rotate 90", 62, function() E.rotate(math.rad(90), true) end },
			{ "All", 30, function() E.selectAll(true) end },
		}) do button(bar, b[1], b[2], b[3]).ZIndex = 41 end
		canvas = mk("Frame", { Name = "RB_UVCanvas", Size = UDim2.fromOffset(SIZE, SIZE), Position = UDim2.fromOffset(8, 48), BackgroundColor3 = Color3.fromRGB(36, 36, 36),
			BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 41 }, frame)
		image = mk("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ImageTransparency = 0.25, ZIndex = 41 }, canvas)
		for i = 1, 7 do
			mk("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(i / 8, 0), BackgroundColor3 = Color3.fromRGB(60, 60, 60), BorderSizePixel = 0, ZIndex = 41 }, canvas)
			mk("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, i / 8), BackgroundColor3 = Color3.fromRGB(60, 60, 60), BorderSizePixel = 0, ZIndex = 41 }, canvas)
		end
		boxFrame = mk("Frame", { BackgroundTransparency = 0.85, BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Visible = false, ZIndex = 45 }, canvas)
		mk("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 1 }, boxFrame)
		info = mk("TextLabel", { Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 1, -32), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
			TextColor3 = Color3.fromRGB(170, 170, 170), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 41, Text = "" }, frame)
		-- drag the window by its title
		title.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then E.moveWin = { m0 = V2(input.Position.X, input.Position.Y), p0 = frame.Position } end
		end)
		title.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then E.moveWin = nil end end)
		title.InputChanged:Connect(function(input)
			if E.moveWin and input.UserInputType == Enum.UserInputType.MouseMovement then
				local d = V2(input.Position.X, input.Position.Y) - E.moveWin.m0
				frame.Position = E.moveWin.p0 + UDim2.fromOffset(d.X, d.Y)
			end
		end)
		st.ui.uvFrame = frame
		return true
	end

	-- ===== drawing =====
	local SEL_COL, LINE_COL, DOT_COL = Color3.fromRGB(255, 160, 40), Color3.fromRGB(200, 200, 200), Color3.fromRGB(255, 200, 80)
	local function line(i, a, b, col)
		local f = linePool[i]
		if not f then
			f = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 43 }, canvas)
			linePool[i] = f
		end
		local pa, pb = toPx(a), toPx(b)
		local d = pb - pa
		local len = math.sqrt(d.X * d.X + d.Y * d.Y)
		f.Visible = true
		f.BackgroundColor3 = col
		f.Position = UDim2.fromOffset((pa.X + pb.X) / 2, (pa.Y + pb.Y) / 2)
		f.Size = UDim2.fromOffset(math.max(len, 1), 1)
		f.Rotation = math.deg(math.atan2(d.Y, d.X))
	end
	local function dot(i, uv)
		local f = dotPool[i]
		if not f then
			f = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 5), BorderSizePixel = 0, ZIndex = 44 }, canvas)
			dotPool[i] = f
		end
		local p = toPx(uv)
		f.Visible = true
		f.BackgroundColor3 = DOT_COL
		f.Position = UDim2.fromOffset(p.X, p.Y)
	end
	local MAX_LINES = 4000
	function E.draw()
		if not (E.open and canvas) then return end
		local nl, nd = 0, 0
		for _, ed in ipairs(E.edges) do
			if nl >= MAX_LINES then break end
			local a, b = E.groups[ed[1]], E.groups[ed[2]]
			if a and b then
				nl += 1
				line(nl, a.loops[1].uv, b.loops[1].uv, (E.isSel(a) and E.isSel(b)) and SEL_COL or LINE_COL)
			end
		end
		for _, g in ipairs(E.points) do
			if E.isSel(g) and nd < MAX_LINES then nd += 1 dot(nd, g.loops[1].uv) end
		end
		for i = nl + 1, #linePool do linePool[i].Visible = false end
		for i = nd + 1, #dotPool do dotPool[i].Visible = false end
		E.drawn = nl
	end
	function E.isSel(g) return E.sel[g.loops[1]] == true end
	local function setSel(g, on) for _, l in ipairs(g.loops) do E.sel[l] = on or nil end end
	local function selectedGroups()
		local out = {}
		for _, g in ipairs(E.points) do if E.isSel(g) then out[#out + 1] = g end end
		return out
	end
	local function updateInfo(extra)
		if not info then return end
		local st = C.get()
		if not st.editing then info.Text = "Tab into Edit Mode on a mesh to see its UVs." return end
		local n = #selectedGroups()
		local txt = ("%d UV points, %d selected. G move, S scale, R rotate, A all, L island; drag a point to move, drag empty space to box select."):format(#E.points, n)
		if E.missing and E.missing > 0 then txt = ("%d faces have no UVs yet - Unwrap or Smart first. "):format(E.missing) .. txt end
		info.Text = extra or txt
	end

	-- rebuild the point / edge lists from the mesh (keeps the selection on loops still shown)
	function E.refresh()
		if not E.open then return end
		local groups, pts, edges, seen = {}, {}, {}, {}
		local missing = 0
		for _, f in ipairs(shownFaces()) do
			if hasUV(f) then
				local ls = BMesh.faceLoops(f)
				local keys = {}
				for i, l in ipairs(ls) do
					local k = key(l)
					keys[i] = k
					local g = groups[k]
					if not g then g = { key = k, loops = {} } groups[k] = g pts[#pts + 1] = g end
					g.loops[#g.loops + 1] = l
				end
				for i = 1, #ls do
					local a, b = keys[i], keys[i % #ls + 1]
					local ek = a < b and (a .. "|" .. b) or (b .. "|" .. a)
					if not seen[ek] then seen[ek] = true edges[#edges + 1] = { a, b } end
				end
			else
				missing += 1
			end
		end
		-- a point is selected only if all its loops are (keeps groups consistent)
		local sel = {}
		for _, g in ipairs(pts) do
			local all = true
			for _, l in ipairs(g.loops) do if not E.sel[l] then all = false break end end
			if all then for _, l in ipairs(g.loops) do sel[l] = true end end
		end
		E.sel, E.groups, E.points, E.edges, E.missing = sel, groups, pts, edges, missing
		local st = C.get()
		local tex
		pcall(function() tex = st.obj and st.obj.TextureID end)
		if image then pcall(function() image.Image = tex or "" end) end
		E.draw()
		updateInfo()
	end

	-- ===== picking / selection =====
	local function nearest(mp, maxPx)
		local best, bd = nil, maxPx or 9
		local p, s = rect()
		for _, g in ipairs(E.points) do
			local uv = g.loops[1].uv
			local x, y = p.X + uv.X * s.X, p.Y + (1 - uv.Y) * s.Y
			local d = math.sqrt((x - mp.X) ^ 2 + (y - mp.Y) ^ 2)
			if d < bd then best, bd = g, d end
		end
		return best
	end
	function E.selectAll(on)
		E.sel = {}
		if on then for _, g in ipairs(E.points) do setSel(g, true) end end
		E.draw() updateInfo()
	end
	-- UV islands: faces that share UV points (a seam splits the points, so it splits the island)
	local function islandsOf()
		local parent = {}
		local function find(x) while parent[x] ~= x do parent[x] = parent[parent[x]] x = parent[x] end return x end
		for _, g in ipairs(E.points) do parent[g] = g end
		local faceGroups = {}
		for _, g in ipairs(E.points) do
			for _, l in ipairs(g.loops) do
				local fg = faceGroups[l.f]
				if fg then local a, b = find(fg), find(g) if a ~= b then parent[a] = b end else faceGroups[l.f] = g end
			end
		end
		local byRoot, list = {}, {}
		for _, g in ipairs(E.points) do
			local r = find(g)
			if not byRoot[r] then byRoot[r] = {} list[#list + 1] = byRoot[r] end
			table.insert(byRoot[r], g)
		end
		return list, find
	end
	function E.selectLinked(g)
		if not g then return end
		local _, find = islandsOf()
		local r = find(g)
		for _, h in ipairs(E.points) do if find(h) == r then setSel(h, true) end end
		E.draw() updateInfo()
	end
	function E.pick(g, add)
		if not add then E.sel = {} end
		if g then
			if add and E.isSel(g) then setSel(g, false) else setSel(g, true) end
		end
		E.draw() updateInfo()
	end

	-- ===== changing UVs =====
	local function changed(what, final)
		C.dirtyMesh()
		if final then C.commit(what) end
		E.draw()
	end
	local function selLoops()
		local out = {}
		for _, g in ipairs(selectedGroups()) do for _, l in ipairs(g.loops) do out[#out + 1] = l end end
		return out
	end
	local function centre(ls)
		local s, n = V2(0, 0), 0
		for _, l in ipairs(ls) do s += l.uv n += 1 end
		return n > 0 and (s / n) or V2(0.5, 0.5)
	end
	function E.translate(d, final)
		for _, l in ipairs(selLoops()) do l.uv = l.uv + d end
		changed("UV Move", final)
	end
	function E.scale(f, final)
		local ls = selLoops()
		local c = centre(ls)
		for _, l in ipairs(ls) do l.uv = c + (l.uv - c) * f end
		changed("UV Scale", final)
	end
	function E.rotate(a, final)
		local ls = selLoops()
		if #ls == 0 then E.selectAll(true) ls = selLoops() end
		local c = centre(ls)
		local cs, sn = math.cos(a), math.sin(a)
		for _, l in ipairs(ls) do
			local d = l.uv - c
			l.uv = c + V2(d.X * cs - d.Y * sn, d.X * sn + d.Y * cs)
		end
		changed("UV Rotate", final)
		if final then E.refresh() end
	end
	function E.flip()
		local ls = selLoops()
		if #ls == 0 then E.selectAll(true) ls = selLoops() end
		local c = centre(ls)
		for _, l in ipairs(ls) do l.uv = V2(2 * c.X - l.uv.X, l.uv.Y) end
		changed("UV Mirror", true)
		E.refresh()
	end
	-- Pack Islands: the shown islands (or the selected ones) fitted into the 0-1 square
	function E.pack()
		local list = islandsOf()
		local anySel = #selectedGroups() > 0
		local islands = {}
		for _, isl in ipairs(list) do
			local use = not anySel
			for _, g in ipairs(isl) do if E.isSel(g) then use = true break end end
			if use then
				local ls = {}
				for _, g in ipairs(isl) do for _, l in ipairs(g.loops) do ls[#ls + 1] = l end end
				islands[#islands + 1] = ls
			end
		end
		if #islands == 0 then C.setStatus("UV Editor: nothing to pack (Unwrap first).") return end
		UVT.pack(islands, 0.02)
		changed("Pack Islands", true)
		E.refresh()
		C.setStatus(("Packed %d island%s."):format(#islands, #islands == 1 and "" or "s"))
	end

	-- ===== G / S / R in the UV editor =====
	local function startModal(kind, mp)
		local ls = selLoops()
		if #ls == 0 then C.setStatus("UV Editor: select some UV points first (A = all).") return end
		local orig = {}
		for _, l in ipairs(ls) do orig[l] = l.uv end
		E.modal = { kind = kind, m0 = mp, orig = orig, c = centre(ls) }
		updateInfo(({ G = "Move", S = "Scale", R = "Rotate" })[kind] .. ": move the mouse, click or Enter to finish, Esc or right click to cancel.")
	end
	local function updateModal(mp)
		local M = E.modal
		local u0, u1 = toUV(M.m0), toUV(mp)
		for l, o in pairs(M.orig) do l.uv = o end
		if M.kind == "G" then
			local d = u1 - u0
			for l, o in pairs(M.orig) do l.uv = o + d end
		elseif M.kind == "S" then
			local a, b = u0 - M.c, u1 - M.c
			local la = math.sqrt(a:Dot(a))
			local f = la > 1e-6 and math.sqrt(b:Dot(b)) / la or 1
			for l, o in pairs(M.orig) do l.uv = M.c + (o - M.c) * f end
		else
			local a, b = u0 - M.c, u1 - M.c
			local ang = math.atan2(b.Y, b.X) - math.atan2(a.Y, a.X)
			local cs, sn = math.cos(ang), math.sin(ang)
			for l, o in pairs(M.orig) do
				local d = o - M.c
				l.uv = M.c + V2(d.X * cs - d.Y * sn, d.X * sn + d.Y * cs)
			end
		end
		changed(nil, false)
	end
	local function finishModal(cancel)
		local M = E.modal
		if not M then return end
		E.modal = nil
		if cancel then
			for l, o in pairs(M.orig) do l.uv = o end
			changed(nil, false)
		else
			changed(({ G = "UV Move", S = "UV Scale", R = "UV Rotate" })[M.kind], true)
		end
		E.refresh()
	end

	-- ===== input (Main routes the plugin mouse / keys here first) =====
	function E.mouseDown(mp)
		if not E.open then return false end
		if E.modal then finishModal(false) return true end
		if not inside(mp) then return frame ~= nil and E.overWindow(mp) end
		local g = nearest(mp)
		local add = C.shiftDown()
		if g then
			if add then E.pick(g, true)
			elseif not E.isSel(g) then E.pick(g, false) end
			local orig = {}
			for _, l in ipairs(selLoops()) do orig[l] = l.uv end
			E.drag = { m0 = mp, orig = orig, moved = false }
		else
			E.box = { a = mp, add = add }
		end
		return true
	end
	function E.mouseMove(mp)
		if not E.open then return false end
		E.hover = inside(mp)
		if E.modal then updateModal(mp) return true end
		if E.drag then
			local d = mp - E.drag.m0
			if E.drag.moved or math.abs(d.X) + math.abs(d.Y) > 3 then
				E.drag.moved = true
				local du = toUV(mp) - toUV(E.drag.m0)
				for l, o in pairs(E.drag.orig) do l.uv = o + du end
				changed(nil, false)
			end
			return true
		end
		if E.box then
			local p = rect()
			local a, b = E.box.a, mp
			boxFrame.Visible = true
			boxFrame.Position = UDim2.fromOffset(math.min(a.X, b.X) - p.X, math.min(a.Y, b.Y) - p.Y)
			boxFrame.Size = UDim2.fromOffset(math.abs(a.X - b.X), math.abs(a.Y - b.Y))
			return true
		end
		return false
	end
	function E.mouseUp(mp)
		if not E.open then return false end
		if E.drag then
			local moved = E.drag.moved
			E.drag = nil
			if moved then changed("UV Move", true) E.refresh() end
			return true
		end
		if E.box then
			local a, b = E.box.a, mp
			local lo, hi = toUV(V2(math.min(a.X, b.X), math.max(a.Y, b.Y))), toUV(V2(math.max(a.X, b.X), math.min(a.Y, b.Y)))
			if not E.box.add then E.sel = {} end
			for _, g in ipairs(E.points) do
				local uv = g.loops[1].uv
				if uv.X >= lo.X and uv.X <= hi.X and uv.Y >= lo.Y and uv.Y <= hi.Y then setSel(g, true) end
			end
			E.box = nil
			if boxFrame then boxFrame.Visible = false end
			E.draw() updateInfo()
			return true
		end
		return false
	end
	function E.rightClick()
		if E.modal then finishModal(true) return true end
		return false
	end
	function E.overWindow(mp)
		if not frame then return false end
		local p, s = frame.AbsolutePosition, frame.AbsoluteSize
		if not p or not s then return false end
		return mp.X >= p.X and mp.Y >= p.Y and mp.X <= p.X + s.X and mp.Y <= p.Y + s.Y
	end
	function E.key(k, shift, ctrl, alt)
		if not E.open then return false end
		local K = Enum.KeyCode
		if E.modal then
			if k == K.Escape then finishModal(true) elseif k == K.Return or k == K.KeypadEnter then finishModal(false) end
			return true
		end
		if not E.hover then return false end
		local mp = C.mousePos()
		if ctrl then return false end
		if k == K.G or k == K.S or k == K.R then startModal(k.Name, mp) return true end
		if k == K.A then E.selectAll(not alt) return true end
		if k == K.L then E.selectLinked(nearest(mp, 30)) return true end
		if k == K.Escape then E.close() return true end
		return false
	end

	-- ===== open / close =====
	function E.openEditor()
		if not frame then if not build() then return end end
		frame.Visible = true
		E.open = true
		E.sig = nil
		E.refresh()
		if not C.get().editing then C.setStatus("UV Editor: Tab into Edit Mode on a mesh to see and move its UVs.") end
	end
	function E.close()
		E.open, E.modal, E.drag, E.box, E.hover = false, nil, nil, nil, false
		if frame then frame.Visible = false end
	end
	function E.toggle() if E.open then E.close() else E.openEditor() end end
	-- called every frame by Main: redraw when the mesh, its selection or its saved data changed
	function E.tick(dataStamp)
		if not E.open or E.modal or E.drag then return end
		local st = C.get()
		local m = st.editing and st.bm
		local nsel = 0
		if m then for f in pairs(m.faces) do if f.sel then nsel += 1 end end end
		local sig = tostring(m) .. ":" .. (m and m.nf or 0) .. ":" .. nsel .. ":" .. tostring(dataStamp)
		if sig ~= E.sig then E.sig = sig E.refresh() end
	end
	return E
end

return UVEditor
