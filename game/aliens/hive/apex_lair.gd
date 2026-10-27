class_name ApexLair
extends Node3D
## Where the hive's apex (the Ravager, `AlienHive.apex`) lives on a location (placed by
## `GeneratedLocation` on some of them): when it enters the tree the apex appears at its route's
## `start`th point, as strong as the nests' aliens for the body's tier, and roams along the route
## (`Alien.route`). The aliens it sheds land here too.

@export var strain: AlienStrain
## Where it roams: the middles of areas away from the landing site (local points).
var route: Array[Vector3] = []
## The route's point it starts at.
var start: int = 0
## How much more health and damage it has than on a tier 1 body (see `HatchTable`).
var health_factor: float = 1.0
var damage_factor: float = 1.0
## The apex, once it appeared (freed when it dies).
var apex: Alien


func _ready() -> void:
	apex = strain.spawn(Alien.Role.GUARD)
	apex.health_factor = health_factor
	apex.damage_factor = damage_factor
	for point: Vector3 in route:
		apex.route.append(to_global(point))
	if not route.is_empty():
		apex.position = route[start % route.size()]
	add_child(apex)
