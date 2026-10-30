class_name Beat
extends Resource
## Something new in the story between runs (see docs/design/story.md, Between missions): on a
## return, the `StoryDirector` puts out the best beat (`priority`) whose `conditions` hold. Putting
## it out sets its flag (`flag`), and that is what opens what it brings: a topic, a quest or a
## message that `requires` it. It then waits until its `done_when` flag is set (e.g. that topic
## heard), so the players aren't handed more than they can follow; one that `repeats` doesn't
## wait and comes again whenever its conditions hold on a later return.

## Which returns it comes on: any, coming back aboard after a run, or docking at a station.
## Saved by number in resources: add new values at the end.
enum Returns { ANY, RUN, DOCKING }

## Who it is in the story's flags (`beat.<id>`): saved, so it never changes.
@export var id: StringName
## Who carries it: their `NpcProfile.id` (only one beat waits per NPC); empty: nobody in
## particular.
@export var npc: StringName = &""
## Where the ship must be on the return: a planet's, moon's or station's `CelestialBody.id`; empty:
## anywhere. Only for beats about a place (a site, a first landing, someone at a station).
@export var at: StringName = &""
## Which returns it comes on.
@export var returns: Returns = Returns.ANY
## Higher goes first when several could come.
@export var priority: int = 0
## Whether it comes again (on a later return its conditions hold on); it never waits then.
@export var repeats: bool = false
## The story flag that ends its wait (e.g. the topic it opens, heard); empty: it doesn't wait.
@export var done_when: StringName = &""
## What it waits for, all of them.
@export var conditions: Array[BeatCondition] = []


## Its story flag, set once it's put out: `beat.<id>`.
func flag() -> StringName:
	return StringName("beat.%s" % id)


## Whether it comes on a return of kind `on` (`Returns.ANY`: either) at the body `body` (its id).
func fits(on: Returns, body: StringName) -> bool:
	if on != Returns.ANY and returns != Returns.ANY and returns != on:
		return false
	return at.is_empty() or at == body


## Whether every one of its `conditions` holds for `director`.
func holds(director: StoryDirector) -> bool:
	return conditions.all(
		func(condition: BeatCondition) -> bool: return condition.holds(director, self)
	)
