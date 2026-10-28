class_name SupplyCache
extends CrateContent
## The usual content of a crate: refills the opener's spare magazines (every ranged weapon of the
## loadout). Used up even when they were full.


func open(player: Player) -> void:
	player.arms.refill_spares()
