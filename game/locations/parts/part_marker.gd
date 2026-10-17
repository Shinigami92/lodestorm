class_name PartMarker
extends Marker3D
## A spot in a map part (`MapPart`) where the location puts something when it places the part: an
## ore node, a nest, a crate, or a site a quest can use. The marker itself stays empty.

enum Kind { ORE, NEST, CRATE, QUEST_ANCHOR }
## Which of the location's ores an ore marker gets: its commonest, the middle one or its rarest.
enum Band { COMMON, MID, RAREST }

@export var kind: Kind = Kind.ORE
## Only for ore markers.
@export var band: Band = Band.COMMON
