extends Node2D
class_name BoneTurret

var bullet = preload("res://turrets/bullet.tscn")
var player: Player
var target: Node2D
@onready var sprite_2d = $LoadedSprite
@onready var shoot_timer = $ShootTimer
@onready var los: Area2D = $LineOfSight

var loaded: bool = false

## What a charged skull does to a turret (gather-8ft).
##
## Two effects, because a turret has two things worth improving and picking only one makes
## the upgrade read differently depending on what the player happened to point it at. Rate is
## the one they will notice first; the damage is what makes it still matter once the ShootTimer
## is already faster than most things can close the distance.
##
## 0.55 on the interval and +2 on the bullet, both stated as ratio and delta against whatever
## the scene and the bullet are authored with, so retuning either does not strand these.
const CHARGED_FIRE_MULTIPLIER := 0.55
const CHARGED_BONUS_DAMAGE := 2

## The blue a charged machine wears. Same value as BoneWorker.CHARGED_TINT and
## Enemy.CHARGED_TINT: three copies of one colour is worse than one, but the alternative is a
## constant on one of them that the other two reach across the codebase for, and the colour is
## the cheapest thing here to keep in step by eye.
const CHARGED_TINT := Color(0.55, 0.85, 1.6)

## Whether a charged skull has been fitted. Persisted alongside `loaded`, and for exactly the
## reason gather-ze1 documents about `loaded`: an upgrade the player paid a rare drop for that
## silently reverts on load is worse than one that never worked.
var charged: bool = false

## The interval the ShootTimer was authored with, captured before anything overwrites it.
##
## Timer.start() ASSIGNS wait_time, so deriving the charged interval from the live wait_time
## would compound every time this ran - the gather-9x0 furnace bug in a new place. Capturing
## the authored value once and always multiplying THAT is what makes make_charged idempotent
## in effect as well as in its guard.
var _base_fire_interval: float = 0.0


## Fits a skull. Idempotent - the inventory consumes the item around this call.
func make_charged() -> void:
	if charged:
		return
	charged = true
	_apply_charged_look()
	_apply_fire_rate()


func _apply_charged_look() -> void:
	for name in ["LoadedSprite", "UnloadedSprite"]:
		var sprite := get_node_or_null(name) as CanvasItem
		if sprite != null:
			sprite.modulate = CHARGED_TINT
	_set_spark_emitting(true)


func _apply_fire_rate() -> void:
	if shoot_timer == null or _base_fire_interval <= 0.0:
		return
	shoot_timer.wait_time = _base_fire_interval * CHARGED_FIRE_MULTIPLIER


## The crackle over a charged turret. CPUParticles2D for the gl_compatibility reason
## BoneWorker._build_sparks spells out.
var _sparks: CPUParticles2D


func _build_sparks() -> void:
	if is_instance_valid(_sparks):
		return

	_sparks = CPUParticles2D.new()
	_sparks.name = "Sparks"
	_sparks.emitting = false
	_sparks.amount = 16
	_sparks.lifetime = 0.45
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparks.emission_rect_extents = Vector2(5, 7)
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 180.0
	_sparks.gravity = Vector2.ZERO
	_sparks.initial_velocity_min = 4.0
	_sparks.initial_velocity_max = 14.0
	_sparks.scale_amount_min = 0.5
	_sparks.scale_amount_max = 1.0
	_sparks.color = Color(0.88, 0.97, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.88, 0.97, 1.0, 1.0))
	ramp.set_color(1, Color(0.35, 0.72, 1.0, 0.0))
	_sparks.color_ramp = ramp
	add_child(_sparks)


func _set_spark_emitting(on: bool) -> void:
	if is_instance_valid(_sparks):
		_sparks.emitting = on
# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveChunks")
	los.connect("body_entered", Callable(self, "_on_body_entered"))
	los.connect("body_exited", Callable(self, "_on_body_exited"))

	shoot_timer.connect("timeout", Callable(self, "_on_timeout_shoot"))
	for node in get_tree().get_nodes_in_group("Player"):
		if node is Player:
			player = node

	# Captured before make_charged can touch it. See _base_fire_interval.
	_base_fire_interval = shoot_timer.wait_time
	_build_sparks()
	if charged:
		_apply_charged_look()
		_apply_fire_rate()

func _on_body_entered(body: Node2D):
	if target != null:
		return
		
	if loaded == false:
		return
		
	if body is Enemy:
		target = body

func _on_body_exited(body: Node2D):
	if body != target:
		return 		
	if loaded == false:
		return
		
	var nodes = los.get_overlapping_bodies()
	for node in nodes:
		if node is Enemy:
			target = node
			return 
	target = null
	
func set_loaded():
	loaded = true
	$LoadedSprite.visible = true
	$UnloadedSprite.visible = false


func _on_timeout_shoot():
	if target == null:
		return
		
			
	if loaded == false:
		return
		
	var direction = (target.global_position - global_position).angle()
	var b = bullet.instantiate()
	b.start(Vector2.ZERO, direction)
	if charged:
		b.damage += CHARGED_BONUS_DAMAGE
	add_child(b)

func save():
	var bullet_data = {}
	var bullets = get_children()
	for i in bullets.size():
		if bullets[i] is Bullet:
			var json = {
				"x": bullets[i].position.x,
				"y": bullets[i].position.y,
				"rotation": bullets[i].rotation,
				"velocityx": bullets[i].velocity.x,
				"velocityy": bullets[i].velocity.y,
				# Also written per bullet, purely so a build rolled back to the old loader
				# still finds it where it used to look. The top-level copy below is the one
				# that means anything.
				"loaded": loaded
			}
			bullet_data[i] = json

	var dict = {
		"x": position.x,
		"y": position.y,
		# Whether the turret is ASSEMBLED, which is a property of the turret and not of any
		# bullet. It used to be written only inside the per-bullet dictionaries, so a loaded
		# turret with nothing currently in flight saved `data: {}` and came back unassembled —
		# permanently inert, and needing another captured skull to fix. The common case for a
		# turret is having no bullet in the air, so this lost the assembly far more often than
		# it kept it (gather-ze1).
		"loaded": loaded,
		"charged": charged,
		"data": bullet_data,
		# See SaveLoad.CHUNK_KIND (gather-34n).
		SaveLoad.CHUNK_KIND: SaveLoad.chunk_kind_of(self),
		"filepath": "343"
	}

	return dict
	
## Every value here comes from JSON.parse of a file on disk, so nothing about its shape is
## guaranteed. `func load(dict)` is untyped, so an unguarded index that raises returns null
## and aborts — with the existing bullets already freed above (gather-wfu).
func load(dict):
	if typeof(dict) != TYPE_DICTIONARY:
		return

	for child in get_children():
		if child is Bullet:
			child.queue_free()

	# The turret's own assembly flag, read before the bullets and independently of whether
	# there are any. typeof, not `== true`: comparing a String to a bool raises "Invalid
	# operands" rather than evaluating false — bone_worker.gd:782 documents this at length,
	# and this is the file that comment was written about.
	if typeof(dict.get("loaded")) == TYPE_BOOL and dict["loaded"]:
		set_loaded()

	# typeof, not `== true`, for the reason the comment above gives. A save from before
	# charged skulls existed has no key and reads as an ordinary turret.
	if typeof(dict.get("charged")) == TYPE_BOOL and dict["charged"]:
		make_charged()

	var saved: Variant = dict.get("data", {})
	if saved is not Dictionary:
		return

	# decode_entries reads both the pre-gather-usv JSON strings and the nested dictionaries
	# written now, and drops anything unreadable rather than raising.
	for node in SaveLoad.decode_entries(saved):
		# The per-bullet copy, kept only for saves written before the flag moved to the top
		# level. Harmless to re-apply: set_loaded() is idempotent.
		if typeof(node.get("loaded")) == TYPE_BOOL and node["loaded"]:
			set_loaded()

		var b = bullet.instantiate()
		add_child(b)
		# Position and rotation as well as velocity. save() has always written all three and
		# load() assigned only the velocity, so every restored bullet reappeared at the
		# turret's own origin pointing right — a shot in flight teleported backwards down the
		# barrel. Set after add_child, because the bullet's own _ready has no say in where it
		# already is (gather-ze1).
		b.position = Vector2(float(node.get("x", 0.0)), float(node.get("y", 0.0)))
		b.rotation = float(node.get("rotation", 0.0))
		b.velocity = Vector2(float(node.get("velocityx", 0.0)), float(node.get("velocityy", 0.0)))
		# Re-derived rather than persisted per bullet. Damage is a property of the TURRET that
		# fired it, `charged` is restored above this loop, and writing it into every bullet
		# would be a second copy of one fact that a future retune could leave stale.
		if charged:
			b.damage += CHARGED_BONUS_DAMAGE

	# Outside the bullet loop, and it breaks rather than returning. This used to sit INSIDE
	# that loop with a `return`, so a turret that had an enemy in line of sight abandoned
	# load() after restoring its first bullet and silently dropped the rest. Retargeting is
	# one decision about the turret, not one per bullet.
	for e in los.get_overlapping_bodies():
		if e is Enemy:
			target = e
			break
