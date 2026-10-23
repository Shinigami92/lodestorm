class_name FlightSettings
extends Resource
## How long the ship's flight between space, a location and a station takes. All values TBD
## (playtest): the flight should leave about enough time to walk from the cockpit to the cargo bay
## (20-25 s).

## Seconds in space on the way, before the descent starts.
@export var departure_time: float = 6.0
## Seconds in space on the way to another planet or moon, instead of `departure_time`.
@export var travel_time: float = 14.0
## Seconds descending through the clouds; longer if the location isn't ready yet.
@export var descent_time: float = 14.0
## Seconds from below the clouds until the ship stands on the ground.
@export var touchdown_time: float = 4.0
## Seconds the ship waits on the ground after a run (ramp up, everyone aboard) before it takes off.
@export var takeoff_delay: float = 5.0
## Seconds from lifting off until the ship is back in space.
@export var takeoff_time: float = 10.0
## Seconds from a station coming into view until it's docked (as long as the descent and the
## touchdown together); the clamps take hold in its last `clamp_time`.
@export var docking_time: float = 18.0
## Seconds the clamps take to take hold of the hull or to let go.
@export var clamp_time: float = 4.0
## Seconds from the clamps letting go until the station is left behind.
@export var undocking_time: float = 10.0
