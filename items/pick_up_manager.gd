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
		# Below the drops (z_index 1), not above them. See Juice.PARTICLE_Z_INDEX — the
		# sparkle for one collect was covering the drops still on the ground beside it.
		_sparkle.z_index = Juice.PARTICLE_Z_INDEX
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


## Where the drops live. SaveLoad.LEGACY_PATHS migrates the entry *key*, so it cannot help
## with a path baked into a method body: rename or reparent PickUps and get_node() used to
## return null, .get_children() raised, and this `-> Dictionary` handed SaveLoad an empty {}
## — every item on the ground gone from that save on (gather-yi9).
const PICKUPS_PATH := "/root/Main/World/PickUps"


func _pickups_root() -> Node:
	return get_node_or_null(PICKUPS_PATH)


func saveObject() -> Dictionary:
	var world_item_data = {}
	var root := _pickups_root()

	# A missing container means no drops to record, not a failed save. Returning a
	# well-formed empty payload keeps the rest of the file readable; raising here is what
	# used to take the whole line out.
	if root == null:
		push_warning("PickUpManager: no node at '%s', saving no ground items" % PICKUPS_PATH)
		return {"filepath": get_path(), "world_items": world_item_data}

	# create() parents a shadow Sprite2D next to every drop, so half of this
	# container has no slot_data at all. Reading it unconditionally aborted the
	# method on the first shadow — and because saveObject is declared
	# `-> Dictionary`, GDScript still handed SaveLoad an empty {}. The result was a
	# blank line in saveFile, an "invalid access to key 'filepath'" on the next
	# load, and every item lying on the ground silently gone.
	var saved := 0
	for node in root.get_children():
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
	var root := _pickups_root()
	if root == null:
		push_warning("PickUpManager: no node at '%s', ground items were not restored" % PICKUPS_PATH)
		return

	for child in root.get_children():
		child.queue_free()

	var world_items: Variant = loadedDict.get("world_items", {})
	if world_items is not Dictionary:
		return

	for key in world_items.keys():
		var json := JSON.new()
		if json.parse(str(world_items[key])) != OK:
			push_warning("PickUpManager: skipping an unparseable ground item")
			continue

		var node: Variant = json.get_data()
		if node is not Dictionary or not (node.has("itemType") and node.has("x") and node.has("y")):
			push_warning("PickUpManager: skipping a malformed ground item")
			continue

		var item_type := int(node["itemType"])
		# get_item() indexes item_list and raises on a type it does not hold — and
		# item_list is deliberately not total over Types.Item (the world resources live in
		# resources.gd). A raise here would abort the loop with the container already
		# emptied above, so every remaining drop would be lost (gather-5rj).
		if not GameItems.item_list.has(item_type):
			push_warning("PickUpManager: no item registered for type %d, skipping that drop" % item_type)
			continue

		# Vector2, not Vector2i. create_pickup takes a Vector2 and the save holds floats;
		# the old cast truncated every drop toward the origin, so items visibly jumped on
		# load (gather-d3m).
		var pos := Vector2(float(node["x"]), float(node["y"]))
		create_pickup(GameItems.get_item(item_type), pos)
