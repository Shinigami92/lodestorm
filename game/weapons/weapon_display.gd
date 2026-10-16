class_name WeaponDisplay
extends RefCounted
## Weapons to look at on stations (the weapons rack, the bench, the lockers): the weapon's scene,
## not acting, its pips showing a player's MK levels.

## How see-through weapons the player doesn't own yet are.
const LOCKED_TRANSPARENCY: float = 0.75


## A display of `weapon_type`, its pips showing `upgrades` (all MK1 when null).
static func create(weapon_type: WeaponType, upgrades: Upgrades = null) -> Weapon:
	var display := weapon_type.scene.instantiate() as Weapon
	display.process_mode = Node.PROCESS_MODE_DISABLED
	display.apply_upgrades(upgrades if upgrades else Upgrades.new(), weapon_type)
	return display


## Moves `display` (in the tree, under its holder) so its meshes' bounds center on the holder's
## origin: weapon models start at their grip, so a long one (the hammer) would stick out.
static func center(display: Node3D) -> void:
	var holder := display.get_parent() as Node3D
	var to_holder: Transform3D = holder.global_transform.affine_inverse()
	var bounds := AABB()
	var first: bool = true
	for node: Node in display.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh or not mesh.visible:
			continue
		var box: AABB = to_holder * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first:
		display.position -= bounds.get_center()


## Shows the meshes under `root` solid when `owned`, else see-through.
static func show_owned(root: Node3D, owned: bool) -> void:
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).transparency = 0.0 if owned else LOCKED_TRANSPARENCY
