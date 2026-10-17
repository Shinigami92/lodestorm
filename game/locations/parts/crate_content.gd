class_name CrateContent
extends Resource
## What a crate in a map part holds (see `Crate`). Decided when the location is made, not rolled:
## a fragment an accepted quest put in the region if one is still to find (`BlueprintFragment`),
## otherwise a supply cache (`SupplyCache`). New kinds are subclasses.

## The glow of what flies out of the crate to the player.
@export var color: Color = Color(1.0, 0.75, 0.3)


## Hands the content to `player`, who opened the crate.
func open(_player: Player) -> void:
	pass
