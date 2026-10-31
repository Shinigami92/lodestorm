class_name LocationQuests
extends RefCounted
## What the active quest steps put into a generated location (its `GeneratedLocation.quest_visit`,
## see `QuestVisit`), once its parts are built: at each quest site's quest anchor (its middle
## without one) a hunt's brood nest or its strain asleep in a lair, an item to recover
## (`QuestItem`), else (if it isn't only there for its crate) a `QuestSite` that counts when
## reached; a goal's quest nests at its site's quest nest markers (`ClearNestsGoal.site_part`); a
## mark on every crate holding a fragment; and the NPCs waiting there for a step to be handed in
## (`QuestVisit.meetings`: at their part's person marker, talked to there through a `VisitQuests`,
## with a `HandInMark` and a hand repeller that keeps aliens off them, see `AlienRepeller`). A
## step handed in out there brings the next one's goals in during the run (`QuestVisit.extended`):
## its site's things, its fragments in unopened crates (as many as there are). Someone who joins
## the crew there packs up what belongs to them at their part (its nodes in `PACKS_UP_GROUP`, e.g.
## Hollis' old miner) as they set off for the ship.

const NPC: PackedScene = preload("res://game/npcs/npc.tscn")
## A part's nodes that the NPC waiting there packs up when they leave for the ship.
const PACKS_UP_GROUP: StringName = &"packs_up"
## How long packing it up takes (it shrinks away), in s.
const PACK_UP_TIME: float = 0.8
## How far the hand repeller of someone waiting out there keeps aliens off, in m. TBD (playtest).
const HAND_REPELLER_RADIUS: float = 4.0

var _location: GeneratedLocation
var _visit: QuestVisit
## The NPCs waiting here, by their profile's id.
var _people: Dictionary[StringName, Npc] = {}


func _init(location: GeneratedLocation) -> void:
	_location = location


## Adds what the visit needs (the location's parts are built).
func build() -> void:
	_visit = _location.quest_visit
	if not _visit:
		return
	_mark_crates()
	for meeting: QuestVisit.Entry in _visit.meetings:
		_add_person(meeting)
	_add_sites(_visit.entries)
	_visit.extended.connect(_on_extended)


## The NPC waiting here of profile `id`, or null.
func person(id: StringName) -> Npc:
	return _people.get(id) as Npc


## A mark on every crate holding a fragment, out once it's opened.
func _mark_crates() -> void:
	for crate: Crate in _location.find_children("*", "Crate", true, false):
		var fragment := crate.content as BlueprintFragment
		if fragment:
			crate.used.connect(QuestMark.on(crate, fragment.entry, _visit).close.unbind(1))


## What every one of `entries` with a quest site holds at its part.
func _add_sites(entries: Array[QuestVisit.Entry]) -> void:
	for entry: QuestVisit.Entry in entries:
		var part: LocationParts.Placed = _location.parts.placed_for(entry.site)
		if not part:
			continue
		var anchors: Array[Vector3] = part.markers(PartMarker.Kind.QUEST_ANCHOR)
		var at: Vector3 = anchors[0] if not anchors.is_empty() else part.origin
		if entry.hunted and entry.brood:
			_add_brood_nest(entry, at)
		elif entry.hunted:
			_add_lair(entry, at)
		elif entry.nests > 0:
			_add_site_nests(entry, part)
		elif entry.item:
			var item := QuestItem.new()
			item.name = "QuestItem"
			item.entry = entry
			item.position = at
			# Picked up, it goes with the item.
			QuestMark.on(item, entry, _visit)
			_location.add_child(item, true)
		elif entry.fragments == 0:
			var site := QuestSite.new()
			site.name = "QuestSite"
			site.position = at
			site.reached.connect(_visit.count.bind(entry, 1.0).unbind(1))
			site.reached.connect(QuestMark.on(site, entry, _visit).close.unbind(1))
			_location.add_child(site, true)


## `entry`'s quest nests at `part`'s quest nest markers (one each, in turn; its middle without
## any).
func _add_site_nests(entry: QuestVisit.Entry, part: LocationParts.Placed) -> void:
	var spots: Array[Vector3] = part.markers(PartMarker.Kind.QUEST_NEST)
	for i: int in entry.nests:
		var nest := GeneratedLocation.QUEST_NEST.instantiate() as AlienNest
		nest.name = "QuestNest"
		nest.table = _location.hatch_table(nest.hive)
		nest.position = spots[i % spots.size()] if not spots.is_empty() else part.origin
		nest.destroyed.connect(_visit.count.bind(entry, 1.0))
		nest.destroyed.connect(QuestMark.on(nest, entry, _visit).close)
		_nests().add_child(nest, true)


## `entry`'s brood nest at `at`: it hatches the hunted strain, as many as the hunt still needs;
## kills of it and the nest destroyed count for the hunt.
func _add_brood_nest(entry: QuestVisit.Entry, at: Vector3) -> void:
	var nest := entry.brood.instantiate() as AlienNest
	nest.name = "BroodNest"
	nest.table = _location.hatch_table(nest.hive)
	nest.brood = entry.hunted
	nest.brood_left = _visit.kills_left(entry)
	nest.position = at
	nest.rotation.y = (
		GeneratedLocation.random_stream(_location.world_seed, "brood_nest").randf() * TAU
	)
	nest.hatched.connect(
		func(alien: Alien) -> void:
			if alien.strain == entry.hunted:
				alien.died.connect(_visit.count_kill.bind(entry))
	)
	nest.destroyed.connect(_visit.count_brood.bind(entry))
	nest.destroyed.connect(QuestMark.on(nest, entry, _visit).close)
	_nests().add_child(nest)


## The hunted strain (the Ravager) asleep at `at`, in its lair, until a player comes close: killing
## it counts for the hunt.
func _add_lair(entry: QuestVisit.Entry, at: Vector3) -> void:
	var table: HatchTable = _location.hatch_table(GeneratedLocation.HIVE)
	var lair := ApexLair.new()
	lair.name = "Lair"
	lair.strain = entry.hunted
	lair.health_factor = table.health_factor
	lair.damage_factor = table.damage_factor
	lair.route = [at] as Array[Vector3]
	lair.asleep = true
	# The apex appears when the location enters the tree.
	var count: Callable = _visit.count_kill.bind(entry)
	var mark: QuestMark = QuestMark.on(lair, entry, _visit, at)
	lair.ready.connect(
		func() -> void:
			lair.apex.died.connect(count)
			lair.apex.died.connect(mark.close),
		CONNECT_ONE_SHOT
	)
	_location.add_child(lair, true)


## `meeting`'s NPC at its part's person marker (its middle without one), facing the way the marker
## does; one already waiting here only gets the meeting's mark.
func _add_person(meeting: QuestVisit.Entry) -> void:
	var id: StringName = meeting.quest.hand_in_npc(meeting.step)
	var npc: Npc = person(id)
	if not npc:
		var profile: NpcProfile = NpcProfile.find(id)
		var part: LocationParts.Placed = _location.parts.placed_for(meeting.site)
		if not profile or not part:
			push_warning("No place out here for %s" % id)
			return
		npc = NPC.instantiate() as Npc
		npc.name = "Person_%s" % id
		npc.profile = profile
		npc.waits_to_join = true
		npc.quests_view = _visit.view()
		npc.transform = _person_spot(part)
		npc.walks_aboard.connect(_pack_up.bind(part))
		var repeller := AlienRepeller.new()
		repeller.name = "HandRepeller"
		repeller.radius = HAND_REPELLER_RADIUS
		npc.add_child(repeller)
		_people[id] = npc
		_location.add_child(npc, true)
	HandInMark.on_person(npc, meeting, _visit)


## Where the NPC waiting at `part` stands: its person marker (facing its way), else its middle.
func _person_spot(part: LocationParts.Placed) -> Transform3D:
	for i: int in part.info.marker_kinds.size():
		if part.info.marker_kinds[i] == PartMarker.Kind.PERSON:
			return part.transform() * part.info.marker_spots[i]
	return part.transform()


## The NPC waiting at `part` set off for the ship: what belongs to them there shrinks away.
func _pack_up(part: LocationParts.Placed) -> void:
	if not part.node:
		return
	for node: Node in part.node.find_children("*", "Node3D", true, false):
		var packed := node as Node3D
		if not packed.is_in_group(PACKS_UP_GROUP):
			continue
		var tween: Tween = packed.create_tween()
		(
			tween
			. tween_property(packed, ^"scale", Vector3.ONE * 0.01, PACK_UP_TIME)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_IN)
		)
		tween.tween_callback(packed.hide)


## A step handed in out here started the next one: what its goals need here comes in now.
func _on_extended(added: Array[QuestVisit.Entry], meeting: QuestVisit.Entry) -> void:
	if meeting:
		_add_person(meeting)
	_add_sites(added)
	_fill_crates(added)


## Puts the fragments of `entries` into unopened crates (one each, at random among them; as many as
## there are crates).
func _fill_crates(entries: Array[QuestVisit.Entry]) -> void:
	var wanted: Array[QuestVisit.Entry] = []
	for entry: QuestVisit.Entry in entries:
		for i: int in entry.fragments:
			wanted.append(entry)
	if wanted.is_empty():
		return
	var crates: Array[Crate] = []
	for crate: Crate in _location.find_children("*", "Crate", true, false):
		if not crate.opened and crate.content is SupplyCache:
			crates.append(crate)
	var rng: RandomNumberGenerator = GeneratedLocation.random_stream(
		_location.world_seed, "late_fragments"
	)
	for i: int in range(crates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Crate = crates[i]
		crates[i] = crates[j]
		crates[j] = swap
	for i: int in mini(wanted.size(), crates.size()):
		var fragment := BlueprintFragment.new()
		fragment.entry = wanted[i]
		crates[i].content = fragment
		crates[i].used.connect(QuestMark.on(crates[i], wanted[i], _visit).close.unbind(1))
	if wanted.size() > crates.size():
		push_warning("No crate left for %d fragments" % (wanted.size() - crates.size()))


## Where the location's nests are.
func _nests() -> Node3D:
	return _location.get_node(^"AlienNests") as Node3D
