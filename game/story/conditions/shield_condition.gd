class_name ShieldCondition
extends BeatCondition
## The heat shield's next plate paid at least this far (`HeatShield.paid_share`, 0–1), e.g. a
## third and two thirds.

@export_range(0.0, 1.0) var paid: float = 0.5


func holds(director: StoryDirector, _beat: Beat) -> bool:
	return director.heat_shield.paid_share() >= paid - HeatShield.PAID_TOLERANCE
