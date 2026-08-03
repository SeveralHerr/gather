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
	
## Called from outside the state machine — game_item_pickaxe.gd:42, via the hotbar's
## gather-stop path — so it can arrive while some other state is current, and before this
## state has ever run enter().
##
## Both cases were reachable. Releasing the gather key mid sword-swing with a pickaxe
## selected forced PlayerIdle, whose enter() clears p.attack.monitoring, so the swing landed
## no damage; and `p` is assigned only in enter(), while input_manager.gd:81 deliberately
## does not gate the gather RELEASE on disable_input — so a release following a press that
## was swallowed while a panel was open ran this with p null (gather-kkz).
func stop():
	if p == null or fsm == null or fsm.state != self:
		return

	p.animation_player.stop()
	p.gather.visible = false
	fsm.change_to("PlayerIdle")

