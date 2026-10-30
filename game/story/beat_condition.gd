@abstract class_name BeatCondition
extends Resource
## What a `Beat` waits for. Each kind is a Resource of its own (story flags, a quest's step, the
## act, runs since a beat, the heat shield's plate, an ore found, a region visited, reputation, a
## fall), so a new kind is code once and data after. Never the wall clock.

## Whether it holds for `beat` with what `director` knows.
@abstract func holds(director: StoryDirector, beat: Beat) -> bool
