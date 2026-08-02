extends Node

const PICK_UP = preload("res://items/pick_up.tscn")
const SHADOW = preload("res://world/shadow.tscn")
const HIT_PARTICLES = preload("res://world/vfx/hit_particles.tscn")

## One shared emitter for every collect sparkle, created on first use and never freed.
##
## A collect fires whenever anything is absorbed, which is several times a second while the
## vacuum is working through a node's yield, so an emitter node per collect would be a
## visible line on the orphan counter — the same class of bug HealthManager was fixed for.
## Sharing it means simultaneous collects cut each other's burst short, which costs nothing
## visually: they happen within a few pixels of each other, at the player.
var _sparkle: GPUParticles2D


func _ready():
	add_to_group("SaveLoad")
	randomize()


## A small burst where a drop was absorbed. Static-ish entry point on the autoload, so
## items/pick_up.gd can call it on the frame it frees itself.
func collect_sparkle(world_position: Vector2) -> void:
	# World, not World/PickUps: loadObject() frees every child of PickUps, and an emitter
	# rebuilt on every load is exactly the slow leak this is shaped to avoid.
	var host := get_node_or_null("/root/Main/World")
	if host == null:
		return

	if _sparkle == null or not is_instance_valid(_sparkle):
		_sparkle = HIT_PARTICLES.instantiate()
		_sparkle.name = "CollectSparkle"
		_sparkle.top_level = true
		_sparkle.one_shot = true
		_sparkle.explosiveness = 1.0
		_sparkle.amount = Juice.PICKUP_SPARKLE_AMOUNT
		_sparkle.lifetime = Juice.PICKUP_SPARKLE_LIFETIME
		_sparkle.emitting = false
		# Above the drops themselves (z_index 1) but below the damage numbers (100).
		_sparkle.z_index = 60
		host.add_child(_sparkle)

	_sparkle.global_position = world_position
	# restart(), not `emitting = true`: a one-shot emitter that is still running ignores the
	# assignment, which would swallow every collect after the first.
	_sparkle.restart()


func create(slot_data: SlotData, position: Vector2):
	var pick_up = PICK_UP.instantiate()
	var shadow = SHADOW.instantiate()
	

	# Widened from ±15. A near-vertical launch made the two or three drops one node yields
	# follow the same line, so a good roll looked like a single item.
	var initial_velocity = Vector2(
		randf_range(-Juice.PICKUP_LAUNCH_X, Juice.PICKUP_LAUNCH_X),
		randf_range(Juice.PICKUP_LAUNCH_Y_MIN, Juice.PICKUP_LAUNCH_Y_MAX)
	)
	pick_up.linear_velocity = initial_velocity
	get_node("/root/Main/World/PickUps").add_child(pick_up)
	get_node("/root/Main/World/PickUps").add_child(shadow)
	pick_up.slot_data = slot_data
	shadow.target = pick_up
	pick_up.shadow = shadow
	
	var random_x = randf_range(-3, 3)
	var random_y = randf_range(-3, 3)
	pick_up.position = position + Vector2(random_x, random_y)
	shadow.position = pick_up.position
	pick_up.y_sort_enabled = true
	if slot_data.item.is_scene_tile:
		pick_up.sprite_2d.scale= Vector2(0.5, 0.5) 
	pick_up.sprite_2d.texture = slot_data.item.get_atlas()

	# Last, deliberately: the scale above is what the pop has to settle back onto, so arming
	# the pop any earlier (in PickUp._ready, say) would capture 1.0 for a scene-tile drop and
	# permanently double its size.
	pick_up.spawn_pop()

	#get_tree().root.add_child(pickup)


func create_pickup(item: GameItem, position: Vector2):
	var slot_data: SlotData = SlotData.new()
	slot_data.item = item
	slot_data.count = 1
	PickUpManager.create(slot_data, position)


func saveObject() -> Dictionary:
	var world_item_data = {}
	var pickups_in_world = get_node("/root/Main/World/PickUps").get_children()

	# create() parents a shadow Sprite2D next to every drop, so half of this
	# container has no slot_data at all. Reading it unconditionally aborted the
	# method on the first shadow — and because saveObject is declared
	# `-> Dictionary`, GDScript still handed SaveLoad an empty {}. The result was a
	# blank line in saveFile, an "invalid access to key 'filepath'" on the next
	# load, and every item lying on the ground silently gone.
	var saved := 0
	for node in pickups_in_world:
		var slot_data = node.get("slot_data")
		if slot_data == null or slot_data.item == null:
			continue

		world_item_data[saved] = JSON.stringify({
			"itemType": slot_data.item.type,
			"x": node.position.x,
			"y": node.position.y,
		})
		saved += 1


	var dict := {
		"filepath": get_path(),
		"world_items": world_item_data
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:

	
	for child in get_node("/root/Main/World/PickUps").get_children(): 
		child.queue_free()
	
	for item in loadedDict.world_items.keys():
		var x = loadedDict.world_items[item]
		var json = JSON.new()
		json.parse(x)
		var node = json.get_data()
		var pos = Vector2i(node["x"], node["y"])
		var newItem = GameItems.get_item(node["itemType"])
		
		create_pickup( newItem, pos)
