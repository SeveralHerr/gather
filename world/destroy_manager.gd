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


## Hands the current target back and forgets it, mirroring ResourceManager2's version
## of the same method and fixing the same defect: main.gd draws a layer-3 selector when
## destroy_removing fires and clears it only on destroy_removing_stop, so a retarget that
## overwrote removing_info left the previous tile's selector on the map with nothing
## holding a reference to it. Pressing destroy beside a wall and then again with nothing
## in range was enough — the second lookup returns null, so the release emitted no stop
## at all.
func _release_target() -> void:
	if removing_info != null:
		emit_signal("destroy_removing_stop", removing_info.location, removing_info.item)
	removing_info = null


func start_removing_resource():
	_release_target()

	is_holding_e = true
	#hold_timer.time_left = 3.0
	hold_timer.start()

	removing_info = tile_map_handler.get_location_of_nearby_item_to_destroy(player.global_position)
	if removing_info != null:
		emit_signal("destroy_removing", removing_info.location, removing_info.item)


func stop_removing_resource():
	is_holding_e = false
	hold_timer.stop()
	_release_target()

func _on_hold_timer_timeout():
	if is_holding_e and removing_info != null:
		PickUpManager.create_pickup(removing_info.item, removing_info.location)
		#tile_map_handler.find_nearest_resource_to_location(player.global_position)
		emit_signal("destroy_removed", removing_info.location, removing_info.item)
		removing_info = null
	
