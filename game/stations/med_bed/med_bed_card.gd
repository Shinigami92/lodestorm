class_name MedBedCard
extends StationCard
## The holo card of a med bed (`MedBedStation`): the health of the player lying on it while it
## heals, then that they're at full health, and "Get up".

@onready var _health: Label = %Health
@onready var _bar: ProgressBar = %Bar
@onready var _get_up: Button = %GetUp


func _ready() -> void:
	_get_up.pressed.connect(press_primary)


func show_part(part: StationPart) -> void:
	var med_bed := station as MedBedStation
	visible = part != null and med_bed != null and med_bed.user != null
	if not visible:
		return
	show_health(med_bed.user.health, med_bed.user.max_health())


## Shows `health` of `maximum`: still healing, or at full health.
func show_health(health: float, maximum: float) -> void:
	var healed: bool = health >= maximum
	var shown: int = roundi(maximum) if healed else mini(ceili(health), roundi(maximum) - 1)
	if healed:
		_health.text = tr("Full health: %d / %d") % [shown, roundi(maximum)]
	else:
		_health.text = tr("Healing: %d / %d") % [shown, roundi(maximum)]
	_health.add_theme_color_override(
		&"font_color", CardPalette.GOOD if healed else CardPalette.STATUS
	)
	_bar.value = health / maximum if maximum > 0.0 else 1.0


func press_primary() -> bool:
	if not station or not station.user:
		return false
	station.close()
	return true
