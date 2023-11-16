extends GameItem
class_name GameResource

@export var gathering_atlas_location: Vector2i

var drop: Types.Item

func _init(atlas_location: Vector2i, 
		tile_source_id: int, 
		type: Types.Item,
		layer: int, 
		is_placeable: bool, 
		name: String,
		tile_atlas_location: Vector2i,
		is_scene_tile: bool,
		drop: Types.Item, 
		gathering_atlas_location: Vector2i = Vector2i.ZERO
	):
	self.atlas_location = atlas_location
	self.tile_source_id = tile_source_id
	self.layer = layer
	self.is_placeable = is_placeable
	self.tile_atlas_location = tile_atlas_location
	self.type = type
	self.drop = drop
	self.gathering_atlas_location = gathering_atlas_location

