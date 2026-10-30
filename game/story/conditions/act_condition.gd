class_name ActCondition
extends BeatCondition
## The act the story is in (`StoryDirector.act`): from `from` up to `to` (0: no end).

@export_range(1, 6) var from: int = 1
@export_range(0, 6) var to: int = 0


func holds(director: StoryDirector, _beat: Beat) -> bool:
	var act: int = director.act()
	return act >= from and (to == 0 or act <= to)
