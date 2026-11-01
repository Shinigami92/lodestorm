class_name SurvivalCalls
extends Node
## The crew's calls that help a new crew survive out there (see docs/design/crew.md, Surviving out
## there), made through `reactions` (`CrewReactions.transmit`):
## - a destination harder than the least equipped player's gear (`gear_needed` > `gear_of`): once
##   per needed count (`DESTINATION_ROUGH`, the region its subject);
## - the first lost run, once everyone is awake again (`FIRST_RUN_LOST`);
## - landing in a normal or hard region the pilot knows (`knows`, as it was when it was chosen as
##   the destination): once per region (`REGION_LANDING`); the first landing anywhere also brings
##   the hint to fill up at a miner first (`MINER_HINT`), once per game;
## - a player badly hurt out there, not hurt and not attacking for `CALM_TIME`: once per run each,
##   only to them (`LOW_HEALTH`);
## - a player's equipped weapon using up its last spares out there with no ore on their back: once
##   per player (`OUT_OF_SPARES`, a hint saved with the player).
## The one-time ones set story flags (`event.<event>`, `event.destination_rough.<count>`,
## `event.region.<region>`).

## Upgrades a region needs per tier of its body above the first. TBD (playtest).
const GEAR_PER_TIER: int = 3
## Upgrades a region needs for its danger (easy, normal, hard). TBD (playtest).
const GEAR_BY_DANGER: Array[int] = [0, 1, 3]
## Below this share of their health, a player is badly hurt. TBD (playtest).
const LOW_HEALTH_SHARE: float = 0.25
## Seconds a badly hurt player goes without being hurt or attacking before the call. TBD
## (playtest).
const CALM_TIME: float = 5.0
## The tier of the colony's own ground (Torvane and its moon): the pilot knows all its regions.
const HOME_TIER: int = 1
## The story flag of a planet's or moon's topic at the bar on the station (`%s`: its id): the
## crews there talk about its regions, so the pilot knows them once it's heard.
const HEARD_AT_THE_BAR: String = "bartender.%s"
## The player's hint (`PlayerHints`) of the call about the last spares.
const OUT_OF_SPARES_HINT: StringName = &"out_of_spares"

## Whose calls these are.
var reactions: CrewReactions

## The destination's region when the pilot knew it as it was chosen (a visit there counts from the
## next one on), else null; used up by the landing.
var _known_region: Region
## Whether the first lost run waits for everyone to wake up.
var _run_lost: bool = false
## Seconds each player has gone without being hurt or attacking this run.
var _calm: Dictionary[Player, float] = {}
## Players badly hurt called this run.
var _hurt_called: Array[Player] = []
## Spare rounds each weapon's ammo had when last looked at this run.
var _spares: Dictionary[WeaponAmmo, int] = {}


func _ready() -> void:
	var events: GameEvents = GameEvents.bus
	events.destination_chosen.connect(_on_destination_chosen)
	events.mission_started.connect(_forget_run.unbind(1))
	events.mission_ended.connect(_on_mission_ended)
	events.player_hurt.connect(_on_player_hurt.unbind(2))
	events.weapon_attacked.connect(_on_player_hurt.unbind(1))


func _physics_process(delta: float) -> void:
	if not _running():
		return
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if player.fallen or reactions.ship.is_aboard(player):
			continue
		_calm[player] = _calm.get(player, 0.0) + delta
		_check_hurt(player)
		_check_spares(player)


## Upgrades the gear of `player` counts: the MK levels above MK1 of their weapons' parts and their
## suit's armor, and the ranks of their skills, each with the one under way.
static func gear_of(player: Player) -> int:
	var count: int = 0
	for upgrade: Upgrade in player.upgrades.levels:
		if upgrade is WeaponPart or upgrade == player.armor_upgrade:
			count += player.upgrades.mk(upgrade) - 1
	for upgrade: Upgrade in player.upgrades.jobs:
		if upgrade is WeaponPart or upgrade == player.armor_upgrade:
			count += 1
	for skill: Skill in player.skills.ranks:
		count += player.skills.rank(skill)
	return count + player.skills.jobs.size()


## Upgrades a region of `danger` on a body of `tier` needs (see `GEAR_PER_TIER`).
static func gear_needed(tier: int, danger: MissionBrief.Difficulty) -> int:
	return (maxi(tier, 1) - 1) * GEAR_PER_TIER + GEAR_BY_DANGER[danger]


## Whether the pilot knows `region`: on the colony's own ground, visited before, or talked about
## at the bar.
func knows(region: Region) -> bool:
	var ship: Ship = reactions.ship
	if region.id in ship.director.regions_visited:
		return true
	var body: CelestialBody = _body_of(region)
	return (
		body != null
		and (body.tier == HOME_TIER or ship.story.is_set(StringName(HEARD_AT_THE_BAR % body.id)))
	)


## The first player stepped out (after the body's first landing call): the region's call and the
## miner hint, each once.
func landed() -> void:
	var region: Region = _known_region
	_known_region = null
	var voyage: Voyage = reactions.ship.voyage
	var brief: MissionBrief = voyage.brief if voyage else null
	if (
		region
		and brief
		and brief.region == region
		and region.danger != MissionBrief.Difficulty.EASY
		and _first(StringName("event.region.%s" % region.id))
	):
		reactions.transmit(CrewReactions.REGION_LANDING, region.id)
	if _first(StringName("event.%s" % CrewReactions.MINER_HINT)):
		reactions.transmit(CrewReactions.MINER_HINT)


## A player woke up in the medical bay (after the first fall's call): the first lost run's call
## once everyone is up.
func woke() -> void:
	if not _run_lost:
		return
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if player.dead:
			return
	_run_lost = false
	reactions.transmit(CrewReactions.FIRST_RUN_LOST)


## The least gear among the players (see `gear_of`), 0 without any.
func least_gear() -> int:
	var least: int = -1
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		var gear: int = gear_of(player)
		least = gear if least < 0 else mini(least, gear)
	return maxi(least, 0)


func _running() -> bool:
	var voyage: Voyage = reactions.ship.voyage if reactions and reactions.ship else null
	return (
		voyage != null
		and voyage.mission != null
		and voyage.mission.state in [Mission.State.RUNNING, Mission.State.STORM]
	)


func _check_hurt(player: Player) -> void:
	if (
		player in _hurt_called
		or player.health >= player.max_health() * LOW_HEALTH_SHARE
		or _calm[player] < CALM_TIME
	):
		return
	_hurt_called.append(player)
	reactions.transmit(CrewReactions.LOW_HEALTH, &"", player)


func _check_spares(player: Player) -> void:
	var ammo: WeaponAmmo = player.arms.get_ammo()
	if not ammo:
		return
	var before: int = _spares.get(ammo, -1)
	_spares[ammo] = ammo.spare_rounds
	if (
		before <= 0
		or ammo.spare_rounds > 0
		or not player.cargo.is_empty()
		or player.hints.is_seen(OUT_OF_SPARES_HINT)
	):
		return
	player.hints.mark_seen(OUT_OF_SPARES_HINT)
	reactions.transmit(CrewReactions.OUT_OF_SPARES, &"", player)


func _body_of(region: Region) -> CelestialBody:
	var voyage: Voyage = reactions.ship.voyage
	var system: StarSystem = voyage.settings.system if voyage and voyage.settings else null
	return system.body_of(region) if system else null


## Sets a one-time story flag; returns whether it wasn't set yet.
func _first(flag: StringName) -> bool:
	var story: Story = reactions.ship.story
	if story.is_set(flag):
		return false
	story.set_flag(flag)
	return true


func _forget_run() -> void:
	_calm.clear()
	_hurt_called.clear()
	_spares.clear()


func _on_destination_chosen(brief: MissionBrief) -> void:
	var region: Region = brief.region if brief else null
	_known_region = region if region and knows(region) else null
	if not region:
		return
	var body: CelestialBody = _body_of(region)
	var needed: int = gear_needed(body.tier if body else 1, region.danger)
	if needed <= 0 or least_gear() >= needed:
		return
	if _first(StringName("event.%s.%d" % [CrewReactions.DESTINATION_ROUGH, needed])):
		reactions.transmit(CrewReactions.DESTINATION_ROUGH, region.id)


func _on_mission_ended(_brief: MissionBrief, returned: bool) -> void:
	_forget_run()
	if not returned and _first(StringName("event.%s" % CrewReactions.FIRST_RUN_LOST)):
		_run_lost = true


func _on_player_hurt(player: Player) -> void:
	if player:
		_calm[player] = 0.0
