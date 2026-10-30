# Ship interior (what's left)

The ship's inside for the art pass (M5), decided 2026-10-25. Its **shell** is built (the layout fitted to the
hull, the kit's walls, floors, frames, doors, lights and signs, see [Spaceship](../design/ship.md)).
What's left are each room's key object (its station) and its dressing, with rounds of their own; their goal:
**a room reads by its purpose** (what stands in it), not by its sign. Values are **TBD (playtest)** unless said
otherwise.

## Rooms

- **The specimen lab's purpose:** a tank per alien strain, dark and empty until the first kill of that strain,
  and the place of the statistics station ([`stats.md`](stats.md)).
- **Room beside the holo table** on the bridge for the quest board (with the messages) and the comms station (invites, the comms log, M7).
- **Reserved, built when something needs them:** a catwalk around the cargo bay at upper-deck height with a
  hatch into each sponson (a maintenance bay looking into the nacelle), and a crawlway along the spine over the
  upper deck (it would need its own cut-away level), e.g. for a quest or a story moment.

## Look, next

- **Recessed wall bays** for the rooms' equipment (suit racks, weapon racks, shelves with cases), with the
  rooms' key objects and dressing.
- **Key objects** modeled by script like the kit (hard-surface, exact sizes for the stations' parts), TRELLIS
  only for organic shapes; their glowing parts keep doing the UI.
- **Ceilings** beyond the lamp housings, for the VR head looking up in close views (see
  [`vr-view.md`](vr-view.md); aboard they stay cut away until then).
- **Textures:** a trim sheet (vents, panel seams, labels) with the exterior's details if the geometry isn't
  enough. StableMaterials (gvecchio, the best generator of PBR sets tried) is used only once its weights'
  license (tagged "openrail", no text) is confirmed.
- **Waypost Ostra** can take the kit later with its own colors.
- **Performance** in VR (two views at 90 fps) is checked with M6: today about 9 ms a frame aboard on the
  development PC's desktop at 4K.
