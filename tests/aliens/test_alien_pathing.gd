extends GutTest
## How aliens find their way (see `AlienPathing`): the path budget per physics frame.


func test_only_a_few_paths_are_looked_up_per_frame() -> void:
	await wait_physics_frames(1)
	var granted: int = 0
	for i: int in AlienPathing.PATHS_PER_FRAME + 3:
		if AlienPathing._may_look_up_path():
			granted += 1
	assert_eq(granted, AlienPathing.PATHS_PER_FRAME, "the others wait")
	await wait_physics_frames(1)
	assert_true(AlienPathing._may_look_up_path(), "the next frame has a new budget")
