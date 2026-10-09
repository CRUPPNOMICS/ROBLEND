# Credits

## Blender

ROBLEND's mesh engine is converted to Luau, and cut down, from Blender's source code:
- Copyright (C) Blender Authors, https://www.blender.org
- Licence: GPL-2.0-or-later
- Source: https://projects.blender.org/blender/blender

The Blender source files used are:

| Blender source file | What ROBLEND uses from it |
|---|---|
| `source/blender/bmesh/intern/bmesh_structure.cc` | Disk and radial cycles |
| `source/blender/bmesh/intern/bmesh_core.cc` | Create, kill, split edge, split face |
| `source/blender/bmesh/intern/bmesh_polygon.cc` | Face normal and centre |
| `source/blender/bmesh/intern/bmesh_delete.cc` | Delete |
| `source/blender/bmesh/operators/bmo_primitive.cc` | Primitives, including cone and ico sphere (the torus follows Blender's add-mesh torus script) |
| `source/blender/bmesh/operators/bmo_extrude.cc` | Extrude |
| `source/blender/bmesh/operators/bmo_inset.cc` | Inset (simplified) |
| `source/blender/bmesh/operators/bmo_subdivide.cc` | Edge ring and loop cut |
| `source/blender/blenlib/intern/polyfill_2d.cc` | The idea behind the ear-clipping triangulation |
| `source/blender/bmesh/tools/bmesh_bevel.cc` | Bevel (offset-meet corners, 1 segment) |
| `source/blender/bmesh/tools/bmesh_bisect_plane.cc` | Bisect and knife plane cuts |
| `source/blender/bmesh/operators/bmo_utils.cc`, `bmo_poke.cc`, `bmo_triangulate.cc`, `bmo_join_triangles.cc` | Smooth vertices, poke, triangulate, tris to quads |
| `source/blender/bmesh/operators/bmo_bridge.cc`, `bmo_dissolve.cc`, `bmo_rotate_edges.cc`, `bmo_connect.cc` | Bridge loops, dissolve, rotate edge, connect vertex pairs |
| `source/blender/bmesh/operators/bmo_dupe.cc`, `bmo_hull.cc`, `bmo_symmetrize.cc`, `bmo_normals.cc` | Duplicate, split, spin, convex hull, symmetrize, recalculate normals |
| `source/blender/modifiers/intern/MOD_mirror.cc`, `MOD_subsurf.cc`, `MOD_solidify.cc`, `MOD_array.cc`, `MOD_bevel.cc`, `MOD_smooth.cc`, `MOD_weld.cc`, `MOD_screw.cc`, `MOD_triangulate.cc`, `MOD_decimate.cc`, `MOD_simpledeform.cc`, `MOD_cast.cc`, `MOD_wave.cc`, `MOD_displace.cc`, `MOD_wireframe.cc` | The modifier stack (Subdivision uses the Catmull-Clark rules OpenSubdiv implements) |
| `scripts/startup/bl_ui/properties_data_modifier.py` | The Modifiers tab and the Add Modifier menu |
| `source/blender/editors/mesh/editmesh_select_similar.cc`, `source/blender/editors/object/object_transform.cc` | Select Similar; Set Origin and Apply Rotation |
| `source/blender/modifiers/intern/MOD_boolean.cc`, `source/blender/editors/mesh/editmesh_intersect.cc` | The Boolean modifier's settings and Edit Mode's Intersect (Boolean) (the solid geometry itself is done differently, see below) |
| `source/blender/editors/object/object_convert.cc` | The idea of Object > Convert (turning other objects into editable meshes) |
| `source/blender/editors/uvedit/uvedit_unwrap_ops.cc`, `source/blender/blenlib/intern/uvproject.cc` | Cube, cylinder and sphere UV projection |
| `source/blender/editors/sculpt_paint/brushes/*.cc`, `sculpt.cc` | Sculpt brushes (draw, clay strips, inflate, grab, smooth, flatten, pinch, crease), area normal, falloff, symmetry |
| `source/blender/editors/sculpt_paint/paint_vertex.cc` | Vertex Paint (draw, blur, average, fill, sample, front faces only) |
| `source/blender/blenkernel/intern/curve_bevel.cc`, `displist.cc` | The Tube modifier (a curve's round bevel swept along a path) |
| `scripts/presets/keyconfig/keymap_data/blender_default.py` | The keyboard shortcuts (Edit Mode, Object Mode and 3D view keymaps) |
| `release/datafiles/userdef/userdef_default_theme.c` | Every colour of the window and the 3D view |
| `scripts/startup/bl_ui/space_view3d.py` | The 3D view header menus, the Add menu and the right-click menus |
| `scripts/startup/bl_ui/space_toolsystem_toolbar.py` | Tool strip names, tooltips and shortcuts |
| `scripts/startup/bl_ui/space_topbar.py`, `space_outliner.py`, `properties_object.py`, `space_statusbar.py` | Layout of the top bar, Outliner, Properties and status bar |

Blender's icon images are not included; the icons are drawn from simple shapes. The text font (src/Font.lua) is ROBLEND's own, not a Blender font.

ROBLEND is not made, endorsed or supported by the Blender Foundation.

## Boolean method

`src/Boolean.lua` uses constructive solid geometry with BSP trees: the classic method of W. Thibault and B. Naylor ("Set operations on polyhedra using binary space partitioning trees", SIGGRAPH 1987), in the form popularised by Evan Wallace's csg.js (MIT licence, https://github.com/evanw/csg.js). ROBLEND's version is written in Luau for this plugin, with its own clean-up step.

## ROBLEND

- Copyright (C) 2026 Cruppnomics (Roblox: Giga_gad27)
- Licence: GPL-2.0-or-later
