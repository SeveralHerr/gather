extends Resource
class_name SawmillData

@export var sawmill: Node

@export var selectedProduction: GameItem.Type

@export var count: int

@export var timer: Timer

func _init(sawmill, count: int):
	self.sawmill = sawmill
	self.count = count
