@tool
class_name KitMesh
extends MeshInstance3D
## A mesh taken by name from a model kit (`ModelParts`), so a scene can use one piece of a kit
## (e.g. a crate of the map parts' field kit) without instancing the whole model. The mesh is
## looked up when the node enters the tree (also in the editor) and never saved with the scene.
## Map parts give the biome's settled cover to every `KitMesh` with `cover` (see `SettledCover`).

## The kit (an imported `.glb`).
@export var model: PackedScene:
	set(value):
		model = value
		_refresh()
## The name of the piece's node in the kit.
@export var part: StringName:
	set(value):
		part = value
		_refresh()
## Whether the biome's cover (snow, salt, ash, ...) settles on it; off for lenses, glowing strips,
## slime and pools.
@export var cover: bool = true


func _ready() -> void:
	_refresh()


func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage = PROPERTY_USAGE_EDITOR


func _refresh() -> void:
	if not is_node_ready() and not Engine.is_editor_hint():
		return
	mesh = ModelParts.mesh(model, part) if model and not part.is_empty() else null
