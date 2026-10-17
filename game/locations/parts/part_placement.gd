class_name PartPlacement
extends Resource
## A map part (`MapPart`) in a biome's pool of points of interest or a region's set pieces: which
## part, where in the location it goes and how often it's picked. All values TBD (playtest).

## Where in the location it goes, by the walking distance from the ship (a third of the farthest
## area's each) or in a dead end.
enum Rule { ANY, NEAR, MID, FAR, DEAD_END }

## A scene with a `MapPart` root.
@export var scene: PackedScene
@export var rule: Rule = Rule.ANY
## How often it's picked from a pool, relative to the others.
@export var weight: float = 1.0
