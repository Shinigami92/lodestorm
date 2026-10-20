@abstract class_name WeaponDelivery
extends Resource
## How a weapon's attack reaches its targets (see `WeaponType.delivery`): projectiles
## (`ProjectileDelivery`) or a swing (`SwingDelivery`) so far; beams, cones, chains, placed
## charges, thrusts, held tools and blocks are planned (see docs/planned/weapons.md). The weapon's
## effects make each hit (`Weapon.make_hit`). All values TBD (playtest).

## Performs one attack of `weapon`, along its aim direction or at its locked target.
@abstract func attack(weapon: Weapon) -> void
