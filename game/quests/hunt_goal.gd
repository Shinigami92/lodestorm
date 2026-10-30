class_name HuntGoal
extends RegionGoal
## Hunt a strain in a region (see docs/planned/quests.md, Quest nests and hunts): while the step is
## active, every visit puts its site's map part in (a den, a hive hollow) and at the part's quest
## anchor a `brood_nest` that hatches `amount` of the strain once a player comes close; only kills
## of it from that nest count, and the nest must be destroyed too, so the goal's target is one more
## than `amount`. Without a brood nest the strain (the hive's apex, the Ravager) sleeps at the
## anchor, in its lair, and killing it does the job.

@export var strain: AlienStrain
## How many of it to kill (with a brood nest; in a lair: one).
@export_range(1, 50) var amount: int = 5
## The map part of the hunt's site (with a quest anchor where the nest stands or the strain
## sleeps; else its middle).
@export var site_part: PartPlacement
## The brood nest's scene (one of its looks, `game/aliens/nest/brood_*.tscn`); null: a lair.
@export var nest_scene: PackedScene


func describe() -> String:
	if nest_scene:
		return tr("Hunt: %s and their brood nest") % tr(strain.display_name)
	return tr("Hunt: %s") % tr(strain.display_name)


## The kills (`amount`) and the brood nest; in a lair, the one kill.
func target() -> float:
	return amount + 1.0 if nest_scene else 1.0


func counted() -> float:
	return float(amount) if nest_scene else 1.0


func site() -> PartPlacement:
	return site_part


func hunted() -> AlienStrain:
	return strain


func brood_nest() -> PackedScene:
	return nest_scene
