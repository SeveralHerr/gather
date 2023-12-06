extends Node

const PICK_UP = preload("res://Items/PickUp.tscn")

func create(slot_data: SlotData):
	var pick_up = PICK_UP.instantiate()
	pick_up.slot_data = slot_data
	pick_up.position = PlayerManager.player.position + Vector2(16,16)
	add_child(pick_up)
	pick_up.sprite_2d.texture = slot_data.item.get_atlas()


func create_pickup(item: GameItem):
	var slot_data: SlotData = SlotData.new()
	slot_data.item = item
	slot_data.count = 1
	PickUpManager.create(slot_data)
