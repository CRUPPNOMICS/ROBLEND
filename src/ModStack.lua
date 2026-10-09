--[[
	ROBLEND - the modifier stack and UV / texture commands behind Properties > Modifiers, Material > Texture,
	the U menu and Ctrl 0-4 (Blender's object.modifier_add / modifier_apply / subdivision_set, uv projections).
	SPDX-License-Identifier: GPL-2.0-or-later
	Original: Copyright (C) Blender Authors. Luau conversion: Copyright (C) 2026 Cruppnomics (Giga_gad27).

	ModStack.install(api, C): adds api.mods / modAdd / modSet / modToggle / modRemove / modMove / modApply /
	subdivSet / setUV / setTexture. C = the shared context (Main.server.lua "ctx").
]]
local ModStack = {}

function ModStack.install(api, C)
	local NAME, Mods, MT, Display = C.NAME, C.Mods, C.MT, C.Display
	local setStatus, loadFrom, encode, dataOf, record = C.setStatus, C.loadFrom, C.encode, C.dataOf, C.record
	local modsOf, setMods, uvOf, modTarget, modsChanged = C.modsOf, C.setMods, C.uvOf, C.modTarget, C.modsChanged

	api.mods = function()
		local p = modTarget()
		if not p then return nil end
		return modsOf(p), p
	end
	api.modTypes = Mods.TYPES
	-- Ctrl 0..5 (Blender's Subdivision Set): add a Subdivision Surface modifier, or set its levels
	api.subdivSet = function(level)
		local p = modTarget()
		if not p then setStatus("Pick a " .. NAME .. " mesh first.") return end
		level = math.clamp(level, 0, 4)
		local list = modsOf(p)
		local idx
		for i, m in ipairs(list) do if m.type == "subsurf" then idx = i end end
		if idx then
			api.modSet(idx, "levels", level)
		else
			api.modAdd("subsurf")
			api.modSet(#modsOf(p), "levels", level)
		end
		setStatus(("Subdivision level %d."):format(level))
	end
	-- U menu / Material > Texture: UV projection + the image
	api.uvModes = Display.UV_MODES
	api.setUV = function(mode, scale)
		local p = modTarget()
		if not p then setStatus("Pick a " .. NAME .. " mesh first.") return end
		record("UV", function()
			if mode ~= nil then p:SetAttribute("RB_UVMode", mode ~= "" and mode or nil) end
			if scale then p:SetAttribute("RB_UVScale", math.max(scale, 0.01)) end
			modsChanged(p)
		end)
		local u = uvOf(p)
		setStatus(u and ("UVs: " .. u.mode .. (u.mode == "box" and (" (repeats every %g studs)"):format(u.scale) or "") .. ". Set a texture in Material > Texture.") or "UVs cleared.")
	end
	api.setTexture = function(id)
		local p = modTarget()
		if not p then return end
		id = tostring(id or "")
		if id:match("^%d+$") then id = "rbxassetid://" .. id end
		record("Texture", function()
			pcall(function() p.TextureID = id end)
			if id ~= "" and not uvOf(p) then p:SetAttribute("RB_UVMode", "boxfit") modsChanged(p) end
		end)
		C.dirtyCage()
		setStatus(id ~= "" and ("Texture set: " .. id .. (uvOf(p) and "" or "")) or "Texture cleared.")
	end
	local function modEdit(what, fn)
		local p = modTarget()
		if not p then setStatus("Pick a " .. NAME .. " part first.") return end
		local list = modsOf(p)
		local msg
		record(what, function()
			msg = fn(list, p)
			setMods(p, list)
			modsChanged(p)
		end)
		if msg then setStatus(msg) end
	end
	api.modAdd = function(id)
		local t = Mods.BY_ID[id]
		if not t then return end
		modEdit("add " .. t.name, function(list)
			local m = Mods.new(id)
			m.name = t.name
			list[#list + 1] = m
			return "Added " .. t.name .. " modifier."
		end)
	end
	api.modSet = function(i, key, value)
		modEdit("modifier", function(list) if list[i] then list[i][key] = value end end)
	end
	-- Boolean modifier: point it at the other selected part
	api.modTargetFromSelection = function(i)
		local p = modTarget()
		local other
		for _, q in ipairs(C.selectedParts()) do if q ~= p and q:IsA("BasePart") then other = q break end end
		if not other then setStatus("Shift click the other part too (keep this one active), then press this again.") return end
		api.modSet(i, "target", other.Name)
		setStatus(("The modifier now uses %s."):format(other.Name))
	end
	api.modToggle = function(i, key)
		modEdit("modifier", function(list)
			if list[i] then
				local cur = list[i][key]
				if cur == nil then cur = key == "on" or key == "edit" end
				list[i][key] = not cur
			end
		end)
	end
	api.modRemove = function(i)
		modEdit("remove modifier", function(list) local m = table.remove(list, i) return m and ("Removed " .. (m.name or m.type) .. ".") end)
	end
	api.modMove = function(i, d)
		modEdit("move modifier", function(list)
			local j = i + d
			if list[i] and list[j] then list[i], list[j] = list[j], list[i] end
		end)
	end
	api.modApply = function(i)
		local p = modTarget()
		if not p then return end
		local list = modsOf(p)
		local m = list[i]
		if not m then return end
		local S = C.get()
		if S.editing and p ~= S.obj then return end
		local base = (S.editing and p == S.obj) and S.bm or loadFrom(p)
		local one = table.clone(m)
		one.on = true
		local ok, res = pcall(Mods.evaluate, base, { one }, C.modEnv and C.modEnv(p))
		if not ok or not res then setStatus("Couldn't apply: " .. tostring(res)) return end
		if res == base then res = MT.fromSpec(MT.toSpec(base)) end
		record("apply " .. (m.name or m.type), function()
			table.remove(list, i)
			setMods(p, list)
			local val = encode(res)
			if S.editing and p == S.obj then C.replaceEdited(res, val) end
			dataOf(p).Value = val
			modsChanged(p)
		end)
		setStatus("Applied " .. (m.name or m.type) .. (i > 1 and " (it wasn't first in the stack, so the result may differ)." or "."))
	end
end

return ModStack
