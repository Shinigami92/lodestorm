class_name MissionBrief
extends Resource
## One destination on offer at the navigator: a mission (where it goes: a generated location of
## `biome` from `world_seed`, a section of `region`; how long until the storm, `length`; how many
## nests wait there, `difficulty`) or a `station` to dock at (no mission there). The voyage offers
## one per open region and one per station it can dock at (see `Voyage.offers`).

enum Difficulty { EASY, NORMAL, HARD }

## The region it's a section of, or null (a location of `biome` anywhere, or a station).
@export var region: Region
## The station it docks at (its map is the location), or null (a mission).
@export var station: CelestialBody
@export var biome: LocationBiome
## The ores found there, commonest first (rarer ones lie farther away); empty: the biome's.
@export var ores: Array[OreType] = []
@export var world_seed: int = 1
## The timer, relative to the standard mission (`MissionSettings.duration`).
@export var length: float = 1.0
@export var difficulty: Difficulty = Difficulty.NORMAL


## A mission to a new section of `of_region` (from `section_seed`), with its biome, danger and
## length, and the ores it finds (`found`, see `StarSystem.ores_of`).
static func for_region(
	of_region: Region, section_seed: int, found: Array[OreType] = []
) -> MissionBrief:
	var brief := MissionBrief.new()
	brief.region = of_region
	brief.biome = of_region.biome
	brief.ores = found
	brief.world_seed = section_seed
	brief.length = of_region.length
	brief.difficulty = of_region.danger
	return brief


## A visit to `at_station` (docking there).
static func for_station(at_station: CelestialBody) -> MissionBrief:
	var brief := MissionBrief.new()
	brief.station = at_station
	return brief


## Where it goes, e.g. "Torvane, Redscar Flats": the body (found in `system`) and the region, or
## the station; empty without either.
func place_name(system: StarSystem) -> String:
	if station:
		return station.display_name
	if not region:
		return ""
	var body: CelestialBody = system.body_of(region) if system else null
	return "%s, %s" % [body.display_name, region.display_name] if body else region.display_name


## A short name for the location: the region (or else the biome) and a sector code from the seed
## (e.g. "Redscar Flats K-417"), so visits read apart; a station's name.
func location_name() -> String:
	if station:
		return tr(station.display_name)
	var letter: String = String.chr(65 + absi(world_seed) % 26)
	var sector: int = 100 + floori(absi(world_seed) / 26.0) % 900
	var place: String = ""
	if region:
		place = tr(region.display_name)
	elif biome:
		place = tr(biome.display_name)
	return ("%s %s-%d" % [place, letter, sector]).strip_edges()


## The ores found there, commonest first: its own, or else its biome's.
func found_ores() -> Array[OreType]:
	if not ores.is_empty() or not biome:
		return ores
	return OreCatalog.sorted(biome.ores)


## The difficulty's name, translated.
func difficulty_name() -> String:
	match difficulty:
		Difficulty.EASY:
			return tr("Easy")
		Difficulty.HARD:
			return tr("Hard")
	return tr("Normal")
