class_name MissionBrief
extends Resource
## One mission on offer at the holo table: where it goes (a generated location of `biome` from
## `world_seed`), how long until the storm (`length`) and how many nests wait there
## (`difficulty`). The mission rolls a few of them per run (see `Mission.offers`).

enum Difficulty { EASY, NORMAL, HARD }

@export var biome: LocationBiome
@export var world_seed: int = 1
## The timer, relative to the standard mission (`MissionSettings.duration`).
@export var length: float = 1.0
@export var difficulty: Difficulty = Difficulty.NORMAL


## A short name for the location: the biome and a sector code from the seed (e.g. "Dust flats
## K-417"), so two offers of the same biome read apart.
func location_name() -> String:
	var letter: String = String.chr(65 + absi(world_seed) % 26)
	var sector: int = 100 + floori(absi(world_seed) / 26.0) % 900
	var biome_name: String = tr(biome.display_name) if biome else ""
	return ("%s %s-%d" % [biome_name, letter, sector]).strip_edges()


## The difficulty's name, translated.
func difficulty_name() -> String:
	match difficulty:
		Difficulty.EASY:
			return tr("Easy")
		Difficulty.HARD:
			return tr("Hard")
	return tr("Normal")
