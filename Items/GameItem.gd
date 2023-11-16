class_name GameItem

@export var atlas_location: Vector2i

@export var tile_source_id: int

@export var tile_atlas_location: Vector2i

@export var layer: int

@export var is_placeable: bool

@export var type: Types.Item

@export var name: String

@export var is_scene_tile: bool


func _init(atlas_location: Vector2i, 
		tile_source_id: int, 
		type: Types.Item,
		layer: int, 
		is_placeable: bool, 
		name: String,
		tile_atlas_location: Vector2i = Vector2i.ZERO,
		is_scene_tile: bool = false
	):
	self.atlas_location = atlas_location
	self.tile_source_id = tile_source_id
	self.layer = layer
	self.is_placeable = is_placeable
	self.tile_atlas_location = tile_atlas_location
	self.type = type
	self.name = name
	self.is_scene_tile = is_scene_tile
	
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
	var atlas_file = load("res://Resources/game_items_atlas.tres")
	atlas_texture.atlas = atlas_file
	atlas_texture.region = location

	return atlas_texture
