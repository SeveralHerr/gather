class_name GameItem

@export var atlas_location: Vector2i

@export var tile_source_id: int

@export var tile_atlas_location: Vector2i

@export var layer: int

@export var is_placeable: bool

@export var type: Types.Item

@export var name: String

@export var is_scene_tile: bool


func _init(_atlas_location: Vector2i, 
		_tile_source_id: int, 
		_type: Types.Item,
		_layer: int, 
		_is_placeable: bool, 
		_name: String,
		_tile_atlas_location: Vector2i = Vector2i.ZERO,
		_is_scene_tile: bool = false
	):
	self.atlas_location = _atlas_location
	self.tile_source_id = _tile_source_id
	self.layer = _layer
	self.is_placeable = _is_placeable
	self.tile_atlas_location = _tile_atlas_location
	self.type = _type
	self.name = _name
	self.is_scene_tile = _is_scene_tile
	
func equal_type(incomingType: Types.Item):
	return type == incomingType
	
func equals(incoming_atlas_location, incoming_tile_source_id):
	return incoming_atlas_location == atlas_location and incoming_tile_source_id == tile_source_id
	
func get_atlas():
	var location
	if tile_atlas_location != Vector2i.ZERO:
		location = Rect2(tile_atlas_location.x*16, tile_atlas_location.y*16, 16, 16)
	else:
		location = Rect2(atlas_location.x*16, atlas_location.y*16, 16, 16)
	
	var atlas_texture = AtlasTexture.new()
	var atlas_file = load("res://assets/tilesets/game_items_atlas.tres")
	atlas_texture.atlas = atlas_file
	atlas_texture.region = location

	return atlas_texture
	
## Whether using this item right now would do anything. Consumables override it so
## that a no-op use does not eat the stack.
func can_use() -> bool:
	return true

func use(_target):
	pass

func stop():
	pass
