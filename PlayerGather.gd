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
	
	if not p.animation_player.animation_finished.is_connected(animation_finished):
		p.animation_player.connect("animation_finished",Callable( self, "animation_finished"))
	
	if not p.animated_sprite_2d.flip_h:
		p.animation_player.play("Gather")
	else:
		p.animation_player.play("Gather_left")
	
	resource_manager.start_removing_resource(p.equip_inventory_data.inventory_slot_datas[0].item.power)
	
func animation_finished(anim_name):
	p.animation_player.stop()
	p.gather.visible = false
	fsm.change_to("PlayerIdle")

