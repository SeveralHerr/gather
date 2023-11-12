extends Resource
class_name SawmillData

@export var sawmill: Node

@export var count: int



func _init(sawmill: Node, count: int):
	self.sawmill = sawmill
	self.count = count
