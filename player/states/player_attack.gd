extends PlayerState


func enter() -> void:
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


## Undoes exactly what enter() armed: the hitbox and the AnimationPlayer connection.
##
## The connection is the load-bearing half. It is made on the PLAYER's AnimationPlayer, not
## on anything this state owns, so before there was an exit() to drop it in, it outlived the
## state and every animation that finished anywhere landed here — Attack, Attack_Left,
## Net_Left and Net_Right all emit; only Gather and Gather_left are looped and do not. Once
## the player had swung a sword once, every net throw for the rest of the session also ran
## animation_finished below, disarming the hitbox from a state that was not current
## (gather-hby).
##
## Disarming here rather than only in animation_finished is what makes a swing interrupted
## by a tool change actually stop hitting things: that path never reaches the handler.
func exit() -> void:
	if p == null:
		return

	if p.attack != null:
		p.attack.visible = false
		p.attack.monitoring = false

	if p.animation_player != null and p.animation_player.animation_finished.is_connected(animation_finished):
		p.animation_player.animation_finished.disconnect(animation_finished)


## The swing played out. Kept guarded on the current state even though exit() now drops the
## connection: change_to() is reachable from item use and from player.gd, so the belt and the
## braces cost one comparison.
func animation_finished(_anim_name):
	if p == null or fsm == null or fsm.state != self:
		return

	fsm.change_to("PlayerIdle")
