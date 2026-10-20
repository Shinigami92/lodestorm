class_name Sound
extends Resource
## A sound effect, played through `Sfx`: its variants (`stream`, an `AudioStreamRandomizer` picking
## one with a small random pitch each time, so repeats never sound like a loop), the bus it plays
## on, how loud and how far it carries, and how many may play at once. The files are built by
## `assets/audio/source/build.py` (see TECHNICAL.md, Sound effects); a better take replaces them
## under the same name. All values TBD (playtest).

@export var stream: AudioStream
@export_enum("Effects", "Ambience") var bus: String = "Effects"
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db: float = 0.0
## How many may play at once (when more start, the farthest ones are dropped); 0: no limit. Loops
## (`Sfx.play_loop_at`, `play_loop`) play outside it.
@export var limit: int = 4
## Up to this distance in m a sound in the world is as loud as close by; beyond, it fades.
@export var unit_size: float = 10.0
## Beyond this distance in m a sound in the world isn't heard.
@export var max_distance: float = 50.0


## The longest it plays, in s: its longest variant at the lowest random pitch.
func length() -> float:
	var randomizer := stream as AudioStreamRandomizer
	if not randomizer:
		return stream.get_length() if stream else 0.0
	var longest: float = 0.0
	for index: int in randomizer.streams_count:
		var variant: AudioStream = randomizer.get_stream(index)
		if variant:
			longest = maxf(longest, variant.get_length())
	return longest * maxf(randomizer.random_pitch, 1.0)
