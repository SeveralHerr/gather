extends Node
class_name DestroyManager

signal destroy_added(location: Vector2i, item)
signal destroy_removed(location: Vector2i, item)
signal destroy_removing(location: Vector2i, item)
signal destroy_removing_stop(location: Vector2i, item)

@export var items: Items
@export var tile_map_handler: TileMapHandler
@export var player: Player

var hold_timer = Timer.new()
var removing_info
var is_holding_e = false

func _ready():
	hold_timer.wait_time = 1
	hold_timer.one_shot = true
	add_child(hold_timer)
	hold_timer.connect("timeout", Callable(self, "_on_hold_timer_timeout"))


func start_removing_resource():
	is_holding_e = true
	#hold_timer.time_left = 3.0
	hold_timer.start()
	
	removing_info = tile_map_handler.get_location_of_nearby_item_to_destroy(player.global_position)
	if removing_info != null:
		print(removing_info.item.name)
		emit_signal("destroy_removing", removing_info.location, removing_info.item)
	
	
func stop_removing_resource():
	is_holding_e = false
	hold_timer.stop()
	if removing_info != null:
		emit_signal("destroy_removing_stop", removing_info.location, removing_info.item)
	
func _on_hold_timer_timeout():
	if is_holding_e and removing_info != null:
		#tile_map_handler.find_nearest_resource_to_location(player.global_position)
		emit_signal("destroy_removed", removing_info.location, removing_info.item)
		removing_info = null
	
