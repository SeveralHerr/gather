extends Resource
class_name GameItem

@export var atlas_location: Vector2i

@export var tile_source_id: int

@export var layer: int

@export var type: Type

enum Type {
	Stone,
	Wood,
	Plank,
	Sawmill,
	WoodFloor
}


func _init(atlas_location: Vector2i, tile_source_id:, type: Type = Type.Stone, layer: int = 1):
	self.atlas_location = atlas_location
	self.tile_source_id = tile_source_id
	self.type = type
	self.layer = layer
