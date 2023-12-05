extends Node

var fsm: StateMachine
var p : Player
@onready var resource_manager: ResourceManager2 = $"../../../../ResourceManager"

func enter():
	p = PlayerManager.player
	var equipped = p.equip_inventory_data.inventory_slot_datas[0]
	var has_pickaxe_equipped = equipped and equipped.item is  GameItemPickaxe
	
	if not has_pickaxe_equipped:
		return
		
	p.gather.visible = true
	p.animation_player.connect("animation_finished",Callable( self, "animation_finished"))
	p.animation_player.play("Gather")
	
	resource_manager.start_removing_resource(p.equip_inventory_data.inventory_slot_datas[0].item.power)
	
func animation_finished(anim_name):
	p.animation_player.stop()
	p.gather.visible = false
	fsm.change_to("PlayerIdle")

