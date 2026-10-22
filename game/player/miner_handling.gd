class_name MinerHandling
extends Node
## Placing a miner and picking one up take time (`MinerSettings.place_time`, `pick_up_time`):
## meanwhile the `holder` stands still with its weapon lowered, facing the miner, which lowers
## from its back to the ore node and unfolds its legs (placing), or folds them and rises onto its
## back (picking up; see `Miner.unfolded`). Moving, dashing or attacking cancels it (`cancel`):
## a miner being placed goes back onto the back, one being picked up stands again where it was;
## nothing is lost. Taking damage doesn't cancel it. The holder drives it every physics step
## (`update`).

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
## Seconds since it started.
var elapsed: float = 0.0


## Whether a miner is being placed or picked up (not once it left the world, e.g. with its
## location).
func busy() -> bool:
	return (
		is_instance_valid(miner) and miner.is_inside_tree() and not miner.is_queued_for_deletion()
	)


## Places the holder's next miner on `node`: it takes the node at once and stands after the place
## time. Returns it, or null while busy or when the node is taken.
func place(node: OreNode) -> Miner:
	if busy() or not node.is_free():
		return null
	miner = node.place_miner(holder.miner_scene, holder.fleet, holder, true)
	_start(true)
	return miner


## Starts picking up `target` (a standing miner of anyone's fleet). Returns whether it started.
func pick_up(target: Miner) -> bool:
	if busy() or not target.fleet or not target.is_standing():
		return false
	miner = target
	miner.carrier = holder
	_start(false)
	return true


## How far it is (0–1).
func progress() -> float:
	if not busy():
		return 0.0
	var seconds: float = miner.settings.place_time if placing else miner.settings.pick_up_time
	return clampf(elapsed / seconds, 0.0, 1.0) if seconds > 0.0 else 1.0


## Stops placing (the miner goes back onto the back) or picking up (it stands again).
func cancel() -> void:
	if busy():
		if placing:
			miner.pick_up(holder)
		else:
			miner.carrier = null
	miner = null


## Moves it on by `delta` seconds; at the end the miner stands or is picked up.
func update(delta: float) -> void:
	if not busy():
		miner = null
		return
	elapsed += delta
	var share: float = progress()
	miner.unfolded = share if placing else 1.0 - share
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
		done.carrier = null


func _start(is_placing: bool) -> void:
	placing = is_placing
	elapsed = 0.0
