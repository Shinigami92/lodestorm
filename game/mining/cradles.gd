class_name Cradles
extends Resource
## How many of the miners' room's cradles the ship has (see docs/design/mining.md): the ship was
## stripped before it was bought, so two are left at first (M-01's and the next); the main quest
## brings the others back one after another (until it does, the debug overlay opens them), up to
## `MinerFleet.SLOTS`. They're the ship's, saved with it; the miners in them are each player's
## (`MinerFleet`): a crafted miner is built only in an open cradle, and a run takes as many miners
## as there are open cradles.

## Open cradles on a new ship.
const START: int = 2

var open: int = START


## Opens the next cradle. Returns whether there was one left.
func open_next() -> bool:
	if open >= MinerFleet.SLOTS:
		return false
	open += 1
	emit_changed()
	return true


## Whether cradle `number` (1–`MinerFleet.SLOTS`) is open.
func is_open(number: int) -> bool:
	return number >= 1 and number <= open


## Sets the number open as saved.
func restore(count: int) -> void:
	open = clampi(count, 1, MinerFleet.SLOTS)
	emit_changed()
