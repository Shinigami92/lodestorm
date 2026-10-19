class_name AlienPack
extends Resource
## A pack that hatches together and goes out as hunters (or waits as guards): how many of each
## strain (e.g. two swarmers and a spitter). A nest picks one by `weight` among the packs whose
## strains all hatch there (see `HatchTable`). All values TBD (playtest).

## How many of each strain.
@export var members: Dictionary[AlienStrain, int] = {}
## How likely it's picked, against the other packs.
@export var weight: float = 1.0


## Its strains, one entry per alien.
func aliens() -> Array[AlienStrain]:
	var all: Array[AlienStrain] = []
	for strain: AlienStrain in members:
		for i: int in members[strain]:
			all.append(strain)
	return all


## How much it counts towards the cap on living aliens (see `AlienStrain.cap_share`).
func cap_load() -> float:
	var total: float = 0.0
	for strain: AlienStrain in members:
		total += strain.cap_share * members[strain]
	return total
