extends GutTest
## The second part of the sweep over every region's set pieces (`set_piece_sweep.gd`).

const SET_PIECES := preload("res://tests/locations/set_piece_sweep.gd")


func test_set_pieces_always_placed_and_parts_reachable() -> void:
	SET_PIECES.check(self, 2)
