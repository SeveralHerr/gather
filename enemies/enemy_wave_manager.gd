extends Node

var boneEnemy = preload("res://enemies/bone_enemy.tscn")
var spiderEnemy = preload("res://enemies/spider_enemy.tscn")

@onready var player = $"../Player"

@onready var tilemap_handler: TileMapHandler = $"../.."

@onready var node_2d = $".."


@onready var wave_label: Label = $"../Player/Camera2D/UI/WaveLabel"
@onready var intensity_label: Label = $"../Player/Camera2D/UI/IntensityLabel"

@onready var timer: Timer = $Timer
@onready var intensity_timer: Timer = $IntensityTimer

# Difficulty ramps toward a ceiling instead of past it. Without the floor the
# interval halves away to nothing (~0.02s about 18 minutes in) and the run buries
# itself no matter how well the player is doing; without the cap, enemies that are
# never killed accumulate until the frame rate collapses.
const MIN_SPAWN_INTERVAL := 1.5
const MAX_LIVE_ENEMIES := 25

var wave = 1

# Spawns telegraph for 2s before the enemy appears, which is longer than the minimum
# spawn interval - so in-flight spawns have to count against the cap too.
var pending_spawns := 0

var enemies = [boneEnemy, spiderEnemy]

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveLoad")
	randomize()
	timer.connect("timeout", Callable(self, "_timeout"))
	intensity_timer.timeout.connect(increase_intensity)
	pass # Replace with function body.


func increase_intensity():
	timer.wait_time = max(MIN_SPAWN_INTERVAL, timer.wait_time * 0.8)
	wave += 1
	wave_label.text = "Wave " + str(wave)


func count_live_enemies() -> int:
	var total = 0
	for child in get_children():
		if child is Enemy:
			total += 1
	return total


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	intensity_label.text = "%.2f" % intensity_timer.time_left

	pass

func _timeout():
	if count_live_enemies() + pending_spawns >= MAX_LIVE_ENEMIES:
		return

	var random_index = randi() % enemies.size()
	var enemy_to_spawn = enemies[random_index]

	var random_tile =  tilemap_handler.get_random_tile()
	if not random_tile:
		return

	pending_spawns += 1

	var x = GameItems.get_item(Types.Item.X)
	tilemap_handler.tileMap.set_cell(x.layer, random_tile, x.tile_source_id, x.atlas_location)
	await get_tree().create_timer(2).timeout
	tilemap_handler.tileMap.set_cell(1, random_tile, -1)

	var pos = tilemap_handler.tileMap.map_to_local(random_tile)
	var instance = enemy_to_spawn.instantiate()
	instance.position = pos
	add_child(instance)

	pending_spawns -= 1

func saveObject() -> Dictionary:	
	
	var _enemies = get_children()
	var enemies_to_save = {}
	
	for i in _enemies.size():
		if _enemies[i] is Enemy:
			var e_dict := {
				"hp": _enemies[i].health_manager.current_health,
				"target": _enemies[i].target == null,
				"attack_target": _enemies[i].attack_target == null, 
				"drop": _enemies[i].drop,
				"x": _enemies[i].position.x,
				"y": _enemies[i].position.y,
				"wave": wave,
				"wait_time": timer.wait_time,
				"type": _enemies[i].type
			}
			
			enemies_to_save[i] =  JSON.stringify(e_dict)
	var dict := {
		"filepath": get_path(),
		"enemies": enemies_to_save
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	for child in get_children(): 
		if child.name == "Timer" or child.name == "IntensityTimer":
			continue
		child.queue_free()
	
	
	for item in loadedDict.enemies.keys():
		var x = loadedDict.enemies[item]
		var json = JSON.new()
		json.parse(x)
		var node = json.get_data()
		var pos = Vector2i(node["x"], node["y"])
		
		wave = node["wave"]
		timer.wait_time = node["wait_time"]
		var e
		if node["type"] == "Spider":
			e = spiderEnemy
		elif node["type"] == "Bone":
			e = boneEnemy
		var instance = e.instantiate()
		add_child(instance)
		instance.position = pos
		instance.health_manager.current_health = node["hp"]
		if node["target"] == false:
			instance.target = player
		if node["attack_target"] == false:
			instance.target = player
		instance.drop = node["drop"]
		
		wave_label.text = "Wave " + str(wave)
		intensity_label.text = str(intensity_timer.time_left)
		
