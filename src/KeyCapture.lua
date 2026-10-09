--[[
	ROBLEND - keeps Studio's own shortcuts (1 2 3 4 build tools, Ctrl D, Delete...) from firing while you work
	in the ROBLEND window: an invisible text box holds the keyboard, so Studio sees typing instead of shortcuts,
	and ROBLEND still reads every key.
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	KeyCapture.new(C) -> K
	  K.grab()      take the keyboard (called when the mouse moves / clicks in our 3D view)
	  K.release()   give it back (window closed, or switched off)
	  K.isOurs(tb)  is this focused text box ours? (Main still reads keys then)
	  K.noteKey()   Main calls this for every key it receives: if the box gets typed into but no key arrives,
	                Studio isn't passing keys through, so blocking switches itself off (keys keep working)
	Setting: plugin setting RB_BlockStudioKeys (default on), Edit > Block Studio Shortcuts.
]]
local KeyCapture = {}

function KeyCapture.new(C)
	local K = { enabled = true, box = nil, lastKey = 0, failed = false }
	pcall(function()
		local v = C.plugin:GetSetting("RB_BlockStudioKeys")
		if v ~= nil then K.enabled = v == true end
	end)

	local function make()
		local st = C.get()
		local gui = st.ui and st.ui.gui
		if not gui then return nil end
		local b = Instance.new("TextBox")
		b.Name = "RB_KeyCapture"
		b.Size = UDim2.fromOffset(1, 1)
		b.Position = UDim2.fromOffset(-10, -10)
		b.BackgroundTransparency = 1
		b.TextTransparency = 1
		b.Text = ""
		b.ClearTextOnFocus = true
		b.TextEditable = true
		b.ZIndex = 0
		b.Parent = gui
		-- Enter / Escape / Tab make a text box let go: take it straight back (a click somewhere else doesn't)
		b.FocusLost:Connect(function(_, input)
			if K.enabled and not K.failed and input and input.UserInputType == Enum.UserInputType.Keyboard then
				task.defer(function() K.grab() end)
			end
		end)
		-- typing goes in here: throw it away, and check that the key also reached ROBLEND
		b:GetPropertyChangedSignal("Text"):Connect(function()
			if b.Text == "" then return end
			b.Text = ""
			local at = C.clock()
			task.delay(0.2, function()
				if K.enabled and not K.failed and K.lastKey < at - 0.5 then
					-- Studio isn't sending key presses to plugins while the box has focus: stop blocking
					K.failed = true
					K.release()
					C.setStatus("Couldn't block Studio's shortcuts on this Studio version, so they're back on (keys still work in ROBLEND).")
				end
			end)
		end)
		return b
	end

	function K.isOurs(tb) return tb ~= nil and tb == K.box end
	function K.noteKey() K.lastKey = C.clock() end
	function K.active()
		local ok, f = pcall(function() return C.UIS:GetFocusedTextBox() end)
		return ok and f ~= nil and f == K.box
	end
	function K.grab()
		if not K.enabled or K.failed then return end
		local st = C.get()
		if not (st.uiOn and st.ui and st.ui.gui) then return end
		-- never take the keyboard from a text box someone is typing in
		local ok, f = pcall(function() return C.UIS:GetFocusedTextBox() end)
		if not ok or (f ~= nil and f ~= K.box) then return end
		if f ~= nil and f == K.box then return end
		if not (K.box and K.box.Parent) then K.box = make() end
		if K.box then pcall(function() K.box:CaptureFocus() end) end
	end
	function K.release()
		if K.box and K.active() then pcall(function() K.box:ReleaseFocus() end) end
	end
	function K.setEnabled(on)
		K.enabled = on == true
		K.failed = false
		pcall(function() C.plugin:SetSetting("RB_BlockStudioKeys", K.enabled) end)
		if K.enabled then K.grab() else K.release() end
		C.setStatus(K.enabled and "Studio's own shortcuts are blocked while you work in ROBLEND." or "Studio's own shortcuts work again inside ROBLEND.")
	end
	return K
end

return KeyCapture
