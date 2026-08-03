extends PlayerState


func enter() -> void:
	p = PlayerManager.player
	if not p.hot_bar_inventory.selected_slot_data:
		return

	var equipped = p.hot_bar_inventory.selected_slot_data.item
	var has_net_equipped = equipped and equipped is  GameItemNet

	if not has_net_equipped:
		return

	_arm_net(p.net)

	if not p.animation_player.animation_finished.is_connected(animation_finished):
		p.animation_player.animation_finished.connect(animation_finished)

	if not p.animated_sprite_2d.flip_h:
		p.animation_player.play("Net_Right")
	else:
		p.animation_player.play("Net_Left")


## Puts the net away and drops the animation connection, however the state is left.
##
## Both early returns in enter() above land here without having armed anything — nothing
## selected, or something that is not a net — which is why _stow_net() is written to tolerate
## an area that was never armed and why the disconnect is guarded. That is the general rule
## for exit() (see PlayerState), not a quirk of this state.
##
## Before there was an exit() to hold this, leaving PlayerNet by any route other than its own
## animation_finished left the net live and connected: the connection is made on the PLAYER's
## AnimationPlayer, so it outlived the state and fired for Attack too (gather-uem).
func exit() -> void:
	if p == null:
		return

	_stow_net(p.net)

	if p.animation_player != null and p.animation_player.animation_finished.is_connected(animation_finished):
		p.animation_player.animation_finished.disconnect(animation_finished)


## Swings the net out: one connection, visible, monitoring.
##
## The connect is guarded because enter() can run twice without the state ever being left —
## change_to() skips exit() when the machine is already in this state, so a repeat press
## re-runs enter(). Unguarded that reconnected the same callable and Godot answered with
## "Signal 'body_entered' is already connected", which is the shape enemy_follow.gd was fixed
## into under gather-0du. A stacked connection is not merely noisy: on_hit consumes a Net
## item, so two of them cost two nets for one skeleton.
##
## `monitoring` is written directly here on purpose. enter() runs from the hotbar's use
## path, not from a physics callback, so the area is not locked and there is nothing to
## defer — see _stow_net() for the case where that is not true (gather-uem).
##
## Takes the area rather than reading p.net so the guards are reachable from a test with a
## stub Area2D; a real Player cannot be stood up headless.
func _arm_net(area: Area2D) -> void:
	if area == null:
		return
	if not area.body_entered.is_connected(on_hit):
		area.body_entered.connect(on_hit)
	area.visible = true
	area.monitoring = true


## Puts the net away, and is safe to call on an area that was never armed.
##
## `monitoring` must be deferred. on_hit() is the body_entered handler, so the physics
## server is mid-callback and holds the area locked; a direct write is refused outright
## with "Function blocked during in/out signal" (area_2d.cpp:429) and the net stays live
## for the rest of the frame (gather-uem). `visible` is a CanvasItem property with no such
## constraint and is written immediately — deferring it too would only blur which of these
## two lines actually had the physics constraint.
func _stow_net(area: Area2D) -> void:
	if area == null:
		return
	area.visible = false
	area.set_deferred("monitoring", false)
	if area.body_entered.is_connected(on_hit):
		area.body_entered.disconnect(on_hit)


func on_hit(body: Node2D):
	if body is Enemy and body.type == "Bone":
		var enemy = SlotData.new(GameItems.get_item(Types.Item.BoneEnemy), 1)
		p.inventory_data.pick_up_slot_data(enemy)
		# Stowing here — connection included — is what makes the catch cost exactly one net.
		# The Net item is consumed two lines down, but the deferred `monitoring` write does
		# not land until the end of the frame, so a second skeleton walking into the same
		# swing would otherwise be caught by a net the player no longer owns. Dropping the
		# connection takes effect immediately and closes that window (gather-uem).
		_stow_net(p.net)
		PlayerManager.player.inventory_data.remove_by_type(Types.Item.Net)
		body.queue_free()

func find_closest_object(nodes, type):
	var closest_object = null
	var closest_distance = INF
	for node in nodes:
		if is_instance_of(node, type):
			var distance = p.global_position.distance_to(node.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_object = node
	return closest_object


## True only while this state is the one the machine is running.
##
## exit() now drops the AnimationPlayer connection, so the stale-handler case this was
## written for is closed at the source. It stays as the handler's own guard: change_to() is
## reachable from item use and from player.gd, and a comparison is cheaper than reasoning
## about every path into this file (gather-uem, gather-3zg.2).
func _is_current_state() -> bool:
	return fsm != null and fsm.state == self


func animation_finished(_anim_name):
	if not _is_current_state():
		return

	p.animation_player.stop()
	fsm.change_to("PlayerIdle")
