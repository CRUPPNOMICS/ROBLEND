-- A small fake Roblox Studio so Main.server.lua can be smoke-tested outside Roblox (tests only).
-- Needs tests/mock.luau (Vector3) loaded first.
local V3 = Vector3.new

-- ===== Vector2 =====
local V2 = {}
V2.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y) return V2.new(t.X / m, t.Y / m) end
	return V2[k]
end
function V2.new(x, y) return setmetatable({ X = x or 0, Y = y or 0, __kind = "Vector2" }, V2) end
V2.__add = function(a, b) return V2.new(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return V2.new(a.X - b.X, a.Y - b.Y) end
V2.__mul = function(a, b) if type(b) == "number" then return V2.new(a.X * b, a.Y * b) end return V2.new(a.X * b.X, a.Y * b.Y) end
V2.__div = function(a, b) return V2.new(a.X / b, a.Y / b) end
function V2.Dot(a, b) return a.X * b.X + a.Y * b.Y end
V2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
Vector2 = { new = V2.new, zero = V2.new(0, 0) }

-- ===== CFrame (position + right / up / back columns) =====
local CF = {}
local function cfNew(p, r, u, b) return setmetatable({ p = p, r = r, u = u, b = b }, CF) end
CF.__index = function(t, k)
	if k == "Position" then return t.p end
	if k == "LookVector" then return -t.b end
	if k == "RightVector" then return t.r end
	if k == "UpVector" then return t.u end
	if k == "Rotation" then return cfNew(V3(), t.r, t.u, t.b) end
	return CF[k]
end
local function rot(t, v) return t.r * v.X + t.u * v.Y + t.b * v.Z end
local function irot(t, v) return V3(t.r:Dot(v), t.u:Dot(v), t.b:Dot(v)) end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then return cfNew(a.p + rot(a, b.p), rot(a, b.r), rot(a, b.u), rot(a, b.b)) end
	return a.p + rot(a, b)
end
CF.__add = function(a, v) return cfNew(a.p + v, a.r, a.u, a.b) end
function CF.VectorToWorldSpace(t, v) return rot(t, v) end
function CF.VectorToObjectSpace(t, v) return irot(t, v) end
function CF.PointToObjectSpace(t, v) return irot(t, v - t.p) end
function CF.PointToWorldSpace(t, v) return t * v end
function CF.Inverse(t)
	local r = V3(t.r.X, t.u.X, t.b.X)
	local u = V3(t.r.Y, t.u.Y, t.b.Y)
	local b = V3(t.r.Z, t.u.Z, t.b.Z)
	local inv = cfNew(V3(), r, u, b)
	inv.p = -rot(inv, t.p)
	return inv
end
function CF.ToOrientation(t)
	local x = math.asin(math.clamp(-t.b.Y, -1, 1))
	local y = math.atan2(t.b.X, t.b.Z)
	local z = math.atan2(t.r.Y, t.u.Y)
	return x, y, z
end
local I = function() return cfNew(V3(), V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1)) end
CFrame = {
	identity = I(),
	new = function(x, y, z)
		if x == nil then return I() end
		local p = type(x) == "number" and V3(x, y, z) or x
		local c = I()
		c.p = p
		return c
	end,
	lookAt = function(at, target, up)
		up = up or V3(0, 1, 0)
		local look = (target - at).Unit
		local r = look:Cross(up).Unit
		local u = r:Cross(look)
		return cfNew(at, r, u, -look)
	end,
	fromMatrix = function(p, vx, vy, vz)
		vz = vz or vx:Cross(vy)
		return cfNew(p, vx, vy, vz)
	end,
	fromOrientation = function(x, y, z)
		return CFrame.fromAxisAngle(V3(0, 1, 0), y) * CFrame.fromAxisAngle(V3(1, 0, 0), x) * CFrame.fromAxisAngle(V3(0, 0, 1), z)
	end,
	fromAxisAngle = function(axis, a)
		axis = axis.Unit
		local function R(v) -- Rodrigues
			return v * math.cos(a) + axis:Cross(v) * math.sin(a) + axis * (axis:Dot(v) * (1 - math.cos(a)))
		end
		return cfNew(V3(), R(V3(1, 0, 0)), R(V3(0, 1, 0)), R(V3(0, 0, 1)))
	end,
}

-- ===== small value types =====
Color3 = { new = function(r, g, b) return { R = r, G = g, B = b } end, fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = {
	new = function(a, b, c, d) return { a, b, c, d } end,
	fromScale = function(a, b) return { a, 0, b, 0 } end,
	fromOffset = function(a, b) return { 0, a, 0, b } end,
}
DockWidgetPluginGuiInfo = { new = function(...) return { ... } end }
Content = { fromObject = function(o) return { obj = o } end, fromAssetId = function(id) return { assetId = id } end, fromUri = function(u) return { uri = u } end }
MOCK_DEFER = {}
task = { delay = function(t, f, ...) local a = { ... } table.insert(MOCK_DEFER, function() f(table.unpack(a)) end) end, spawn = function(f, ...) f(...) end, wait = function() end, defer = function(f, ...) local a = { ... } table.insert(MOCK_DEFER, function() f(table.unpack(a)) end) end }
local enumCache = {}
Enum = setmetatable({}, { __index = function(_, cat)
	enumCache[cat] = enumCache[cat] or setmetatable({}, { __index = function(t, name)
		local e = { Name = name, EnumType = cat }
		rawset(t, name, e)
		return e
	end })
	return enumCache[cat]
end })

local realTypeof = typeof
typeof = function(x)
	if type(x) == "table" then
		local mt = getmetatable(x)
		if mt == getmetatable(V3()) then return "Vector3" end
		if mt == V2 then return "Vector2" end
		if mt == CF then return "CFrame" end
		if rawget(x, "__inst") then return "Instance" end
	end
	return realTypeof(x)
end

-- ===== signals =====
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ fns = {} }, Signal) end
function Signal:Connect(fn)
	local fns = self.fns
	fns[#fns + 1] = fn
	return { Disconnect = function() for i, f in ipairs(fns) do if f == fn then table.remove(fns, i) break end end end }
end
function Signal:Fire(...) for _, f in ipairs(table.clone(self.fns)) do f(...) end end

-- ===== instances =====
MOCK = { buttons = {}, warns = {}, opened = {} }
local Inst = {}
local SIGNALS = { Activated = true, Changed = true, Click = true, Deactivation = true, Button1Down = true, Button1Up = true, Button2Down = true, Move = true, MouseEnter = true, MouseLeave = true, FocusLost = true, MouseButton2Click = true, Unloading = true, Button2Up = true, WheelForward = true, WheelBackward = true, InputEnded = true, InputChanged = true, DescendantAdded = true, MouseButton1Down = true }
local function newInst(class)
	local o = { __inst = true, _p = { ClassName = class, Name = class }, _kids = {}, _attr = {}, _sig = {}, _psig = {} }
	return setmetatable(o, Inst)
end
Inst.__index = function(o, k)
	local m = rawget(Inst, k)
	if m then return m end
	if SIGNALS[k] then o._sig[k] = o._sig[k] or Signal.new() return o._sig[k] end
	local v = o._p[k]
	if v == nil then
		for _, c in ipairs(o._kids) do if c._p.Name == k then return c end end
	end
	return v
end
Inst.__newindex = function(o, k, v)
	if k == "Parent" then
		local old = o._p.Parent
		if old then for i, c in ipairs(old._kids) do if c == o then table.remove(old._kids, i) break end end end
		if v then table.insert(v._kids, o) end
	end
	local changed = o._p[k] ~= v
	o._p[k] = v
	if k == "Text" and o._p.ClassName == "TextButton" then MOCK.buttons[v] = o end
	if changed and o._psig[k] then o._psig[k]:Fire() end
end
function Inst.IsA(o, c)
	local cls = o._p.ClassName
	if cls == c then return true end
	if c == "BasePart" then return cls == "Part" or cls == "MeshPart" or cls == "WedgePart" or cls == "CornerWedgePart" or cls == "UnionOperation" end
	if c == "JointInstance" then return cls == "Weld" or cls == "Motor6D" end
	return false
end
function Inst.FindFirstChild(o, n) for _, c in ipairs(o._kids) do if c._p.Name == n then return c end end return nil end
function Inst.FindFirstChildOfClass(o, n) for _, c in ipairs(o._kids) do if c._p.ClassName == n then return c end end return nil end
function Inst.GetChildren(o) return table.clone(o._kids) end
function Inst.GetDescendants(o)
	local out = {}
	local function go(x) for _, c in ipairs(x._kids) do out[#out + 1] = c go(c) end end
	go(o)
	return out
end
function Inst.Destroy(o) o.Parent = nil end
function Inst.Clone(o)
	local c = newInst(o._p.ClassName)
	for k, v in pairs(o._p) do if k ~= "Parent" then c._p[k] = v end end
	for k, v in pairs(o._attr) do c._attr[k] = v end
	for _, k in ipairs(o._kids) do local kk = k:Clone() kk.Parent = c end
	return c
end
function Inst.SetAttribute(o, k, v) o._attr[k] = v end
function Inst.GetAttribute(o, k) return o._attr[k] end
function Inst.GetAttributes(o) return table.clone(o._attr) end
function Inst.GetPropertyChangedSignal(o, k) o._psig[k] = o._psig[k] or Signal.new() return o._psig[k] end
function Inst.ApplyMesh(o, mp)
	assert(o._p.ClassName == "MeshPart" and mp._p.ClassName == "MeshPart", "ApplyMesh needs MeshParts")
	o._p.MeshSize = mp._p.Size
	o._p.Mesh = mp._p.Mesh
	-- (worst case: the part takes the source's collision detail - ROBLEND must put the chosen one back)
	o._p.CollisionFidelity = mp._p.CollisionFidelity
	o._p.RenderFidelity = mp._p.RenderFidelity
end
Instance = { new = function(class) return newInst(class) end }

-- ===== services =====
local function svc(name) local s = newInst(name) return s end
workspace = svc("Workspace")
workspace.Name = "Workspace"
local terrain = newInst("Terrain")
terrain.Parent = workspace
local cam = newInst("Camera")
cam.CFrame = CFrame.lookAt(V3(14, 16, 22), V3(0, 4, 0))
cam.ViewportSize = V2.new(1200, 800)
cam.FieldOfView = 70
workspace.CurrentCamera = cam
local function focal() return (cam.ViewportSize.Y / 2) / math.tan(math.rad(cam.FieldOfView) / 2) end
function Inst.WorldToViewportPoint(c, wp)
	local p = c.CFrame:PointToObjectSpace(wp)
	local z = -p.Z
	local f = focal()
	if z <= 1e-6 then return V3(0, 0, z), false end
	local x = c.ViewportSize.X / 2 + p.X / z * f
	local y = c.ViewportSize.Y / 2 - p.Y / z * f
	return V3(x, y, z), x >= 0 and y >= 0 and x <= c.ViewportSize.X and y <= c.ViewportSize.Y
end
function Inst.Raycast() return nil end

local held = {}
MOCK.held = held
local UIS = svc("UserInputService")
UIS._sig.InputBegan = Signal.new()
SIGNALS.InputBegan = true
function Inst.IsKeyDown(_, k) return held[k.Name] == true end
function Inst.GetFocusedTextBox() return nil end
function Inst.IsFocused() return false end
function Inst.SetActive(o, on) o._p.ActiveState = on end

local RunService = svc("RunService")
SIGNALS.Heartbeat = true

local sel = {}
local Selection = svc("Selection")
function Inst.Get(o) if o == Selection then return table.clone(sel) end end
function Inst.Set(o, t) if o == Selection then sel = table.clone(t) end end

local CHS = svc("ChangeHistoryService")
MOCK.recordings = {}
function Inst.TryBeginRecording(_, n, d) local id = "rec" .. (#MOCK.recordings + 1) MOCK.recordings[#MOCK.recordings + 1] = d return id end
function Inst.FinishRecording() end
function Inst.SetWaypoint(_, n) MOCK.recordings[#MOCK.recordings + 1] = n end

-- JSON: real encoding (checks the data is plain), decode through a registry
local Http = svc("HttpService")
local reg = {}
local function enc(x)
	local t = type(x)
	if t == "number" then assert(x == x and x ~= math.huge and x ~= -math.huge, "bad number in JSON") return tostring(x) end
	if t == "string" then return string.format("%q", x) end
	if t == "boolean" then return tostring(x) end
	assert(t == "table" and getmetatable(x) == nil, "JSON can't hold a " .. typeof(x))
	local parts = {}
	if #x > 0 or next(x) == nil then
		for i, v in ipairs(x) do parts[i] = enc(v) end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	for k, v in pairs(x) do assert(type(k) == "string", "mixed table in JSON") parts[#parts + 1] = string.format("%q", k) .. ":" .. enc(v) end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end
local function deep(x) if type(x) ~= "table" then return x end local o = {} for k, v in pairs(x) do o[k] = deep(v) end return o end
function Inst.JSONEncode(_, x) local s = enc(x) reg[s] = deep(x) return s end
function Inst.JSONDecode(_, s) assert(reg[s], "unknown JSON") return deep(reg[s]) end

local CoreGui = svc("CoreGui")

-- EditableMesh + MeshPart
local Asset = svc("AssetService")
local EM = {}
EM.__index = EM
MOCK.emAlive = 0
function Inst.CreateEditableMesh() MOCK.emAlive += 1 return setmetatable({ v = {}, t = {}, c = 0, __kind = "EditableMesh" }, EM) end
function EM:AddVertex(p)
	assert(p.X == p.X and p.Y == p.Y and p.Z == p.Z, "NaN vertex sent to EditableMesh")
	self.v[#self.v + 1] = p
	return #self.v
end
function EM:AddTriangle(a, b, c)
	assert(self.v[a] and self.v[b] and self.v[c], "bad vert id")
	self.t[#self.t + 1] = { a, b, c }
	assert(#self.t <= 20000, "too many triangles")
	return #self.t
end
function EM:AddColor() self.c += 1 return self.c end
function EM:AddUV(p) assert(p.X == p.X and p.Y == p.Y, "NaN uv") self.uv = self.uv or {} self.uv[#self.uv + 1] = p return #self.uv end
function EM:SetFaceUVs(f, ids) assert(self.t[f] and #ids == 3, "face uvs") for _, i in ipairs(ids) do assert(self.uv[i], "bad uv id") end self.fuv = (self.fuv or 0) + 1 end
function EM:Destroy() if not self.destroyed then MOCK.emAlive -= 1 end self.destroyed = true end
function EM:SetFaceColors(f, cols) assert(self.t[f] and #cols == 3) end
-- reading a mesh back (Convert): ids are just the array indices
function EM:GetVertices() local o = {} for i in ipairs(self.v) do o[i] = i end return o end
function EM:GetPosition(i) return assert(self.v[i], "bad vert id") end
function EM:SetPosition(i, p) assert(self.v[i], "bad vert id") assert(p.X == p.X, "NaN") self.v[i] = p MOCK.setPositions = (MOCK.setPositions or 0) + 1 end
function EM:GetFaces() local o = {} for i in ipairs(self.t) do o[i] = i end return o end
function EM:GetFaceVertices(f) return table.clone(assert(self.t[f], "bad face id")) end
-- AssetService:CreateEditableMeshAsync(content): a copy of an uploaded mesh (MOCK.denyMesh = Roblox says no)
function Inst.CreateEditableMeshAsync(_, content)
	if MOCK.denyMesh then error("Failed to load asset: not allowed") end
	local src
	if content.obj then src = content.obj
	elseif content.assetId then src = MOCK.uploads[content.assetId - 900000] and MOCK.uploads[content.assetId - 900000].em
	elseif content.uri then local n = tonumber(content.uri:match("%d+$")) src = n and MOCK.uploads[n - 900000] and MOCK.uploads[n - 900000].em end
	assert(src, "unknown mesh")
	MOCK.emAlive += 1
	return setmetatable({ v = table.clone(src.v), t = table.clone(src.t), c = 0, __kind = "EditableMesh" }, EM)
end
MOCK.meshesMade = 0
MOCK.uploads = {}
-- EditableImage (the logo)
local EI = {}
EI.__index = EI
function Inst.CreateEditableImage(_, opts) return setmetatable({ size = opts.Size, __kind = "EditableImage" }, EI) end
function EI:WritePixelsBuffer(pos, size, buf) assert(buffer.len(buf) == size.X * size.Y * 4, "pixel buffer size") self.written = true end
function EI:Destroy() end
MOCK.imageUploads = 0
function Inst.CreateAssetAsync(_, em, assetType, params)
	if MOCK.noAssetApi then error("CreateAssetAsync is not enabled") end
	if assetType.Name == "Image" then
		assert(em.__kind == "EditableImage" and em.written, "uploads the logo image")
		MOCK.imageUploads += 1
		return Enum.CreateAssetResult.Success, 800001
	end
	assert(assetType.Name == "Mesh", "mesh asset")
	assert(em.__kind == "EditableMesh", "uploads an EditableMesh")
	MOCK.uploads[#MOCK.uploads + 1] = { em = em, params = params }
	return Enum.CreateAssetResult.Success, 900000 + #MOCK.uploads
end
function Inst.CreateMeshPartAsync(_, content, opts)
	if content.assetId then content = { obj = assert(MOCK.uploads[content.assetId - 900000], "unknown asset").em } end
	assert(content.obj, "content")
	local em = content.obj
	assert(#em.t > 0, "empty mesh")
	local lo, hi = V3(math.huge, math.huge, math.huge), V3(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(em.v) do
		lo = V3(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
		hi = V3(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
	end
	local c = (lo + hi) / 2
	assert(c.Magnitude < 1e-3, "mesh not centred on its box: " .. tostring(c))
	local mp = newInst("MeshPart")
	mp.Size = hi - lo
	mp.MeshSize = hi - lo
	mp.Mesh = em
	mp.CFrame = CFrame.new()
	mp.CollisionFidelity = opts and opts.CollisionFidelity or Enum.CollisionFidelity.Default
	mp.RenderFidelity = opts and opts.RenderFidelity or Enum.RenderFidelity.Automatic
	mp.CanCollide, mp.CastShadow = true, true
	MOCK.meshesMade += 1
	return mp
end

local Geo = svc("GeometryService")
function Inst.UnionAsync(_, first, rest)
	local u = newInst("UnionOperation")
	u.Size = first.Size
	u.CFrame = first.CFrame
	return { u }
end

local services = { Selection = Selection, UserInputService = UIS, RunService = RunService, ChangeHistoryService = CHS,
	HttpService = Http, CoreGui = CoreGui, AssetService = Asset, GeometryService = Geo, Workspace = workspace }
game = newInst("DataModel")
function Inst.GetService(_, n) return assert(services[n], "no service " .. n) end
MOCK.services = services

-- ===== plugin =====
plugin = newInst("Plugin")
local mouse = newInst("PluginMouse")
mouse.X, mouse.Y = 600, 400
MOCK.mouse = mouse
function Inst.CreateToolbar() return newInst("Toolbar") end
function Inst.CreateButton() local b = newInst("ToolbarButton") MOCK.toolbarButton = b return b end
function Inst.CreateDockWidgetPluginGui() return newInst("DockWidgetPluginGui") end
function Inst.GetMouse() return mouse end
function Inst.Activate(o) o._p.Active = true end
function Inst.IsActivated(o) return o._p.Active == true end
local settings = { RB_TutorialSeen = true } -- (the first-run tutorial is tested on its own)
function Inst.GetSetting(_, k) return settings[k] end
function Inst.SetSetting(_, k, v) settings[k] = v end
function Inst.Deactivate(o) o._p.Active = false end
function Inst.OpenScript(_, s) MOCK.opened[#MOCK.opened + 1] = s end
local origIndex = Inst.__index
Inst.__index = function(o, k)
	if k == "UnitRay" and o == mouse then
		local c = cam.CFrame
		local f = focal()
		local d = V3((mouse.X - cam.ViewportSize.X / 2) / f, -(mouse.Y - cam.ViewportSize.Y / 2) / f, -1)
		return { Origin = c.Position, Direction = c:VectorToWorldSpace(d).Unit }
	end
	return origIndex(o, k)
end

warn = function(...) local s = table.concat({ ... }, " ") MOCK.warns[#MOCK.warns + 1] = s print("WARN " .. s) end
script = newInst("Script")
