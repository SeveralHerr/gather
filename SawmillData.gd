extends Resource
class_name CraftingStationData

@export var craftingStation: Node

@export var selectedProduction: GameItem.Type

@export var count: int

@export var timer: Timer

func _init(craftingStation, count: int):
	self.craftingStation = craftingStation
	self.count = count
