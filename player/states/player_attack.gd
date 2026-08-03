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
		
	
	
## Connected to the PLAYER's shared AnimationPlayer, and the player state machine has no
## exit() hook at all (state_machine.gd:15 only ever calls enter()), so this can never be
## disconnected — the current-state check is the only available guard.
##
## Without it, every animation that finishes anywhere lands here. main.tscn decides which:
## Gather and Gather_left set loop_mode 1 and never emit, but Attack, Attack_Left, Net_Left
## and Net_Right do. So once the player had swung a sword once, every net throw for the rest
## of the session also ran this — PlayerIdle.enter() twice per throw, and the attack hitbox
## disarmed from a state that was not current (gather-hby, the same shape as gather-3zg.2).
func animation_finished(_anim_name):
	if p == null or fsm == null or fsm.state != self:
		return

	p.attack.visible = false
	p.attack.monitoring = false
	fsm.change_to("PlayerIdle")

