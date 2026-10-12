class_name ScatterType
extends Resource
## Something a generated location scatters over its ground: plants, rocks, ... One mesh, drawn
## many times (in chunks, so far ones are culled). Blocking ones get a collider (a cylinder) that
## players, aliens and shots can't pass and the navigation mesh goes around; the others are only
## looks. All values are greybox, TBD (playtest).

@export var display_name: String = ""
## The mesh drawn, unless `model` is set.
@export var mesh: Mesh
## A model kit (.glb) to take the mesh from instead: the part named `model_part`.
@export var model: PackedScene
@export var model_part: StringName
## Instances per 100 m² where they grow (before clustering and steep ground thin them out).
@export var density: float = 1.0
## 0: spread evenly; 1: only in patches (a noise mask decides where).
@export_range(0.0, 1.0) var clustering: float = 0.5
## Size of the patches, in m.
@export var patch_size: float = 40.0
@export var min_scale: float = 0.8
@export var max_scale: float = 1.2
## Steepest ground (rise per m) it stands on.
@export var max_slope: float = 0.6
## How far it sinks into the ground, in m (at scale 1), so it doesn't float on slopes.
@export var sink: float = 0.0
## Random lean, in degrees.
@export var max_tilt: float = 0.0
## Collider radius at scale 1, in m; 0: no collider, players and aliens walk through.
@export var blocking_radius: float = 0.0
## Collider height at scale 1, in m.
@export var blocking_height: float = 2.0
## Hidden beyond this distance from the camera, in m; 0: always drawn.
@export var visibility_range: float = 0.0
@export var cast_shadow: bool = true

var _model_mesh: Mesh


## The mesh to draw: the model's part if a model is set, `mesh` otherwise.
func get_mesh() -> Mesh:
	if not model:
		return mesh
	if not _model_mesh:
		_model_mesh = ModelParts.mesh(model, model_part)
	return _model_mesh
