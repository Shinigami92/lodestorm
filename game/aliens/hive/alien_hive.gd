class_name AlienHive
extends Resource
## The hive's roster (`hive.tres`): every strain and the packs hunters and guards come in. A
## location's nests hatch from a `HatchTable` built from it (`table`): the strains of the body's
## tier and below, the tier's new ones late in a run, and in hard regions one of the next tier's
## even later. A new strain is its folder in `game/aliens/strains/`, an entry here and packs with
## it. Its apex (the Ravager) isn't hatched by nests: some locations have one roaming (see
## `apex_chance_at`, `ApexLair`). All values TBD (playtest).

## Every strain.
@export var strains: Array[AlienStrain] = []
## The packs hunters and guards come in.
@export var packs: Array[AlienPack] = []
## The escalation from which the body's own new strains (of its tier) hatch: late in a run on the
## first planet that brings them, from the start on the next one. The first tier's hatch from the
## start.
@export_range(0.0, 1.0) var new_strains_from: float = 0.5
## The escalation from which hard regions preview one strain of the next tier.
@export_range(0.0, 1.0) var preview_from: float = 0.75
## How much likelier packs (and raiders) with a strain the biome favors are (see
## `LocationBiome.favored_strains`).
@export var favored_weight: float = 2.0

@export_group("Tiers")
## Each tier above 1 (planets farther in, see `CelestialBody.tier`) adds this share of the aliens'
## health (the nests' and the apex's too) ...
@export var health_per_tier: float = 0.3
## ... and of their damage (more nests: `VoyageSettings.nests_per_tier`).
@export var damage_per_tier: float = 0.2

@export_group("Apex")
## The hive's apex (the Ravager): at most one per location, roaming (see `ApexLair`); null: none.
@export var apex: AlienStrain
## From this tier on a location may have it: with `apex_chance` on that tier and
## `apex_chance_per_tier` more for each tier above.
@export var apex_from_tier: int = 3
@export_range(0.0, 1.0) var apex_chance: float = 0.25
@export var apex_chance_per_tier: float = 0.1


## What nests hatch on a body of `tier` in `biome`; `preview` (a hard region) adds one strain of
## the next tier, picked by `pick_seed` (the location's seed, so a location keeps it).
func table(
	tier: int, biome: LocationBiome = null, preview: bool = false, pick_seed: int = 0
) -> HatchTable:
	var hatching := HatchTable.new()
	hatching.hive = self
	hatching.health_factor = health_at(tier)
	hatching.damage_factor = damage_at(tier)
	if biome:
		hatching.favored = biome.favored_strains
	var first: int = first_tier()
	var next: Array[AlienStrain] = []
	for strain: AlienStrain in strains:
		if strain.tier < tier or strain.tier == first:
			hatching.from[strain] = 0.0
		elif strain.tier == tier:
			hatching.from[strain] = new_strains_from
		elif strain.tier == tier + 1:
			next.append(strain)
	if preview and not next.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = pick_seed
		var weights: Array[float] = []
		for strain: AlienStrain in next:
			weights.append(favored_weight if strain in hatching.favored else 1.0)
		hatching.from[next[rng.rand_weighted(PackedFloat32Array(weights))]] = preview_from
	return hatching


## How much more health aliens have on a body of `tier` than on a tier 1 one.
func health_at(tier: int) -> float:
	return MissionSettings.per_tier(health_per_tier, tier)


## How much more damage aliens do on a body of `tier` than on a tier 1 one.
func damage_at(tier: int) -> float:
	return MissionSettings.per_tier(damage_per_tier, tier)


## How likely a location on a body of `tier` has the apex.
func apex_chance_at(tier: int) -> float:
	if not apex or tier < apex_from_tier:
		return 0.0
	return clampf(apex_chance + apex_chance_per_tier * (tier - apex_from_tier), 0.0, 1.0)


## The lowest tier of its strains: the first planet's.
func first_tier() -> int:
	var lowest: int = 1 << 30
	for strain: AlienStrain in strains:
		lowest = mini(lowest, strain.tier)
	return lowest
