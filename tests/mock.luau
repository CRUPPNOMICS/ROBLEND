-- tiny Vector3 stand-in so the mesh engine can run outside Roblox (tests only)
local V = {}
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) if m == 0 then return t end return V.new(t.X / m, t.Y / m, t.Z / m) end
	return V[k]
end
function V.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
V.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return V.new(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return V.new(a.X * b, a.Y * b, a.Z * b) end
	return V.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return V.new(a.X / b, a.Y / b, a.Z / b) end
V.__unm = function(a) return V.new(-a.X, -a.Y, -a.Z) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V.__tostring = function(a) return string.format("%g, %g, %g", a.X, a.Y, a.Z) end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V.Cross(a, b) return V.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V.Lerp(a, b, t) return a + (b - a) * t end
function V.Min(a, b) return V.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end
function V.Max(a, b) return V.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end
Vector3 = { new = V.new, zero = V.new(0, 0, 0) }

-- just enough CFrame for MeshTools (rotation about an axis applied to a Vector3)
local CFm = {}
CFm.__mul = function(a, v)
	local axis, ang = a.axis, a.ang
	return v * math.cos(ang) + axis:Cross(v) * math.sin(ang) + axis * (axis:Dot(v) * (1 - math.cos(ang)))
end
CFrame = { fromAxisAngle = function(axis, ang) return setmetatable({ axis = axis.Unit, ang = ang }, CFm) end }

-- Color3 stand-in for engine tests (Vertex Paint)
Color3 = { new = function(r, g, b) return { R = r, G = g, B = b } end, fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }
