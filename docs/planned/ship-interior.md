# Ship interior

The ship's inside for the art pass (M5), decided 2026-10-25. This is the **shell**: floors, walls, ceilings,
frames, windows, doors, corridors, lobbies, lift shafts, the cargo bay's hall, and the signs. Each room's key
object (its station) and its dressing get rounds of their own later; their goal: **a room reads by its
purpose** (what stands in it), not by its sign. Values are **TBD (playtest)** unless said otherwise.

## The layout

Fitted to the hull's model in **A** (built, see [Spaceship](../GAME_DESIGN.md#5-spaceship-hub)): the cockpit under
its canopy in the nose, the bigger bridge, the specimen lab below the cockpit, window niches, the upper deck
5.5 m high. What's left:

- **The specimen lab's purpose:** a tank per alien strain, dark and empty until the first kill of that
  strain, and the place of the statistics station ([`stats.md`](stats.md)).
- **Room beside the holo table** on the bridge for the quest board and the comms station.
- **The drive core stays at the nose:** it's the reactor, feeding the nacelles through conduits that run
  along the back walls' tops from the engine room to the cargo bay, the shell's biggest pipe run (with C).
- **Reserved, built when something needs them:** a catwalk around the cargo bay at upper-deck height with a
  hatch into each sponson (a maintenance bay looking into the nacelle), and a crawlway along the spine over
  the upper deck (it would need its own cut-away level), e.g. for a quest or a story moment.

## Doors

Sliding doors that are always open by the time a player reaches them: they open when a player or crew
member is within 5 m (0.4 s; at 6 m/s that's done about 1 m before arriving, dashing too), close 1.5 s after
nobody is near, and have **no collision**, so even a moving door never blocks anyone; a short hiss on the
Effects bus. On every room door off the corridors and lobbies and on the cargo bay's doors; the ramp and the
lifts keep their own. A door in a wall cut away for the camera goes with its wall; its frame stays as part
of the stub.

## Signs instead of floor paint

The room names and the floor guides painted on the floor are replaced by **signs on the walls, like neon
tubes**. Aboard the camera sees only the back outer wall, the back halves of the cross walls, the stubs'
faces towards the camera and the lobbies' back walls (both corridor walls are 1 m stubs), so:

- **Room names:** a sign on the room's own back wall where it has one (rooms behind the corridor); rooms in
  front of the corridor (the vendors, cabins 2 and 4, crew 5–8, the engine room) get theirs standing on the
  corridor stub by their door, facing the camera, about 0.5 m above the stub. In the room's accent color.
- **Guides:** amber neon arrows with the destinations' names on the stubs' faces at the corridors' ends, the
  lobbies and the lifts, and a big sign on each lobby's back wall ("Lift: upper deck").
- **Text** stays translated text (a tube-like font, emissive, a little bloom, a slight flicker on some),
  mounted on a frame from the kit: no mesh per language.

## Look

- Heavy painted steel with ribs every 2 m and rounded frames, pipes and cable trays along the walls' tops,
  plated floors with gratings over the corridors' middle and amber edge markings, wear and grime; a few warm
  lamps, cool rim light. Refs: `local/art-references/ship-interior/` (batch 5, see its `INDEX.md`), without
  their faults (the same cyan everywhere, small boxy rooms, few windows).
- **The detail goes where the camera looks:** most on the back walls and floors; the stubs' tops capped (a
  dark band showing the wall's thickness, so cut walls read as cut); side walls plainer; ceilings simpler,
  but built (the VR head can look up in close views, see [`vr-view.md`](vr-view.md); aboard they stay cut
  away until then).
- **Each room its own:** one shared steel look; each room sets its floor tint, its light color and one
  accent color (screens, lamp strips, its sign), e.g. the medical bay pale green-white, the engine room hot
  orange, the bridge cold blue, the mess hall warm yellow, the armory amber, the cabins dim warm. Data per
  room, checked in the palette viewer against the ores' and players' colors.
- **Light:** real-time (the windows' outside light changes per body and storm, lifts move), 2–4 lights per
  room (a key light over the station, a lamp strip along the back wall, the accent glow), only the key light
  casting shadows; lamp strips along the corridors.

## How it's built

- A **modular kit** made in Blender by script (an asset script like the others, deterministic): wall panel,
  rib, door frame and door, window niche, floor plate and grating, stub cap, corner, ceiling panel, duct and
  pipe runs, sign frame. `hull_build.py` places the kit's pieces where it places greybox boxes today, in the
  same cut groups, so moving a room stays "change the layout, rerun". Waypost Ostra can use the kit later
  with its own colors.
- Textures: the **trim sheet** shared with the exterior's details (2048: ribs, seams, vents, hazard stripes,
  edge wear) plus tiling painted steel and grating; grime from a world-space noise in the shader (darker low
  on the walls, around doors, on the walking lines), no per-room bakes.
- Key objects later modeled by script too (hard-surface, exact sizes for the stations' parts), TRELLIS only
  for organic shapes.
- **Performance:** the pieces merged per room and cut group by the build script (few draw calls), about 100k
  triangles for all rooms' shells, occlusion culling as today; checked with the frame time aboard.
- **One room first:** the armory with its stretch of corridor, screenshots from the iso camera and the
  lockers' close-up, before the kit goes everywhere.
