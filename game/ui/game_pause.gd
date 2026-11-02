class_name GamePause
extends RefCounted
## Stops the game solo while a menu asks for it (`SceneTree.paused`: aliens, the timer, the
## storm), e.g. the pause panel or a talk out in a location: stopped while anyone `hold`s it, going
## on once the last one `release`s it (also on leaving the tree, so it's never left stopped).

## Everyone holding the game stopped.
const GROUP: StringName = &"game_pause_holders"


## Stops the game for `holder` (in the tree).
static func hold(holder: Node) -> void:
	holder.add_to_group(GROUP)
	holder.get_tree().paused = true


## Lets the game go on for `holder`: it does once nobody else holds it.
static func release(holder: Node) -> void:
	if not holder.is_in_group(GROUP):
		return
	holder.remove_from_group(GROUP)
	var tree: SceneTree = holder.get_tree()
	if tree:
		tree.paused = not tree.get_nodes_in_group(GROUP).is_empty()
