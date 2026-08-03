extends PlayerState

@onready var resource_manager: ResourceManager2 = $"../../../../Systems/ResourceManager"

func enter() -> void:
	p = PlayerManager.player
	if not p.hot_bar_inventory.selected_slot_data:
		return

	var equipped = p.hot_bar_inventory.selected_slot_data.item
	var has_pickaxe_equipped = equipped and equipped is  GameItemPickaxe

	if not has_pickaxe_equipped:
		return

	# A repeat press while a gather is already running must not restart it. enter() runs on
	# every change_to("PlayerGather") — and change_to() deliberately skips exit() when the
	# machine is already here, so a repeat is a bare re-entry — and there is nothing upstream
	# that dedupes: repeats are cheap to come by on touch, because input_manager.gd polls
	# is_action_just_pressed() from inside _input() — frame-scoped, while _input() runs once
	# per event — and the virtual joystick emits an InputEventScreenDrag every frame.
	# Restarting resets hold_timer, so a held gather could never actually finish (gather-3zg.2).
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


## Hides the swing and drops the animation connection.
##
## Deliberately does NOT call resource_manager.stop_removing_resource(). The gather timer is
## owned by the release path — Player._gather_input_release, via the hotbar — and stopping it
## from here would mean any state change during a hold silently cancelled a gather the player
## is still holding the key for. The visual belongs to the state; the work order does not.
##
## The connection is what needed the exit(). Gather and Gather_left are the two animations in
## main.tscn authored with loop_mode 1, so they never emit animation_finished themselves —
## which means this handler only ever fired for somebody else's animation, and that is exactly
## the bug (gather-3zg.2).
func exit() -> void:
	if p == null:
		return

	if p.gather != null:
		p.gather.visible = false

	if p.animation_player != null and p.animation_player.animation_finished.is_connected(animation_finished):
		p.animation_player.animation_finished.disconnect(animation_finished)


## Kept guarded on the current state even though exit() now drops the connection: the guard
## is one comparison and it is the thing that made the original bug survivable (gather-3zg.2).
func animation_finished(_anim_name):
	if fsm == null or fsm.state != self:
		return

	p.animation_player.stop()
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
	fsm.change_to("PlayerIdle")
