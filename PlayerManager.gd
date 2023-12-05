extends Node

var player

func use_slot_data(slot_data: SlotData):
	slot_data.item.use(player)
	pass

func get_global_position():
	return player.global_position
