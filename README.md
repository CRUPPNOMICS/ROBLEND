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

Click the **ROBLENDER** button in the Plugins tab. A Blender-style window opens over Studio:

| Part of the window | What's in it |
|---|---|
| Top bar | File, Edit and Help menus. The Layout tab is Object Mode and the Modeling tab is Edit Mode. |
| 3D view | ROBLENDER's own 3D view: Blender's grey background, the grid and axis lines. |
| 3D view header | Mode dropdown; View, Select, Add and Object / Mesh / Vertex / Edge / Face menus; X-Ray; Wireframe and Solid. |
| Tool strip | Select, Move, Rotate, Scale, Add Cube, Extrude, Inset, Loop Cut. Hover a tool for its tooltip. |
| Navigation gizmo | Click an axis ball to snap the view to it, or drag the gizmo to orbit. The buttons under it zoom, pan and frame everything. |
| Outliner | Every ROBLENDER mesh in the place. Click a row to select it; the eye hides or shows it. |
| Properties | Object tab: name, location, rotation, size. Data tab: mesh counts. Material tab: colour and material. Output tab: bake and export. |
| Status bar | Mouse hints and the last message. |

**Getting around the 3D view**

| Action | How |
|---|---|
| Orbit | Drag with the middle mouse button or the right mouse button. |
| Pan | Hold Shift and drag. |
| Zoom | Mouse wheel. |
| Snap to a view | Numpad 1, 3 or 7 (add Ctrl for the opposite side). |
| Frame selected | Numpad . |
| Frame everything | Home |
| Context menu | Right-click without dragging. |

Object Mode keys: G, R and S move, rotate and scale whole parts. X deletes. Shift D duplicates. A, Alt A and Ctrl I select all, none and invert.

The 3D view only shows ROBLENDER meshes. To edit in Studio's own 3D view instead, use **Edit > Use Studio's 3D View**.

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
| Shift A | Add menu. In Edit Mode it adds into the mesh. |
| N / T | Sidebar / tool strip |
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
| `src/UI.lua` | The Blender-style window: top bar, header and menus, tool strip, gizmo, Outliner, Properties, status bar. |
| `src/View.lua` | ROBLENDER's own 3D view: a ViewportFrame with its own camera, grid, lighting and the edit cage. |
| `src/Main.server.lua` | The plugin: picking, the selection cage, the modal tools and the keys. |
| `tests/` | Headless tests: the engine, plus the whole editor running in a fake Studio. Run `python3 tools/test.py path/to/luau`. |

## Licence

GPL-2.0-or-later (see `LICENSE`), the same as Blender, which this code is converted from.
You may use, change and share it, including selling it. If you pass it on, changed or not, you must:
- keep it under the GPL
- keep the copyright notices
- make the source available

See `CREDITS.md`.
