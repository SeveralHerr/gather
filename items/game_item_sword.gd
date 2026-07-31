extends GameItem
class_name GameItemSword


@export var power: int


func _init(_atlas_location: Vector2i, 
		_tile_source_id: int, 
		_type: Types.Item,
		_layer: int, 
		_is_placeable: bool, 
		_name: String,
		_tile_atlas_location: Vector2i = Vector2i.ZERO,
		_is_scene_tile: bool = false,
		_power: int = 0
	):
	self.atlas_location = _atlas_location
	self.tile_source_id = _tile_source_id
	self.layer = _layer
	self.is_placeable = _is_placeable
	self.tile_atlas_location = _tile_atlas_location
	self.type = _type
	self.name = _name
	self.is_scene_tile = _is_scene_tile
	self.power = _power
	
func use(_target):
	PlayerManager.player.state_machine.change_to("PlayerAttack")
	pass
