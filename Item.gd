extends Resource
class_name Item

@export var atlas_location: Vector2i

@export var scene: PackedScene

@export var name: String

@export var icon: Texture


func _init(atlas_location: Vector2i = Vector2i(), scene: PackedScene = null, name: String = "", icon: Texture = null):
	self.atlas_location = atlas_location
	self.scene = scene
	self.name = name
	self.icon = icon
