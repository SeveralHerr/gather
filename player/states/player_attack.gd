extends Node

var fsm: StateMachine
var p : Player


func enter():
	p = PlayerManager.player

	#var equipped = p.equip_sword_inventory_data.inventory_slot_datas[0]
	var selected = p.hot_bar_inventory.selected_slot_data
	var equipped = selected.item if selected else null
	var has_sword_equipped = equipped and equipped is  GameItemSword

	# Without a sword there is no swing animation to wait on, so hand control back
	# immediately rather than parking the machine in a state that never exits.
	if not has_sword_equipped:
		fsm.change_to("PlayerIdle")
		return

	p.attack.visible = true
	p.attack.monitoring = true
	
	if not p.animation_player.animation_finished.is_connected(animation_finished):
		p.animation_player.connect("animation_finished",Callable( self, "animation_finished"))
	
	if not p.animated_sprite_2d.flip_h:
		p.animation_player.play("Attack")
	else:
		p.animation_player.play("Attack_Left")
		
	
	
func animation_finished(_anim_name):
	p.attack.visible = false
	p.attack.monitoring = false
	fsm.change_to("PlayerIdle")

