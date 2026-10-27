# NPCs who know where they are (planned)

Decided 2026-10-27. All values **TBD (playtest)**. NPCs know the room they stand in and their own (see [`design/crew.md`](../design/crew.md), The crew aboard) and say what fits there; what's left:

- **Ostra's people walking** (**B**): Kade, Selin, Nell and Rook stay in their own room, at or near their place, until their greeting has been heard to the end (a talk cut off doesn't count; once per save, the flag is the ship's). Every docking they start at their place, and after a while (the crew's 20–40 s) they move on; then they walk:
  - **Kade:** the depot only: his counter, the shelves behind it, the depot's door to the hangar (watching crates come in).
  - **Selin:** the council office (the head of the table, the window); now and then the observation gallery and the concourse.
  - **Nell:** behind her counter most of the time; now and then to a booth (wiping its table, checking on the guests sitting there, taking a glass back; a new short clip setting a glass down or picking one up) and back.
  - **Rook:** his booth in the bar; now and then the hangar (looking over the players' ship), the gallery, the bar's counter.
  - Outside their own room they only stand or look around (no work clips there). Talked to while walking, they stop, turn to the player and talk where they stand (with their lines for elsewhere), then walk on; Nell at a booth is talked to there (where she can be used follows her).
  - The station gets a navigation mesh of its own like the ship's (baked when first needed, on its own map, floors only), sharing the ship's code; the colonists keep their routes for now.
- **Closing time:** the station has no clock yet, so the bar never closes and Nell never leaves it. Closing (Nell leaving her bar) comes with a station day, together with the colonists' day routine (see [`station.md`](station.md), Smarter NPCs later).
- **Later:** starting somewhere along their day at each docking (where they might be at that hour) instead of at their place, once the station has a day; the crew leaving their rooms more (e.g. eating in the mess hall), each walk adding lines for elsewhere where needed.
- **Smarter NPCs** (an idea, needs research first): NPCs that also know who is near them (a related NPC: a remark to them, a line that names them) and the things of interest in their room (pointing at the rack they're beside), for more immersion.
