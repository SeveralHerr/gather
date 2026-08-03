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
	# super(), not eight copies of GameItem's own assignments. Re-assigning the base fields by
	# hand meant a field added to GameItem was silently left unset on every pickaxe and sword,
	# which reads at the call site as the new field being broken (gather-q6t).
	super(_atlas_location, _tile_source_id, _type, _layer, _is_placeable, _name, _tile_atlas_location, _is_scene_tile)
	self.power = _power
	self.bonus_yield_chance = _bonus_yield_chance


func use(_target):
	PlayerManager.player.state_machine.change_to("PlayerGather")
	pass
	
func stop():
	PlayerManager.player.gather_state.stop()
