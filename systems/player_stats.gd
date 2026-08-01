class_name PlayerStats
# RefCounted, not Node: the Player holds one as a plain field for its whole life.
extends RefCounted

## Emitted after every recompute so the Player can push the new numbers into the
## things that only read them once (max health, the hp bar).
signal stats_changed

## Base values every run starts from. recompute() resets to these before summing,
## so a skill can never be applied twice and a load never needs to undo anything.
const BASE := {
	"gather_speed_mult": 1.0,
	"bonus_yield_chance": 0.0,
	"xp_mult": 1.0,
	"max_health_bonus": 0,
	"damage_bonus": 0,
	"move_speed_mult": 1.0,
	"pickup_radius_mult": 1.0,
}

## Multiplies the equipped pickaxe's gather time. Below 1.0 is faster; the caller
## still clamps to ResourceManager2.MIN_GATHER_TIME so this can never reach zero.
var gather_speed_mult: float = 1.0

## Added on top of the pickaxe's own bonus_yield_chance.
var bonus_yield_chance: float = 0.0

var xp_mult: float = 1.0
var max_health_bonus: int = 0
var damage_bonus: int = 0
var move_speed_mult: float = 1.0
var pickup_radius_mult: float = 1.0


func _init():
	reset()


func reset() -> void:
	for stat in BASE:
		set(stat, BASE[stat])


## Rebuilds every stat from scratch out of the skills currently taken. Recomputing
## rather than applying deltas incrementally is what makes load, respec and
## out-of-order _ready() all safe: the taken set is the only source of truth.
func recompute(taken: Dictionary, tree: SkillTree) -> void:
	reset()

	for skill_id in taken:
		var skill: Skill = tree.get_skill(skill_id)
		if skill == null:
			push_warning("PlayerStats: taken skill '%s' is not in the tree" % skill_id)
			continue

		for stat in skill.effects:
			if not BASE.has(stat):
				push_warning("PlayerStats: skill '%s' targets unknown stat '%s'" % [skill_id, stat])
				continue
			set(stat, get(stat) + skill.effects[stat])

	stats_changed.emit()
