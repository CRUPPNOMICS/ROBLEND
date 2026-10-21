-- the MeshKeeper module's source, for putting a copy in the game (ReplicatedStorage.MeshKeeper)
return [====[-- MeshKeeper v1 - made by PROTO / ROBLEND (CRUPPNOMICS). Free to use and change.
-- Plugins installed from the Creator Store aren't allowed to upload meshes to Roblox. So instead, the plugin keeps each
-- mesh IN THE PLACE as data (a "MeshKeeperData" folder inside the part, tagged "MeshKeeper"), and this module builds the
-- real mesh again when the game runs (on the server for collisions, on each player for what they see) - and in Studio
-- when the place is opened.
-- Needs: Game Settings > Security > "Allow Mesh / Image APIs" ON (Creator Dashboard > Configure > Settings, "Enable
-- Mesh / Image APIs"). Without it Roblox won't let the game build meshes.
local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local M = {}
M.VERSION = 4
M.TAG = "MeshKeeper"
M.DATA = "MeshKeeperData"
M.CHUNK = 100000   -- characters per StringValue

-- ===== base64 (binary-safe text for the place file) =====
local A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
	local c = string.byte(A, i)
	ENC[i - 1] = c
	DEC[c] = i - 1
end
function M.toB64(b)
	local n = buffer.len(b)
	local out = buffer.create(math.ceil(n / 3) * 4)
	local o = 0
	local i = 0
	while i + 2 < n do
		local v = buffer.readu8(b, i) * 65536 + buffer.readu8(b, i + 1) * 256 + buffer.readu8(b, i + 2)
		buffer.writeu8(out, o, ENC[bit32.rshift(v, 18)])
		buffer.writeu8(out, o + 1, ENC[bit32.band(bit32.rshift(v, 12), 63)])
		buffer.writeu8(out, o + 2, ENC[bit32.band(bit32.rshift(v, 6), 63)])
		buffer.writeu8(out, o + 3, ENC[bit32.band(v, 63)])
		i += 3
		o += 4
	end
	local r = n - i
	if r > 0 then
		local v = buffer.readu8(b, i) * 65536 + ((r == 2) and buffer.readu8(b, i + 1) * 256 or 0)
		buffer.writeu8(out, o, ENC[bit32.rshift(v, 18)])
		buffer.writeu8(out, o + 1, ENC[bit32.band(bit32.rshift(v, 12), 63)])
		buffer.writeu8(out, o + 2, (r == 2) and ENC[bit32.band(bit32.rshift(v, 6), 63)] or 61)
		buffer.writeu8(out, o + 3, 61)
	end
	return buffer.tostring(out)
end
function M.fromB64(s)
	local n = #s
	local pad = 0
	if n >= 1 and string.byte(s, n) == 61 then pad += 1 end
	if n >= 2 and string.byte(s, n - 1) == 61 then pad += 1 end
	local out = buffer.create(math.floor(n / 4) * 3 - pad)
	local src = buffer.fromstring(s)
	local o = 0
	for i = 0, n - 4, 4 do
		local a = DEC[buffer.readu8(src, i)] or 0
		local b = DEC[buffer.readu8(src, i + 1)] or 0
		local c = DEC[buffer.readu8(src, i + 2)] or 0
		local d = DEC[buffer.readu8(src, i + 3)] or 0
		local v = a * 262144 + b * 4096 + c * 64 + d
		if o < buffer.len(out) then buffer.writeu8(out, o, bit32.rshift(v, 16)) end
		if o + 1 < buffer.len(out) then buffer.writeu8(out, o + 1, bit32.band(bit32.rshift(v, 8), 255)) end
		if o + 2 < buffer.len(out) then buffer.writeu8(out, o + 2, bit32.band(v, 255)) end
		o += 3
	end
	return out
end

-- ===== mesh <-> data =====
-- format 1: "MK1" | u32 nV, nUV, nN, nC, nF | nV x f32 xyz | nUV x f32 uv | nN x f32 xyz | nC x u8 rgba |
--           nF x (u32 v1 v2 v3, u32 uv1 uv2 uv3, u32 n1 n2 n3, u32 c1 c2 c3)   (0 = none, else 1-based)
local NONE = 0
-- everything an EditableMesh holds that shows: points, UVs, normals, colours, triangles
function M.pack(em)
	local vIds, uvIds, nIds, cIds = {}, {}, {}, {}
	local verts, uvs, nrms, cols = {}, {}, {}, {}
	local function idx(map, list, id)
		if id == nil then return NONE end
		local k = map[id]
		if not k then
			list[#list + 1] = id
			k = #list
			map[id] = k
		end
		return k
	end
	local faces = {}
	for _, f in ipairs(em:GetFaces()) do
		local fv = em:GetFaceVertices(f)
		if #fv == 3 then
			local fu, fn, fc = {}, {}, {}
			pcall(function() fu = em:GetFaceUVs(f) or {} end)
			pcall(function() fn = em:GetFaceNormals(f) or {} end)
			pcall(function() fc = em:GetFaceColors(f) or {} end)
			faces[#faces + 1] = {
				idx(vIds, verts, fv[1]), idx(vIds, verts, fv[2]), idx(vIds, verts, fv[3]),
				idx(uvIds, uvs, fu[1]), idx(uvIds, uvs, fu[2]), idx(uvIds, uvs, fu[3]),
				idx(nIds, nrms, fn[1]), idx(nIds, nrms, fn[2]), idx(nIds, nrms, fn[3]),
				idx(cIds, cols, fc[1]), idx(cIds, cols, fc[2]), idx(cIds, cols, fc[3]),
			}
		end
	end
	local nV, nU, nN, nC, nF = #verts, #uvs, #nrms, #cols, #faces
	local b = buffer.create(3 + 20 + nV * 12 + nU * 8 + nN * 12 + nC * 4 + nF * 48)
	buffer.writestring(b, 0, "MK1")
	local o = 3
	for _, n in ipairs({ nV, nU, nN, nC, nF }) do buffer.writeu32(b, o, n) o += 4 end
	for _, id in ipairs(verts) do
		local p = em:GetPosition(id)
		buffer.writef32(b, o, p.X) buffer.writef32(b, o + 4, p.Y) buffer.writef32(b, o + 8, p.Z)
		o += 12
	end
	for _, id in ipairs(uvs) do
		local u = em:GetUV(id)
		buffer.writef32(b, o, u.X) buffer.writef32(b, o + 4, u.Y)
		o += 8
	end
	for _, id in ipairs(nrms) do
		local n = em:GetNormal(id)
		buffer.writef32(b, o, n.X) buffer.writef32(b, o + 4, n.Y) buffer.writef32(b, o + 8, n.Z)
		o += 12
	end
	for _, id in ipairs(cols) do
		local c = em:GetColor(id)
		local a = 1
		pcall(function() a = em:GetColorAlpha(id) end)
		buffer.writeu8(b, o, math.clamp(math.floor(c.R * 255 + 0.5), 0, 255))
		buffer.writeu8(b, o + 1, math.clamp(math.floor(c.G * 255 + 0.5), 0, 255))
		buffer.writeu8(b, o + 2, math.clamp(math.floor(c.B * 255 + 0.5), 0, 255))
		buffer.writeu8(b, o + 3, math.clamp(math.floor(a * 255 + 0.5), 0, 255))
		o += 4
	end
	for _, f in ipairs(faces) do
		for k = 1, 12 do buffer.writeu32(b, o, f[k]) o += 4 end
	end
	return M.toB64(b), nF
end
-- data -> a new EditableMesh (nil, why if it can't)
function M.build(s)
	local b = M.fromB64(s)
	if buffer.len(b) < 23 or buffer.readstring(b, 0, 3) ~= "MK1" then return nil, "not MeshKeeper data" end
	local o = 3
	local cnt = {}
	for k = 1, 5 do cnt[k] = buffer.readu32(b, o) o += 4 end
	local nV, nU, nN, nC, nF = cnt[1], cnt[2], cnt[3], cnt[4], cnt[5]
	local em = AssetService:CreateEditableMesh()
	if not em then return nil, "Roblox wouldn't make a mesh (Allow Mesh / Image APIs off, or out of mesh memory)" end
	local V, Uv, N, C = {}, {}, {}, {}
	for i = 1, nV do
		V[i] = em:AddVertex(Vector3.new(buffer.readf32(b, o), buffer.readf32(b, o + 4), buffer.readf32(b, o + 8)))
		o += 12
	end
	for i = 1, nU do
		Uv[i] = em:AddUV(Vector2.new(buffer.readf32(b, o), buffer.readf32(b, o + 4)))
		o += 8
	end
	for i = 1, nN do
		N[i] = em:AddNormal(Vector3.new(buffer.readf32(b, o), buffer.readf32(b, o + 4), buffer.readf32(b, o + 8)))
		o += 12
	end
	for i = 1, nC do
		C[i] = em:AddColor(Color3.fromRGB(buffer.readu8(b, o), buffer.readu8(b, o + 1), buffer.readu8(b, o + 2)), buffer.readu8(b, o + 3) / 255)
		o += 4
	end
	for _ = 1, nF do
		local f = {}
		for k = 1, 12 do f[k] = buffer.readu32(b, o) o += 4 end
		local fid = em:AddTriangle(V[f[1]], V[f[2]], V[f[3]])
		if f[4] ~= NONE and f[5] ~= NONE and f[6] ~= NONE then pcall(function() em:SetFaceUVs(fid, { Uv[f[4]], Uv[f[5]], Uv[f[6]] }) end) end
		if f[7] ~= NONE and f[8] ~= NONE and f[9] ~= NONE then pcall(function() em:SetFaceNormals(fid, { N[f[7]], N[f[8]], N[f[9]] }) end) end
		if f[10] ~= NONE and f[11] ~= NONE and f[12] ~= NONE then pcall(function() em:SetFaceColors(fid, { C[f[10]], C[f[11]], C[f[12]] }) end) end
	end
	return em
end

-- ===== kept in the place =====
function M.read(part)
	local f = part:FindFirstChild(M.DATA)
	if not f then return nil end
	local bits = {}
	for _, v in ipairs(f:GetChildren()) do
		if v:IsA("StringValue") then
			local i = tonumber(v.Name)
			if i then bits[i] = v.Value end
		end
	end
	return table.concat(bits)
end
-- (plugins) keep this mesh on the part as data + tag it
function M.write(part, s)
	local old = part:FindFirstChild(M.DATA)
	if old then old.Parent = nil end
	local f = Instance.new("Folder")
	f.Name = M.DATA
	f:SetAttribute("v", M.VERSION)
	local i = 0
	for at = 1, #s, M.CHUNK do
		i += 1
		local v = Instance.new("StringValue")
		v.Name = tostring(i)
		v.Value = string.sub(s, at, at + M.CHUNK - 1)
		v.Parent = f
	end
	f.Parent = part
	CollectionService:AddTag(part, M.TAG)
end
-- (plugins) the part's mesh changed - forget the kept copy
function M.forget(part)
	local f = part:FindFirstChild(M.DATA)
	if f then f.Parent = nil end
	pcall(function() CollectionService:RemoveTag(part, M.TAG) end)
end

-- ===== putting the mesh on a part =====
-- v2: each player may only hold ~8 live EditableMeshes (Roblox's client memory budget). So once a mesh is on its part,
-- its EditableMesh is freed (FREE = true) - the part should keep the shape. If a game shows blank parts with this, set
-- the module's attribute FreeAfterApply = false (then only ~8 meshes can show per player).
M.FREE = false   -- (v4: freeing it loses the shape - tested 21 Oct; keep it, ~8 meshes per player)
local cache = {}   -- same data + same collision = one mesh shared by every part that uses it (less memory)
local warned = false
function M.apply(part)
	if not (part and part:IsA("MeshPart")) then return false end
	local s = M.read(part)
	if not s or s == "" then return false end
	local fid = part.CollisionFidelity
	local key = s .. "|" .. tostring(fid)
	local free = M.FREE
	pcall(function()
		local mod = script
		if mod and mod:GetAttribute("FreeAfterApply") ~= nil then free = mod:GetAttribute("FreeAfterApply") == true end
	end)
	if M.noShare then free = false end   -- (Studio: the plugins keep editing it)
	local tpl = (not M.noShare and not free) and cache[key] or nil
	if not tpl then
		local em, why = M.build(s)
		if not em then
			if not warned then warned = true warn("MeshKeeper: " .. tostring(why) .. " - turn on Game Settings > Security > Allow Mesh / Image APIs.") end
			return false
		end
		local ok, mp = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromObject(em), { CollisionFidelity = fid })
		end)
		if not ok or not mp then
			if not warned then warned = true warn("MeshKeeper: couldn't make the mesh part - " .. tostring(mp)) end
			return false
		end
		tpl = { em = em, mp = mp }
		if not M.noShare and not free then cache[key] = tpl end
	end
	local okA, err = pcall(function() part:ApplyMesh(tpl.mp) end)
	if okA then
		if free then
			-- the shape is on the part now: give the memory back so the next mesh fits in the budget
			pcall(function() tpl.mp:Destroy() end)
			pcall(function() tpl.em:Destroy() end)
		end
		return true
	end
	-- (no ApplyMesh: a copy of the built part takes this one's place - same look, place, children)
	local okS, err2 = pcall(function()
		local np = tpl.mp:Clone()
		for _, k in ipairs({ "Name", "Size", "CFrame", "Color", "Material", "MaterialVariant", "Transparency", "Reflectance", "Anchored",
			"CanCollide", "CanQuery", "CanTouch", "CastShadow", "Massless", "CollisionGroup", "Locked", "TextureID" }) do
			pcall(function() np[k] = part[k] end)
		end
		for k, v in pairs(part:GetAttributes()) do np:SetAttribute(k, v) end
		for _, ch in ipairs(part:GetChildren()) do ch.Parent = np end
		np.Parent = part.Parent
		part.Parent = nil
	end)
	if not okS then warn("MeshKeeper: couldn't put the mesh on " .. part:GetFullName() .. " - " .. tostring(err) .. " / " .. tostring(err2)) return false end
	return true
end
-- every kept part now (onlyMissing = skip parts that already show a live mesh - Studio)
function M.applyAll(onlyMissing)
	local n = 0
	for _, p in ipairs(CollectionService:GetTagged(M.TAG)) do
		local skip = false
		if onlyMissing then
			pcall(function()
				local mc = p.MeshContent
				skip = mc.SourceType == Enum.ContentSourceType.Object
			end)
		end
		if not skip and M.apply(p) then n += 1 end
	end
	return n
end
-- the game: every kept part, now and as they stream in. v3: ONE AT A TIME (a queue) and each part once - building
-- several at the same time held several meshes in memory together and ran past the players' mesh budget.
local started = false
local queue, queued, done = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local running = false
local function pump()
	if running then return end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local p = table.remove(queue, 1)
			queued[p] = nil
			if p.Parent and not done[p] then
				if not p:FindFirstChild(M.DATA) then p:WaitForChild(M.DATA, 10) end
				local ok, applied = pcall(M.apply, p)
				if ok and applied then done[p] = true end
				task.wait()   -- (let Roblox take the freed memory back before the next one)
			end
		end
		running = false
	end)
end
function M.queue(p)
	if not (p and p:IsA("MeshPart")) or queued[p] or done[p] then return end
	queued[p] = true
	table.insert(queue, p)
	pump()
end
function M.start()
	if started then return end
	started = true
	CollectionService:GetInstanceAddedSignal(M.TAG):Connect(M.queue)
	for _, p in ipairs(CollectionService:GetTagged(M.TAG)) do M.queue(p) end
end
return M
]====]
