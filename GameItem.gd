extends Resource
class_name GameItem


@export var atlas_location: Vector2i

@export var tile_source_id: int

@export var tile_atlas_location: Vector2i

@export var layer: int

@export var isPlaceable: bool

@export var type: Type

enum Type {
	Stone,
	Wood,
	Plank,
	Sawmill,
	WoodFloor,
	CoalOre,
	IronOre,
	IronBar,
	Furnace,
	WoodWall,
	WoodDoor
}


func _init(atlas_location: Vector2i, 
		tile_source_id: int, 
		type: Type, layer: int, 
		isPlaceable: bool, 
		tile_atlas_location: Vector2i = Vector2i.ZERO,
		isSceneTile: bool = false
	):
	self.atlas_location = atlas_location
	self.tile_source_id = tile_source_id
	self.type = type
	self.layer = layer
	self.isPlaceable = isPlaceable
	self.tile_atlas_location = tile_atlas_location
	
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
