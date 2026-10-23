class_name MinerHandling
extends Node
## Placing a miner and picking one up take time (`MinerSettings.place_time`, `pick_up_time`): the
## miner stands on its node as a hologram that turns real from the bottom up (placing), or back
## into a hologram from the top down until it's gone (picking up; see `Miner.built`). The `holder`
## moves, dashes and fights freely meanwhile; it only goes on while they stay within the miner's
## hose range (`in_range`, the circle of its ring) and waits while they're out of it
## (`Miner.paused`). One at a time: while it goes on, nothing else is placed or picked up; placing
## or picking up another miner while it waits gives it up (`cancel`: a miner being placed goes
## back to the fleet, one being picked up turns real again where it stands); nothing is lost.
## Taking damage doesn't cancel it, dying does. The holder drives it every physics step (`update`).

## Emitted when a miner it placed stands, and when one it picked up is on the back.
signal placed(miner: Miner)
signal picked_up(miner: Miner)

const LATCH_SOUND: Sound = preload("res://assets/audio/sfx/mining/miner_latch.tres")

## The player placing and picking up.
var holder: Player
## The miner being placed or picked up, or null.
var miner: Miner
## Whether `miner` is being placed (else picked up).
var placing: bool = false
## Seconds it went on so far.
var elapsed: float = 0.0


## Whether a miner is being placed or picked up (not once it left the world, e.g. with its
## location).
func busy() -> bool:
	return (
		is_instance_valid(miner) and miner.is_inside_tree() and not miner.is_queued_for_deletion()
	)


## Whether it goes on: busy, with the holder within the miner's hose range.
func in_range() -> bool:
	if not busy():
		return false
	var offset: Vector3 = miner.global_position - holder.global_position
	return Vector2(offset.x, offset.z).length() <= miner.hose_range()


## Places the holder's next miner on `node`: it takes the node at once and stands after the place
## time. Returns it, or null while another goes on or when the node is taken or dry.
func place(node: OreNode) -> Miner:
	if not node.is_free() or node.is_dry() or not _free_hands():
		return null
	miner = node.place_miner(holder.miner_scene, holder.fleet, holder, true)
	_start(true)
	return miner


## Starts picking up `target` (a standing miner of anyone's fleet). Returns whether it started.
func pick_up(target: Miner) -> bool:
	if not target.fleet or not target.is_standing() or not _free_hands():
		return false
	miner = target
	miner.handled_by = holder
	_start(false)
	return true


## How far it is (0–1).
func progress() -> float:
	if not busy():
		return 0.0
	var seconds: float = miner.settings.place_time if placing else miner.settings.pick_up_time
	return clampf(elapsed / seconds, 0.0, 1.0) if seconds > 0.0 else 1.0


## Gives it up: a miner being placed goes back to the fleet, one being picked up turns real again.
func cancel() -> void:
	if busy():
		miner.paused = false
		if placing:
			miner.pick_up(holder)
		else:
			miner.handled_by = null
	miner = null


## Moves it on by `delta` seconds while the holder is in range; at the end the miner stands or is
## picked up.
func update(delta: float) -> void:
	if not busy():
		miner = null
		return
	miner.paused = not in_range()
	if miner.paused:
		return
	elapsed += delta
	var share: float = progress()
	miner.built = share if placing else 1.0 - share
	if share < 1.0:
		return
	var done: Miner = miner
	miner = null
	if placing:
		done.stand()
		placed.emit(done)
	elif done.pick_up(holder):
		Sfx.play_at(LATCH_SOUND, holder.global_position)
		picked_up.emit(done)
	else:
		# Left behind meanwhile (the run ended): it stays.
		done.handled_by = null


## Whether another can start: nothing goes on, or what waits is given up.
func _free_hands() -> bool:
	if in_range():
		return false
	cancel()
	return true


func _start(is_placing: bool) -> void:
	placing = is_placing
	elapsed = 0.0
