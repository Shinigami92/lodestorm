class_name SkillCluster
extends Resource
## A category of skills (mobility, survival, ...): a constellation on the skill graph, a small tree
## growing out from its center.

## Player-facing name.
@export var display_name: String = ""
## The color its skills and links glow in.
@export var color: Color = Color(0.3, 0.85, 1.0)
## Where its center sits on the graph, in m (x right, y up).
@export var center: Vector2 = Vector2.ZERO
## Its skills; the roots first.
@export var skills: Array[Skill] = []
