# Credits

## Blender

ROBLENDER's mesh engine is converted to Luau, and cut down, from Blender's source code:
- Copyright (C) Blender Authors, https://www.blender.org
- Licence: GPL-2.0-or-later
- Source: https://projects.blender.org/blender/blender

The Blender source files used are:

| Blender source file | What ROBLENDER uses from it |
|---|---|
| `source/blender/bmesh/intern/bmesh_structure.cc` | Disk and radial cycles |
| `source/blender/bmesh/intern/bmesh_core.cc` | Create, kill, split edge, split face |
| `source/blender/bmesh/intern/bmesh_polygon.cc` | Face normal and centre |
| `source/blender/bmesh/intern/bmesh_delete.cc` | Delete |
| `source/blender/bmesh/operators/bmo_primitive.cc` | Primitives |
| `source/blender/bmesh/operators/bmo_extrude.cc` | Extrude |
| `source/blender/bmesh/operators/bmo_inset.cc` | Inset (simplified) |
| `source/blender/bmesh/operators/bmo_subdivide.cc` | Edge ring and loop cut |
| `source/blender/blenlib/intern/polyfill_2d.cc` | The idea behind the ear-clipping triangulation |
| `source/blender/bmesh/tools/bmesh_bevel.cc` | Bevel (offset-meet corners, 1 segment) |
| `source/blender/bmesh/tools/bmesh_bisect_plane.cc` | Bisect and knife plane cuts |
| `source/blender/bmesh/operators/bmo_utils.cc`, `bmo_poke.cc`, `bmo_triangulate.cc`, `bmo_join_triangles.cc` | Smooth vertices, poke, triangulate, tris to quads |
| `source/blender/bmesh/operators/bmo_bridge.cc`, `bmo_dissolve.cc`, `bmo_rotate_edges.cc`, `bmo_connect.cc` | Bridge loops, dissolve, rotate edge, connect vertex pairs |
| `source/blender/bmesh/operators/bmo_dupe.cc`, `bmo_hull.cc`, `bmo_symmetrize.cc`, `bmo_normals.cc` | Duplicate, split, spin, convex hull, symmetrize, recalculate normals |
| `source/blender/modifiers/intern/MOD_mirror.cc`, `MOD_subsurf.cc`, `MOD_solidify.cc`, `MOD_array.cc`, `MOD_bevel.cc`, `MOD_smooth.cc` | The modifier stack (Subdivision uses the Catmull-Clark rules OpenSubdiv implements) |
| `scripts/startup/bl_ui/properties_data_modifier.py` | The Modifiers tab and the Add Modifier menu |
| `release/datafiles/userdef/userdef_default_theme.c` | Every colour of the window and the 3D view |
| `scripts/startup/bl_ui/space_view3d.py` | The 3D view header menus, the Add menu and the right-click menus |
| `scripts/startup/bl_ui/space_toolsystem_toolbar.py` | Tool strip names, tooltips and shortcuts |
| `scripts/startup/bl_ui/space_topbar.py`, `space_outliner.py`, `properties_object.py`, `space_statusbar.py` | Layout of the top bar, Outliner, Properties and status bar |

Blender's icon images are not included; the icons are drawn from simple shapes.

ROBLENDER is not made, endorsed or supported by the Blender Foundation.

## ROBLENDER

- Copyright (C) 2026 Cruppnomics (Roblox: Giga_gad27)
- Licence: GPL-2.0-or-later
