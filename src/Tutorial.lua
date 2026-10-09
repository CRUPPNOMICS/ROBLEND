--[[
	ROBLEND - Help > Tutorial: step cards that wait for you to actually do each thing.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	Tutorial.new(C) -> T. Each step has a check(state, start) that is run every frame; when it passes the card
	turns green and moves on. `start` is what things looked like when the step began.
	Tutorial.STEPS is plain data so it can be tested headless.
]]
local Tutorial = {}

local function count(t) local n = 0 for _ in pairs(t or {}) do n += 1 end return n end
local function faces(st) return st.stats and st.stats.f or (st.meshInfo and st.meshInfo.f) or 0 end

Tutorial.STEPS = {
	{ title = "Add a cube", text = "Press Shift A (with the mouse over the 3D view), then Mesh > Cube. Or use Add in the header.",
		check = function(st, s0) return st.outlinerCount > s0.outlinerCount end },
	{ title = "Look around", text = "Drag with the middle mouse button to orbit (Shift = pan, wheel = zoom). The numpad keys snap to front / side / top.",
		check = function(st, s0) return st.camCF ~= s0.camCF end },
	{ title = "Edit Mode", text = "Press Tab with the cube selected. You're now editing its points, edges and faces.",
		check = function(st) return st.editing == true end },
	{ title = "Face select", text = "Press 3 for face select mode (1 = points, 2 = edges).",
		check = function(st) return st.editing == true and st.mode == "face" end },
	{ title = "Pick a face", text = "Click a face of the cube. It turns orange.",
		check = function(st) return st.editing == true and st.stats ~= nil and st.stats.fs >= 1 end },
	{ title = "Extrude", text = "Press E and move the mouse: the face pulls out with new sides. Click to finish.",
		check = function(st, s0) return st.editing == true and st.modal == nil and faces(st) > s0.faces end },
	{ title = "Inset", text = "Press I and move the mouse to make a smaller face inside the selected one. Click to finish.",
		check = function(st, s0) return st.editing == true and st.modal == nil and faces(st) > s0.faces end },
	{ title = "Loop Cut", text = "Press Ctrl R, point at an edge round the side and click: a new ring of edges goes all the way round. Click again to place it.",
		check = function(st, s0) return st.editing == true and st.modal == nil and faces(st) > s0.faces end },
	{ title = "Back to Object Mode", text = "Press Tab again. Your changes are kept on the part.",
		check = function(st) return st.editing ~= true end },
	{ title = "A modifier", text = "Press Ctrl 1 to add a Subdivision Surface modifier (it rounds the shape off). See it in Properties > the wrench tab.",
		check = function(st) return st.mods ~= nil and #st.mods > 0 end },
	{ title = "Save it to Roblox", text = "File > Save Mesh uploads it as a real mesh so it stays in the place (it needs the CreateAssetAsync beta). Skip this if you haven't set that up.",
		check = function(st) return st.saved == true end },
	{ title = "You're done!", text = "F3 searches every command, right click opens the menu for what's selected, and Help > Tutorial runs this again. Have fun!",
		check = function() return false end, last = true },
}

function Tutorial.snapshot(api)
	local st = api.state()
	st.outlinerCount = api.outliner and #api.outliner() or 0
	return st
end
function Tutorial.startOf(st)
	return { outlinerCount = st.outlinerCount or 0, camCF = st.camCF, faces = faces(st) }
end

function Tutorial.new(C)
	local T = { open = false, step = 1, start = nil, doneAt = nil }
	local card, title, body, stepLbl, back, skip
	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = parent
		return o
	end
	local function btn(parent, text, x, fn)
		local b = mk("TextButton", { Size = UDim2.fromOffset(60, 20), Position = UDim2.new(1, x, 1, -26), BackgroundColor3 = Color3.fromRGB(84, 84, 84), BorderSizePixel = 0,
			Text = text, Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Color3.fromRGB(230, 230, 230), ZIndex = 61 }, parent)
		mk("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
		b.Activated:Connect(fn)
		return b
	end
	local function build()
		local st = C.get()
		local gui = st.ui and st.ui.gui
		if not gui then return false end
		card = mk("Frame", { Name = "RB_Tutorial", Size = UDim2.fromOffset(310, 128), Position = UDim2.new(0, 60, 1, -190), BackgroundColor3 = Color3.fromRGB(40, 40, 46),
			BorderSizePixel = 0, ZIndex = 60, Active = true }, gui)
		mk("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
		mk("UIStroke", { Color = Color3.fromRGB(71, 114, 179), Thickness = 2 }, card)
		stepLbl = mk("TextLabel", { Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 6), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10,
			TextColor3 = Color3.fromRGB(150, 160, 180), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 61, Text = "" }, card)
		title = mk("TextLabel", { Name = "RB_TutorialTitle", Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 20), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
			TextSize = 14, TextColor3 = Color3.fromRGB(240, 240, 240), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 61, Text = "" }, card)
		body = mk("TextLabel", { Size = UDim2.new(1, -20, 0, 54), Position = UDim2.fromOffset(10, 40), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12,
			TextColor3 = Color3.fromRGB(205, 205, 210), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 61, Text = "" }, card)
		back = btn(card, "Back", -200, function() T.go(T.step - 1) end)
		skip = btn(card, "Skip", -134, function() T.go(T.step + 1) end)
		btn(card, "Close", -68, function() T.close() end)
		return true
	end
	local function show()
		local s = Tutorial.STEPS[T.step]
		if not (card and s) then return end
		stepLbl.Text = ("TUTORIAL  %d / %d"):format(T.step, #Tutorial.STEPS)
		title.Text = s.title
		body.Text = s.text
		card.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
		back.Visible = T.step > 1
		skip.Text = s.last and "Restart" or "Skip"
	end
	function T.go(i)
		if i > #Tutorial.STEPS then i = 1 end
		T.step = math.clamp(i, 1, #Tutorial.STEPS)
		T.start = Tutorial.startOf(Tutorial.snapshot(C.api))
		T.doneAt = nil
		show()
	end
	function T.openTutorial()
		if not card then if not build() then return end end
		card.Visible = true
		T.open = true
		T.go(1)
	end
	function T.close()
		T.open = false
		if card then card.Visible = false end
	end
	function T.toggle() if T.open then T.close() else T.openTutorial() end end
	-- every frame: has the current step been done?
	function T.tick(now)
		if not T.open then return end
		local s = Tutorial.STEPS[T.step]
		if not s or s.last then return end
		if T.doneAt then
			if now - T.doneAt > 0.6 then T.go(T.step + 1) end
			return
		end
		local ok, done = pcall(function() return s.check(Tutorial.snapshot(C.api), T.start) end)
		if ok and done then
			T.doneAt = now
			if card then card.BackgroundColor3 = Color3.fromRGB(38, 92, 52) title.Text = "Done: " .. s.title end
		end
	end
	return T
end

return Tutorial
