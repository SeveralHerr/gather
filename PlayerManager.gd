extends Node

var player: Player

func use_slot_data(slot_data: SlotData):
	slot_data.item.use(slot_data)
	pass

func get_global_position():
	return player.global_position

func show_slot_data(slot_data: SlotData):
	
	if slot_data.item is GameItemSword:
		player.attack_sprite.texture = slot_data.item.get_atlas()
		player.damage = slot_data.item.power
	elif slot_data.item is GameItemPickaxe:
		player.gather.texture = slot_data.item.get_atlas()
	pass
	
func place_tile(slot_data):
	var tile_pos =  player.tilemap.get_tile_in_front_of_player()
	if not player.tilemap.is_occupied(player.tilemap.tileMap.local_to_map(tile_pos), true, false) and slot_data.item.is_placeable:
		slot_data.count -= 1
		player.tilemap.set_tile(player.tilemap.tileMap.local_to_map(tile_pos), slot_data.item.tile_source_id, slot_data.item.atlas_location, slot_data.item.layer, slot_data.item.is_scene_tile)
	pass

func place_wall(slot_data):
	var tile_pos =  player.tilemap.get_tile_in_front_of_player()
	if not player.tilemap.is_occupied(player.tilemap.tileMap.local_to_map(tile_pos), true, true) and slot_data.item.is_placeable:
		slot_data.count -= 1
		player.tilemap.set_tile(player.tilemap.tileMap.local_to_map(tile_pos), slot_data.item.tile_source_id, slot_data.item.atlas_location, slot_data.item.layer, slot_data.item.is_scene_tile)
	pass
