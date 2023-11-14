extends Resource
class_name GameResource

@export var atlas_location: Vector2i

@export var tile_source_id: int

@export var type: Type

@export var drop: GameItem

enum Type {
	Stone,
	Tree,
	Iron,
	Coal
}


func _init(atlas_location: Vector2i, tile_source_id: int, drop: GameItem, type: Type = Type.Stone):
	self.atlas_location = atlas_location
	self.tile_source_id = tile_source_id
	self.type = type
	self.drop = drop
