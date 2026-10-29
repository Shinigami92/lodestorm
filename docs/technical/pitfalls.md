# Pitfalls

Traps that cost time once, grouped by where they bite. The rules themselves are in [Code quality and tooling](development.md); this file is what the rules don't say.

## Imports and the editor

- `reimport`/`scan` (godot-ai's `filesystem_manage`) return before the import finishes: wait until the `.import` files exist and the `.godot/imported/*` files are new before running probes or tests. A hand-edited `.glb.import` isn't picked up by `reimport`: touch the `.glb` and scan; a reimported `.glb` needs `reimport`, a scan alone didn't take it.
- A new `class_name` script is unknown to other scripts until the project is imported (`tools/import.sh`; `tools/test.sh` does it first). `tools/uids.sh` can't resolve a just-written `.gd`/`.tscn` before that either ("no uid ... missing file?"): copy the `.gd.uid` or the scene header's UID into the `ext_resource` by hand.
- godot-ai's `project_manage settings_set` writes nested values as JSON (a `Vector4` becomes a string or a dict): write such settings (e.g. `[shader_globals]`) into `project.godot` by hand while the editor is closed, or reload it afterwards.
- Setting animation loops through a `.glb.import`'s `_subresources` blows the file up to thousands of lines: set the loop on the `AnimationNodeAnimation` in code.
- Saving a scene through the editor adds a `unique_id` to every node; the repo's scenes are kept without them, so patch hand-kept `.tscn` files as text.
- The editor log keeps parse errors from reloads in the middle of an edit: check whether the game run itself was clean.
- godot-ai's `game_eval` fails with `EVAL_GAME_NOT_READY` while the game window is in the background. `input_mouse` motion doesn't move `get_viewport().get_mouse_position()` (aim through `player.aim.at_screen_position`); `input_action`/`input_sequence` set the action state without `InputEvent`s, so menus driven by `_input` ignore them: use `input_key`.
- `source/` folders with `.blend` files need a `.gdignore` before the first `.blend` lands there, or the editor imports it (a stray `.blend.import` and `textures/` folder). `tmp/` has one too: keep it when cleaning up.

## GDScript

- Every warning is an error, but `--check-only` and headless runs don't print GDScript warnings: `tests/project/test_scripts_parse.gd` finds them (or the open editor's language server). `--check-only -s` fails on most game scripts because of the `Sfx` autoload.
- A local variable named like a member of the base class or a signal (`ready`, `point`, `along`) is a parse error.
- Indexing a typed `Dictionary[ItemType, int]` with an `AlloyType` variable fails: assign it to an `ItemType` variable first.
- `var x: Array[T] = a.list if a else [] as Array[T]` fails at runtime when the else branch runs: use an `if`.
- A typed const `Array[PackedStringArray]` of literals iterated as empty strings (and crashed on bone look-ups): use a flat `PackedStringArray`.
- `_init` isn't chained implicitly: a subclass's `_init` calls `super()`.
- Preloading a scene whose scripts refer back to the preloading class gives an empty `PackedScene`: `load()` it in `_ready`.
- `Vector3.slerp` errors every frame when two vectors are a hair apart: smooth directions with `lerp(...).normalized()`, and test such helpers with a sweep of tiny offsets.
- **Reentry through signals:** a reaction to damage (e.g. the player going down → the rescue drone's flash → `Alien.stagger_for` → the attack ends) can run inside the alien's own attack; code after a callback that can end the attack must check again whether it is still running. Test the case where an alien itself causes it, not only a call from the test.
- gdlint caps public methods at 20 (`static func` doesn't count) and files at 1000 lines (the defaults, `gdlint --dump-default-config`). Classes near a cap (`Player`, `GeneratedLocation`, `Alien`, `Npc`, ...) grow through components or split files, not new methods: check before adding.

## Scenes and nodes

- `Transform3D(...)` in a `.tscn` lists the basis by rows, not columns: check hand-written rotations with a screenshot.
- `find_child` (with the default `owned = true`) skips nodes added at runtime without an owner: keep a reference instead.
- A `.glb`'s `Skin` binds by name: resolve bones with `skeleton.find_bone(skin.get_bind_name(i))`. Setting up bones in `_skeleton_changed` crashed: do it lazily.
- Mesh names in a model must not clash with scene node or bone names (the swarmer's mesh is `Creature`, not `Body`).
- `CPUParticles3D` starts emitting: set `emitting = false` before `add_child`, place it, then emit; its `direction` is local.
- Pushing input into the root viewport: `push_input(event, true)`, or the window rescales the position.
- Exported enums are saved as numbers (see [Conventions](development.md#conventions)); resources are saved by UID. Before moving or renaming many files, check data and tables that name old paths on purpose.
- `NpcProfile.model` is a `"uid://..."` path string, not an `ext_resource`: with an `ExtResource` the suit silently stays (and the head-height test still passes).
- Python generators that rewrite `.tres`/`.tscn` files drop the `ext_resource` UIDs (run `tools/uids.sh`); replace text with raw strings or `str.replace` (a regex replacement once turned a group reference into a control character).

## Materials and shaders

- A `BaseMaterial3D`'s generated shader isn't reachable from GDScript: to clip or blend an imported model, build a `ShaderMaterial` that copies the `StandardMaterial3D`'s parameters (`MinerHologram._built_material`), cached per source material.
- `instance uniform` values are shared by every material on one `GeometryInstance3D` (surface overrides and `material_overlay`) when the names match, and uniforms with *different* names share slots by index: the ship shell's floor took the accent strip's color as its tint. Give each material with an instance uniform its own `MeshInstance3D`.
- Materials duplicated per instance with stencil on a skinned mesh caused "Parameter material is null" on free: change the shared imported materials in place.
- The headless renderer doesn't compile shaders and doesn't store `MultiMesh` instance transforms: shader errors only show in a windowed run.

## Navigation and the world

- The navmesh (cell 0.5, climb 0.25) tears on ground steeper than about 0.5 and in walkable strips narrower than about 4 m; ledges eat a cell ring per side (so canyons are 9–11 m wide, ramps 12–15 m, bridges at least 10 m). `agent_max_climb = 0.5` made baking about 60 times slower. Check alien paths with a navigation probe, not only the player's reach.
- Channels deeper than about 4.5 m hide their floor from the isometric camera.
- The location bakes its navmesh in `_ready`, so nodes added later (miners, test nests) aren't in it; without any region the navigation map never syncs (no paths, no avoidance).
- Navigation queries scan every polygon (about 0.35–0.5 ms on a generated world): budget path look-ups (`AlienPathing`), never query every frame.
- `GeneratedLocation.plan()` runs on a worker thread and touches no nodes or servers; `build()` runs on the main thread. A `Voyage` freed in the middle of planning waits for the task first.
- Aliens: a strain must never reach `AlienNest` (a load loop); an alien with `move_speed` 0 gets NaN legs (use guards with detection 0 in tests); RVO avoidance zeroes velocities that something else drives (held aliens skip it).
- The main map's ship and the test map's location are turned 45°: set yaw with `global_rotation`/`global_basis`. In ship-local axes the camera looks along -z (35° down), +x is screen right. The camera is perspective (fov 30, 40 m away), not orthographic: place far backdrops by viewing angle, and mind the 4000 m far plane.

## Tests (GUT)

- GUT silently skips a script that fails to parse ("does not extend GutTest"): read the parse error above that line. `assert_eq` with a Variant from a getter needs a cast (`as float`) or it fails to parse.
- Move bodies per physics frame, not per process frame (huge velocities headless). GUT's `wait_seconds` counts process time, which runs ahead of physics on a busy runner: wait for physics results with physics frames, and for real-time work with `tests/support/real_time.gd` (see [Code quality and tooling](development.md)). Heavier ship scenes shift frame timing too: state updated in `_process` needs process frames.
- `wait_seconds` hangs while `SceneTree.paused`: a test that waits while paused sets itself to `PROCESS_MODE_ALWAYS` and the map to `PROCESS_MODE_PAUSABLE`.
- Freeing nodes with `queue_free` shows as GUT orphans: `free()` them at once. Where that isn't safe (a node that may be freed during its own callback: a swapped location, weapon, model or hologram view), the tests that swap it wait a frame in `after_each` (or add their map with `add_child_autoqfree`, after which GUT waits). Nodes created in a scene script's field initializers leak as orphans when freed outside the tree: create them in `_ready`, or free the unparented ones on `NOTIFICATION_PREDELETE` (`Player` does).
- A CI run that reports objects or resources leaked at exit doesn't say which: `TEST_VERBOSE=1 tools/test.sh` runs Godot with `--verbose`, which lists them.
- Headless, `VisibleOnScreenNotifier3D.is_on_screen()` is always false: culling must be off there.
- Tests that list weapons, rows, MK levels or offers by hand break when content is added (MK levels must rise strictly): grep `tests/` (e.g. for `offers.size()`) when adding content.
- Cards: fit tests must render buttons enabled too (the wider style); a card that refreshes every frame must never set a `Button` disabled and back within one refresh (it cancels a real press), so test card buttons with a click held a few frames. Never `grab_focus()` every frame (a `Button` loses its press): mark the selection with a style override.
- Flaky physics shows up under load: stress-test with every core busy.

## Screenshot probes

A probe is a windowed run that sets up a scene and saves screenshots, for checking what tests can't see (readability, shaders, the log during real play). `tools/probe.sh [--headless] [--seconds N] <probe.gd> [arguments]` runs one: the probe extends `tests/support/probe.gd` by path and overrides `run()` (an example is in that script's comment); keep probes in `tmp/`.

- The base turns off saving, the title view and pausing on focus loss, and gives `add_map()` (the main map at the test location, `tests/support/map_fixture.gd`; `game/maps/main.tscn` itself starts in space), `physics_frames(n)` (process frames run at the monitor's rate), `wait(seconds)` and `shot(name, region)` (the next drawn frame, cropped if a region is given, to `$PROBE_OUT`, default `tmp/probe/`; skipped headless, which draws nothing). The probe's own arguments are in `args`.
- The loader (`tools/probe.gd`) loads the probe once the autoloads exist (game classes refer to `Sfx`, see [Audio](audio.md)) and quits at once when it or a script it extends doesn't compile (`can_instantiate()` alone passes a script whose base failed). A probe still running after `--seconds` (default 120) quits with 124; `timeout`, where there is one, ends a run stuck in a loop. `$PROBE_SCREEN` picks the window's monitor.
- `--headless` runs a probe without a window, e.g. to read the log of a played scene. Probe scripts are strict too (cast `get_node(...) as Node3D`, no integer division); for German screenshots set the locale in the probe. Stop a stuck probe by its process id, never every Godot process (the editor runs as the same executable).
- Measure frame times with `Time.get_ticks_usec` in `process_frame` with `--fixed-fps 60` and vsync off, and compare averages and the 95th percentile rather than the maximum (background tools cause occasional hitches).
- Generated layouts: the location viewer scene with `-- --shot=`.

## Blender and the asset scripts

- Procedural Cycles materials export to glTF as Principled defaults: everything visible is baked to textures.
- Bakes use no Blender margin (its extend margin overwrote other objects' pixels): `tools/blender/bake.py` grows the islands and fills the gaps itself. Skinned meshes: the bake removes the armature modifier and adds it back afterwards (`player_bake.py`).
- Blender's 4D noise `Fac` has a standard deviation of only about 0.09: the terrain script standardizes it (`Nodes.noise()`); thresholds on the noise's tail give uneven density.
- `plants_build.py` isn't deterministic between runs (up to 4.7 cm).
- A new ore kit needs the old kits' texture import settings (VRAM compression, normal map) copied onto its `.import` files.
- MPFB headless: `C.reset()`, then `addon_utils.enable("bl_ext.blender_org.mpfb")`. Extracted textures take the Blender image's name (name them `OutfitBase`/`ORM`/`Normal`).
- Several asset scripts can run in parallel with headless Blender on separate files; bakes are GPU-bound, so run at most two at once, and give every job an explicit output path in the repo.
- Python on Windows writes CRLF and reads cp1252: read and write files with `encoding="utf-8"` and `newline="\n"`.
