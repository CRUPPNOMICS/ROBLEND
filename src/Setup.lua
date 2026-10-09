--[[
	ROBLEND - "Before you start": ROBLEND needs two things switched on, and this screen checks them itself.
	  1. Mesh / Image APIs for this game (Game Settings > Security) - without it Roblox won't let any plugin make meshes.
	  2. Studio's "CreateAssetAsync Luau API" beta (File > Beta Features) - saving meshes to Roblox needs it.
	Until both are on, the screen covers ROBLEND; when they are, Start lets you in.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	Setup.new(C) -> S ; S.ready() / S.open() / S.close() / S.check() ; S.onDone = fn
]]
local Setup = {}

function Setup.new(C)
	local S = { isOpen = false, mesh = false, beta = false, onDone = nil }
	local AssetService = C.AssetService
	local overlay, card, rows, startBtn, note

	-- the beta: the method only exists when it's switched on (Studio has to be restarted after ticking it)
	function S.checkBeta()
		local ok, has = pcall(function() return AssetService.CreateAssetAsync ~= nil end)
		S.beta = ok and has == true
		return S.beta
	end
	-- Mesh / Image APIs: try to make (and free) a tiny editable mesh
	function S.checkMesh()
		local ok = pcall(function()
			local em = AssetService:CreateEditableMesh()
			if not em then error("no mesh") end
			pcall(function() em:Destroy() end)
		end)
		S.mesh = ok
		if S.onMesh then pcall(S.onMesh, ok) end
		return ok
	end
	function S.check()
		S.checkBeta()
		S.checkMesh()
		S.refresh()
		return S.mesh and S.beta
	end
	function S.ready() return S.check() end

	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		o.Parent = parent
		return o
	end
	local function text(parent, props)
		local d = { BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(215, 215, 220), TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 92, Text = "" }
		for k, v in pairs(props) do d[k] = v end
		return mk("TextLabel", d, parent)
	end
	local function button(parent, label, pos, size, col, fn)
		local b = mk("TextButton", { Position = pos, Size = size, BackgroundColor3 = col, BorderSizePixel = 0, AutoButtonColor = true, Font = Enum.Font.GothamMedium, TextSize = 13,
			TextColor3 = Color3.fromRGB(240, 240, 240), Text = label, ZIndex = 92 }, parent)
		mk("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
		b.Activated:Connect(fn)
		return b
	end
	local STEPS = {
		{ key = "mesh", title = "Mesh / Image APIs  (this game)",
			how = "Home tab > Game Settings > Security > turn on \"Allow Mesh / Image APIs\" > Save. Every game needs this once." },
		{ key = "beta", title = "CreateAssetAsync beta  (Studio)",
			how = "File > Beta Features > tick \"CreateAssetAsync Luau API\" > Save, then close and reopen Studio." },
	}
	local function build()
		local st = C.get()
		local gui = st.ui and st.ui.gui
		if not gui then return false end
		overlay = mk("Frame", { Name = "RB_Setup", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.35,
			BorderSizePixel = 0, ZIndex = 90, Active = true }, gui)
		-- (a big invisible button underneath, so clicks never reach ROBLEND behind the screen)
		mk("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 90, AutoButtonColor = false }, overlay)
		card = mk("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 330), BackgroundColor3 = Color3.fromRGB(36, 36, 42),
			BorderSizePixel = 0, ZIndex = 91, Active = true }, overlay)
		mk("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		mk("UIStroke", { Color = Color3.fromRGB(230, 180, 40), Thickness = 2 }, card)
		text(card, { Position = UDim2.fromOffset(22, 18), Size = UDim2.new(1, -44, 0, 26), Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = Color3.fromRGB(245, 245, 245),
			Text = "Before you start" })
		text(card, { Position = UDim2.fromOffset(22, 50), Size = UDim2.new(1, -44, 0, 36), TextColor3 = Color3.fromRGB(180, 180, 190),
			Text = "ROBLEND needs these two switched on. Turn them on, then press Check again - each one goes green when it's done." })
		rows = {}
		for i, s in ipairs(STEPS) do
			local y = 96 + (i - 1) * 84
			local row = mk("Frame", { Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, 74), BackgroundColor3 = Color3.fromRGB(28, 28, 33), BorderSizePixel = 0, ZIndex = 91 }, card)
			mk("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
			local badge = mk("TextLabel", { Name = "Badge", Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.fromRGB(165, 55, 55), BorderSizePixel = 0,
				Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = "X", ZIndex = 92 }, row)
			mk("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
			text(row, { Position = UDim2.fromOffset(50, 10), Size = UDim2.new(1, -60, 0, 18), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.fromRGB(240, 240, 240), Text = s.title })
			text(row, { Position = UDim2.fromOffset(50, 30), Size = UDim2.new(1, -60, 0, 40), TextSize = 12, Text = s.how })
			rows[s.key] = badge
		end
		note = text(card, { Position = UDim2.fromOffset(22, 268), Size = UDim2.new(1, -300, 0, 40), TextSize = 11, TextColor3 = Color3.fromRGB(150, 150, 160), Text = "" })
		button(card, "Check again", UDim2.new(1, -264, 1, -50), UDim2.fromOffset(116, 32), Color3.fromRGB(70, 70, 80), function() S.check() end)
		startBtn = button(card, "Start", UDim2.new(1, -138, 1, -50), UDim2.fromOffset(116, 32), Color3.fromRGB(46, 130, 70), function()
			if S.check() then S.close(true) end
		end)
		if st.ui.blockers then table.insert(st.ui.blockers, overlay) end
		return true
	end
	function S.refresh()
		if not card then return end
		for key, badge in pairs(rows) do
			local on = S[key] == true
			badge.Text = on and "OK" or "X"
			badge.TextSize = on and 11 or 15
			badge.BackgroundColor3 = on and Color3.fromRGB(46, 150, 80) or Color3.fromRGB(165, 55, 55)
		end
		local both = S.mesh and S.beta
		startBtn.BackgroundColor3 = both and Color3.fromRGB(46, 150, 80) or Color3.fromRGB(60, 60, 66)
		startBtn.TextColor3 = both and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(130, 130, 135)
		note.Text = both and "All set - press Start." or (not S.beta and "The beta only shows up after Studio is restarted." or "")
	end
	function S.open()
		if not card then if not build() then return end end
		overlay.Visible = true
		S.isOpen = true
		S.refresh()
	end
	function S.close(done)
		S.isOpen = false
		if overlay then overlay.Visible = false end
		if done and S.onDone then pcall(S.onDone) end
	end
	-- every couple of seconds while it's open: the beta check is free (the mesh one only runs on Check again,
	-- because Studio prints a warning each time it's refused)
	function S.tick(now)
		if not S.isOpen then return end
		if not S.lastTick or now - S.lastTick > 2 then
			S.lastTick = now
			local was = S.beta
			if S.checkBeta() ~= was then S.refresh() end
		end
	end
	return S
end

return Setup
