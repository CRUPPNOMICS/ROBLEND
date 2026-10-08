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

ROBLENDER is not made, endorsed or supported by the Blender Foundation.

## ROBLENDER

- Copyright (C) 2026 Cruppnomics (Roblox: Giga_gad27)
- Licence: GPL-2.0-or-later
