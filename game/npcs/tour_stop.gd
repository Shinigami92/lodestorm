class_name TourStop
extends Resource
## A stop of a `Tour`: where to stand (`id`, the name of a marker under the ship's `Tour`: their
## feet, facing the way it faces) and what to say there, one speech bubble each.

@export var id: StringName
## What they say there (the English texts, translated), one speech bubble each.
@export var lines: Array[String] = []
