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
	dev.register_command("gather_state", _cmd_gather_state)
	dev.register_command("spawn_stats", _cmd_spawn_stats)
	dev.register_command("coin_count", _cmd_coin_count)
	dev.register_command("land_state", _cmd_land_state)
	dev.register_command("buy_land", _cmd_buy_land)
	dev.register_command("land_panel", _cmd_land_panel)
	dev.register_command("splash", _cmd_splash)
	dev.register_command("spawn_resource", _cmd_spawn_resource)
	dev.register_command("goto_resource", _cmd_goto_resource)
	dev.register_command("skill_panel", _cmd_skill_panel)
	dev.register_command("learn_skill", _cmd_learn_skill)
	dev.register_command("place_station", _cmd_place_station)
	dev.register_command("crafting_panel", _cmd_crafting_panel)
	dev.register_command("craft_state", _cmd_craft_state)
	dev.register_command("queue_craft", _cmd_queue_craft)
	dev.register_command("advance_crafting", _cmd_advance_crafting)

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


## The skill panel builds itself in code, so its inner nodes have generated paths.
## Going through the script instead keeps callers off those paths.
func _skill_tree_ui() -> SkillTreeUi:
	return _dev.get_tree().root.get_node_or_null("Main/UI2/SkillTreeUI") as SkillTreeUi


func _skill_panel_open() -> bool:
	var ui := _skill_tree_ui()
	return ui != null and ui.is_open()


func _crafting_panel() -> CraftingUi:
	return _dev.get_tree().root.get_node_or_null("Main/UI2/CraftingUI") as CraftingUi


## Every live station, in a stable order so `--args '{"station": 1}'` means the same
## thing across calls. Type-checked rather than indexed: main.tscn's root is in the
## CraftingStations group too.
func _stations() -> Array:
	var found := []
	for node in _dev.get_tree().get_nodes_in_group("CraftingStations"):
		if node is CraftingStation:
			found.append(node)
	found.sort_custom(func(a, b):
		return a.position.y < b.position.y if a.position.y != b.position.y else a.position.x < b.position.x)
	return found


func _station_at(args: Dictionary) -> CraftingStation:
	var stations := _stations()
	if stations.is_empty():
		return null
	var index: int = int(args.get("station", 0))
	if index < 0 or index >= stations.size():
		return null
	return stations[index]


func _type_name(type) -> String:
	var item = GameItems.get_item(type)
	return item.name if item else str(type)


func _station_report(station: CraftingStation) -> Dictionary:
	var recipe_names := []
	for recipe in station.recipe_list:
		if recipe:
			recipe_names.append(_type_name(recipe.product))
	return {
		"type": _type_name(station.type),
		"position": {"x": station.position.x, "y": station.position.y},
		"count": station.count,
		"starting_count": station.starting_count,
		"selected_recipe": _type_name(station.selected_recipe.product) if station.selected_recipe else "",
		"unlocked_recipes": recipe_names,
		"timer_stopped": station.timer.is_stopped() if station.timer else true,
		"time_to_next": station.timer.time_left if station.timer else 0.0,
	}


func _enemy_spawner() -> EnemySpawner:
	return _dev.get_tree().root.get_node_or_null("Main/Node2D/EnemySpawner") as EnemySpawner


func _land_manager() -> LandManager:
	return _dev.get_tree().root.get_node_or_null("Main/LandManager") as LandManager


func _land_panel() -> LandPurchaseUi:
	return _dev.get_tree().root.get_node_or_null("Main/UI2/LandPurchaseUI") as LandPurchaseUi


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

	# Gold and the live enemy count ride along on every reply: both are now the
	# heartbeat of a run (enemies spawn forever, gold is what land costs), and a
	# spawner that has stopped or an economy that never pays out is invisible in a
	# response that only reports hp and xp.
	status["gold"] = player.inventory_data.count_of_type(Types.Item.Coin)

	var spawner := _enemy_spawner()
	if spawner:
		status["live_enemies"] = spawner.count_live_enemies()
		status["spawner_running"] = not spawner.timer.is_stopped()

	# Splashes free themselves on a tween; a count that only ever climbs is the shape
	# a leak makes, and it is invisible in any other reading.
	status["live_splashes"] = _live_splashes()

	var level_up = _level_up_manager()
	if level_up:
		status["xp"] = level_up.xp
		status["next_level"] = level_up.next_level
		status["level"] = level_up.level
		status["skill_points"] = level_up.points
		status["skill_panel_open"] = _skill_panel_open()

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
			"max_hp": player.health_manager.max_health,
			# PlayerStats is a RefCounted, so get-state serialises it as an opaque
			# object id. These are the skill-tree totals spelled out, and they are
			# the only way to see from the CLI whether a passive actually landed.
			"stats": {
				"gather_speed_mult": player.stats.gather_speed_mult,
				"bonus_yield_chance": player.stats.bonus_yield_chance,
				"xp_mult": player.stats.xp_mult,
				"max_health_bonus": player.stats.max_health_bonus,
				"damage_bonus": player.stats.damage_bonus,
				"move_speed_mult": player.stats.move_speed_mult,
				"pickup_radius_mult": player.stats.pickup_radius_mult,
			},
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
			"level": level_up.level,
			"skill_points": level_up.points,
			"panel_open": _skill_panel_open(),
			"has_available_skill": level_up.has_available_skill(),
			"taken": level_up.taken.keys(),
		},
	}


## Opens or closes the skill panel. `{"open": true|false}`, or omit to toggle.
## Goes through set_open() rather than the visible property so the mouse-mode and
## disable_input handshake runs the same way a K press would.
func _cmd_skill_panel(args: Dictionary) -> Dictionary:
	var ui := _skill_tree_ui()
	if ui == null:
		return {"success": false, "message": "no SkillTreeUi in the scene", "data": {}}

	if args.has("open"):
		ui.set_open(bool(args["open"]))
	else:
		ui.toggle()

	return {
		"success": true,
		"message": "ok",
		"data": {"open": ui.is_open()},
	}


## Spends a banked point on a skill by id. Returns success=false when the purchase
## was refused, so a test can assert the guard as well as the happy path.
func _cmd_learn_skill(args: Dictionary) -> Dictionary:
	var level_up = _level_up_manager()
	if level_up == null:
		return {"success": false, "message": "no LevelUpManager in the scene", "data": {}}

	var skill_id: String = str(args.get("id", ""))
	var bought: bool = level_up.purchase(skill_id)

	return {
		"success": bought,
		"message": "learned %s" % skill_id if bought else "refused %s" % skill_id,
		"data": {
			"skill_points": level_up.points,
			"taken": level_up.taken.keys(),
		},
	}


## Teleports the player next to a live resource node. Gathering only engages when a
## node is within reach, so without this a gather test just stands in empty grass and
## proves nothing.
## `{"name": "Copper"}` narrows it to one resource. Without that the verb walks to
## whatever is nearest the origin of the used-cell list — always a common node — so the
## rare tiers could not be gather-tested at all.
func _cmd_goto_resource(args: Dictionary) -> Dictionary:
	var player := _player()
	var handler := _tile_map_handler()
	if player == null or handler == null:
		return {"success": false, "message": "player or tilemap handler missing", "data": {}}

	var wanted: String = str(args.get("name", "")).to_lower()

	var resource_atlases := {}
	for key in handler.resources.GetAllTypes():
		var resource = handler.resources.Get(key)
		if not resource.is_scene_tile:
			resource_atlases[resource.atlas_location] = resource.name

	var target = null
	var target_name := ""

	for cell in handler.tileMap.get_used_cells(1):
		var atlas = handler.tileMap.get_cell_atlas_coords(1, cell)
		if not resource_atlases.has(atlas):
			continue
		if wanted != "" and str(resource_atlases[atlas]).to_lower() != wanted:
			continue
		target = handler.tileMap.map_to_local(cell)
		target_name = resource_atlases[atlas]
		break

	if target == null and wanted != "":
		return {
			"success": false,
			"message": "no live '%s' node on the island" % wanted,
			"data": {"census": handler.resource_node_census()},
		}

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


## Spawn-pressure readout. Replaces the old wave_stats: there are no waves any more,
## and the numbers that matter now are the island-scaled cap and whether the timer is
## still firing at all. A spawner that has quietly stopped still answers every other
## verb with well-formed zeros, which reads exactly like a calm island.
func _cmd_spawn_stats(_args: Dictionary) -> Dictionary:
	var spawner := _enemy_spawner()
	if spawner == null:
		return {"success": false, "message": "no EnemySpawner in the scene", "data": {}}

	var handler := _tile_map_handler()

	return {
		"success": true,
		"message": "ok",
		"data": {
			"live_enemies": spawner.count_live_enemies(),
			"pending_spawns": spawner.pending_spawns,
			"enemy_cap": spawner.enemy_cap(),
			"land_tiles": handler.count_land_tiles() if handler else 0,
			"spawn_interval": spawner.spawn_interval(),
			"base_interval": EnemySpawner.SPAWN_INTERVAL,
			"min_spawn_distance": EnemySpawner.MIN_SPAWN_DISTANCE,
			"timer_stopped": spawner.timer.is_stopped(),
			"time_to_next_spawn": spawner.timer.time_left,
		},
	}


## Coin economy readout. "Enemies drop coins" is otherwise only assertable from a
## screenshot: coins are an ordinary inventory item, so nothing else reports them.
func _cmd_coin_count(_args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"success": false, "message": "no player in the scene", "data": {}}

	# The PickUps container holds shadows as well as drops, so every child has to be
	# probed for slot_data rather than assumed to have one.
	var world_coins := 0
	var container := _dev.get_tree().root.get_node_or_null("Main/Node2D/PickUps")
	if container:
		for node in container.get_children():
			var slot_data = node.get("slot_data")
			if slot_data and slot_data.item and slot_data.item.type == Types.Item.Coin:
				world_coins += slot_data.count

	return {
		"success": true,
		"message": "ok",
		"data": {
			"inventory_coins": player.inventory_data.count_of_type(Types.Item.Coin),
			"world_coin_pickups": world_coins,
		},
	}


## The land economy in one read. current_cost()/gold()/can_afford() are methods and
## the island size lives on the handler, so get-state on LandManager alone answers
## none of the questions a land test actually asks.
func _cmd_land_state(_args: Dictionary) -> Dictionary:
	var land := _land_manager()
	if land == null:
		return {"success": false, "message": "no LandManager in the scene", "data": {}}

	var handler := _tile_map_handler()
	var panel := _land_panel()

	return {
		"success": true,
		"message": "ok",
		"data": {
			"radius": land.radius,
			"parcels_bought": land.parcels_bought,
			"max_parcels": LandManager.MAX_PARCELS,
			"current_cost": land.current_cost(),
			"cost_mult": land.cost_mult(),
			"gold": land.gold(),
			"can_afford": land.can_afford(),
			"is_maxed": land.is_maxed(),
			"land_tiles": handler.count_land_tiles() if handler else 0,
			"panel_open": panel.is_open() if panel else false,
		},
	}


## Buys land and reports what the world actually did. purchase() returning true is
## not proof the island grew — the expansion runs after the payment, so the tile
## count before and after is the only honest evidence.
func _cmd_buy_land(args: Dictionary) -> Dictionary:
	var land := _land_manager()
	var handler := _tile_map_handler()
	if land == null or handler == null:
		return {"success": false, "message": "no LandManager or TileMapHandler", "data": {}}

	var count: int = maxi(1, int(args.get("count", 1)))
	var radius_before := land.radius
	var tiles_before := handler.count_land_tiles()
	var gold_before := land.gold()

	var bought := 0
	for _i in count:
		if not land.purchase():
			break
		bought += 1

	return {
		"success": bought > 0,
		"message": "bought %d of %d parcel(s)" % [bought, count],
		"data": {
			"bought": bought,
			"radius_before": radius_before,
			"radius_after": land.radius,
			"tiles_before": tiles_before,
			"tiles_after": handler.count_land_tiles(),
			"spent": gold_before - land.gold(),
			"gold_left": land.gold(),
			"next_cost": land.current_cost(),
		},
	}


## Opens or closes the land panel. Mirrors skill_panel: goes through set_open() so the
## mouse-mode and disable_input handshake runs exactly as a B press would.
func _cmd_land_panel(args: Dictionary) -> Dictionary:
	var panel := _land_panel()
	if panel == null:
		return {"success": false, "message": "no LandPurchaseUi in the scene", "data": {}}

	if args.has("open"):
		panel.set_open(bool(args["open"]))
	else:
		panel.toggle()

	return {"success": true, "message": "ok", "data": {"open": panel.is_open()}}


## Fires a splash on demand. The splash system is the one part of this pass that can
## only be judged by eye, and grinding to a level threshold to see the level-up variant
## is not a test loop.
func _cmd_splash(args: Dictionary) -> Dictionary:
	var player := _player()
	var at: Vector2 = player.global_position if player else Vector2.ZERO
	if args.has("x"):
		at = Vector2(float(args.get("x", 0.0)), float(args.get("y", 0.0)))

	var text: String = str(args.get("text", ""))
	var big: bool = bool(args.get("big", false))

	var node
	if text == "":
		node = SplashText.spawn_xp(_dev, at, int(args.get("amount", 3)))
	else:
		node = SplashText.spawn(
			_dev, at, text,
			SplashText.COLOR_LEVEL if big else SplashText.DEFAULT_COLOR,
			SplashText.Emphasis.BIG if big else SplashText.Emphasis.NORMAL
		)

	return {
		"success": node != null,
		"message": "spawned" if node != null else "no splash produced",
		"data": {"at": {"x": at.x, "y": at.y}, "live_splashes": _live_splashes()},
	}


func _live_splashes() -> int:
	var container = _dev.get_tree().root.get_node_or_null("Main/Node2D/SplashTexts")
	return container.get_child_count() if container else 0


## Places a named resource node on a free tile near the player. Two things make this
## worth a verb rather than a run-method call: set_resource() takes a GameResource
## object, which cannot be expressed in JSON, and it takes a Vector2i, which run-method
## cannot coerce (gather-6sp). It is also the only way to see a rare node — gold spawns
## at weight 0.4 behind a tier-3 skill — without grinding for it.
func _cmd_spawn_resource(args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var player := _player()
	if handler == null or player == null:
		return {"success": false, "message": "no TileMapHandler or player", "data": {}}

	var wanted: String = str(args.get("name", ""))
	var resource: GameResource = null
	for key in handler.resources.GetAllTypes():
		var candidate = handler.resources.Get(key)
		if candidate.name.to_lower() == wanted.to_lower():
			resource = candidate
			break

	if resource == null:
		var known := []
		for key in handler.resources.GetAllTypes():
			known.append(handler.resources.Get(key).name)
		return {
			"success": false,
			"message": "no resource named '%s'" % wanted,
			"data": {"known": known},
		}

	# Search outward from the player so the node lands somewhere visible.
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var target = null
	for ring in range(1, 8):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				var cell := origin + Vector2i(dx, dy)
				if not handler.is_occupied(cell, true):
					target = cell
					break
			if target != null:
				break
		if target != null:
			break

	if target == null:
		return {"success": false, "message": "no free tile near the player", "data": {}}

	handler.resource_manager.set_resource(target, resource)

	return {
		"success": true,
		"message": "placed %s" % resource.name,
		"data": {
			"resource": resource.name,
			"cell": {"x": target.x, "y": target.y},
			"tile_source_id": resource.tile_source_id,
			"atlas": {"x": resource.atlas_location.x, "y": resource.atlas_location.y},
			"census": handler.resource_node_census(),
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
			"cap": handler.resource_manager.resource_cap(),
			"land_tiles": handler.count_land_tiles(),
			"spawnable": spawnable,
			"tuning": tuning,
		},
	}


## In-flight gather state, and — the part that matters — the two tilemap artefacts a
## gather leaves behind: the layer-3 selector tile and the layer-1 mid-gather frame.
##
## Both are written by main.gd:_on_resource_removing and undone only by
## _on_resource_removing_stop, so a press whose stop never fires strands them on the
## tile forever. Nothing else can see that: gather_stats counts nodes (a stranded
## highlight is not a node), get-state on the TileMap reports no cell contents, and a
## screenshot shows a selector box that looks exactly like a legitimately selected
## tile. `stranded` is the assertion — highlight cells while nothing is being gathered.
func _cmd_gather_state(_args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var player := _player()
	if handler == null or player == null:
		return {"success": false, "message": "no TileMapHandler or player", "data": {}}

	var manager: ResourceManager2 = handler.resource_manager
	var tile_map = handler.tileMap

	# Reverse map of the mid-gather atlas cell back to the resource, so a layer-1 cell
	# left on the gathering frame can be named rather than just counted.
	var mid_gather := {}
	for key in handler.resources.GetAllTypes():
		var resource = handler.resources.Get(key)
		if resource.gathering_atlas_location != Vector2i.ZERO:
			mid_gather[resource.gathering_atlas_location] = resource.name

	var highlights := []
	for cell in tile_map.get_used_cells(3):
		highlights.append({"x": cell.x, "y": cell.y})

	var mid_gather_cells := []
	for cell in tile_map.get_used_cells(1):
		var atlas = tile_map.get_cell_atlas_coords(1, cell)
		if mid_gather.has(atlas):
			mid_gather_cells.append({"x": cell.x, "y": cell.y, "resource": mid_gather[atlas]})

	var info = manager.removing_info
	var target = null
	if info != null:
		target = {
			"resource": info.resource.name if info.resource else "",
			"location": str(info.location),
		}

	# A gather is only legitimately in flight while the hold timer is running. Anything
	# drawn on the map outside that window is a leak, whatever the player is doing.
	var gathering: bool = manager.is_holding_e and not manager.hold_timer.is_stopped()

	# player.gd:_process redraws a layer-3 highlight on the nearest chest every frame,
	# so a highlight is legitimate while one is in range. Without this the verb would
	# report `stranded` for every player standing next to a chest and the flag would be
	# worthless exactly where a gather test puts the player.
	var chest_in_range: bool = player.nearest_chest != null

	return {
		"success": true,
		"message": "ok",
		"data": {
			"is_holding": manager.is_holding_e,
			"timer_stopped": manager.hold_timer.is_stopped(),
			"time_left": manager.hold_timer.time_left,
			"wait_time": manager.hold_timer.wait_time,
			"gathering": gathering,
			"removing_info": target,
			"removing_node": manager.removing_node != null,
			"removing_tool": manager.removing_tool.name if manager.removing_tool else "",
			"progress_visible": manager.gather_progress.visible if manager.gather_progress else false,
			"action_pressed": Input.is_action_pressed("gather"),
			"chest_in_range": chest_in_range,
			"highlight_cells": highlights,
			"mid_gather_cells": mid_gather_cells,
			# The whole point of the verb: tilemap artefacts with no gather behind them.
			# A mid-gather frame is never legitimate outside a gather, so it counts on its
			# own; a highlight only counts when no chest is claiming it.
			"stranded": not gathering and (
				mid_gather_cells.size() > 0 or (highlights.size() > 0 and not chest_in_range)),
		},
	}


# --- crafting ----------------------------------------------------------------

## Places a sawmill or furnace next to the player. set_tile takes a Vector2i, which
## run-method cannot coerce (gather-6sp), and a station is a scene tile whose
## alternative id carries the is_scene flag - nothing generic can express that.
func _cmd_place_station(args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var player := _player()
	if handler == null or player == null:
		return {"success": false, "message": "no TileMapHandler or player", "data": {}}

	var wanted: String = str(args.get("type", "Sawmill")).to_lower()
	var station_type = Types.Item.Sawmill if wanted == "sawmill" else (
		Types.Item.Furnace if wanted == "furnace" else -1)
	if station_type == -1:
		return {"success": false, "message": "type must be Sawmill or Furnace", "data": {}}

	var item: GameItem = GameItems.get_item(station_type)
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var target = null
	for ring in range(1, 8):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				var cell := origin + Vector2i(dx, dy)
				if not handler.is_occupied(cell, true):
					target = cell
					break
			if target != null:
				break
		if target != null:
			break

	if target == null:
		return {"success": false, "message": "no free tile near the player", "data": {}}

	# atlas_location, not tile_atlas_location: the latter is the inventory ICON cell
	# (get_atlas() prefers it), and feeding it to a TileSetScenesCollectionSource
	# writes a cell that instances nothing at all. player_manager.place_tile:29 is the
	# path the game itself uses, and it passes atlas_location.
	handler.set_tile(target, item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)

	# The tilemap instances the station scene on its own schedule, so the node may not
	# exist yet on this frame. Report the cell; craft_state picks it up next call.
	return {
		"success": true,
		"message": "placed %s" % item.name,
		"data": {
			"type": item.name,
			"cell": {"x": target.x, "y": target.y},
			"stations_before": _stations().size(),
		},
	}


## Opens or closes the crafting panel on a station. Routes through the panel's own
## set_open so the cursor/disable_input handshake runs exactly as an F press would.
## Opening it any other way is impossible from the CLI: it needs the player standing
## inside the station's Area2D.
func _cmd_crafting_panel(args: Dictionary) -> Dictionary:
	var panel := _crafting_panel()
	if panel == null:
		return {"success": false, "message": "no CraftingUi in the scene", "data": {}}

	var want_open: bool = bool(args.get("open", not panel.is_open()))
	if want_open:
		var station := _station_at(args)
		if station == null:
			return {
				"success": false,
				"message": "no crafting station to open (place_station first)",
				"data": {"stations": _stations().size()},
			}
		panel.open_station(station)
	else:
		panel.set_open(false)

	var input_manager = _dev.get_tree().root.get_node_or_null("Main/InputManager")
	return {
		"success": true,
		"message": "ok",
		"data": {
			"open": panel.is_open(),
			# Returned alongside `open` on purpose: a panel that is visible while the
			# player can still walk around is exactly what the old toggled
			# disable_input caused, and it is invisible in a visibility read.
			"disable_input": input_manager.disable_input if input_manager else null,
			"mouse_mode": "visible" if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else "captured",
			"stations": _stations().size(),
		},
	}


## Everything a crafting assertion needs in one read. get-state on a station reports
## selected_recipe as an opaque CraftingRecipe object id, and nothing at all reports
## what the panel is showing.
func _cmd_craft_state(args: Dictionary) -> Dictionary:
	var panel := _crafting_panel()
	var stations := _stations()

	var data := {
		"panel_open": panel != null and panel.is_open(),
		"stations": stations.size(),
	}

	var station := _station_at(args)
	if station:
		data["station"] = _station_report(station)

	if panel and panel.is_open() and panel.station:
		var inventory: InventoryData = panel._inventory()
		var rows := []
		if panel._selected and inventory:
			for type in panel._selected.cost_list:
				rows.append({
					"item": _type_name(type),
					# required is per-unit x the panel's amount. The old panel showed
					# this number and then charged 1, so the two have to be readable
					# together to prove they agree.
					"required": int(panel._selected.cost_list[type]) * panel._amount,
					"held": inventory.count_of_type(type),
				})
		data["ui"] = {
			"station": _type_name(panel.station.type),
			"selected_recipe": _type_name(panel._selected.product) if panel._selected else "",
			"amount": panel._amount,
			"cost_rows": rows,
			"can_craft": not panel._craft_button.disabled,
			"cards": panel._cards.size(),
			"queue_visible": panel._queue_bar.visible,
			"compact": panel._compact,
		}

	return {"success": true, "message": "ok", "data": data}


## Drives the whole buy path - select, validate, pay, queue - and reports the
## inventory delta so the charge can be asserted directly rather than inferred. This
## is the verb that would have caught "every recipe costs 1 of each ingredient".
func _cmd_queue_craft(args: Dictionary) -> Dictionary:
	var station := _station_at(args)
	if station == null:
		return {"success": false, "message": "no crafting station", "data": {}}

	var player := _player()
	if player == null:
		return {"success": false, "message": "no player", "data": {}}

	var wanted: String = str(args.get("recipe", ""))
	var recipe: CraftingRecipe = null
	for candidate in station.recipe_list:
		if candidate and _type_name(candidate.product).to_lower() == wanted.to_lower():
			recipe = candidate
			break

	if recipe == null:
		var known := []
		for candidate in station.recipe_list:
			if candidate:
				known.append(_type_name(candidate.product))
		return {
			"success": false,
			"message": "'%s' is not unlocked at this station" % wanted,
			"data": {"refused_reason": "recipe_locked", "unlocked_recipes": known},
		}

	var amount: int = int(args.get("amount", 1))
	var expected := {}
	var before := {}
	for type in recipe.cost_list:
		expected[_type_name(type)] = int(recipe.cost_list[type]) * amount
		before[_type_name(type)] = player.inventory_data.count_of_type(type)

	var queued: bool = station.enqueue(recipe, amount, player.inventory_data)

	var after := {}
	var spent := {}
	for type in recipe.cost_list:
		var now: int = player.inventory_data.count_of_type(type)
		after[_type_name(type)] = now
		spent[_type_name(type)] = before[_type_name(type)] - now

	return {
		"success": queued,
		"message": "queued %d %s" % [amount, _type_name(recipe.product)] if queued else "refused",
		"data": {
			"recipe": _type_name(recipe.product),
			"amount": amount,
			"expected_cost": expected,
			"spent": spent,
			"inventory_before": before,
			"inventory_after": after,
			"count": station.count,
			"starting_count": station.starting_count,
			"refused_reason": "" if queued else "unaffordable",
		},
	}


## Fires a station's production tick N times and reports what actually landed in the
## world. step-time works but scales badly for a 20-item order and cannot attribute
## the drops to the station that made them.
func _cmd_advance_crafting(args: Dictionary) -> Dictionary:
	var station := _station_at(args)
	if station == null:
		return {"success": false, "message": "no crafting station", "data": {}}

	var level_up = _level_up_manager()
	var xp_before: int = level_up.xp if level_up else 0
	var count_before: int = station.count
	var pickups_before: int = _pickup_count()

	var ticks: int = int(args.get("ticks", 1))
	var produced := 0
	for i in ticks:
		if station.count <= 0:
			break
		station._on_timeout()
		produced += 1

	return {
		"success": true,
		"message": "produced %d" % produced,
		"data": {
			"produced": produced,
			"product": _type_name(station.selected_recipe.product) if station.selected_recipe else "",
			"count_before": count_before,
			"count_after": station.count,
			"pickups_before": pickups_before,
			# The only honest evidence that the tick reached PickUpManager rather than
			# just decrementing a counter.
			"pickups_after": _pickup_count(),
			"xp_gained": (level_up.xp if level_up else 0) - xp_before,
		},
	}


## Drops in the world. The PickUps container holds a shadow per pickup, so a raw
## child count is double what the player can actually collect.
func _pickup_count() -> int:
	var container := _dev.get_tree().root.get_node_or_null("Main/Node2D/PickUps")
	if container == null:
		return 0
	var total := 0
	for child in container.get_children():
		# There is no PickUp class_name to type-check against, so a drop is
		# identified the way _cmd_coin_count does it: by carrying slot_data.
		if child.get("slot_data") != null:
			total += 1
	return total
