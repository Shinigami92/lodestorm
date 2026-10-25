# Ship exterior

The ship's outside for the art pass (M5). The rooms stay greybox; they may be adjusted slightly where the
new hull needs it. Values are **TBD (playtest)** unless said otherwise.

## Shape

- **A skin over the box:** the rooms' box (96 x 30 m, two decks) stays; the outer skin may grow anywhere
  outside it, since the front walls and the roof disappear aboard anyway. First the refs' language over the
  box: chamfered and rounded long edges, sides leaning in towards the top, a raised spine on the roof (2–3
  m, with the hull's machinery: vents, radiators, antenna mast, sensor dome), the belly stepping down
  towards the legs. A taller, rounder hull (closer to the refs' tube) is tried alongside as a second
  blockout; if it wins, the decks may change to fit it.
- **Thrusters:** two big nacelles on the tail's shoulders with the ramp between them, high and short enough
  that they never hide the ramp and the ground right of it from the iso camera (checked with a probe), the
  nozzles at the tail. A dim glow in the nozzles while flying, off when landed.
- **Nose:** rounded like the refs: the cockpit's glazing on the upper deck, a round sensor eye in the nose
  tip with a faint glow, landing lights under it; solid below the cockpit (medical bay and engine room).
- **Landing gear:** the six legs along the sides become heavy hydraulic legs with broad pads (skids, no
  wheels or tracks) in bays in the belly's sides. They fold into their bays in space and in flight (title
  view, flight, docked) and come down in the touchdown's last seconds, up again at take-off (about 3 s).
- **Ramp:** wider than the greybox's 4 m (a cargo ramp: 10 m), still 5 m long at 30°: a heavy plate with
  ribs and side rails, lit edges, the status light over the door. The ramp button moves beside the wider
  door.

## Aboard

- The skin's parts in front of the camera vanish with their walls (shadows only, as the greybox walls);
  the greybox stubs inside stay as the cut line. A capped edge showing the hull's thickness comes with the
  VR viewpoint ([`vr-view.md`](vr-view.md)).
- Windows stay where the rooms have them and see-through both ways, through the skin.

## Look

- Weathered light grey panels (darker than the refs' off-white, so the hull sits in the muted world), dark
  grey machinery, a thin amber stripe along the sides, amber running lights, the warm window glow from
  inside, a registry code in stencil letters on the nose and tail (e.g. "LS-0417"; a name only if the story
  gives the ship one).
- Refs: `local/art-references/shipext_v2.png` (favorite) and its siblings; they're slim tubes, so they
  guide the language, not the proportions.

## How it's built

- A scripted Blender build (an asset script like the others, deterministic): the skin in pieces per cut
  group, window and door holes from the same layout as `game/ship/hull_build.py`, greebles from a small kit
  (vents, panels, pipes, lights) placed by the script, baked textures with weathering. Moving a room means
  rerunning the script.
- Blockout first, at the real size, rendered from the iso camera, the title view's angle and the side;
  then optional img2img paint-overs of the blockout (ComfyUI, rated on the concepts page) to explore detail
  and color on the right shape.
- Performance: one mesh per cut group with the kit merged in, about 150k triangles for the whole outside,
  2048 textures (trim sheet and a baked weathering mask), checked with the frame time on the landed view.

## The station

- The skin and nacelles are bigger than the box: the hangar's pressure frame and the four clamps at Waypost
  Ostra are resized to fit (in the station's greybox builder), so docking still looks right.
