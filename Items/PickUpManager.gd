extends Node

const PICK_UP = preload("res://Items/PickUp.tscn")
@onready var pick_ups = $Node2D/PickUps



func create(slot_data: SlotData, position: Vector2):
	var pick_up = PICK_UP.instantiate()

	get_node("/root/Main/Node2D/PickUps").add_child(pick_up)
	pick_up.slot_data = slot_data
	pick_up.position = position
	pick_up.y_sort_enabled = true
	if slot_data.item.is_scene_tile:
		pick_up.sprite_2d.scale= Vector2(0.5, 0.5) 
	pick_up.sprite_2d.texture = slot_data.item.get_atlas()


func create_pickup(item: GameItem, position: Vector2):
	var slot_data: SlotData = SlotData.new()
	slot_data.item = item
	slot_data.count = 1
	PickUpManager.create(slot_data, position)
