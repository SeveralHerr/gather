extends Node2D
class_name BoneTurret

var bullet = preload("res://turrets/bullet.tscn")
var player: Player
var target: Node2D
@onready var sprite_2d = $LoadedSprite
@onready var shoot_timer = $ShootTimer
@onready var los: Area2D = $LineOfSight

var loaded: bool = false

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveChunks")
	los.connect("body_entered", Callable(self, "_on_body_entered"))
	los.connect("body_exited", Callable(self, "_on_body_exited"))

	shoot_timer.connect("timeout", Callable(self, "_on_timeout_shoot"))
	for node in get_tree().get_nodes_in_group("Player"):
		if node is Player:
			player = node
	pass # Replace with function body.

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
		"data": bullet_data,
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

	# Outside the bullet loop, and it breaks rather than returning. This used to sit INSIDE
	# that loop with a `return`, so a turret that had an enemy in line of sight abandoned
	# load() after restoring its first bullet and silently dropped the rest. Retargeting is
	# one decision about the turret, not one per bullet.
	for e in los.get_overlapping_bodies():
		if e is Enemy:
			target = e
			break
