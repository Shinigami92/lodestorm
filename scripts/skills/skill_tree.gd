class_name SkillTree
extends Resource
## Every skill of the game, in clusters: what the skill graph shows.

@export var clusters: Array[SkillCluster] = []


## Every skill, cluster by cluster.
func get_skills() -> Array[Skill]:
	var skills: Array[Skill] = []
	for cluster: SkillCluster in clusters:
		skills.append_array(cluster.skills)
	return skills


## The cluster `skill` belongs to, or null.
func cluster_of(skill: Skill) -> SkillCluster:
	for cluster: SkillCluster in clusters:
		if skill in cluster.skills:
			return cluster
	return null
