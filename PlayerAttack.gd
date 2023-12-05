extends Node

var fsm: StateMachine
var p : Player


func enter():
	p = PlayerManager.player

	var equipped = p.equip_sword_inventory_data.inventory_slot_datas[0]
	var has_sword_equipped = equipped and equipped.item is  GameItemSword
	
	if not has_sword_equipped:
		return
	
	p.attack.visible = true
	p.attack.monitoring = true
	p.animation_player.connect("animation_finished",Callable( self, "animation_finished"))
	if not p.animated_sprite_2d.flip_h:
		p.animation_player.play("Attack")
	else:
		p.animation_player.play("Attack_Left")
		
	
	
func animation_finished(anim_name):
	p.attack.visible = false
	p.attack.monitoring = false
	fsm.change_to("PlayerIdle")

