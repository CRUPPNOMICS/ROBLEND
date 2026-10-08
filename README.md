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
| Properties | Object tab: name, location, rotation, size. Modifiers tab (wrench): the modifier stack. Data tab: mesh counts. Material tab: colour and material. Output tab: bake and export. |
| Status bar | Mouse hints and the last message. |

**The Modeling tab (Edit Mode)**

The tool strip has Blender's Edit Mode tools. Click a tool, then **drag on the selection** to use it. A plain click still selects, and a drag that starts anywhere else box-selects, like Blender. Right-click a tool with a small corner mark to pick the other tools in its group.

| Group | Tools |
|---|---|
| Select and place | Select Box; Cursor (also Shift right-click) |
| Transform | Move, Rotate, Scale, Transform |
| Notes | Annotate; Measure |
| Add | Add Cube (drag the base, then the height) |
| Extrude | Extrude Region, Extrude Along Normals, Extrude Individual |
| Cutting | Inset Faces; Bevel; Loop Cut; Knife and Bisect; Poly Build |
| Reshaping | Spin; Smooth and Randomize; Edge Slide and Vertex Slide; Shrink/Fatten and Push/Pull; Shear and To Sphere |
| Rip | Rip Region and Rip Edge |

The header menus (Mesh, Vertex, Edge, Face) follow Blender's own menu lists:

| Menu | What's in it |
|---|---|
| Mesh | Transform, Mirror, Snap, Duplicate, Extrude, Merge, Split, Separate, Bisect, Knife, Convex Hull, Symmetrize, Normals, Shading (smooth or flat), Show/Hide, Clean Up, Delete |
| Vertex | Extrude, Bevel Vertices, New Edge/Face, Connect Vertex Pairs, Rip, Slide, Smooth |
| Edge | Extrude, Bevel Edges, Bridge Edge Loops, Subdivide (and Edge-Ring), Rotate Edge, Edge Slide, Loop Cut, Mark/Clear Seam and Sharp |
| Face | Extrude (three ways), Inset, Poke, Triangulate, Tris to Quads, Solidify, Fill, Beautify, Shade Smooth/Flat |

The header also has toggles for snapping, proportional editing (O; the mouse wheel changes its size while moving) and X mirror.

| Keys | What they do |
|---|---|
| Ctrl B, Ctrl Shift B | Bevel edges, bevel vertices (while bevelling, the mouse wheel or PageUp/PageDown changes the number of segments, for rounded edges) |
| Ctrl R | Loop cut and slide (the mouse wheel changes the number of cuts; click to cut, then slide; Esc keeps the cut centred) |
| Ctrl click | Select the shortest path from the last element you picked |
| K | Knife |
| V, Alt D | Rip, rip and extend |
| Y | Split |
| P | Separate into a new part |
| Shift D | Duplicate |
| X / Delete | Delete menu |
| Ctrl X | Dissolve |
| M | Merge menu |
| J | Connect vertex pairs |
| Ctrl T, Alt J | Triangulate, tris to quads |
| Shift N | Recalculate normals |
| H, Shift H, Alt H | Hide selected, hide unselected, reveal |
| L, Ctrl L | Select linked under the mouse, select linked |
| Ctrl + / Ctrl - | Select more / less |
| Alt S, Shift Alt S, Shift Ctrl Alt S | Shrink/Fatten, To Sphere, Shear |
| G G | Edge slide |
| Shift S | Snap menu |
| Alt E | Extrude menu |
| Ctrl V, Ctrl E, Ctrl F | Vertex, Edge and Face menus |

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

## Saving (needs a Studio beta)

ROBLENDER saves each mesh to Roblox as a real **Mesh asset**, using `AssetService:CreateAssetAsync`, so the mesh stays in the place and publishes like any imported mesh.

**Set it up once**
1. In Studio, open File > Beta Features and turn on **CreateAssetAsync Luau API**, then restart Studio.
2. Install ROBLENDER as a **local plugin** (the .rbxmx in your Plugins folder). Roblox only allows this API in local plugins, not in plugins installed from the Creator Store.

**When it saves**
- Automatically when you leave Edit Mode, if the mesh changed. You can turn this off under File > Auto Save.
- When you choose File > Save Mesh to Roblox or File > Save All Meshes.
- Unsaved meshes have a `*` after their name in the Outliner.

**Things to know**
- Every save is a new upload. Uploads are moderated like any other mesh.
- Roblox allows 30 uploads a minute.
- In a group game, meshes upload to the group.
- The editable copy of the mesh is also kept on the part (`RB_Data`), so you can always edit it again.

**Other ways to keep a mesh**
- Bake to Parts: builds a copy out of wedge parts.
- Export .obj: bring the file in with the 3D Importer.

**Modifiers (Properties > wrench tab)**

Modifiers change how a mesh looks without touching your edits, like Blender's. Click **Add Modifier**:

| Modifier | What it does | Settings |
|---|---|---|
| Array | Repeats the mesh in a row | Count, axis, relative offset |
| Bevel | Rounds every edge sharper than the angle | Amount, segments, angle |
| Decimate (Planar) | Joins faces that are flatter than the angle into bigger ones | Angle limit |
| Mirror | Copies the mesh across its own X / Y / Z, welding the middle | Axis, merge, distance |
| Screw | Spins the open edges (a profile line) round an axis: vases, springs, bolts | Angle, screw height, steps, axis |
| Solidify | Gives a flat surface thickness | Thickness, offset |
| Subdivision Surface | Catmull-Clark smoothing (Ctrl 0 to 4 sets it) | Levels (0 to 4) |
| Triangulate | Splits every face into triangles | - |
| Weld | Merges verts closer than the distance | Distance |
| Cast | Pulls the mesh towards a sphere | Factor |
| Displace | Pushes the surface in and out with noise (rocks, terrain) | Strength, texture size, seed |
| Simple Deform | Twist, Bend, Taper or Stretch | Method, angle / factor, axis |
| Smooth | Relaxes the shape | Factor, repeat |
| Wave | Ripples, out from the middle or along X | Height, width, offset |

- Each modifier panel has: the eye (on or off), the Edit Mode toggle, move up / down, **Apply** (makes it real geometry) and **X** (removes it).
- The stack runs top to bottom. It is stored on the part (`RB_Mods`), and saving uploads the result.
- Roblox allows 20,000 triangles per mesh, so Subdivision stops a level early if the next one would go over.

**Handy shortcuts in Edit Mode**
- Ctrl + right-click: extrude the selection to the mouse, or add a vertex there when nothing is selected.
- Shift R: repeat the last operator (also in the Edit menu).
- Auto Merge (the header button next to Mirror X): after a move, vertices that land on each other are welded.
- C: circle select. Drag to paint a selection, Shift-drag to remove, wheel for the size, right-click or Esc when done. Also in the tool strip (right-click Select Box).
- Inset (I): press I again for each face on its own; press Ctrl to set the depth with the mouse.
- P: Separate > Selection or By Loose Parts.
- Ctrl 0 to 4 (both modes): sets the Subdivision Surface level, adding the modifier if needed.

**Object Mode**
- Ctrl J joins the selected meshes into the active one (Object > Join).

## What's in it

| Path | What it holds |
|---|---|
| `src/BMesh.lua` | The mesh structure: verts, edges, loops and faces, with disk and radial cycles. Also the Euler ops (from `bmesh_core.cc` and `bmesh_structure.cc`). |
| `src/Ops.lua` | Primitives, extrude, inset, edge ring and loop cut, subdivide, delete, merge, fill. |
| `src/MeshTools.lua` | The Modeling tab's operators: bevel, knife, bisect, spin, smooth, rip, split, dissolve, bridge, poke, triangulate, solidify, hull, symmetrize, normals, selection tools. |
| `src/Modifiers.lua` | The modifier stack (14 modifiers) and merge by distance. |
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
