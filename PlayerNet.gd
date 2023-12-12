extends Node

var fsm: StateMachine
var p : Player


func enter():
	p = PlayerManager.player
	if not p.hot_bar_inventory.selected_slot_data:
		return
	
	var equipped = p.hot_bar_inventory.selected_slot_data.item
	var has_net_equipped = equipped and equipped is  GameItemNet
	
	if not has_net_equipped:
		return
		
	p.net.body_entered.connect(on_hit)
		
	p.net.visible = true
	p.net.monitoring = true
	
	if not p.animation_player.animation_finished.is_connected(animation_finished):
		p.animation_player.animation_finished.connect(animation_finished)
	
	if not p.animated_sprite_2d.flip_h:
		p.animation_player.play("Net_Right")
	else:
		p.animation_player.play("Net_Left")
	
	

	

func on_hit(body: Node2D):
	if body is Enemy and body.type == "Bone":
		var enemy = SlotData.new(GameItems.get_item(Types.Item.BoneEnemy), 1)
		p.inventory_data.pick_up_slot_data(enemy)
		p.net.visible = false
		p.net.monitoring = false	
		PlayerManager.player.inventory_data.remove_by_type(Types.Item.Net)
		body.queue_free()
	pass

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
	
func animation_finished(anim_name):
	p.animation_player.stop()
	p.net.visible = false
	p.net.monitoring = false	
			
	p.net.body_entered.disconnect(on_hit)
	fsm.change_to("PlayerIdle")

