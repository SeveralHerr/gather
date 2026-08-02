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
	
## Atlas source id of the generated placeholder sheet, as registered in
## assets/tilesets/world_tile_set.tres.
const PLACEHOLDER_SOURCE_ID := 10

## Atlas source id of the generated stone building set (walls + floor), same file.
const STONE_BUILD_SOURCE_ID := 11

## Icon sheet per tileset source. Everything hand-drawn lives on one sheet; the
## generated placeholder ores are on a second one (tools/generate_placeholder_art.gd)
## and the generated stone building set on a third (generate_stone_build_art.gd), so
## the icon lookup has to key off the source id rather than assume the first.
const SOURCE_ATLASES := {
	PLACEHOLDER_SOURCE_ID: "res://assets/tilesets/placeholder_items_atlas.tres",
	STONE_BUILD_SOURCE_ID: "res://assets/tilesets/stone_build_atlas.tres",
}
const DEFAULT_ATLAS := "res://assets/tilesets/game_items_atlas.tres"


func get_atlas():
	var location
	if tile_atlas_location != Vector2i.ZERO:
		location = Rect2(tile_atlas_location.x*16, tile_atlas_location.y*16, 16, 16)
	else:
		location = Rect2(atlas_location.x*16, atlas_location.y*16, 16, 16)

	var atlas_texture = AtlasTexture.new()
	var atlas_file = load(SOURCE_ATLASES.get(tile_source_id, DEFAULT_ATLAS))
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
