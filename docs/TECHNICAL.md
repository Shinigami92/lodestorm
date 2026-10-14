# Lodestorm — Technical Guidelines

## 1. Source-available & licensing

- Code **and** assets (incl. `.blend` source files) are public on GitHub.
- License: **[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)** for everything original to this project (full text in `LICENSE`).
  - Others may fork, modify and share, with attribution, non-commercially, under the same license.
  - Only the owner sells the game (Steam/Epic/GOG). Strictly speaking this is *source-available*, not OSI "open source".
  - Third-party code and assets keep their own licenses, shipped next to them (e.g. `addons/godot_ai/` and `addons/gut/` are MIT, see their license files; GUT's bundled fonts are OFL). Only add third-party material whose license allows redistribution in this repo and in the commercial release.
- **CLA required for contributions** (via [CLA Assistant](https://github.com/cla-assistant/cla-assistant) GitHub app), so the owner may use contributions in the commercial release.
- Game name/logo: consider protecting as trademark before release.
- Get a short legal review before the commercial release.
- Secrets (Steam credentials, store tokens) only live in GitHub Actions secrets, never in the repo.

## 2. Code quality

| Tool | Purpose |
|---|---|
| [godot-gdscript-toolkit](https://github.com/Scony/godot-gdscript-toolkit) `gdlint` | Linting (naming, complexity, ordering) — config in `gdlintrc` (only overrides of the defaults) |
| `gdformat` (same toolkit) | Formatting, checked with `gdformat --check` — config in `gdformatrc` |
| Godot GDScript warnings | Enforce static typing: `untyped_declaration`, `unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument` are **errors** in the project settings, so a violating script fails to load. `addons/` is exempt (Godot's default `directory_rules`) |
| Unit tests | [GUT](https://github.com/bitwes/Gut) in `addons/gut/` (version in its `plugin.cfg`, must support the pinned Godot version), tests in `tests/` (`test_*.gd`, config `.gutconfig.json`), run headless |
| `.editorconfig` | Consistent whitespace/line endings across editors |

All checks are enforced by CI on every pull request (failing jobs block the merge), not by local git hooks. The same scripts run locally and in CI:

- `tools/lint.sh` — `gdformat --check` + `gdlint` over the project (`addons/`, `local/`, `tmp/` excluded in the rc files). gdtoolkit is pinned in `requirements-dev.txt`: `pip install -r requirements-dev.txt`, ideally in a `.venv/` (gitignored).
- `tools/test.sh` — imports the project (`tools/import.sh`: fails if the import prints any `ERROR`, e.g. an LFS pointer instead of a file), then runs GUT headless with `$GODOT4_EDITOR`; extra arguments go to GUT (e.g. `-gselect=test_foo.gd`). Exits non-zero on failures.
- GUT silently skips test scripts that fail to parse, so `tests/test_scripts_parse.gd` loads every project script and fails on parse or typing errors.
- Tests that need the map get it from `tests/support/test_map.gd`: the test map with the small hand-built test location instead of the generated outside world (fixed ore nodes, rocks and nests; generating 500 m takes over a second per test). The ramp button needs a picked mission: `pick_mission(map)` picks the first one on offer (picking reinstances the location).

`scripts/` holds game GDScript, `scenes/` the scenes; both are grouped by feature (`player/`, `camera/`, `maps/`, ...). A scene's tuning `.tres` sits next to it (e.g. `scenes/player/player_settings.tres`). Developer shell scripts live in `tools/` (ignored by Godot via `.gdignore`).

### Conventions

- Static typing everywhere (`var speed: float = 5.0`, typed function signatures).
- Follow the official GDScript style guide (snake_case files/functions, PascalCase classes/nodes).
- Gameplay logic separated from presentation where it helps testing (e.g. miner fill logic, resource inventory, upgrade math as plain testable classes/resources).
- Tunable values live in `Resource` files (`.tres`), not hardcoded — needed for playtest tuning anyway.

### Cross-platform development

Development must work on Windows (Git Bash), Linux and macOS.

- Scripts are POSIX `sh`/`bash` (no PowerShell/`.bat`-only tooling); avoid GNU-only flags (e.g. `sed -i` differs on macOS) or use Python instead.
- No hardcoded absolute or machine-specific paths; use env vars (`GODOT4_EDITOR`, `BLENDER`, `BLENDER_MCP_PATH`) and paths relative to the repo root.
- Line endings are LF (`.gitattributes`); mark scripts executable in git with `git update-index --chmod=+x` (Windows doesn't keep the bit).
- File names: lowercase, no spaces, never rely on case to distinguish files (Windows/macOS file systems are case-insensitive).
- Platform-specific project settings use Godot feature overrides (e.g. `rendering_device/driver.windows`), never replace the shared default.

### Engine settings

- **Versions:** each version is defined once and referenced everywhere else. Godot: `.godot-version` (read by CI and scripts; when upgrading, also let the editor update `config/features` in `project.godot`). godot-ai: `.mcp.json`, kept equal to `addons/godot_ai/plugin.cfg`.
- Renderer Forward+, Jolt physics, **Vulkan on all platforms** (Godot's default, so `project.godot` has no driver line). D3D12 was rejected: in a sibling project on the same Godot 4.7.2 + SteamVR setup it logged texture errors every frame and the headset image stayed black, while Vulkan worked. Retry D3D12 only after a Godot update and with a reason.
- **Performance targets** (see [`GAME_DESIGN.md`](GAME_DESIGN.md#2-platform--technical-constraints)): desktop 60 FPS minimum, 120–144 target; VR 90 minimum, with two views per frame. Settings follow from that:
  - Display: base resolution 1920×1080 (the reference size for 2D and stretching; 3D renders at the window's native resolution), fullscreen (borderless) by default, also when run from the editor. Window mode and resolution become player settings later.
  - Anti-aliasing: MSAA 2x for 3D (sharp geometry edges, works in VR), no TAA/FXAA (blur and smearing, worst in VR). The level is a starting value, **TBD (playtest)**, later a player setting.
  - Physics interpolation on: physics ticks at 60 Hz while the display runs at 90–144 Hz, interpolation keeps movement smooth without raising the tick rate. Nodes that are moved outside `_physics_process` or teleported need `reset_physics_interpolation()`.
  - Expensive per-`Environment` effects (SDFGI, SSR, volumetric fog) are off by default and only added when a profile shows the budget for them; the art direction leans on rim light and emissive accents for readability instead.
  - Look of the outside (`scenes/maps/test_map.tscn`): AgX tonemapping, glow (bloom) only above HDR 1.2, so only emissive parts bloom (ore, eyes, lamps), a dim warm sun, a faint cool back light without shadows and low ambient light. Aboard, `Weather` raises the ambient light (`indoor_ambient_energy`), because the cut-away roof still shades the rooms. Values are **TBD (playtest)**.
  - Rim light: `assets/shaders/rim_light.tres` is a material overlay that adds a cool glow along the outline, independent of the lights (players, aliens, miners). It costs one extra additive pass per mesh that uses it.
  - Occlusion culling stays off until there are occluders to bake (ship interior, M3); remember to enable it on SubViewports too.
  - Renderer for VR: Forward+ is used for PC VR. Whether Steam Frame standalone needs the Mobile renderer is checked in M6, through a feature override (see above), not by switching the default.
- **Input map** (`[input]` in `project.godot`, checked by `tests/test_input_map.gd`): every gameplay action has a keyboard/mouse and a gamepad binding on all devices (developer tools only get a key); keys use physical keycodes so WASD stays in place on non-QWERTY layouts. Mouse aiming uses the cursor position, so `aim_*` only has right-stick bindings. godot-ai can only bind logical keycodes: add keys with the editor closed or via the editor's Input Map tab ("Physical Keycode"). Stick deadzone 0.2 is a starting value, **TBD (playtest)**.

  | Action | Keyboard / mouse | Gamepad (Xbox / PlayStation) |
  |---|---|---|
  | `move_left/right/forward/back` | WASD | left stick |
  | `aim_left/right/forward/back` | cursor | right stick |
  | `attack` | left mouse button | RT / R2 |
  | `interact` | E | A / Cross |
  | `place_miner` | F | X / Square |
  | `switch_weapon` | Q | Y / Triangle |
  | `reload` | R | RB / R1 |
  | `pause` | Escape | Menu / Options |
  | `debug_overlay` | F3 | — |

- **Navigation:** 0.5 m cells (`navigation/3d/default_cell_size`; navigation meshes must use the same), so baking the 500 m outside world stays under a second; `merge_rasterizer_cell_scale` is 0.01, which avoids most edge merge errors on its terrain; the few left on some worlds (a handful of unlinked edges among about 12,000 polygons) are harmless, so their warning is off (`navigation/3d/warnings/navmesh_edge_merge_errors`). The map takes a baked mesh over in the background, so paths exist a few frames after the bake.
- **Physics layers:** everything collides on layer 1. Layer 2 only stops projectiles (they raycast against every layer; players and aliens only collide with layer 1), e.g. the force field in the ship's shooting range doorway.
- **Debug overlay** (autoload `DebugOverlay`, `scripts/debug/debug_overlay.gd`): a 2D developer panel, toggled with F3. It only exists when the game runs from the editor (`OS.has_feature("editor")`, also true for the headless tests); exported builds, debug ones included, remove it at start. It shows the mission state, the ship's flight phase, time, escalation, player health, how many aliens are left (chasing, hunters, raiders), how many nests there are and how many miners (broken), has shortcuts (skip to the warning time, storm now, skip the flight, kill / heal players, kill aliens, let every nest hatch a hunter or a raider, break every miner, unlock every weapon for every player, fill the hold with 900 units of every ore to test the upgrade stations, reset the save and reload the map) and sliders for the settings resources (`TUNING` in the script; add new tuning values there; integer settings get whole-number sliders). Sliders change the loaded resources live, so every scene using them sees the new value; changes last until the game stops and aren't saved, so copy good values into the `.tres` files by hand. A tuned mission duration also moves the running timer. While the mouse is over the panel, the player neither aims nor attacks with it.

### Localization

English and German so far (see [`GAME_DESIGN.md`](GAME_DESIGN.md#localization-and-voice)), with gettext PO files in `locale/`: one file per language, plain text, readable in a diff.

- **Texts are the English originals:** a scene's text property (e.g. `Label3D.text`) or `tr("Text")` in a script is the key, and English needs no translation file. Write them in sentence case ("Mess hall"); labels that show capitals set `uppercase`, so translations don't have to shout. `tr("Text", "context")` tells apart texts that read the same but translate differently.
- `locale/lodestorm.pot` is the template with every text. `tools/translations.sh` (`tools/translations.gd`, headless) collects it from `scenes/` and `scripts/` (text properties of nodes, unless their auto translation is disabled; `tr()` calls with string literals; the player-facing texts of resource types listed in `RESOURCE_TEXTS`, e.g. biome names, weapon names and descriptions) and brings every translation listed in the project settings (`internationalization/locale/translations`) up to date: new texts come in untranslated, unused ones go. Run it after adding or changing texts, then fill in the translations.
- `tests/test_translations.gd` fails when the template or a translation is out of date, or when a listed translation misses a text, so every new text needs its German translation in the same pull request.
- Nodes translate their texts themselves, also when the language changes while playing. A label whose text is set from code (e.g. the countdowns) disables its auto translation and gets `tr()` results, so nothing is translated twice.
- The game follows the system language (regional variants like `de_AT` use `de`, unknown languages show English); the settings terminal (`SettingsMenu`) switches it while playing and saves it (`GameSettings`, see [Saving](#saving)); `--language de` on the command line forces one for testing. The tests always run in English (`tests/support/pre_run.gd`).
- Room for longer texts: German runs about a third longer than English. Floor markings (`FloorGuide`) never get wider than their English text; they wrap between rooms instead and grow away from their arrow, which stays in place.
- **Adding a language:** create `locale/<code>.po` with a header (`Language: <code>`), add it to the translations in the project settings, add the language's own name to `SettingsMenu.LANGUAGE_NAMES`, run `tools/translations.sh` and translate every entry.

### Saving

What's saved and when: [`GAME_DESIGN.md`](GAME_DESIGN.md#11-death--persistence). A `SaveGame` node in the map (`scripts/save/save_game.gd`) loads the save when the map starts and writes it.

- **Files:** JSON in `save/` under `SaveGame.directory`: `ship.json` for the host's part (the hold; later the story, crew and quests) and `player.json` for the local player's (owned weapons, loadout, upgrade levels), split for co-op (see [Co-op progression](GAME_DESIGN.md#co-op-progression)). The settings are in `settings.cfg` (`ConfigFile`, `scripts/save/game_settings.gd`) next to `save/`, so resetting keeps them.
- **Where:** Godot's user data folder (`user://`); runs from the editor use `user://dev/`, so the debug overlay's shortcuts never reach a real save. The tests never touch either: `tests/support/pre_run.gd` sets `SaveGame.directory` to empty (nothing is loaded or saved), and `tests/test_save_game.gd` uses its own folder.
- **When:** on every change of the hold, the arsenal, the loadout or the upgrades (`changed` / `Ship.hold_changed`, batched to one write per frame) unless a mission is underway (`Mission.is_underway`), and when a mission is returned or lost.
- **Format:** each file has a `version` (`SaveGame.VERSION`); raise it and convert older saves in `SaveGame._read` when the format changes. Newer saves aren't read. Ore types, weapon types and upgrades are saved by their `res://` path: moving or renaming one of those resources needs a migration. Entries that don't resolve to the expected resource type are skipped with a warning (only `res://` paths are loaded); a file that can't be parsed is kept as `<file>.corrupt` and the game starts from the defaults. Files are written to `<file>.tmp` first and then renamed, so a crash never leaves half a save.
- **Reset:** `SaveGame.reset_progress` deletes `save/` and reloads the map, only while `SaveGame.is_solo` (no connected peers and at most one player; hosting a session alone counts, since friends can join any time); the settings terminal disables its button otherwise.
- **Language:** the saved one is applied when the map enters the tree, unless the command line forced another one (`--language`; detected as a locale other than the system's, so forcing the system language doesn't win).

### 3D menus

Menus are screens in the world (see [`GAME_DESIGN.md`](GAME_DESIGN.md#ui-in-the-world-not-on-the-screen)): a `WorldPanel` (`scenes/ui/world_panel.tscn`) renders a normal Control scene (`menu`) in a SubViewport onto an unshaded quad. A `Terminal` (`scenes/ui/terminal.tscn`, an `Interactable`) is a console with such a screen; set its `menu` to the Control scene. The settings terminal in cabin 1 shows `scenes/ui/settings_menu.tscn`, the mission console beside the bridge's holo table `scenes/ui/mission_menu.tscn` (a terminal scaled up 1.35×, so its text reads while the camera also frames the hologram).

- **Building a menu:** a Control scene filling its viewport, laid out for `size * pixels_per_meter` (960 × 600 for the default 1.2 × 0.75 m screen), with `assets/ui/terminal_theme.tres` (fonts 30 px, titles 46 px with the `Title` variation; a focus style that stands out, since gamepads navigate by focus). Texts go through translations like any scene (see Localization). A control closes its menu with `WorldPanel.showing(self).close()`.
- **Using:** `WorldPanel.open(player)` sets `Player.menu`; the player then ignores movement, aiming and actions (an action still held when the menu opens or closes waits for its release, so the closing press doesn't act in the world). The `IsoCameraRig` moves to the panel (or its `view_focus`, e.g. between the mission console and the hologram) and zooms until it sees `view_height` m (1.6, the mission console 4, **TBD (playtest)**; a `Terminal` passes both on to its panel). The screen material switches to no depth test while used and renders after the player's silhouette and rim light (`ON_TOP_PRIORITY`), so a player standing in front doesn't hide it.
- **Input:** while open, the panel takes the events in `_input`. Mouse events become a ray from the camera; `pixel_at(origin, direction)` turns it into a menu pixel, and the event is pushed into the SubViewport (`push_input(event, true)`: layout coordinates). A VR controller will use `pixel_at` the same way. Other events are translated into GUI actions (`NAVIGATION`: `move_*` and `ui_*` directions, `interact` and `ui_accept`), so the menus use Godot's focus navigation; a held stick presses once, held keys repeat. `pause` and `ui_cancel` close.
- **Sharpness:** the SubViewport keeps its layout size as `size_2d_override` (stretched) and renders at about the pixels the screen covers on the display, in half-octave steps (`_update_resolution`): zoomed in on a 4K display that's 2× the layout, from the isometric distance 1/8 (viewport textures have no mipmaps, so a big texture would shimmer). Fonts re-rasterize at that size (viewport oversampling), so text stays crisp.
- **Testing:** push input into the root viewport with `push_input(event, true)`: without it the window rescales the position (a headless window is tiny). Headless, the window is too small to test the render resolution; check it with a windowed probe.

### MCP servers (`.mcp.json`)

- **godot-ai** ([hi-godot/godot-ai](https://github.com/hi-godot/godot-ai)), version pinned in `.mcp.json` (`godot-ai==<version>`); needs the editor plugin of the same version in `addons/godot_ai/` enabled and the editor open.
- **blender** (official Blender Lab MCP server), path supplied via the `BLENDER_MCP_PATH` env var so the repo stays machine-independent.

## 3. CI/CD (GitHub Actions)

| Workflow | Trigger | Steps |
|---|---|---|
| `ci.yml` | PR, merge queue, push to `main` | gdformat check, gdlint, unit tests (headless Godot), import check |
| `build.yml` | push to `main` | Export Windows + Linux (+ macOS later) builds, upload as workflow artifacts |
| `release.yml` | git tag `v*` | Export builds, create GitHub Release with zipped builds attached |
| `steam-deploy.yml` (later) | release / manual | Upload build to Steam via SteamCMD to a beta branch |

Godot is run headless in CI with matching export templates (version read from `.godot-version`).

`ci.yml` has two jobs, `Lint` (`tools/lint.sh`) and `Test` (`tools/test.sh`); both are required status checks in the `main` ruleset, so a failing job blocks the merge. The Godot binary and the Git LFS objects are cached between runs (LFS bandwidth quota). The shared setup steps are composite actions in `.github/actions/` (`lfs-pull`, `setup-godot`), so workflows don't repeat them.

`build.yml` runs `tools/export.sh` (also usable locally): it imports the project, then exports a release build of every preset in `export_presets.cfg` to its export path under `builds/` (gitignored); CI uploads them as the `lodestorm-windows` / `lodestorm-linux` workflow artifacts. Presets: Windows Desktop and Linux, x86_64, PCK next to the binary, `tests/` and `addons/gut/` excluded; the godot-ai plugin strips its own autoload from exports. `application/modify_resources` (exe icon and metadata) is off because it needs rcedit, and Wine on Linux CI; turn it on with the release work (M8). `export_presets.cfg` is committed: Godot keeps signing credentials in `.godot/export_credentials.cfg`, never put them in the presets.

Export templates: the full archive is >1 GB, so `setup-godot` (with `export-templates: "true"`) downloads it once per Godot version and caches only the two release templates used. Locally, install them via the editor (Editor → Manage Export Templates), or extract `windows_release_x86_64.exe`, `linux_release.x86_64` and `version.txt` from the archive into Godot's `export_templates/<version>.stable/` folder in its user data directory (Windows `%APPDATA%\Godot`, Linux `~/.local/share/godot`, macOS `~/Library/Application Support/Godot`).

### Dependency updates (Renovate)

[Renovate](https://docs.renovatebot.com/) (config `.github/renovate.json5`) opens PRs early on Mondays; non-major updates are grouped into one PR. It tracks:

| Dependency | Source of truth | Note |
|---|---|---|
| GitHub Actions | `.github/workflows/*.yml`, `.github/actions/*/action.yml` | pinned to commit digests (`config:best-practices`) |
| gdtoolkit | `requirements-dev.txt` | |
| Godot | `.godot-version` | own PR (only `-stable` releases); open the project in the new editor so it updates `project.godot`, check GUT compatibility |
| godot-ai | `.mcp.json` | own PR; replace `addons/godot_ai/` with the matching plugin in the same PR, `tests/test_addon_versions.gd` fails until the versions match |

Vendored addons without a server counterpart (GUT) are updated by hand: GUT releases are tied to Godot versions.

## 4. Asset pipeline

- Blender (via Blender MCP) → export glTF (`.glb`) → `assets/` in Godot.
- `.blend` source files are committed too (open source).
- Binary assets (`.blend`, textures, audio) via **Git LFS** (watch GitHub LFS storage/bandwidth quotas).
- **Swappable models:** a gameplay scene keeps its look under a `Model` child, and its script finds the parts it animates by name among all descendants, so a modeled `.glb` can replace the greybox without code changes. The miner's model provides `Fill` (scaled along Y from 0 to 1 with the fill level, origin at its bottom), `FullLamp`, `HoseOutlet` and meshes named `Frame*`; damage (rust, hit flash, alarm blink) is drawn as an overlay on the `Frame*` meshes, so it works on top of the model's own materials. Blender models are Z-up meters; the glTF export converts to Godot's Y-up.
- **Model kits:** one `.glb` can hold many parts that scenes and resources pick by node name, e.g. all rock variants in `assets/rocks/rocks.glb`. `ModelParts` (`scripts/assets/model_parts.gd`) reads a part's mesh (and transform) from the imported scene without instancing it. A `ScatterType` takes its mesh from `model` + `model_part`; an `OreType` names its `variants` in `model` (each a node with a `Base*` rock mesh and `Crystal*` meshes, drawn in the ore's glowing material), and each `OreNode` shows one of them.
- **Model files:** the game imports the `.glb` (e.g. `assets/miners/miner_glow.glb`; Godot extracts its embedded textures next to it). The `.blend` sources live in a `source/` folder with a `.gdignore` next to it, because Godot would import `.blend` files too (through Blender) and duplicate the model. Procedural Blender materials are baked into one texture set per model (base color, ORM, normal) before export. Godot doesn't import glTF transmission, so glass gets a Godot material override in the scene (see `scenes/mining/miner.tscn`).
- **Characters:** a character `.glb` carries its skeleton and animations. The player (`assets/player/player.glb`) has a skeleton with Godot's humanoid bone names (`SkeletonProfileHumanoid`, no fingers, T-pose rest), so its clips could be retargeted later, and one skinned mesh: hard-surface parts weighted 100 % to their bone, the undersuit limbs blended across elbows and knees. The clips are keyframed by the build script, not by hand: every pose is a set of world-space rotations per bone plus two-bone IK for arms and legs (feet planted on the ground, hands on the blaster's grips), sampled every frame at 30 fps, one Blender action and NLA track per clip. Loops are set in the game (`PlayerAnimator` builds its `AnimationTree` in code), so the `.glb.import` stays default. Markers the game uses are empties on bones (Godot imports them under a `BoneAttachment3D`), and the scene's nodes follow them through a `RemoteTransform3D`, so their paths stay stable. The model faces glTF +Z (Blender -Y), the player's `Body` turns it by 180°. Four-legged aliens (`assets/aliens/swarmer/swarmer.glb`) have their own skeleton: `Body` (moves the whole trunk), `Hips` with the tail and the hind legs, `Spine`, `Chest` with the front legs and the scythes, `Neck`, `Head`, `Jaw`; legs are `<Front|Hind><Left|Right><UpperLeg|LowerLeg|Foot>` (front elbows bend back, hind knees forward, the hind `Foot` is the long metatarsal). Their organic mesh is lofted along the bones and weighted to the two nearest bones; plates, teeth, claws and blades are rigid. The clips (`Idle`, `Run`, `Attack`, `Die`) only move the trunk, head, tail and blades; the legs come from `AlienLegs` (`scripts/aliens/alien_legs.gd`), a `SkeletonModifier3D` added under the model's `Skeleton3D` at runtime: every foot stays planted until the spot under its hip (plus half a step's travel) is too far away, then steps there in an arc, the diagonal pairs taking turns (a trot); a ray finds the ground under each new step (other characters skipped), and two-bone IK bends the upper and lower leg so the ankle sits above the foot, the foot keeping its animated angle. It works with the interpolated transform, so feet stay put between physics ticks. On death it switches off and `Die` folds the legs. `AlienAnimator` builds the alien's `AnimationTree` in code (idle/run blend by speed, attack one-shot, death).
- **Terrain textures:** the generated ground is drawn with `assets/shaders/terrain.gdshader`, one `ShaderMaterial` per biome (`assets/terrain/<biome>_terrain.tres`, set as the biome's `ground_material`) with three tileable texture sets: ground (6 m tile) and scree (4 m), projected from above, and rock (8 m), projected from the sides with the image's up as the world's up. Hex tiling hides the tiling: every pixel mixes three samples from randomly shifted copies of the texture on a grid of hexagons (ground and scree turned too, rock only shifted sideways so its strata stay level; `hex_cells`, `hex_contrast`), and a large noise varies the brightness (`macro_strength`, `macro_size`). Layers without weight at a pixel aren't sampled, so open ground costs 6 texture reads, cliffs 12. Rock takes over by the slope; scree comes from the vertex color's alpha, which `GeneratedLocation` paints at the foot of steep ground (higher ground within 2 grid points, `LocationTerrain.highest_around`) and in patches; the vertex color's RGB tints the low ground darker and varies the brightness over large areas. Where layers meet, the textures' heights decide (stones and ledges poke through). Each set is two 1024 px PNGs: `<layer>_albedo` (RGB base color, A height) and `<layer>_nra` (RG normal X/Y, B roughness, A AO), imported VRAM compressed in high quality (BPTC) without alpha border fix. They're made by `assets/terrain/source/terrain_textures.py` (`tools/blender.sh assets/terrain/source/terrain_textures.py [layer ...] [preview]`): each layer is real geometry (a displaced ground grid, stones, roots) with procedural materials, surrounded by eight instances of itself so everything tiles, rendered from straight above with an orthographic camera as emission passes (base color, roughness, normal, height, AO); the shader noise is periodic 4D noise on a torus, the numpy maps are filtered noise and wrapped Voronoi cells. `preview` also renders a lit 2×2 tile check to `tmp/terrain/`. Only the script and the PNGs are committed (no `.blend`, the script rebuilds the scenes in about 10 s each; reruns give the same layers, the PNG bytes differ slightly from GPU sampling).
- **Asset scripts:** a modeled asset is built by Python scripts next to its `.blend` (e.g. `assets/miners/source/miner_glow_build.py` models it with procedural materials, `miner_glow_bake.py` bakes the textures and writes the `.blend` and `.glb`), with shared helpers in `tools/blender/`: `common.py` for building (transforms, the `Part` mesh builder, material node helpers, preview scene, renders, contact sheets, export) and `bake.py` for the bake. A bake script only describes its asset in a `bake.Job` (objects sharing the atlas, texture size and supersampling, material name, optional hooks for bake-only props, a custom unwrap or constant materials) and calls `bake.run()`: unwrap into one atlas, bake base color / ORM / normal (and emission), fill the gaps between the islands, swap in one baked PBR material, export, re-import and render checks. It bakes without Blender's bake margin (with several objects, one object's margin paints over the others' islands) and grows the islands itself. `<script> verify` only re-imports and renders the checks; the env var `BAKE_OUT=<dir>` writes the `.glb`, `.blend`, textures and checks to `<dir>` instead, to compare a re-bake without touching `assets/`. Run them headless with `tools/blender.sh <script> [args]`, which needs the env var `BLENDER` (path to the Blender executable). Preview renders and intermediate files go to `tmp/`; only the scripts, the baked `.blend` and the `.glb` are committed.

## 5. Platform services & distribution

### Abstraction

A `PlatformService` layer (autoload) with backends:

- `NullPlatform` — GitHub/itch builds, development, CI (no-op)
- `SteamPlatform` — via [GodotSteam](https://godotsteam.com/) (GDExtension)
- `EpicPlatform` / `GogPlatform` — later, via EOS / GOG Galaxy plugins (to be evaluated)

Gameplay only calls e.g. `PlatformService.unlock_achievement(&"first_miner")`; the game must run fully without any store client.

### Achievements

- Defined once in the game (id, name, description, icon), mirrored in each store's backend config.
- Optional in-game achievement list so non-Steam builds have them too.
- During development Steam's test App ID `480` (Spacewar) is used until the real App ID exists.

### Steam publishing — first-timer checklist

1. Create a Steamworks partner account (identity, tax and bank info).
2. Pay the Steam Direct fee per game (currently USD 100, recoupable after USD 1,000 gross revenue). After payment there is a mandatory waiting period (~30 days) before release.
3. Get the App ID; set up depots (Windows/Linux/macOS), and the SteamPipe upload via SteamCMD.
4. Configure achievements + icons in Steamworks.
5. Build the store page (capsule images, screenshots, trailer, description) → Valve review.
6. "Coming Soon" page must be public for at least ~2 weeks before release (wishlists matter a lot).
7. Upload a build → Valve build review → release (Early Access is an option for an iterating game).

These rules may change; re-verify on the Steamworks documentation when we get there.

### Other stores

Epic Games Store and GOG have their own submission processes and SDKs — evaluated once the game approaches release.
