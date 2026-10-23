class_name StatCounters
extends RefCounted
## Counters by name, each split by its labels in a fixed order (e.g. `kills` by weapon, then by
## strain): `values["kills"]["weapons/types/harl/harl"]["aliens/strains/brute/brute"]` is a count.
## A counter without labels is a plain number. Kept as plain dictionaries, so they're written to
## JSON as they are (see `StatsRecorder`).

## The counters: a number, or a dictionary per label value (nested once per further label).
var values: Dictionary = {}


## Adds `amount` to counter `counter` at `labels` (the same number of labels, in the same order,
## every time).
func add(counter: String, labels: Array[String] = [], amount: float = 1.0) -> void:
	if labels.is_empty():
		var so_far: float = values.get(counter, 0.0)
		values[counter] = so_far + amount
		return
	var level: Dictionary = values.get_or_add(counter, {})
	for i: int in labels.size() - 1:
		level = level.get_or_add(labels[i], {})
	var last: String = labels[-1]
	var before: float = level.get(last, 0.0)
	level[last] = before + amount


## The value of counter `counter` at `labels`; with fewer labels, the sum of everything under them.
func value(counter: String, labels: Array[String] = []) -> float:
	var at: Variant = values.get(counter, 0.0)
	for label: String in labels:
		if not at is Dictionary:
			return 0.0
		at = (at as Dictionary).get(label, 0.0)
	return _sum(at)


## Whether nothing was counted.
func is_empty() -> bool:
	return values.is_empty()


## The counters as JSON-ready data, every number rounded to thousandths.
func to_data() -> Dictionary:
	return _rounded(values)


## Takes the counters from `data` (what `to_data` gave), skipping what isn't a number.
func from_data(data: Dictionary) -> void:
	values = _numbers(data)


static func _sum(at: Variant) -> float:
	if at is Dictionary:
		var total: float = 0.0
		for key: Variant in at as Dictionary:
			total += _sum((at as Dictionary)[key])
		return total
	if at is float or at is int:
		var number: float = at
		return number
	return 0.0


static func _rounded(level: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in level:
		var entry: Variant = level[key]
		if entry is Dictionary:
			out[key] = _rounded(entry as Dictionary)
		else:
			var number: float = entry
			out[key] = snappedf(number, 0.001)
	return out


static func _numbers(level: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in level:
		var entry: Variant = level[key]
		if entry is Dictionary:
			out[str(key)] = _numbers(entry as Dictionary)
		elif entry is float or entry is int:
			var number: float = entry
			out[str(key)] = number
	return out
