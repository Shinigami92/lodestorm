class_name FallCondition
extends BeatCondition
## Players fell in the run just ended, at least `falls` times (`StoryDirector.falls`); never on a
## docking.

@export_range(1, 100) var falls: int = 1


func holds(director: StoryDirector, _beat: Beat) -> bool:
	return director.falls >= falls
