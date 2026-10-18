class_name PhysicsLayers
extends RefCounted
## The physics layers, as bits of `collision_layer` and `collision_mask`.

## The ground, rocks, props, players and aliens.
const WORLD: int = 1
## Blocks shots but not walking (the shooting range's door).
const SHOTS_ONLY: int = 2
## Blocks walking but not shots or sight (the invisible walls at a gap's edge).
const WALKING_ONLY: int = 4
## What players and aliens bump into.
const WALKERS: int = WORLD | WALKING_ONLY
## What shots and sight lines hit: everything but `WALKING_ONLY`.
const SHOTS: int = 0xFFFFFFFF & ~WALKING_ONLY
