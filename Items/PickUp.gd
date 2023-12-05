extends RigidBody2D

@export var slot_data: SlotData

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var area_2d: Area2D = $Area2D

func _ready():
	area_2d.body_entered.connect(_on_body_entered)
	
func _physics_process(delta):
	pass
	
func _on_body_entered(body: Node2D):
	if not body is Player:
		return
	
	if slot_data.item is GameItemPickaxe:
		if body.equip_inventory_data.pick_up_slot_data(slot_data):
			queue_free()
			
	elif slot_data.item is GameItemSword:
		if body.equip_sword_inventory_data.pick_up_slot_data(slot_data):
			queue_free()
			
	elif slot_data.item is GameItem:
		if body.inventory_data.pick_up_slot_data(slot_data):
			queue_free()
