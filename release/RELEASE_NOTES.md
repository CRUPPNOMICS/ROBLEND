# ROBLEND 0.30.0

A free, open-source (GPL-2.0-or-later) Blender-style modelling plugin for Roblox Studio, by Cruppnomics.
ROBLEND is not affiliated with or endorsed by the Blender Foundation.

## Install

1. Download `ROBLEND.rbxmx` below.
2. Put it in your Studio plugins folder (Studio: Plugins > Plugins Folder) and restart Studio.
3. In your place: Game Settings > Security > allow Mesh / Image APIs. Saving meshes needs File > Beta Features > "CreateAssetAsync Lua API".

## New since 0.16

**0.30.0 - Transform gizmo:** Blender's move / rotate / scale gizmo. Pick **Move**, **Rotate**, **Scale** or **Transform** in the tool strip (left) and coloured handles sit on whatever is selected, in Object Mode and Edit Mode: **arrows** (drag = move along X, Y or Z), **rings** (drag = turn round that axis), **boxes** (drag = stretch along it), little **squares** (move or scale flat on that plane) and a **white ring** (move freely, or turn / scale round the view). They light up under the mouse, and letting go finishes it. It's the same move as G / R / S with X / Y / Z, so typing a number, Ctrl to snap and Esc to cancel still work. No more lining things up by eye. **View > Transform Gizmo** turns it off. Turning round an axis now follows the mouse the same way whichever way the axis points (Blender), with the keys too.

**0.29.0 - Make Lighter:** Cut a mesh's triangle count fast, so your game doesn't lag. In Properties > Data > Mesh, the new **Make lighter** section: type how many triangles you want in **Aim for** (or press **1/2**, **1/4** or **1/10**) and ROBLEND trims the mesh down to about that many, keeping the shape as well as it can (Blender's Decimate > Collapse). It starts as a preview, so nothing is lost: **Apply** makes it real, **Remove** goes back to the full mesh, and Ctrl Z works too. The same is in **Object > Make Lighter**. The triangle count now shows in the corner of the view in Object Mode as well as Edit Mode, in colour: green = light (under 2,000), amber = getting heavy (under 10,000), red = heavy, with a warning near Roblox's 20,000-per-mesh limit. The count in Properties is coloured the same way.

**0.28.1 - the view always turns, and no more shake:** Another tool plugin can take control of the mouse away from ROBLEND (Studio only lets one plugin have it at a time), and then holding the middle button did nothing. Now ROBLEND also reads Roblox's own mouse movement, so the view turns, slides and zooms either way (never counting a move twice), and if another plugin keeps taking the mouse, a notice across the top of the view says so once (with what to do and a button to the Mouse Test), and Output too. New **Help > Mouse Test** shows live what ROBLEND hears from the mouse, plus the frame rate. The 3D view no longer shakes when you zoom in close: the workshop is 10,000 studs under the map, and drawing it there lost detail, so the view is now drawn near 0 (it looks the same, just steady). The mouse wheel now zooms towards whatever is under the mouse (Blender's Zoom to Mouse Position, like Studio's wheel), so you can't get stuck with the pivot in empty space just in front of the camera, crawling half a stud per scroll; from very far out it comes back in a few scrolls. **Faster Edit Mode:** the lines and points over the mesh (the heavy part) are no longer redrawn every frame while you turn the view - only once it has moved enough to show - and only the ones that changed get updated. Lines and points on the back of the mesh, or far off screen, aren't drawn at all (the mesh hides them anyway; X-ray still shows everything). The big-mesh slow-down now also works while you turn the view. **Orbit Mode:** a new button under the zoom / hand buttons (and View > Orbit Mode): while it's on (lit blue), a left-drag turns the view, Shift + drag slides it, Ctrl + drag zooms - for a mouse or touchpad with no middle button, or anyone new to Blender's controls. Esc or the button turns it off; it's remembered. **The view starts fresh each time ROBLEND opens:** the normal starting angle, framing what's in the workshop (its middle when empty), not wherever you left it.

**0.28.0 - Place in Studio saves first:** Placing work on your map now saves any ROBLEND mesh that isn't saved yet, so it shows in the published game straight away (an unsaved mesh only lives in your Studio session, and in a game it shows as Roblox's checkered cube). Output says when it's saved, or why it couldn't be. A copy from the Creator Store still can't save (Roblox blocks store plugins from uploading), so Output warns you instead. Nothing uploads by itself any more: the save when leaving Edit Mode, the timed save every 90 seconds and the save after a modifier change are gone (every save is an upload, and that was too many). You can still save any time with File > Save Mesh to Roblox / Save All Meshes. A save that works after a store-copy block clears that block.

**0.27.2:** The toolbar button shows the ROBLEND logo straight away in every copy (it's built in now; nothing gets uploaded). A copy installed from the Creator Store can't save meshes to Roblox yet, because Roblox doesn't let store plugins upload anything (coming later, with a permission prompt). ROBLEND now says so once, points to the file version and Bake to Parts / Export .obj, and stops retrying in the background.

**0.27.1:** Studio's Plugins tab shows just the ROBLEND button (the extra Edit in ROBLEND and Place buttons are gone; the same things are inside ROBLEND: Import from Studio, Bring in, Place in Studio).

**0.27.0:** Texture Paint is taken out again: it was slow on real meshes and the paint didn't show reliably. Vertex Paint (Q > Vertex Paint) stays.

**0.26.6 - the view can't get stuck:** If the middle / right mouse button was let go somewhere ROBLEND didn't hear about (over another window or panel), the view kept turning with every mouse move and nothing else worked. Now ROBLEND checks the button is really still held, and a left click or Esc always ends the drag. The mouse wheel takes its turns from both places Studio sends them (it could go dead before), and zooming right in carries on forward instead of stopping at the point you're turning round.

**0.26.5:** With ROBLEND closed, Studio gets every key back: ROBLEND's keys (Tab, Shift A, X, Delete...) do nothing until it's opened again. Closing ROBLEND also puts Studio's edit camera back to a normal Fixed camera, so the mouse wheel and orbiting always work.

**0.26.4:** Fixed: 0.26.0 to 0.26.3 wouldn't load in Studio ("Out of local registers... exceeded limit 200"). The main script uses fewer top-level names now, and the tests compile every file the way Studio does, keeping some room spare.

**0.26.3:** The Baseplate (or anything floor-sized, 512 x 512 studs or more) is never brought into the workshop or turned into a mesh: it isn't in the Import from Studio list, gets no Bring in button, and Tab / Edit in ROBLEND leave it on the map and say why.

**0.26.2:** Studio's camera can't get stranded down in the workshop any more: where it was on the map is remembered (per place), and closing ROBLEND any way - the button, Back to Studio, Studio's own 3D view mode, closing Studio, or reopening the place after a crash - brings it back up.

**0.26.1:** Plane lock, like Blender: while moving / scaling / rotating, Shift X / Y / Z locks that axis out so the selection slides flat on the other two (G Shift Y = across the ground at the same height, S Shift Y = wider and deeper, not taller). Works in Edit Mode and Object Mode.

**0.26.0 - Texture Paint:** Q > Texture Paint paints straight onto the model's picture through its UVs, like Blender: Draw / Soften / Average brushes, S picks a colour, Shift K fills, X symmetry, Ctrl Z / Y per stroke. The brush works in 3D, so strokes cross UV seams, and paint bleeds past island edges so no seams show. Meshes without UVs get Smart UV Project first. Leaving saves the picture to Roblox as an Image and puts it on the part as its texture.

**0.25.0 - meshes from Blender:** Tab on a MeshPart you made in Blender now brings it back the way Blender showed it: welded into one surface, its UVs kept so the texture / SurfaceAppearance still fits after editing (and its TextureID stays on), smooth shading with sharp edges where the file's normals split, and the export's triangles joined back into quads. Tris to Quads and Dissolve now keep UVs too. Wording: the Studio beta is "CreateAssetAsync Lua API".

**0.24.6:** The plugin file now carries its licence: a LICENSE module inside ROBLEND holds the notice, the Blender credits and the full GPL text.

**0.24.5:** One click on any part (a part on its own or one part of a model) selects just that part and gives it the outline. Alt + click selects the whole model or group; G / R / S then move, turn or resize all of it.

**0.24.4:** Things brought in show they're selected: a yellow box round a whole model or group, and an outline round a selected part or union (they had none before). Home / frame all includes them.

**0.24.3:** In a model, out a model: picking any part of a model brings in (and places) the whole model, and a group that was brought in goes back as the whole group.

**0.24.2:** Final check before publishing: a tidy-up (a leftover function taken out, the Bring in button sees Place in Studio properly) and the README now covers Before you start, the workshop, importing and placing, Q, and the three Help-menu tests.

**0.24.1:** Colour picker: a honeycomb of hexagon swatches (white in the middle, full colours round it, darker at the edge) and a row of greys - click one to paint with it. Opens from the colour square in Vertex Paint's header and Paint > Colour....

**0.24.0 - importing:** Import from Studio (top bar): a list of what's on your map, like the Explorer - click one, or drag it into the 3D view. It comes down to the ROBLEND scene, centred, and the view frames it. Parts, meshes, unions, models and groups (folders) all come in as they are; Tab on a part turns it into a ROBLEND mesh to edit. Place in Studio takes groups back too. Fixed: the Bring in button couldn't be clicked.

**0.23.5:** Bring things in from the Explorer: click a part or model in Studio's Explorer while ROBLEND is open and a "Bring in" button appears at the top of the view. Edit in ROBLEND and Place in Studio can also be given keyboard shortcuts (File > Advanced > Customize Shortcuts).

**0.23.4:** Vertex Paint works on plain shapes: on a cube (only 8 corner points) painting the middle of a face colours that face.

**0.23.3:** "Before you start": ROBLEND checks the two things it needs - Mesh / Image APIs for the game and Studio's CreateAssetAsync beta - shows a tick or a cross for each with how to turn it on, and lets you in when both are on. While a game can't make meshes, ROBLEND stops retrying (no more Output warnings).

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
