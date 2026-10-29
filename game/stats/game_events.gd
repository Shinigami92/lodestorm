class_name GameEvents
extends RefCounted
## What happens in the game, as signals on one bus (`GameEvents.bus`) that anyone can listen to:
## the statistics (`StatsRecorder`), later achievements and quest objectives. Gameplay emits them
## where they happen (`GameEvents.bus.alien_killed.emit(...)`) and never waits for a listener;
## a signal nobody listens to costs next to nothing. Events of a player name the one they're
## credited to (null: nobody's, e.g. an alien killed by acid); every machine sees all of them and
## keeps its own player's (see `Player.local`). Adding an event: a signal here, its emit where it
## happens, and its handling in the listeners that care.
## Not an autoload: the bus is a static instance, so scripts run before the autoloads exist (tests,
## probes) can emit too.

@warning_ignore_start("unused_signal")

# Combat.

## A weapon attacked once (a shot, a swing, a flame's tick).
signal weapon_attacked(player: Player, weapon_type: WeaponType)
## A hit landed on an alien, and whether its armor took a share.
signal alien_hit(player: Player, weapon_type: WeaponType, alien: Alien, armored: bool)
## An alien lost `amount` health (past its armor; burning and acid too).
signal alien_damaged(player: Player, weapon_type: WeaponType, alien: Alien, amount: float)
## An alien died, credited to the player (and weapon) who hurt it last.
signal alien_killed(player: Player, weapon_type: WeaponType, alien: Alien)
## An alien appeared (hatched from a nest, a pack, the apex's lair).
signal alien_appeared(alien: Alien)
## A nest lost `amount` health.
signal nest_damaged(player: Player, weapon_type: WeaponType, nest: AlienNest, amount: float)
## A nest was destroyed, credited to the player who hurt it last.
signal nest_destroyed(player: Player, weapon_type: WeaponType, nest: AlienNest)
## A reload started (`vent`: a hot weapon venting).
signal reload_started(player: Player, weapon_type: WeaponType, vent: bool)
## The timing press of a reload or vent: whether it was within the window.
signal reload_timed(player: Player, weapon_type: WeaponType, hit: bool)
## A reload couldn't start: nothing pays more rounds.
signal reload_denied(player: Player, weapon_type: WeaponType)
## Carried ore made into ammo.
signal ammo_paid(player: Player, ore_type: OreType, amount: float)
## A shield's field took `amount` damage (a blow or a shot).
signal shield_blocked(player: Player, weapon_type: WeaponType, amount: float)
## The suit's dash.
signal dashed(player: Player)

# The player's health.

## The player lost `amount` health to `cause` (an alien, acid, the ground, the storm: the node
## that dealt it, or null).
signal player_hurt(player: Player, amount: float, cause: Node)
## The player died; `cause` dealt the last damage.
signal player_died(player: Player, cause: Node)
## The player got `amount` health back (regeneration, the med bed, a mending beam).
signal player_healed(player: Player, amount: float)
## A dead player came back.
signal player_respawned(player: Player)

# Mining and ore.

## A miner was placed on an ore node, or picked up again.
signal miner_placed(player: Player, miner: Miner)
signal miner_picked_up(player: Player, miner: Miner)
## A miner broke down, works again after repairs, or its ore node ran dry.
signal miner_broke(miner: Miner)
signal miner_repaired(miner: Miner)
signal miner_ran_dry(miner: Miner)
## Ore arrived on the player's back (a hose, a miner picked up).
signal ore_collected(player: Player, ore_type: OreType, amount: float)
## Ore the player brought into the hold: carried aboard at the end of a run, or at the cargo hatch.
signal ore_hauled(player: Player, ore_type: OreType, amount: float)
## Ore the player carried when they died.
signal ore_lost(player: Player, ore_type: OreType, amount: float)

# Progression.

## A weapon was built (or unlocked), or its blueprint found.
signal weapon_unlocked(player: Player, weapon_type: WeaponType)
signal blueprint_learned(player: Player, weapon_type: WeaponType)
## An upgrade reached its MK level `mk`, a skill its rank.
signal upgrade_finished(player: Player, upgrade: Upgrade, mk: int)
signal skill_finished(player: Player, skill: Skill, rank: int)
## A crafted miner was built, a part of it (`upgrade`) reached its MK level `mk`, or it was left on
## the planet (at `where`, e.g. "Torvane, Redscar Flats") when the run ended.
signal miner_built(player: Player, miner: CraftedMiner)
signal miner_part_finished(player: Player, miner: CraftedMiner, upgrade: Upgrade, mk: int)
signal miner_lost(player: Player, miner: CraftedMiner, where: String)
## A furnace finished `count` bars of `alloy` for the player.
signal bars_refined(player: Player, alloy: AlloyType, count: int)
## The ship's heat shield reached MK level `mk`.
signal heat_shield_raised(mk: int)
## A story flag was set (a topic heard to the end).
signal story_flag_set(flag: StringName)

# Missions and the ship.

## A run started (the first player left the ship).
signal mission_started(brief: MissionBrief)
## The storm's warning started (see `Mission.warning_time`).
signal storm_warned
## The storm broke (the timer ran out).
signal storm_started
## The late deposit's meteor hit the ground at `position` (see `LateDeposit`).
signal deposit_landed(position: Vector3)
## A run ended: everyone alive aboard (`returned`), or everyone dead.
signal mission_ended(brief: MissionBrief, returned: bool)
## The player opened a 3D menu (a station, a terminal).
signal menu_opened(player: Player, menu: WorldMenu)

@warning_ignore_restore("unused_signal")

## The bus.
static var bus: GameEvents = GameEvents.new()


## The player `node` is (a hit's attacker, a weapon's holder), or null.
static func player_of(node: Object) -> Player:
	return node as Player if is_instance_valid(node) else null


## A short, readable id of `resource` for the statistics: its path in `game/` without the
## extension (e.g. `weapons/types/harl/harl`), "none" without one. File names stay when display
## names change, so ids survive a rename.
static func id_of(resource: Resource) -> String:
	if not resource or resource.resource_path.is_empty():
		return "none"
	return resource.resource_path.trim_prefix("res://game/").trim_suffix(".tres")
