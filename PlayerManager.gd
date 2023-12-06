extends Node

var player: Player

func use_slot_data(slot_data: SlotData):
	slot_data.item.use(player)
	pass

func get_global_position():
	return player.global_position

func show_slot_data(slot_data: SlotData):
	player.attack.show()
