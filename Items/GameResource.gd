extends GameItem
class_name GameResource

@export var gathering_atlas_location: Vector2i
var sound: GameSoundManager.SoundType
var drop: Types.Item

# Gameplay tuning. These are set from the table in Resources.gd rather than through
# the constructor, which already takes as many positional arguments as it can carry.

## XP awarded for clearing this node. Slower, rarer nodes pay more.
@export var xp: int = 1

## Inclusive range of `drop` items a single gather yields, before any tool bonus.
@export var yield_min: int = 1
@export var yield_max: int = 1

## Relative chance of this resource being picked when the spawn timer fires.
@export var spawn_weight: float = 1.0

## Optional extra drop rolled independently of the main yield.
@export var secondary_drop: Types.Item = Types.Item.X
@export var secondary_drop_chance: float = 0.0


func roll_yield(bonus_chance: float = 0.0) -> int:
	var amount := randi_range(yield_min, yield_max)
	if bonus_chance > 0.0 and randf() < bonus_chance:
		amount += 1
	return amount


func roll_secondary_drop() -> bool:
	return secondary_drop_chance > 0.0 and randf() < secondary_drop_chance

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
	self.name = _name
	self.drop = _drop
	self.gathering_atlas_location = _gathering_atlas_location
	self.sound = _sound

