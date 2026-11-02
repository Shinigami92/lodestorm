extends RefCounted
## Waiting for a player's radio in tests (see `PlayerRadio`).


## Waits until `player`'s radio is quiet (no line shown, none waiting; at most 50 s of game time),
## then its gap between lines, so the next call isn't held back.
static func quiet(test: GutTest, player: Player) -> void:
	await test.wait_until(
		func() -> bool:
			return player.radio.get_line().is_empty() and player.radio.waiting_count() == 0,
		50.0
	)
	await test.wait_seconds(PlayerRadio.GAP + 0.1)
