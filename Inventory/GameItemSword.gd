extends GameItem
class_name GameItemSword


@export var power: int


func _init(atlas_location: Vector2i, 
		tile_source_id: int, 
		type: Types.Item,
		layer: int, 
		is_placeable: bool, 
		name: String,
		tile_atlas_location: Vector2i = Vector2i.ZERO,
		is_scene_tile: bool = false,
		power: int = 0
	):
	self.atlas_location = atlas_location
	self.tile_source_id = tile_source_id
	self.layer = layer
	self.is_placeable = is_placeable
	self.tile_atlas_location = tile_atlas_location
	self.type = type
	self.name = name
	self.is_scene_tile = is_scene_tile
	self.power = power
	
func use(target):
	PlayerManager.player.state_machine.change_to("PlayerAttack")
	pass
