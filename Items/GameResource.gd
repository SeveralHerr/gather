extends GameItem
class_name GameResource

@export var gathering_atlas_location: Vector2i
var sound: GameSoundManager.SoundType
var drop: Types.Item

func _init(_atlas_location: Vector2i, 
		_tile_source_id: int, 
		_type: Types.Item,
		_layer: int, 
		_is_placeable: bool, 
		_name: String,
		_tile_atlas_location: Vector2i,
		_is_scene_tile: bool,
		_drop: Types.Item, 
		_gathering_atlas_location: Vector2i = Vector2i.ZERO,
		_sound: GameSoundManager.SoundType = GameSoundManager.SoundType.STONE
	):
	self.atlas_location = _atlas_location
	self.tile_source_id = _tile_source_id
	self.layer = _layer
	self.is_placeable = _is_placeable
	self.tile_atlas_location = _tile_atlas_location
	self.type = _type
	self.drop = _drop
	self.gathering_atlas_location = _gathering_atlas_location
	self.sound = _sound

