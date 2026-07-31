extends GameItem
class_name  GameItemConsumable

@export var heal_value: int


func _init(_atlas_location: Vector2i,
		_tile_source_id: int,
		_type: Types.Item,
		_layer: int,
		_is_placeable: bool,
		_name: String,
		_tile_atlas_location: Vector2i = Vector2i.ZERO,
		_is_scene_tile: bool = false,
		_heal_value: int = 0
	):
	super(_atlas_location, _tile_source_id, _type, _layer, _is_placeable, _name, _tile_atlas_location, _is_scene_tile)
	self.heal_value = _heal_value


# Checked before the stack is decremented, so eating at full health is a no-op rather
# than quietly burning the item.
func can_use() -> bool:
	if heal_value == 0:
		return false

	var player = PlayerManager.player
	if player == null or player.is_dead:
		return false

	return player.health_manager.current_health < player.health_manager.max_health


func use(_target):
	var player = PlayerManager.player
	if player == null:
		return

	player.health_manager.heal(heal_value)
	player.update_hp_bar()
