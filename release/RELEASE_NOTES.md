# ROBLEND 0.21.2

A free, open-source (GPL-2.0-or-later) Blender-style modelling plugin for Roblox Studio, by Cruppnomics.
ROBLEND is not affiliated with or endorsed by the Blender Foundation.

## Install

1. Download `ROBLEND.rbxmx` below.
2. Put it in your Studio plugins folder (Studio: Plugins > Plugins Folder) and restart Studio.
3. In your place: Game Settings > Security > allow Mesh / Image APIs. Saving meshes needs File > Beta Features > "CreateAssetAsync Luau API".

## New since 0.16

**0.21.2:** while you work in the ROBLEND window, Studio's own shortcuts (1 2 3 4 build tools, Ctrl D, Delete and so on) no longer fire; ROBLEND gets the keys. Ctrl Z / Ctrl Y still undo and redo. Edit > Block Studio Shortcuts turns it off.

**0.21.1:** the tutorial's Face select card shows which select mode you're in right now, and explains the number-row 3 vs the numpad 3.

**0.21: Tutorial**
- Help > Tutorial: step cards that wait for you to really do each thing (add a cube, look around, Edit Mode, face select, extrude, inset, loop cut, back to Object Mode, a modifier, saving). It opens by itself the first time.

**0.20: Knife, Bridge and three more modifiers**
- Knife: C = angle constraint (45 degree steps), Z = cut through to the back.
- Bridge Edge Loops: cuts (wheel), twist (T / Shift T) and smoothness (mouse) after bridging.
- Decimate now has Collapse (keep a ratio of the triangles) as well as Planar.
- New modifiers: Edge Split, Shrinkwrap (nearest surface point, nearest point, or project along normals onto another part).

**0.19: Real UVs**
- U > Unwrap: cut at the seams you mark, flattened keeping angles (conformal) and packed.
- U > Smart UV Project: no seams needed.
- U > UV Editor: the UVs over your texture; select, drag, G / S / R, pack, flip, rotate.

**0.18: Boolean**
- Object > Boolean > Difference / Union / Intersect between parts (cutters are used up; Ctrl Z brings them back).
- Boolean modifier: a live cut that follows the cutter part when you move it.
- Face > Intersect (Boolean) in Edit Mode.

**0.17: Edit anything, faster**
- Convert any Part, Wedge, Corner Wedge, Ball, Cylinder or MeshPart into a ROBLEND mesh: select it and press Tab (or Object > Convert to ROBLEND Mesh). MeshParts only open if you (or the experience) own the mesh.
- Moving points, sculpting and painting update the mesh in place instead of rebuilding it every frame.
- Properties > Object > Collision: collision and render detail (kept through edits), Can Collide, Anchored, Cast Shadow.

## Good to know

- Modifiers that use another part (Boolean, Shrinkwrap) find it by name: give it a name nothing else in the place uses.
- Unions can't be read by plugins, so they can't be converted.
- Unwrap on a closed shape with no seams falls back to Smart UV Project; mark seams (Edge > Mark Seam) for a proper unwrap.

## Licence

GPL-2.0-or-later. Portions are converted from Blender's source code (Copyright Blender Authors); see CREDITS.md and NOTICE in the repository. The plugin file contains the full source.
