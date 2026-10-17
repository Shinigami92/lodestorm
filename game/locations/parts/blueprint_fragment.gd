class_name BlueprintFragment
extends CrateContent
## A fragment of a blueprint a quest step asks for (see GAME_DESIGN.md, Quests): only in the crates
## of the step's region while it's active, one per crate. Carried like ore (lost when its carrier
## dies) and counted once it's aboard; the quest framework (M4, step 10) puts it into
## `GeneratedLocation.crate_contents` and takes it from the player. Until then nothing does.

## The blueprint it belongs to (later the quest's item).
@export var blueprint: StringName
