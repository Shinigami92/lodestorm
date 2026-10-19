class_name HatchTable
extends RefCounted
## What a location's nests hatch (built by `AlienHive.table`): which strains, from which point of
## the hive's escalation on, and which of the hive's packs that allows. Hunters and guards come in
## packs, raiders one by one (by `AlienStrain.raider_weight`); strains the biome favors come more
## often.

var hive: AlienHive
## The escalation from which each strain hatches; strains not in it don't hatch here.
var from: Dictionary[AlienStrain, float] = {}
## The biome's favored strains.
var favored: Array[AlienStrain] = []


## Whether `strain` hatches at escalation `level`.
func hatches(strain: AlienStrain, level: float) -> bool:
	return from.has(strain) and level >= from[strain]


## The strains that hatch at escalation `level`.
func strains_at(level: float) -> Array[AlienStrain]:
	var hatching: Array[AlienStrain] = []
	for strain: AlienStrain in from:
		if hatches(strain, level):
			hatching.append(strain)
	return hatching


## The packs whose strains all hatch at escalation `level`.
func packs_at(level: float) -> Array[AlienPack]:
	var usable: Array[AlienPack] = []
	for pack: AlienPack in hive.packs:
		if pack.weight > 0.0 and pack.members.keys().all(hatches.bind(level)):
			usable.append(pack)
	return usable


## How likely `pack` is picked: its weight, more if it has a favored strain.
func weight_of(pack: AlienPack) -> float:
	for strain: AlienStrain in pack.members:
		if strain in favored:
			return pack.weight * hive.favored_weight
	return pack.weight


## A pack to hatch at escalation `level`, or null when none fits.
func pick_pack(rng: RandomNumberGenerator, level: float) -> AlienPack:
	var usable: Array[AlienPack] = packs_at(level)
	var weights: Array[float] = []
	for pack: AlienPack in usable:
		weights.append(weight_of(pack))
	var index: int = _pick(rng, weights)
	return usable[index] if index >= 0 else null


## A raider's strain at escalation `level`, or null when none raids.
func pick_raider(rng: RandomNumberGenerator, level: float) -> AlienStrain:
	var raiders: Array[AlienStrain] = []
	var weights: Array[float] = []
	for strain: AlienStrain in strains_at(level):
		if strain.raider_weight > 0.0:
			raiders.append(strain)
			weights.append(
				strain.raider_weight * (hive.favored_weight if strain in favored else 1.0)
			)
	var index: int = _pick(rng, weights)
	return raiders[index] if index >= 0 else null


func _pick(rng: RandomNumberGenerator, weights: Array[float]) -> int:
	if weights.is_empty():
		return -1
	return rng.rand_weighted(PackedFloat32Array(weights))
