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
	# super(), not eight copies of GameItem's own assignments — see GameItemPickaxe
	# (gather-q6t). This matters more here than anywhere: attack types are the thing most
	# likely to add a field to GameItem, and this is the class they will subclass.
	super(_atlas_location, _tile_source_id, _type, _layer, _is_placeable, _name, _tile_atlas_location, _is_scene_tile)
	self.power = _power
	
func use(_target):
	PlayerManager.player.state_machine.change_to("PlayerAttack")
	pass
