class_name HealthManager
# RefCounted, not Node: these are built with .new() and held as a plain field, never
# added to the scene tree. As a Node nothing ever freed them, so every enemy the wave
# manager spawned leaked its HealthManager for the life of the process.
extends RefCounted

signal health_changed(current_health)
signal died

var max_health: int = 100
var current_health: int = 100

func _init(health_value: int = 100):
	max_health = health_value
	current_health = max_health

func set_health(value: int):
	current_health = clamp(value, 0, max_health)
	emit_signal("health_changed", current_health)
	if current_health <= 0:
		emit_signal("died")

## Raising the ceiling heals for the difference, so a +max-health skill is felt the
## moment it is bought rather than only after the next heal. Lowering it just
## re-clamps. Never allows a max of zero, which would make set_health() fire died.
func set_max_health(value: int):
	var delta: int = value - max_health
	max_health = max(1, value)

	if delta > 0:
		set_health(current_health + delta)
	else:
		set_health(current_health)

func take_damage(damage: int):
	set_health(current_health - damage)

func heal(amount: int):
	set_health(current_health + amount)

func is_alive() -> bool:
	return current_health > 0

func reset_health():
	set_health(max_health)
