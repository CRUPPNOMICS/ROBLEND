# ROBLEND 0.23.2

A free, open-source (GPL-2.0-or-later) Blender-style modelling plugin for Roblox Studio, by Cruppnomics.
ROBLEND is not affiliated with or endorsed by the Blender Foundation.

## Install

1. Download `ROBLEND.rbxmx` below.
2. Put it in your Studio plugins folder (Studio: Plugins > Plugins Folder) and restart Studio.
3. In your place: Game Settings > Security > allow Mesh / Image APIs. Saving meshes needs File > Beta Features > "CreateAssetAsync Luau API".

## New since 0.16

**0.23.2:** Place in Studio: a click in Studio's view always places it (and it stays - Esc afterwards does nothing to it); no hint bar.

**0.23.1:** Place in Studio: ROBLEND closes and your work is in your hand in Studio's view - it follows the mouse, click to place, R turns it, Enter puts it back exactly where it came from, Esc cancels. Buttons renamed: Studio's toolbar has Edit in ROBLEND and Place; ROBLEND's top bar has Place in Studio and Back to Studio.

**0.23.0 - the workshop:** ROBLEND now works 10,000 studs under your map, so models never get mixed up with it. **Import** (Studio's Plugins tab, ROBLEND's top bar or File menu) sends the selected parts / models down - normal parts become ROBLEND meshes - and remembers where they came from; **Export** sends them back to exactly that spot (new work goes where Studio's camera is looking). **Back to Studio** closes ROBLEND with Studio's camera where you left it. Tab on a part up on the map brings it down too. Properties show locations from the workshop's middle. Turn it off with Edit > Workshop Under the Map.

**0.22.9:** Fixed: a shape could stay drawn in ROBLEND's view after its part was gone (and couldn't be clicked or deleted); such leftovers are now cleared straight away.

**0.22.8:** Add > Text is now a menu: Type Your Own... (a box to type in) or a ready-made word, and it's there in Edit Mode and the right-click menu too. Properties > Data > Change Text... types new words; changing the words works from Edit Mode as well.

**0.22.7:** Q opens the mode menu (Object / Edit / Sculpt / Vertex Paint) - Studio keeps Ctrl Tab for itself.

**0.22.6:** Fixed: after Esc cancelled a move in Object Mode, the next move could be snapped back (Studio put the parts back late).

**0.22.5:** The Auto-Test finishes with a show-off: a block painted in four colours, swept round, then a slow spin of the camera. The block stays in your place.

**0.22.4:** Fixed (found by the Auto-Test in real Studio): big meshes (a sculpt subdivided a few times) couldn't be stored - Roblox caps one text value at 200,000 characters, so the mesh now carries on in extra pieces. Collision / render detail from Properties now really changes the part (Roblox only takes them when the mesh part is made, so it's made again). Auto-Test made steadier.

**0.22.3:** Help > Run Auto-Test: checks about 100 features by itself (pretend mouse and keys through the real controls) and prints a report. Faster: moving a big selection (G / S / R) no longer redraws thousands of outline pieces every step, and orbiting round a big mesh in Edit Mode is smoother. Fixed: Ctrl + numpad plus / minus now grows / shrinks the selection in Edit Mode (it zoomed); Select Mirror works in edge and face select.

**0.22.2:** Help > Quick Test: a card that sets up each feature for you, says what to press and what you should see, with Works / Broken / Skip buttons. Fixed: Booleans on round or detailed shapes could crash with "stack overflow".

**0.22.1:** closing ROBLEND puts Studio back on its Select tool, so Studio's move arrows don't appear on parts afterwards.

**0.22.0:** typing in Properties boxes (like the Text box) is no longer interrupted by the shortcut blocking; numpad 1 2 3 4 orbit / change view even when Studio grabs them.

**0.21.9:** Help > Run Self-Test checks the features inside your real Studio and prints a report to Output. Double-click a Properties panel or an Outliner name (rename) works.

**0.21.4:** the number-row 1 2 3 work in ROBLEND with no setup: Studio swallows them for its build tools, so ROBLEND catches Studio's tool switching and turns it back into the key (and puts Studio's tool back).

**0.21.3:** Studio keeps its 1 2 3 4 build-tool keys before any plugin sees them. ROBLEND now adds commands (ROBLEND: Vertex / Edge / Face Select, Edit / Object Mode) to File > Advanced > Customize Shortcuts so you can give those keys to ROBLEND. Help > Show Key Presses prints every key ROBLEND receives.

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
