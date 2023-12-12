extends GameItem
class_name GameItemBoneEnemy


	
func use(_target):
	var nodes = PlayerManager.player.area_2d.get_overlapping_areas()
	var closest_turret = find_closest_object_parent(nodes, BoneTurret)

	if closest_turret != null and  closest_turret is BoneTurret:
		closest_turret.set_loaded()
		PlayerManager.player.inventory_data.remove_by_type(Types.Item.BoneEnemy)
	pass

func find_closest_object_parent(nodes, type):
	var closest_object = null
	var closest_distance = INF
	for n in nodes:
		var node = n.get_parent()
		if is_instance_of(node, type):
			var distance = PlayerManager.player.global_position.distance_to(node.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_object = node
	return closest_object
