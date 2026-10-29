class_name SaveData
extends RefCounted
## What the saved systems share (see `SaveGame`): each one writes its own part of the save as JSON
## values (`save_data`) and reads it back (`load_data`), skipping what doesn't read with a warning
## (`skipped`) and returning whether all of it did; null means nothing was saved and changes
## nothing. Resources are named by their UID (`uid_of`), so their files can be moved and
## renamed.


## How a save names `resource`: its UID (its path if it has none).
static func uid_of(resource: Resource) -> String:
	return ResourceUID.path_to_uid(resource.resource_path)


## The references of `resources`, in their order.
static func uids_of(resources: Array) -> Array:
	var saved: Array = []
	for resource: Resource in resources:
		saved.append(uid_of(resource))
	return saved


## A number per resource as saved: its UID -> the number.
static func numbers_by_uid(values: Dictionary) -> Dictionary:
	var saved: Dictionary = {}
	for resource: Resource in values:
		saved[uid_of(resource)] = values[resource]
	return saved


## The resource of `kind` a save names with `saved` (a UID), or null for anything else.
static func load_uid(saved: Variant, kind: Script) -> Resource:
	if not saved is String or not (saved as String).begins_with("uid://"):
		return null
	# Asking the loader about an unknown UID is an error, the UID table isn't.
	if not ResourceUID.has_id(ResourceUID.text_to_id(saved as String)):
		return null
	var loaded: Resource = load(saved as String)
	return loaded if is_instance_of(loaded, kind) else null


## The resources of `kind` a saved list names (see `uids_of`), in their order, without those
## that don't read (each skipped as `what`).
static func load_uids(saved: Array, kind: Script, what: String) -> Array:
	var read: Array = []
	for entry: Variant in saved:
		var found: Resource = load_uid(entry, kind)
		if found:
			read.append(found)
		else:
			skipped(what, entry)
	return read


## The resources of `kind` and their numbers a save has (see `numbers_by_uid`), without those
## that don't read or are below `minimum` (each skipped as `what`).
static func load_numbers(
	saved: Dictionary, kind: Script, minimum: float, what: String
) -> Dictionary:
	var read: Dictionary = {}
	for key: Variant in saved:
		var found: Resource = load_uid(key, kind)
		var value: float = number(saved[key], -INF)
		if found and value >= minimum:
			read[found] = value
		else:
			skipped(what, key)
	return read


## `value` from a save as a number, or `fallback` when it isn't one.
static func number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var read: float = value
		return read
	return fallback


## Warns that `value` (a `what`) was skipped. Returns false, for `load_data` to return.
static func skipped(what: String, value: Variant) -> bool:
	push_warning("Save: skipped %s %s" % [what, value])
	return false
