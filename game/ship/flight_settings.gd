class_name FlightSettings
extends Resource
## How long the ship's flight between space and a location takes. All values TBD (playtest): the
## flight should leave about enough time to walk from the cockpit to the cargo bay (20-25 s).

## Seconds in space on the way, before the descent starts.
@export var departure_time: float = 6.0
## Seconds descending through the clouds; longer if the location isn't ready yet.
@export var descent_time: float = 14.0
## Seconds from below the clouds until the ship stands on the ground.
@export var touchdown_time: float = 4.0
## Seconds the ship waits on the ground after a run (ramp up, everyone aboard) before it takes off.
@export var takeoff_delay: float = 5.0
## Seconds from lifting off until the ship is back in space.
@export var takeoff_time: float = 10.0
