extends Node
class_name ResourceManager2

signal resource_added(location: Vector2i, resource)
signal resource_removed(location: Vector2i, resource)
signal resource_removing(location: Vector2i, resource)
signal resource_removing_stop(location: Vector2i, resource)

@export var resources: Resources
@export var tile_map_handler: TileMapHandler
@export var player: Player

var hold_timer = Timer.new()
var removing_info
var is_holding_e = false

func _ready():
	tile_map_handler.resource_found.connect(_resource_found)
	hold_timer.wait_time = 1
	hold_timer.one_shot = true
	add_child(hold_timer)
	hold_timer.connect("timeout", Callable(self, "_on_hold_timer_timeout"))
	
func add_random_resource():
	var random_tile = tile_map_handler.get_random_tile()
	var random_resource = resources.get_random()
	
	if random_tile != null:
		set_resource(random_tile, random_resource)

func set_resource(location, resource: GameResource):
	#tile_map_handler.set_game_resource(location, resource.tile_source_id, resource.atlas_location)
	emit_signal("resource_added", location, resource)

func remove_resource(location, resource: GameResource):

	#tile_map_handler.clear_tile(location)
	emit_signal("resource_removed", location, resource)
	
func start_removing_resource():
	is_holding_e = true
	#hold_timer.time_left = 3.0
	hold_timer.start()
	
	removing_info = tile_map_handler.get_location_of_nearby_resource(player.global_position)
	if removing_info != null:
		emit_signal("resource_removing", removing_info.location, removing_info.resource)
	
	
func stop_removing_resource():
	is_holding_e = false
	hold_timer.stop()
	if removing_info != null:
		emit_signal("resource_removing_stop", removing_info.location, removing_info.resource)
	
func _on_hold_timer_timeout():
	if is_holding_e:
		#tile_map_handler.find_nearest_resource_to_location(player.global_position)
		remove_resource(removing_info.location, removing_info.resource)
		removing_info = null
	
func Test(PlayerPos):
	var resource = tile_map_handler.find_nearest_resource_to_location(PlayerPos)
	
func _resource_found( resource: GameResource, location: Vector2i):
	remove_resource(location, resource)
