class_name NpcPresence
extends RefCounted
## Whether a crew member (`npc`, see docs/design/crew.md) is here (`is_here`): one who joins later
## (`NpcProfile.join_flag`) isn't there until they're aboard, and their place before joining
## (`Npc.waits_to_join`) is there until they join, then walks aboard (`NpcBoarding`) and is gone
## once through the door, where their crew member aboard takes over (`arrive`). Follows the story
## (`start`) and shows or hides them (`update`, `changed`).

## Emitted after `update` (the NPC then lets them move and be talked to, or not).
signal changed

## Whose presence it is.
var npc: Npc

## At their place before joining: whether they've joined (walking aboard or gone).
var _joined: bool = false


func _init(who: Npc) -> void:
	npc = who


## Starts following the story (the ship's, found a frame after the rooms are ready); at their
## place before joining, one who joined already (a save) is gone from it.
func start() -> void:
	var story: Story = npc.get_story()
	_joined = npc.waits_to_join and npc.profile.is_aboard(story)
	story.changed.connect(update)
	update()


## Whether they're here: a crew member once they're aboard (`NpcProfile.is_aboard`) and not on
## their way aboard any more (`NpcBoarding.is_walking`); at their place before joining
## (`Npc.waits_to_join`), until they join and while they walk aboard; anyone else always.
func is_here() -> bool:
	var profile: NpcProfile = npc.profile
	if not profile:
		return true
	if npc.waits_to_join:
		var walking: bool = npc.routine != null and npc.routine.boarding != null
		return not profile.is_aboard(npc.get_story()) or walking
	if not profile.station.is_empty():
		return true
	return (
		profile.is_aboard(npc.get_story())
		and not NpcBoarding.is_walking(npc.get_tree(), profile.id)
	)


## Whether they have something to say where they are: always, except at their place before
## joining, there only a topic that goes once they join, or quests as seen out there.
func talks_here() -> bool:
	if not npc.waits_to_join or npc.quests_view:
		return true
	var profile: NpcProfile = npc.profile
	var topics: Array[Topic] = profile.dialogue.topics if profile and profile.dialogue else []
	var flag: StringName = profile.join_flag if profile else &""
	return (
		not flag.is_empty() and topics.any(func(listed: Topic) -> bool: return listed.until == flag)
	)


## Comes aboard at `at` (global, inside the ramp's door; from their place before joining, see
## `NpcBoarding`) and walks on from there to their post.
func arrive(at: Transform3D) -> void:
	npc.global_transform = at
	npc.reset_physics_interpolation()
	npc.routine.arrive()
	update()


## Shows them while they're here (`is_here`), else hides them; at their place before joining, they
## start walking aboard once they join, and stop if that's taken back (a lost run).
func update() -> void:
	var aboard: bool = npc.profile.is_aboard(npc.get_story()) if npc.profile else true
	if npc.waits_to_join and not _joined and aboard:
		_joined = true
		npc.routine.start_boarding()
	elif npc.waits_to_join and _joined and not aboard:
		_joined = false
		npc.routine.stop_boarding()
	npc.visible = is_here()
	changed.emit()
