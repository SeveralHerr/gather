extends Node

var boneEnemy = preload("res://Enemies/BoneEnemy.tscn")
var spiderEnemy = preload("res://Enemies/SpiderEnemy.tscn")

@onready var player = $"../Player"

@onready var tilemap_handler: TileMapHandler = $"../.."

@onready var node_2d = $".."


@onready var wave_label: Label = $"../Player/Camera2D/UI/WaveLabel"
@onready var intensity_label: Label = $"../Player/Camera2D/UI/IntensityLabel"

@onready var timer: Timer = $Timer
@onready var intensity_timer: Timer = $IntensityTimer

var wave = 1

var enemies = [boneEnemy, spiderEnemy]

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveLoad")
	randomize()
	timer.connect("timeout", Callable(self, "_timeout"))
	intensity_timer.timeout.connect(increase_intensity)
	_timeout()
	_timeout()
	_timeout()
	_timeout()
	_timeout()
	_timeout()
	pass # Replace with function body.


func increase_intensity():
	timer.wait_time *= 0.8
	wave += 1
	wave_label.text = "Wave " + str(wave)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	intensity_label.text = "%.2f" % intensity_timer.time_left

	pass

func _timeout():
	var random_index = randi() % enemies.size()	
	var enemy_to_spawn = enemies[random_index]
	
	var random_tile =  tilemap_handler.get_random_tile()
	if not random_tile:
		return
	
	var pos = tilemap_handler.tileMap.map_to_local(random_tile)
	var instance = enemy_to_spawn.instantiate()
	instance.position = pos
	add_child(instance)
	pass

func saveObject() -> Dictionary:	
	
	var enemies = get_children()
	var enemies_to_save = {}
	
	for i in enemies.size():
		if enemies[i] is Enemy:
			var dict := {
				"hp": enemies[i].health_manager.current_health,
				"target": enemies[i].target == null,
				"attack_target": enemies[i].attack_target == null, 
				"drop": enemies[i].drop,
				"x": enemies[i].position.x,
				"y": enemies[i].position.y,
				"wave": wave,
				"wait_time": timer.wait_time,
				"type": enemies[i].type
			}
			
			enemies_to_save[i] =  JSON.stringify(dict)
	var dict := {
		"filepath": get_path(),
		"enemies": enemies_to_save
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	var enemies_to_load = []
	
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
		
