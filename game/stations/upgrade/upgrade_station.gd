class_name UpgradeStation
extends Station
## An upgrade station (see GAME_DESIGN.md, Upgrade stations): a station whose parts are upgrades
## (each `StationPart.item` an `Upgrade`), e.g. the fitting frame (the suit) or the miners'
## maintenance pad (drill, ore tank, hose reel, plating). Its card (`UpgradeCard`) shows the
## selected upgrade and buys its next level into `get_levels` (the player using the station's, or
## the miner on the pad's), with ore from the player's own hold;
## the level then runs on the wall clock (see `Upgrades.start`) and can be stopped for the whole
## cost back (pressed twice). Upgrades of weapons the player doesn't own yet are locked, levels
## above the ship's reach wait for the next heat shield plate (`upgrade_cap`), and nothing can be
## bought or stopped while a mission is underway.

## The mission that locks it while underway; found in the scene tree when not set.
var mission: Mission
## The ship whose heat shield caps the levels; the one it stands in when not set.
var ship: Ship

## "Stop" waiting for its second press.
var stop_press := ConfirmPress.new()


func _process(delta: float) -> void:
	super(delta)
	if not mission:
		mission = get_tree().get_first_node_in_group(Mission.GROUP) as Mission
	if not ship:
		ship = Ship.nearest(get_tree(), global_position)
	# The hold, the owned weapons or the mission may change meanwhile.
	if user:
		refresh()


## Every upgrade it sells.
func get_upgrades() -> Array[Upgrade]:
	var upgrades: Array[Upgrade] = []
	for part: StationPart in get_parts():
		var upgrade := part.item as Upgrade
		if upgrade and upgrade not in upgrades:
			upgrades.append(upgrade)
	return upgrades


## The part showing `upgrade`, or null.
func get_part(upgrade: Upgrade) -> StationPart:
	for part: StationPart in get_parts():
		if part.item == upgrade:
			return part
	return null


## The levels it buys into: those of the player using it (null without one); the miners' bay
## buys into the miner on its pad.
func get_levels() -> Upgrades:
	return user.upgrades if user else null


## The weapon `upgrade` belongs to, or null (not a weapon's).
func get_weapon(_upgrade: Upgrade) -> WeaponType:
	return null


## Whether nothing can be bought right now.
func is_locked() -> bool:
	return mission != null and mission.is_underway()


## Whether the player using it has the upgrade's weapon (or it's not a weapon's).
func is_available(upgrade: Upgrade) -> bool:
	var weapon_type: WeaponType = get_weapon(upgrade)
	return not weapon_type or (user != null and user.arsenal.owns(weapon_type))


## The highest MK level that can be bought: the ship's heat shield decides (see
## `HeatShield.upgrade_cap`).
func upgrade_cap() -> int:
	return ship.heat_shield.upgrade_cap() if ship else 1


## Whether the player using it can buy the next level of `upgrade` right now.
func can_buy(upgrade: Upgrade) -> bool:
	if is_locked() or not user or not ship or not upgrade or not is_available(upgrade):
		return false
	var bought: Upgrades = get_levels()
	if not bought:
		return false
	var mk: int = bought.mk(upgrade)
	return (
		bought.next_level(upgrade) != null
		and not bought.is_running(upgrade)
		and mk < upgrade_cap()
		and user.hold.can_pay(bought.next_cost(upgrade))
	)


## Buys the next level of `upgrade` for the player using it, paid from their hold, and starts it on
## the wall clock. Returns whether it did.
func buy(upgrade: Upgrade) -> bool:
	if not can_buy(upgrade):
		return false
	var bought: Upgrades = get_levels()
	if not user.hold.pay(bought.next_cost(upgrade)):
		return false
	bought.start(upgrade, Time.get_unix_time_from_system())
	_bought(upgrade)
	refresh()
	return true


## Whether the user's level of `upgrade` under way can be stopped now.
func can_stop(upgrade: Upgrade) -> bool:
	var bought: Upgrades = get_levels()
	return not is_locked() and bought != null and bought.is_running(upgrade)


## Stops the user's level of `upgrade` under way on the second press (`stop_press`), its whole cost
## back into their hold. Returns whether it stopped.
func stop(upgrade: Upgrade) -> bool:
	if not can_stop(upgrade):
		return false
	if not stop_press.press(upgrade):
		refresh()
		return false
	var refund: Dictionary[OreType, int] = get_levels().stop(upgrade)
	for ore_type: OreType in refund:
		user.hold.add(ore_type, refund[ore_type])
	_bought(upgrade)
	refresh()
	return true


func sells(item: Resource) -> bool:
	return item is Upgrade and item in get_upgrades()


func select(part: StationPart) -> void:
	if part != selected:
		stop_press.reset()
	super(part)


## Called after buying or stopping a level of `upgrade` (e.g. to show it on the pips of what's
## shown).
func _bought(_upgrade: Upgrade) -> void:
	pass
