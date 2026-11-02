class_name Seeded
extends RefCounted
## Random picks drawn from a generator of their own (see `GeneratedLocation.random_stream`), so the
## same seed always gives the same result (unlike `Array.shuffle`, which uses the global one).


## Shuffles `items` in place with `rng` (Fisher-Yates, from the back).
static func shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap
