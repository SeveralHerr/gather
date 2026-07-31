extends GameItem
class_name GameItemPickaxe


## Seconds of holding required to clear one node. Lower is better, so a tier upgrade
## shows up as a shorter swing.
@export var power: float

## Chance of one extra item on top of the node's base yield. This is the half of a
## tool upgrade the player actually notices - speed alone is easy to miss.
@export var bonus_yield_chance: float


func _init(_atlas_location: Vector2i,
		_tile_source_id: int,
		_type: Types.Item,
		_layer: int,
		_is_placeable: bool,
		_name: String,
		_tile_atlas_location: Vector2i = Vector2i.ZERO,
		_is_scene_tile: bool = false,
		_power: float = 0.0,
		_bonus_yield_chance: float = 0.0
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
	self.bonus_yield_chance = _bonus_yield_chance


func use(_target):
	PlayerManager.player.state_machine.change_to("PlayerGather")
	pass
	
func stop():
	PlayerManager.player.gather_state.stop()
