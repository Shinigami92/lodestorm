class_name RackCard
extends StationCard
## The holo card of the ingot rack (`IngotRack`): the selected shelf's alloy (its badge, name and
## tier), how many bars the hold has, its recipe per bar and what it's used for (the miners' build,
## the upgrade levels and the weapons whose cost has it). An unknown alloy shows as "?" with the
## ores of its recipe found so far.

const ALL_WEAPONS: Arsenal = preload("res://game/weapons/all_weapons.tres")
const MINER_SETTINGS: MinerSettings = preload("res://game/mining/miner_settings.tres")

## The alloy, whether it was known and how many of its ores were found when `_recipe` was last
## filled.
var _recipe_of: AlloyType
var _recipe_known: bool = false
var _recipe_found: int = -1

@onready var _badge: CenterContainer = %Badge
@onready var _title: Label = %Title
@onready var _tier: Label = %Tier
@onready var _amount: Label = %Amount
@onready var _recipe_label: Label = %RecipeLabel
@onready var _recipe: HFlowContainer = %Recipe
@onready var _used_for: Label = %UsedFor
@onready var _close: Button = %Close


func _ready() -> void:
	_close.pressed.connect(_on_close_pressed)


func show_part(part: StationPart) -> void:
	var shelf := part as RackShelf
	var rack := station as IngotRack
	visible = shelf != null and rack != null
	if not visible:
		return
	var alloy: AlloyType = shelf.alloy
	var player: Player = rack.get_shown_player()
	var hold: PlayerHold = player.hold if player else PlayerHold.new()
	_set_badge(alloy if shelf.known else null)
	_tier.text = tr("Tier %d alloy") % alloy.tier
	if not shelf.known:
		_title.text = tr("Unknown alloy")
		_amount.visible = false
		_recipe_label.text = tr("Ores found so far:")
	else:
		_title.text = alloy.get_display_name()
		_amount.visible = true
		_amount.text = tr("In the rack: %d") % shelf.count
		_recipe_label.text = tr("Per bar:")
	_show_recipe(alloy, shelf.known, hold)
	var uses: PackedStringArray = uses_of(alloy)
	_used_for.visible = not uses.is_empty()
	_used_for.text = tr("Used for: %s") % ", ".join(uses)


## What `alloy` goes into, translated: the miners' build ("Miners"), the upgrade levels whose cost
## has it ("Upgrades MK4") and the weapons whose build cost has it (their names); empty: nothing
## yet.
func uses_of(alloy: AlloyType) -> PackedStringArray:
	var uses: PackedStringArray = []
	if MINER_SETTINGS.build_cost.has(alloy):
		uses.append(tr("Miners"))
	var levels: PackedStringArray = []
	for mk: int in range(2, Upgrade.COSTS.levels.size() + 2):
		if Upgrade.COSTS.cost_of(mk).has(alloy):
			levels.append("MK%d" % mk)
	if not levels.is_empty():
		uses.append(tr("Upgrades %s") % ", ".join(levels))
	for weapon_type: WeaponType in ALL_WEAPONS.weapons:
		if weapon_type.build_cost.has(alloy):
			uses.append(weapon_type.display_name)
	return uses


## Lists the recipe's ores with their units per bar, or (unknown) the ones found so far and "?".
func _show_recipe(alloy: AlloyType, known: bool, hold: PlayerHold) -> void:
	var found: Array[OreType] = alloy.found_ores(hold)
	if alloy == _recipe_of and known == _recipe_known and found.size() == _recipe_found:
		return
	_recipe_of = alloy
	_recipe_known = known
	_recipe_found = found.size()
	for node: Node in _recipe.get_children():
		_recipe.remove_child(node)
		node.queue_free()
	for ore_type: OreType in alloy.recipe:
		if not known and ore_type not in found:
			continue
		var entry := HBoxContainer.new()
		entry.add_theme_constant_override(&"separation", 8)
		entry.add_child(ItemBadge.new(ore_type))
		if known:
			entry.add_child(_label(str(alloy.recipe[ore_type])))
		_recipe.add_child(entry)
	if not known:
		var unknown := _label("?")
		unknown.modulate = CardPalette.NOTE
		_recipe.add_child(unknown)


func _set_badge(item: ItemType) -> void:
	var shown := _badge.get_child(0) as ItemBadge if _badge.get_child_count() > 0 else null
	if not shown:
		shown = ItemBadge.new(null, false)
		_badge.add_child(shown)
	shown.item = item
	_badge.visible = item != null


func _on_close_pressed() -> void:
	if station:
		station.close()
