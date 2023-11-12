extends Resource
class_name GameItem

@export var atlas_location: Vector2i

@export var tile_source_id: int

@export var type: Type

enum Type {
	Stone,
	Wood,
	Plank,
	Sawmill
}


func _init(atlas_location: Vector2i, tile_source_id:, type: Type = Type.Stone):
	self.atlas_location = atlas_location
	self.tile_source_id = tile_source_id
	self.type = type
