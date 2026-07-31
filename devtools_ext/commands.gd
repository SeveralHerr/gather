extends RefCounted

## Gather's project-specific DevTools verbs.
##
## The godot_selftest core instantiates this once at startup and calls
## register_commands(dev) after its generic verbs are in place.
##
## Every handler returns exactly { "success": bool, "message": String, "data": {} }.
## Verbs are reachable from the CLI with hyphens: `cmd gather-stats`.

var _dev: Node


func register_commands(dev: Node) -> void:
	_dev = dev

	dev.register_command("player_state", _cmd_player_state)
	dev.register_command("revive_player", _cmd_revive_player)
	dev.register_command("damage_player", _cmd_damage_player)
	dev.register_command("give_item", _cmd_give_item)
	dev.register_command("add_xp", _cmd_add_xp)
	dev.register_command("gather_stats", _cmd_gather_stats)
	dev.register_command("wave_stats", _cmd_wave_stats)
	dev.register_command("goto_resource", _cmd_goto_resource)

	# Merged into every reply. Without it, a session whose player has died or whose
	# island never generated keeps answering with well-formed zeros, which reads
	# exactly like a clean pass.
	dev.register_status_provider(_status)


func _player() -> Player:
	return PlayerManager.player


## main.tscn's root node is a member of every group in the project, so a plain
## get_first_node_in_group lookup hands back the root instead of what was asked for.
## Callers must say what they expect.
func _level_up_manager() -> LevelUpManager:
	for node in _dev.get_tree().get_nodes_in_group("LevelUpManager"):
		if node is LevelUpManager:
			return node
	return null


func _tile_map_handler() -> TileMapHandler:
	for node in _dev.get_tree().get_nodes_in_group("TileMapHandler"):
		if node is TileMapHandler:
			return node
	return null


func _status(_args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"player": "absent"}

	var status := {
		"player": "dead" if player.is_dead else "alive",
		"hp": player.health_manager.current_health,
		"max_hp": player.health_manager.max_health,
		"invulnerable": player.invulnerable,
	}

	var level_up = _level_up_manager()
	if level_up:
		status["xp"] = level_up.xp
		status["next_level"] = level_up.next_level
		status["pending_levels"] = level_up.pending_levels
		status["upgrade_panel_open"] = level_up.visible

	return status


func _cmd_player_state(_args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"success": false, "message": "no player in the scene", "data": {}}

	var selected = player.hot_bar_inventory.selected_slot_data

	return {
		"success": true,
		"message": "ok",
		"data": {
			"position": {"x": player.position.x, "y": player.position.y},
			"spawn": {"x": player.spawn_position.x, "y": player.spawn_position.y},
			"hp": player.health_manager.current_health,
			"is_dead": player.is_dead,
			"invulnerable": player.invulnerable,
			"state": player.state_machine.state.name if player.state_machine.state else "",
			"selected_slot": player.hot_bar_inventory.selected_index,
			"selected_item": selected.item.name if selected and selected.item else "",
			"selected_count": selected.count if selected else 0,
		},
	}


## Clears the death flag and restores the player. Restoring health alone is not
## enough - is_dead and the disabled input outlive it, leaving the run unrescuable.
func _cmd_revive_player(_args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"success": false, "message": "no player in the scene", "data": {}}

	player.is_dead = false
	player.invulnerable = false
	player.input_manager.disable_input = false
	player.animated_sprite_2d.modulate.a = 1.0
	player.health_manager.reset_health()
	player.update_hp_bar()

	return {
		"success": true,
		"message": "player revived",
		"data": {"hp": player.health_manager.current_health},
	}


func _cmd_damage_player(args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"success": false, "message": "no player in the scene", "data": {}}

	var amount: int = int(args.get("amount", 1))
	player.receive_hit(Vector2.ZERO, amount)

	return {
		"success": true,
		"message": "dealt %d damage" % amount,
		"data": {"hp": player.health_manager.current_health, "is_dead": player.is_dead},
	}


func _cmd_give_item(args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"success": false, "message": "no player in the scene", "data": {}}

	var item_name: String = str(args.get("name", ""))
	var count: int = int(args.get("count", 1))

	var type = GameItems.get_type(item_name)
	if type == null:
		return {"success": false, "message": "no item named '%s'" % item_name, "data": {}}

	var added := 0
	for _i in count:
		if player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(type), 1)):
			added += 1

	return {
		"success": added > 0,
		"message": "added %d of %d %s" % [added, count, item_name],
		"data": {"added": added},
	}


func _cmd_add_xp(args: Dictionary) -> Dictionary:
	var level_up = _level_up_manager()
	if level_up == null:
		return {"success": false, "message": "no LevelUpManager in the scene", "data": {}}

	level_up.add_xp(int(args.get("amount", 1)))

	return {
		"success": true,
		"message": "ok",
		"data": {
			"xp": level_up.xp,
			"next_level": level_up.next_level,
			"pending_levels": level_up.pending_levels,
			"panel_open": level_up.visible,
			"has_available_upgrade": level_up.has_available_upgrade(),
			"taken": level_up.taken.keys(),
		},
	}


## Teleports the player next to a live resource node. Gathering only engages when a
## node is within reach, so without this a gather test just stands in empty grass and
## proves nothing.
func _cmd_goto_resource(_args: Dictionary) -> Dictionary:
	var player := _player()
	var handler := _tile_map_handler()
	if player == null or handler == null:
		return {"success": false, "message": "player or tilemap handler missing", "data": {}}

	var resource_atlases := {}
	for key in handler.resources.GetAllTypes():
		var resource = handler.resources.Get(key)
		if not resource.is_scene_tile:
			resource_atlases[resource.atlas_location] = resource.name

	var target = null
	var target_name := ""

	for cell in handler.tileMap.get_used_cells(1):
		var atlas = handler.tileMap.get_cell_atlas_coords(1, cell)
		if resource_atlases.has(atlas):
			target = handler.tileMap.map_to_local(cell)
			target_name = resource_atlases[atlas]
			break

	if target == null:
		for node in handler.tileMap.get_children():
			if node is GameSceneResource:
				target = node.position
				target_name = "scene resource"
				break

	if target == null:
		return {"success": false, "message": "no resource nodes on the island", "data": {}}

	# Stand just beside the node rather than on top of it.
	player.position = target + Vector2(6, 0)

	return {
		"success": true,
		"message": "moved next to %s" % target_name,
		"data": {
			"resource": target_name,
			"resource_position": {"x": target.x, "y": target.y},
			"player_position": {"x": player.position.x, "y": player.position.y},
		},
	}


## Wave difficulty readout, for asserting the spawn interval floor and enemy cap.
func _cmd_wave_stats(_args: Dictionary) -> Dictionary:
	var manager = _dev.get_tree().current_scene.get_node_or_null("Node2D/EnemyWaveManager")
	if manager == null:
		return {"success": false, "message": "no EnemyWaveManager in the scene", "data": {}}

	return {
		"success": true,
		"message": "ok",
		"data": {
			"wave": manager.wave,
			"live_enemies": manager.count_live_enemies(),
			"pending_spawns": manager.pending_spawns,
			"enemy_cap": manager.MAX_LIVE_ENEMIES,
			"spawn_interval": manager.timer.wait_time,
			"min_spawn_interval": manager.MIN_SPAWN_INTERVAL,
		},
	}


## Island resource census, for asserting that the spawn cap and weighting hold.
func _cmd_gather_stats(_args: Dictionary) -> Dictionary:
	var handler = _tile_map_handler()
	if handler == null:
		return {"success": false, "message": "no TileMapHandler in the scene", "data": {}}

	var tuning := {}
	for key in handler.resources.GetAllTypes():
		var resource = handler.resources.Get(key)
		tuning[resource.name] = {"xp": resource.xp, "spawn_weight": resource.spawn_weight}

	var spawnable := []
	for resource in handler.resource_manager.curent_resources:
		spawnable.append(resource.name)

	return {
		"success": true,
		"message": "ok",
		"data": {
			"live_nodes": handler.count_resource_nodes(),
			"census": handler.resource_node_census(),
			"cap": ResourceManager2.MAX_RESOURCE_NODES,
			"spawnable": spawnable,
			"tuning": tuning,
		},
	}
