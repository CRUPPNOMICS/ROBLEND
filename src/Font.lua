--[[
	ROBLEND - 3D text (Add > Text): a chunky 5 x 7 block font, built as a closed, extruded mesh.
	(Blender's text objects use outline fonts; this blocky font is ROBLEND's own, drawn for this plugin,
	to suit Roblox's look and keep the plugin small.)
	SPDX-License-Identifier: GPL-2.0-or-later
	Copyright (C) 2026 Cruppnomics (Giga_gad27).

	Font.build(bm, text, { pixel = studs per block, depth = studs, gap = blocks between letters })
	builds the text centred on (0, 0, 0), facing -Z (front) with the letters reading left to right along +X.
]]
local Font = {}
local V3 = Vector3.new

-- 7 rows each, top to bottom; "#" = a block
Font.GLYPHS = {
	A = { " ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #" },
	B = { "#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### " },
	C = { " ####", "#    ", "#    ", "#    ", "#    ", "#    ", " ####" },
	D = { "#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### " },
	E = { "#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####" },
	F = { "#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    " },
	G = { " ####", "#    ", "#    ", "#  ##", "#   #", "#   #", " ### " },
	H = { "#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #" },
	I = { "#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####" },
	J = { "  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  " },
	K = { "#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #" },
	L = { "#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####" },
	M = { "#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #" },
	N = { "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #" },
	O = { " ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " },
	P = { "#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    " },
	Q = { " ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #" },
	R = { "#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #" },
	S = { " ####", "#    ", "#    ", " ### ", "    #", "    #", "#### " },
	T = { "#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  " },
	U = { "#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### " },
	V = { "#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  " },
	W = { "#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #" },
	X = { "#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #" },
	Y = { "#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  " },
	Z = { "#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####" },
	["0"] = { " ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### " },
	["1"] = { "  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### " },
	["2"] = { " ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####" },
	["3"] = { "#### ", "    #", "    #", " ### ", "    #", "    #", "#### " },
	["4"] = { "   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # " },
	["5"] = { "#####", "#    ", "#### ", "    #", "    #", "#   #", " ### " },
	["6"] = { " ### ", "#    ", "#    ", "#### ", "#   #", "#   #", " ### " },
	["7"] = { "#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   " },
	["8"] = { " ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### " },
	["9"] = { " ### ", "#   #", "#   #", " ####", "    #", "    #", " ### " },
	["."] = { "     ", "     ", "     ", "     ", "     ", " ##  ", " ##  " },
	[","] = { "     ", "     ", "     ", "     ", " ##  ", "  #  ", " #   " },
	["!"] = { "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  " },
	["?"] = { " ### ", "#   #", "    #", "   # ", "  #  ", "     ", "  #  " },
	["-"] = { "     ", "     ", "     ", "#####", "     ", "     ", "     " },
	["+"] = { "     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     " },
	["="] = { "     ", "     ", "#####", "     ", "#####", "     ", "     " },
	[":"] = { "     ", " ##  ", " ##  ", "     ", " ##  ", " ##  ", "     " },
	["'"] = { "  #  ", "  #  ", "     ", "     ", "     ", "     ", "     " },
	['"'] = { " # # ", " # # ", "     ", "     ", "     ", "     ", "     " },
	["/"] = { "    #", "    #", "   # ", "  #  ", " #   ", "#    ", "#    " },
	["("] = { "   # ", "  #  ", " #   ", " #   ", " #   ", "  #  ", "   # " },
	[")"] = { " #   ", "  #  ", "   # ", "   # ", "   # ", "  #  ", " #   " },
	["#"] = { " # # ", " # # ", "#####", " # # ", "#####", " # # ", " # # " },
	["&"] = { " ##  ", "#  # ", "# #  ", " #   ", "# # #", "#  # ", " ## #" },
	["_"] = { "     ", "     ", "     ", "     ", "     ", "     ", "#####" },
	["<"] = { "   # ", "  #  ", " #   ", "#    ", " #   ", "  #  ", "   # " },
	[">"] = { " #   ", "  #  ", "   # ", "    #", "   # ", "  #  ", " #   " },
	["*"] = { "     ", "# # #", " ### ", "#####", " ### ", "# # #", "     " },
	["%"] = { "##   ", "##  #", "   # ", "  #  ", " #   ", "#  ##", "   ##" },
	["$"] = { "  #  ", " ####", "# #  ", " ### ", "  # #", "#### ", "  #  " },
	["@"] = { " ### ", "#   #", "# ###", "# # #", "# ###", "#    ", " ####" },
}

-- which blocks are lit: cells[x][y] (x across, y up), plus the size in blocks
function Font.cells(text, gap)
	gap = gap or 1
	text = tostring(text or ""):upper()
	local cells, x, w = {}, 0, 0
	local function lit(cx, cy) cells[cx] = cells[cx] or {} cells[cx][cy] = true end
	for ch in text:gmatch(".") do
		if ch == " " then
			x += 3 + gap
		else
			local g = Font.GLYPHS[ch] or Font.GLYPHS["?"]
			for row = 1, 7 do
				local line = g[row]
				for col = 1, 5 do if line:sub(col, col) == "#" then lit(x + col - 1, 7 - row) end end
			end
			x += 5 + gap
		end
		w = x - gap
	end
	return cells, math.max(w, 0), 7
end

-- build the text as one closed mesh: front + back faces for every block, sides only where a block has no
-- neighbour (shared corners are welded, so letters come out as solid pieces)
function Font.build(bm, text, opts)
	opts = opts or {}
	local px = opts.pixel or 0.5
	local depth = opts.depth or 1
	local cells, w, h = Font.cells(text, opts.gap)
	local ox, oy = -w * px / 2, -h * px / 2
	local verts = {}
	local function vert(ix, iy, iz)
		local k = ix .. "," .. iy .. "," .. iz
		if not verts[k] then verts[k] = bm:vertCreate(V3(ox + ix * px, oy + iy * px, (iz - 0.5) * depth)) end
		return verts[k]
	end
	local function on(x, y) return cells[x] ~= nil and cells[x][y] == true end
	local made = {}
	local function face(a, b, c, d) local f = bm:faceCreate({ a, b, c, d }) if f then made[#made + 1] = f end end
	for x, col in pairs(cells) do
		for y in pairs(col) do
			-- front (-Z) and back (+Z), wound to face out
			face(vert(x, y, 0), vert(x, y + 1, 0), vert(x + 1, y + 1, 0), vert(x + 1, y, 0))
			face(vert(x, y, 1), vert(x + 1, y, 1), vert(x + 1, y + 1, 1), vert(x, y + 1, 1))
			if not on(x - 1, y) then face(vert(x, y, 0), vert(x, y, 1), vert(x, y + 1, 1), vert(x, y + 1, 0)) end
			if not on(x + 1, y) then face(vert(x + 1, y, 0), vert(x + 1, y + 1, 0), vert(x + 1, y + 1, 1), vert(x + 1, y, 1)) end
			if not on(x, y - 1) then face(vert(x, y, 0), vert(x + 1, y, 0), vert(x + 1, y, 1), vert(x, y, 1)) end
			if not on(x, y + 1) then face(vert(x, y + 1, 0), vert(x, y + 1, 1), vert(x + 1, y + 1, 1), vert(x + 1, y + 1, 0)) end
		end
	end
	bm:normalsUpdate()
	return made
end

return Font
