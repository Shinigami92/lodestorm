extends GutTest
## What the alloys go into besides the miners (see docs/design/resources.md): the upgrade levels
## from MK4 on, the prototypes' build, the ingot rack's "Used for" line, and jobs keeping what was
## paid.

const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")
const RACK_CARD: PackedScene = preload("res://game/stations/refinery/rack_card.tscn")
const ARMOR: Upgrade = preload("res://game/progression/upgrades/armor.tres")
const KYRITE: OreType = preload("res://game/ores/types/ore_kyrite.tres")
const COBREL: AlloyType = preload("res://game/refinery/alloys/alloy_cobrel.tres")
const GANTRITE: AlloyType = preload("res://game/refinery/alloys/alloy_gantrite.tres")
const MERISK: AlloyType = preload("res://game/refinery/alloys/alloy_merisk.tres")
const INDITE: AlloyType = preload("res://game/refinery/alloys/alloy_indite.tres")
const SYLITH: AlloyType = preload("res://game/refinery/alloys/alloy_sylith.tres")
const AURALT: AlloyType = preload("res://game/refinery/alloys/alloy_auralt.tres")
## Bars per prototype, by name (TBD (playtest)).
const PROTOTYPE_BARS: Dictionary[String, int] = {
	"Clout": 6, "Kith": 8, "Fulgen": 10, "Mantle": 10, "Nadir": 12, "Zenith": 15
}


## A prototype takes bars of the alloy of its own signature ore; the others take ores only.
func test_prototypes_take_the_alloy_of_their_signature_ore() -> void:
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		var alloys: Array[AlloyType] = []
		var signature: OreType = null
		for item: ItemType in weapon_type.build_cost:
			if item is AlloyType:
				alloys.append(item as AlloyType)
			elif (item as OreType).band == OreType.Band.SIGNATURE:
				signature = item as OreType
		var named: String = weapon_type.display_name
		if weapon_type.origin != WeaponType.Origin.PROTOTYPE:
			assert_true(alloys.is_empty(), "%s: ores only" % named)
			continue
		assert_eq(alloys.size(), 1, named)
		assert_true(alloys[0].recipe.has(signature), "%s: from its own signature ore" % named)
		assert_eq(weapon_type.build_cost[alloys[0]], PROTOTYPE_BARS[named], named)


## A job keeps what was paid when it started: retuning the costs doesn't change what stopping it
## gives back.
func test_a_job_gives_back_what_was_paid() -> void:
	var upgrades := Upgrades.new()
	upgrades.levels[ARMOR] = 3
	assert_true(upgrades.start(ARMOR, 0.0))
	var paid: Dictionary[ItemType, int] = ARMOR.cost_of(4)
	assert_eq(upgrades.get_job(ARMOR).paid, paid)
	assert_true(paid.has(MERISK))
	upgrades.get_job(ARMOR).paid.erase(MERISK)
	paid.erase(MERISK)
	assert_eq(upgrades.stop(ARMOR), paid, "what the job kept, not today's cost")


func test_rack_card_says_what_an_alloy_is_used_for() -> void:
	var card := RACK_CARD.instantiate() as RackCard
	add_child_autofree(card)
	assert_eq(card.uses_of(COBREL), PackedStringArray(["Miners"]))
	assert_eq(card.uses_of(MERISK), PackedStringArray(["Upgrades MK4"]))
	assert_eq(card.uses_of(INDITE), PackedStringArray(["Upgrades MK6", "Kith"]))
	assert_eq(card.uses_of(SYLITH), PackedStringArray(["Upgrades MK7", "Fulgen", "Mantle"]))
	assert_eq(card.uses_of(AURALT), PackedStringArray(["Zenith"]))
	assert_true(card.uses_of(GANTRITE).is_empty(), "the station's requests come later")
