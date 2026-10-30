class_name RunsCondition
extends BeatCondition
## Runs since the last beat (any, or this one), e.g. something bigger every few runs or a request
## coming again: at least `runs` of them (`StoryDirector.runs_since`).

## Saved by number in resources: add new values at the end.
enum Since { ANY_BEAT, THIS_BEAT }

@export_range(0, 100) var runs: int = 1
@export var since: Since = Since.ANY_BEAT


func holds(director: StoryDirector, beat: Beat) -> bool:
	return director.runs_since(beat if since == Since.THIS_BEAT else null) >= runs
