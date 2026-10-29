class_name MinerPicker
extends Node
## Which of its miners still to place the `holder` places next (see docs/design/mining.md): by
## default the one `MinerChoice.default_for` picks for the ore of `Player.miner_target`; `step`
## (`miner_prev`/`miner_next`) goes through the others, wrapping around. The choice sticks until
## it's placed (`placed`, also on another node); the next one starts on the default again. While the
## holder could place one, a `MinerPreview` of it stands on that node (the local player's only),
## gone while a miner it places or picks up goes on nearby, when it walks off or has none left.

## The player choosing.
var holder: Player
## The miner the holder chose, or null: the default.
var chosen: MinerChoice
## The hologram of the miner it would place (the local player's), or null.
var preview: MinerPreview


func _ready() -> void:
	if holder.local:
		preview = MinerPreview.new()
		preview.name = "Preview"
		preview.miner_scene = holder.miner_scene
		add_child(preview)


func _physics_process(_delta: float) -> void:
	if not preview:
		return
	var node: OreNode = holder.miner_target
	var choice: MinerChoice = choice_for(node) if node else null
	if choice and not holder.handling.in_range():
		preview.show_choice(node, choice, holder.color())
	else:
		preview.wanted = false


## The miner placing takes on `node`: the chosen one while it's still to place, else the default;
## null when none is left.
func choice_for(node: OreNode) -> MinerChoice:
	var options: Array[MinerChoice] = MinerChoice.options(holder.fleet)
	for option: MinerChoice in options:
		if option.same_as(chosen):
			return option
	return MinerChoice.default_for(holder.fleet, node.ore_type if node else null)


## Chooses the next miner still to place (`direction` 1) or the one before (-1), wrapping around;
## only while there's a node to place it on and more than one to choose from. Returns whether it
## changed.
func step(direction: int) -> bool:
	var node: OreNode = holder.miner_target
	var options: Array[MinerChoice] = MinerChoice.options(holder.fleet)
	if not node or options.size() < 2:
		return false
	var current: MinerChoice = choice_for(node)
	var index: int = options.find_custom(func(o: MinerChoice) -> bool: return o.same_as(current))
	chosen = options[posmod(index + direction, options.size())]
	return true


## Forgets the choice once it's placed, and hides the preview at once (the building hologram takes
## over).
func placed() -> void:
	chosen = null
	if preview:
		preview.hide_now()
