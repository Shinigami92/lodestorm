class_name BlueprintFragment
extends CrateContent
## A fragment of a blueprint a quest step asks for (see `RecoverFragmentsGoal`): only in the crates
## of the step's region while it's active, one per crate. The opener carries it on the back
## (`QuestPack`) until they're aboard, where it counts (lost when they die).

## The goal it counts for.
var entry: QuestVisit.Entry


func open(player: Player) -> void:
	player.quest_pack.add(entry)
