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
	Furnace
}


func _init(atlas_location: Vector2i, tile_source_id:, type: Type = Type.Stone, layer: int = 1, isPlaceable: bool = false, tile_atlas_location: Vector2i = Vector2i.ZERO):
	self.atlas_location = atlas_location
	self.tile_source_id = tile_source_id
	self.type = type
	self.layer = layer
	self.isPlaceable = isPlaceable
	self.tile_atlas_location = tile_atlas_location
