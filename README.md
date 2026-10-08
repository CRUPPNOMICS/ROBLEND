# ROBLENDER

A free, open-source mesh editor for Roblox Studio, with Blender-style edit mode.
The mesh engine is Blender's BMesh, converted to Luau and cut down to fit a Roblox plugin.

> ROBLENDER is not made, endorsed or supported by the Blender Foundation. "Blender" is a trademark of the Blender Foundation.

## Install

**From a release file**
1. Download `ROBLENDER.rbxmx`.
2. Put it in your Studio plugins folder (Studio: *Plugins > Plugins Folder*).
3. Restart Studio.

**From source** (needs Python 3)

```
python3 tools/build.py   # makes build/ROBLENDER.rbxmx
```

Your place must allow the Mesh / Image APIs: *Game Settings > Security > Allow Mesh / Image APIs*.

## Use

1. Open the panel from the ROBLENDER toolbar button and add a shape (Cube, Plane, Grid, Cylinder, Sphere, Circle).
2. With the part selected, press **Tab** (or click **Edit**) to start editing it.
3. Press **Tab** again when you're done.

| Key | What it does |
|---|---|
| 1 / 2 / 3 | Vertex / edge / face mode |
| Click, Shift-click, drag a box | Select (Ctrl+drag takes things out of the selection) |
| Alt-click | Select an edge loop |
| A, Alt+A, Ctrl+I | Select all, select none, invert |
| G / S / R | Move / scale / rotate. Then: X Y Z to lock to an axis, type a number, hold Ctrl to snap. Click or Enter confirms; Esc or right-click cancels. |
| E | Extrude. In face mode it moves along the normal. |
| I | Inset |
| Ctrl+R | Loop cut |
| X / Delete | Delete |
| M | Merge at the centre |
| F | Fill |
| Alt+Z | X-ray |
| Ctrl+Z | Undo. Every edit is one Studio undo step. |

Studio's own camera keys (W A S D Q E) still move the camera, so tap those keys quickly. The panel buttons do the same jobs.

## Saving

The mesh data is stored on the part (`RB_Data`), and editing the part again brings the mesh back.
Roblox doesn't yet save meshes that a plugin makes into the place file. To keep a model permanently, use one of these:
- **Bake to parts**: builds a copy out of normal wedge parts.
- **Export .obj**: then bring the file in with the 3D Importer.

## What's in it

| Path | What it holds |
|---|---|
| `src/BMesh.lua` | The mesh structure: verts, edges, loops and faces, with disk and radial cycles. Also the Euler ops (from `bmesh_core.cc` and `bmesh_structure.cc`). |
| `src/Ops.lua` | Primitives, extrude, inset, edge ring and loop cut, subdivide, delete, merge, fill. |
| `src/Display.lua` | Triangulation, the EditableMesh view, bake to parts, OBJ export. |
| `src/Main.server.lua` | The plugin: panel, picking, the selection cage, and the modal tools. |
| `tests/` | Headless tests: the engine, plus the whole editor running in a fake Studio. Run `python3 tools/test.py path/to/luau`. |

## Licence

GPL-2.0-or-later (see `LICENSE`), the same as Blender, which this code is converted from.
You may use, change and share it, including selling it. If you pass it on, changed or not, you must:
- keep it under the GPL
- keep the copyright notices
- make the source available

See `CREDITS.md`.
