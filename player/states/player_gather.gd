extends Node

var fsm: StateMachine
var p : Player
@onready var resource_manager: ResourceManager2 = $"../../../../Systems/ResourceManager"

func enter():
	p = PlayerManager.player
	if not p.hot_bar_inventory.selected_slot_data:
		return
	
	var equipped = p.hot_bar_inventory.selected_slot_data.item
	var has_pickaxe_equipped = equipped and equipped is  GameItemPickaxe
	
	if not has_pickaxe_equipped:
		return

	# A repeat press while a gather is already running must not restart it. enter() runs on
	# every change_to("PlayerGather") and there is nothing upstream that dedupes: repeats are
	# cheap to come by on touch, because input_manager.gd polls is_action_just_pressed() from
	# inside _input() — frame-scoped, while _input() runs once per event — and the virtual
	# joystick emits an InputEventScreenDrag every frame. Restarting resets hold_timer, so a
	# held gather could never actually finish (gather-3zg.2).
	if resource_manager.is_holding_e:
		return

	p.gather.visible = true
	
	if not p.animation_player.animation_finished.is_connected(animation_finished):
		p.animation_player.connect("animation_finished",Callable( self, "animation_finished"))
	
	if not p.animated_sprite_2d.flip_h:
		p.animation_player.play("Gather")
	else:
		p.animation_player.play("Gather_left")
	
	resource_manager.start_removing_resource(equipped)
	
## This state connects to the PLAYER's AnimationPlayer, and that connection outlives the
## state — it is made once and never disconnected. So every animation that finishes anywhere,
## Attack included, lands here. Without the guard, finishing an attack yanked the player back
## to PlayerIdle for the rest of the session (gather-3zg.2).
func animation_finished(_anim_name):
	if fsm == null or fsm.state != self:
		return

	p.animation_player.stop()

	p.gather.visible = false
	fsm.change_to("PlayerIdle")
	
func stop():
	p.animation_player.stop()
	print("Stop")
	p.gather.visible = false
	fsm.change_to("PlayerIdle")

