extends GutTest
## The setup and checks `test_menu_fit.gd` and `test_speech_fit.gd` share: the test map, and
## whether a menu fits its card and its text reads from the camera.

const TEST_MAP := preload("res://tests/support/map_fixture.gd")
const THEME: Theme = preload("res://assets/ui/terminal_theme.tres")
## Body text is at least this part of the view's height (see docs/design/ui.md).
const MIN_TEXT_HEIGHT: float = 0.02
## Crew members aboard, by their profile.
const NPCS: Dictionary[String, String] = {
	"res://game/npcs/crew/quartermaster.tres": "Rooms/Lower/Armory/Quartermaster",
	"res://game/npcs/crew/pilot.tres": "Rooms/Upper/Bridge/Pilot",
	"res://game/npcs/crew/engineer.tres": "Rooms/Lower/EngineRoom/Engineer",
	"res://game/npcs/crew/medic.tres": "Rooms/Lower/MedicalBay/Medic",
	"res://game/npcs/crew/gunsmith.tres": "Rooms/Lower/Weapons/Gunsmith",
	"res://game/npcs/crew/suit_tech.tres": "Rooms/Lower/Armor/SuitTech",
	"res://game/npcs/crew/miner_mechanic.tres": "Rooms/Lower/Miners/MinerMechanic",
	"res://game/npcs/crew/cook.tres": "Rooms/Upper/MessHall/Cook",
}

var _map: Node3D
var _player: Player
var _ship: Ship


func before_each() -> void:
	_map = TEST_MAP.instantiate() as Node3D
	add_child_autofree(_map)
	_player = _map.get_node("Player") as Player
	_ship = _map.get_node("Ship") as Ship
	await wait_physics_frames(2)


func after_each() -> void:
	TranslationServer.set_locale("en")


func _assert_card_fits(station: Station, label: String) -> void:
	var panel: WorldPanel = station.card
	_assert_fits(station.card_menu, Vector2(panel.size * panel.pixels_per_meter), label)


func _assert_fits(content: Control, layout: Vector2, label: String) -> void:
	var needed: Vector2 = content.get_combined_minimum_size()
	assert_lte(needed.x, layout.x + 0.5, "%s: %s wide" % [label, needed.x])
	assert_lte(needed.y, layout.y + 0.5, "%s: %s high" % [label, needed.y])


## The bubble's text height as a part of the view's height around `speaker` (an NPC's while
## talking, or the camera's without zoom for colonists).
func _bubble_text_height(bubble: WorldPanel, speaker: Node3D) -> float:
	var text_height: float = (
		THEME.default_font_size / bubble.pixels_per_meter * bubble.global_basis.y.length()
	)
	var npc := speaker as Npc
	var rig := _map.get_node("IsoCameraRig") as IsoCameraRig
	return text_height / (npc.view_height if npc else rig.view_height() * rig.zoom)
