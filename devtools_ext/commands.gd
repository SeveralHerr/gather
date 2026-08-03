extends RefCounted

## Gather's project-specific DevTools verbs.
##
## The godot_selftest core instantiates this once at startup and calls
## register_commands(dev) after its generic verbs are in place.
##
## Every handler returns exactly { "success": bool, "message": String, "data": {} }.
## Verbs are reachable from the CLI with hyphens: `cmd gather-stats`.

var _dev: Node

## freeze_ambient's book-keeping: exactly the timers IT paused, so unfreezing resumes
## each one with its remaining time intact and never restarts a timer that was already
## stopped for its own reasons (G-042).
var _ambient_frozen := false
var _frozen_timers: Array = []

## Built on first use, so a session that never records a clip never constructs it.
var _director: DemoDirector = null


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
	dev.register_command("freeze_ambient", _cmd_freeze_ambient)
	dev.register_command("coin_count", _cmd_coin_count)
	dev.register_command("land_state", _cmd_land_state)
	dev.register_command("buy_land", _cmd_buy_land)
	dev.register_command("land_panel", _cmd_land_panel)
	dev.register_command("splash", _cmd_splash)
	dev.register_command("spawn_resource", _cmd_spawn_resource)
	dev.register_command("goto_resource", _cmd_goto_resource)
	dev.register_command("goto_cell", _cmd_goto_cell)
	dev.register_command("skill_panel", _cmd_skill_panel)
	dev.register_command("learn_skill", _cmd_learn_skill)
	dev.register_command("place_station", _cmd_place_station)
	dev.register_command("crafting_panel", _cmd_crafting_panel)
	dev.register_command("craft_state", _cmd_craft_state)
	dev.register_command("queue_craft", _cmd_queue_craft)
	dev.register_command("advance_crafting", _cmd_advance_crafting)
	dev.register_command("place_build", _cmd_place_build)
	dev.register_command("tile_at", _cmd_tile_at)
	dev.register_command("panels_state", _cmd_panels_state)
	dev.register_command("island_census", _cmd_island_census)
	dev.register_command("place_worker", _cmd_place_worker)
	dev.register_command("place_tile", _cmd_place_tile)
	dev.register_command("load_worker", _cmd_load_worker)
	dev.register_command("worker_state", _cmd_worker_state)
	dev.register_command("press_key", _cmd_press_key)
	dev.register_command("demo_clip", _cmd_demo_clip)
	dev.register_command("demo_state", _cmd_demo_state)

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
	return _dev.get_tree().root.get_node_or_null("Main/UI/SkillTreeUI") as SkillTreeUi


func _skill_panel_open() -> bool:
	var ui := _skill_tree_ui()
	return ui != null and ui.is_open()


func _crafting_panel() -> CraftingUi:
	return _dev.get_tree().root.get_node_or_null("Main/UI/CraftingUI") as CraftingUi


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
	return _dev.get_tree().root.get_node_or_null("Main/World/EnemySpawner") as EnemySpawner


func _land_manager() -> LandManager:
	return _dev.get_tree().root.get_node_or_null("Main/LandManager") as LandManager


func _land_panel() -> LandPurchaseUi:
	return _dev.get_tree().root.get_node_or_null("Main/UI/LandPurchaseUI") as LandPurchaseUi


func _tile_map_handler() -> TileMapHandler:
	for node in _dev.get_tree().get_nodes_in_group("TileMapHandler"):
		if node is TileMapHandler:
			return node
	return null


## A Vector2/Vector2i flattened for the wire. Vectors always cross as {"x":..,"y":..}
## dicts — run-method cannot coerce them back (gather-6sp), so no verb emits one raw.
func _xy(v) -> Dictionary:
	return {"x": v.x, "y": v.y}


## The map cell the game itself treats as "in front of the player", or null when there
## is no tilemap to ask. get_tile_in_front_of_player() returns the tile's top-left
## corner in tilemap space, so this converts it back the same way
## GameItemPlaceable._placed_cell does — one implementation, not two that can disagree.
func _front_cell(player: Player):
	var handler = player.tilemap if player else null
	if handler == null or handler.tileMap == null:
		return null
	return handler.tileMap.local_to_map(handler.get_tile_in_front_of_player() + Vector2(8, 8))


## Teleports the player onto `stand` (the same +6px offset goto_resource uses) and
## points the sprite so `face` is what get_tile_in_front_of_player() resolves. Velocity
## is zeroed so the next _physics_process cannot re-flip the sprite from leftover input.
func _stand_facing(player: Player, handler: TileMapHandler, stand: Vector2i, face: Vector2i) -> void:
	player.position = handler.tileMap.map_to_local(stand) + Vector2(6, 0)
	player.velocity = Vector2.ZERO
	player.animated_sprite_2d.flip_h = face.x < stand.x


## The unoccupied cell NEAREST the player within `radius` rings, or null. Shared by
## spawn_resource and place_station: nearest-first is what keeps a placed station inside
## the crafting panel's 24-unit keep-open radius (G-037a).
func _free_cell_near_player(handler: TileMapHandler, origin: Vector2i, radius: int = 7):
	var free := []
	for offset in TileMapHandler.cells_within(radius):
		var cell: Vector2i = origin + offset
		if not handler.is_occupied(cell, true):
			free.append(cell)
	return TileMapHandler.cell_nearest_to(free, origin)


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

	# The cursor rides along because every clickable thing in the game depends on it
	# and nothing else reports it. MOUSE_MODE_CAPTURED stops Godot picking any
	# Control at all, so a stray re-capture turns the HUD toolbar, the hotbar's
	# arrows and every panel button into decoration — with no error, no visual
	# difference beyond a missing pointer, and every state read still answering
	# correctly. The game plays VISIBLE now (player.gd); anything else here is a bug.
	status["mouse_mode"] = _mouse_mode_name()

	# Whether freeze_ambient is holding the world still (G-042). A frozen session that
	# outlives the assertion it was frozen for would otherwise read as a dead spawner.
	status["ambient_frozen"] = _ambient_frozen

	var level_up = _level_up_manager()
	if level_up:
		status["xp"] = level_up.xp
		status["next_level"] = level_up.next_level
		status["level"] = level_up.level
		status["skill_points"] = level_up.points
		status["skill_panel_open"] = _skill_panel_open()

	return status


## Sends a real `InputEventKey` — both halves — for a key named the way
## `OS.get_keycode_string` prints it ("Left", "E", "1").
##
## The bridge's own `input` verbs all dispatch `InputEventAction`, which never
## reaches `_unhandled_key_input`. Everything in this game that reads a *raw keycode*
## is therefore invisible to them: the hotbar's number keys, its Left/Right step keys,
## and — until it was removed — the Q/E pair that collided with `gather`. That
## collision made every pickaxe swing advance the hotbar a slot, and it survived lint,
## the unit suite and a full `/verify` run precisely because no primitive here could
## deliver the event that triggered it.
##
## Both halves, and in that order, for the reason `hud_toolbar.gd` spells out: a key
## left logically down is a trap for whatever asks `Input.is_key_pressed` next.
##
## Deprecated: superseded by the generic `input_key` bridge verb landing in harness
## 0.8.0. Kept working because this project's installed addon is 0.7.0, which has no
## input_key yet.
func _cmd_press_key(args: Dictionary) -> Dictionary:
	var name_arg := str(args.get("key", ""))
	if name_arg == "":
		return {"success": false, "message": "press_key needs a 'key' (e.g. \"Left\")", "data": {}}

	var keycode := OS.find_keycode_from_string(name_arg)
	if keycode == KEY_NONE:
		return {
			"success": false,
			"message": "'%s' is not a key name OS.find_keycode_from_string knows" % name_arg,
			"data": {},
		}

	var repeat: int = maxi(1, int(args.get("count", 1)))
	for _i in repeat:
		for pressed in [true, false]:
			var event := InputEventKey.new()
			event.keycode = keycode
			# Both, because handlers in this project are split between the two:
			# hot_bar_inventory.gd compares `keycode`, project.godot binds `gather`
			# by `physical_keycode`. Sending one would exercise half the game.
			event.physical_keycode = keycode
			event.pressed = pressed
			Input.parse_input_event(event)

	return {
		"success": true,
		"message": "sent %s x%d" % [OS.get_keycode_string(keycode), repeat],
		"data": {"key": OS.get_keycode_string(keycode), "keycode": keycode, "count": repeat},
	}


## `Input.mouse_mode` as a word. All four are named rather than folded into
## visible/other, because CONFINED and HIDDEN fail in different ways: HIDDEN leaves
## the picking working but draws no pointer, CONFINED draws one but pins it to the
## window.
func _mouse_mode_name() -> String:
	match Input.mouse_mode:
		Input.MOUSE_MODE_VISIBLE:
			return "visible"
		Input.MOUSE_MODE_HIDDEN:
			return "hidden"
		Input.MOUSE_MODE_CAPTURED:
			return "captured"
		Input.MOUSE_MODE_CONFINED:
			return "confined"
	return "unknown"


func _cmd_player_state(_args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"success": false, "message": "no player in the scene", "data": {}}

	var selected = player.hot_bar_inventory.selected_slot_data
	var front = _front_cell(player)

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
			# Facing decides which cell every placement lands on (gather-dsk), and the
			# sprite flip is the only place the game records it.
			"facing_left": player.is_facing_left(),
			"tile_in_front": _xy(front) if front != null else null,
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


const GOTO_CELL_PREDICATES := ["grass_clear", "shore", "resource"]


## Teleports the player so the nearest cell matching a predicate is the game's own
## "tile in front" (G-064). Predicates: grass_clear (unoccupied land), shore (grass
## bordering water), resource (a standable cell horizontally adjacent to a layer-1
## resource node). Optional dx/dy bias the search centre away from the player, so a
## test can ask for "a shore cell roughly north of here".
## cmd goto_cell --args '{"predicate":"shore"}'
func _cmd_goto_cell(args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var player := _player()
	if handler == null or player == null:
		return {"success": false, "message": "no TileMapHandler or player", "data": {}}

	var predicate: String = str(args.get("predicate", ""))
	if not GOTO_CELL_PREDICATES.has(predicate):
		return {
			"success": false,
			"message": "unknown predicate '%s'" % predicate,
			"data": {"known": GOTO_CELL_PREDICATES},
		}

	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var centre: Vector2i = origin + Vector2i(int(args.get("dx", 0)), int(args.get("dy", 0)))

	var grass := {}
	for cell in handler.land_tiles():
		grass[cell] = true

	# resource stands ON the matched cell and faces the node beside it; the other two
	# stand on a horizontal neighbour and face the matched cell itself. Either way the
	# matched cell (or the node) ends up as get_tile_in_front_of_player()'s answer.
	var resource_cells := _resource_cells(handler) if predicate == "resource" else {}

	var candidates := []
	for cell in grass:
		if handler.is_occupied(cell, true):
			continue
		match predicate:
			"grass_clear":
				if _stand_cell_beside(handler, grass, cell) != null:
					candidates.append(cell)
			"shore":
				if _stand_cell_beside(handler, grass, cell) == null:
					continue
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					# An unused layer-0 cell answers (-1,-1), so "not grass" covers open
					# water and the void beyond the map in one comparison.
					if handler.tileMap.get_cell_atlas_coords(0, cell + step) != TileMapHandler.GRASS_ATLAS:
						candidates.append(cell)
						break
			"resource":
				if resource_cells.has(cell + Vector2i(1, 0)) or resource_cells.has(cell + Vector2i(-1, 0)):
					candidates.append(cell)

	if candidates.is_empty():
		return {
			"success": false,
			"message": "no cell on the map matches '%s'" % predicate,
			"data": {"predicate": predicate, "known": GOTO_CELL_PREDICATES},
		}

	var target: Vector2i = TileMapHandler.cell_nearest_to(candidates, centre)

	var stand: Vector2i
	var face: Vector2i
	if predicate == "resource":
		stand = target
		face = target + (Vector2i(1, 0) if resource_cells.has(target + Vector2i(1, 0)) else Vector2i(-1, 0))
	else:
		face = target
		stand = _stand_cell_beside(handler, grass, target)

	_stand_facing(player, handler, stand, face)
	var front = _front_cell(player)

	return {
		"success": true,
		"message": "standing at %s facing %s (%s)" % [stand, face, predicate],
		"data": {
			"predicate": predicate,
			"cell": _xy(target),
			"stand": _xy(stand),
			"player_pos": {"x": player.position.x, "y": player.position.y},
			"facing_left": player.is_facing_left(),
			# The proof of alignment: the cell the game itself would act on.
			"tile_in_front": _xy(front) if front != null else null,
		},
	}


## A grass cell immediately west or east of `cell` for the player to stand on,
## preferring an unoccupied one, or null when the cell has no horizontal land
## neighbour — facing is horizontal-only in this game, so a cell reachable solely from
## above or below can never be "in front".
func _stand_cell_beside(handler: TileMapHandler, grass: Dictionary, cell: Vector2i):
	var options := [cell + Vector2i(-1, 0), cell + Vector2i(1, 0)]
	for side in options:
		if grass.has(side) and not handler.is_occupied(side, true):
			return side
	for side in options:
		if grass.has(side):
			return side
	return null


## Every layer-1 cell currently holding a tile-based resource, keyed for membership
## tests. Same atlas-map approach as goto_resource; scene-backed nodes are excluded
## because they are not cells.
func _resource_cells(handler: TileMapHandler) -> Dictionary:
	var atlases := {}
	for key in handler.resources.GetAllTypes():
		var resource = handler.resources.Get(key)
		if not resource.is_scene_tile:
			atlases[resource.atlas_location] = true

	var cells := {}
	for cell in handler.tileMap.get_used_cells(1):
		if atlases.has(handler.tileMap.get_cell_atlas_coords(1, cell)):
			cells[cell] = true
	return cells


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


## Freezes ambient drift — enemy spawning, resource regrowth and station production
## ticks — so xp, gold and censuses hold still for an assertion window (G-042).
## `{"frozen": true|false}` (default true). Pauses via Timer.paused and stores exactly
## what it paused, so unfreezing resumes each timer with its remaining time intact:
## the game is left in a state it can reach itself. Calling with true again is safe and
## also catches timers that appeared (a newly placed station) since the first freeze.
## cmd freeze_ambient --args '{"frozen":true}'
func _cmd_freeze_ambient(args: Dictionary) -> Dictionary:
	var want: bool = bool(args.get("frozen", true))

	if want:
		for timer in _ambient_timers():
			if not timer.paused:
				timer.paused = true
				_frozen_timers.append(timer)
	else:
		for timer in _frozen_timers:
			if is_instance_valid(timer):
				timer.paused = false
		_frozen_timers.clear()
	_ambient_frozen = want

	var paused_paths := []
	for timer in _frozen_timers:
		if is_instance_valid(timer):
			paused_paths.append(str(timer.get_path()))

	return {
		"success": true,
		"message": "ambient timers %s" % ("frozen" if want else "resumed"),
		"data": {"frozen": _ambient_frozen, "paused": paused_paths},
	}


## Every timer that advances the world without player action: the enemy spawner's, the
## resource respawn tick, and each crafting station's production tick — stations pay
## XP_CRAFT per unit, so a queued craft drifts xp through a freeze window too.
func _ambient_timers() -> Array:
	var timers := []
	var spawner := _enemy_spawner()
	if spawner and spawner.timer:
		timers.append(spawner.timer)
	var respawn := _dev.get_tree().root.get_node_or_null("Main/World/ResourceTimer")
	if respawn is Timer:
		timers.append(respawn)
	for station in _stations():
		if station.timer:
			timers.append(station.timer)
	return timers


## Coin economy readout. "Enemies drop coins" is otherwise only assertable from a
## screenshot: coins are an ordinary inventory item, so nothing else reports them.
func _cmd_coin_count(_args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"success": false, "message": "no player in the scene", "data": {}}

	# The PickUps container holds shadows as well as drops, so every child has to be
	# probed for slot_data rather than assumed to have one.
	var world_coins := 0
	var container := _dev.get_tree().root.get_node_or_null("Main/World/PickUps")
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
	var open_before := _open_islands(handler)

	var bought := 0
	for _i in count:
		if not land.purchase():
			break
		bought += 1

	# Which islands this purchase opened, i.e. what it actually unlocked rather than how many
	# tiles it drew. Growing the coastline into an island is the one thing a parcel does that
	# no other reading here shows: the tile count moves by the same amount either way.
	var opened := []
	for id in _open_islands(handler):
		if not open_before.has(id):
			opened.append(id)

	return {
		"success": bought > 0,
		"message": "bought %d of %d parcel(s)%s" % [bought, count, ", opened %s" % [opened] if opened else ""],
		"data": {
			"bought": bought,
			"radius_before": radius_before,
			"radius_after": land.radius,
			"tiles_before": tiles_before,
			"tiles_after": handler.count_land_tiles(),
			"spent": gold_before - land.gold(),
			"gold_left": land.gold(),
			"next_cost": land.current_cost(),
			"islands_opened": opened,
		},
	}


## The ids of every island currently open to spawning, as a lookup.
func _open_islands(handler: TileMapHandler) -> Dictionary:
	var open := {}
	for region in handler.island_regions:
		if region.connected:
			open[region.id] = true
	return open


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
	var container = _dev.get_tree().root.get_node_or_null("Main/World/SplashTexts")
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

	# Nearest free cell outward from the player, so the node lands somewhere visible.
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var target = _free_cell_near_player(handler, origin)

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

	# The gather in flight right now (G-024). A hold is only legitimate while the timer
	# runs — same definition gather_state uses — and the target is named so a test can
	# assert WHAT is being gathered, not just that something is.
	var manager: ResourceManager2 = handler.resource_manager
	var gathering: bool = manager.is_holding_e and not manager.hold_timer.is_stopped()
	var info = manager.removing_info
	var target_resource = null
	if info != null and info.resource:
		target_resource = info.resource.name

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
			"is_gathering": gathering,
			"hold_time_left": manager.hold_timer.time_left if gathering else -1.0,
			"target_resource": target_resource,
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
	# Nearest free cell, not first-found: the old scan started at each ring's far corner
	# and put stations 48px away — outside the crafting panel's 24-unit keep-open radius,
	# so the panel closed the frame after it opened (G-037a, gather-7y9).
	var target = _free_cell_near_player(handler, origin)

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
			# Assertable against the panel's keep-open radius: > 24 and the panel
			# would close itself the frame after open_station.
			"distance_px": (player.global_position - Vector2(handler.tileMap.map_to_local(target))).length(),
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

	var input_manager = _dev.get_tree().root.get_node_or_null("Main/Systems/InputManager")
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
	var container := _dev.get_tree().root.get_node_or_null("Main/World/PickUps")
	if container == null:
		return 0
	var total := 0
	for child in container.get_children():
		# There is no PickUp class_name to type-check against, so a drop is
		# identified the way _cmd_coin_count does it: by carrying slot_data.
		if child.get("slot_data") != null:
			total += 1
	return total


## --- Building set -----------------------------------------------------------
##
## Walls and floors are placed through TileMapHandler.set_tile, which takes two
## Vector2i arguments. run-method hands raw JSON to callv with no vector coercion
## (gather-6sp), so there is no way to drive that path generically - hence a verb.

const BUILD_ITEMS := {
	"woodwall": Types.Item.WoodWall,
	"stonewall": Types.Item.StoneWall,
	"woodfloor": Types.Item.WoodFloor,
	"stonefloor": Types.Item.StoneFloor,
}


## The cell `dx`,`dy` away from the player, in tilemap coordinates.
## The cell a verb is aimed at: absolute `x`/`y` when given, otherwise a `dx`/`dy` offset
## from the player's own cell.
##
## The absolute branch is not decoration. Without it `tile_at --args '{"x":3,"y":-2}'`
## silently fell through to the player's cell and reported that instead, so six queries for
## six different cells all came back describing the same one — a read verb that answers a
## question you did not ask (gather-tfb).
func _cell_near_player(handler: TileMapHandler, args: Dictionary) -> Vector2i:
	if args.has("x") or args.has("y"):
		return Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))
	var origin: Vector2i = handler.tileMap.local_to_map(_player().global_position)
	return origin + Vector2i(int(args.get("dx", 0)), int(args.get("dy", 0)))


## Registry lookup by display name, insensitive to case, spaces, underscores and hyphens, so
## "Bone Worker", "bone_worker" and "boneworker" all land. GameItems.get_type() is an exact
## string match, which is why it is not used here.
func _name_key(text: String) -> String:
	return text.to_lower().replace(" ", "").replace("_", "").replace("-", "")


func _item_by_name(wanted: String) -> GameItem:
	var key := _name_key(wanted)
	for type in GameItems.item_list.keys():
		var item: GameItem = GameItems.item_list[type]
		if item != null and _name_key(item.name) == key:
			return item
	return null


func _placeable_names() -> Array:
	var names: Array = []
	for type in GameItems.item_list.keys():
		var item: GameItem = GameItems.item_list[type]
		if item != null and item.is_placeable:
			names.append(item.name)
	names.sort()
	return names


## Places any placeable tile from the registry, by name, at a chosen cell.
##
## Exists because place_station (sawmill/furnace), place_build (walls/floors) and
## place_worker (bone workers) were three partial reimplementations of one operation, each
## covering its own author's case, and a runtime pass that needed a chest beside a worker
## could not get one from any of them (G-077).
##
## Two things it does that its predecessors did not:
##
##  * writes atlas_location, never tile_atlas_location. The latter is the inventory icon
##    cell; feeding it to a scenes-collection source writes a cell that instances nothing
##    and still reports success (gather-w41).
##  * reads the cell back instead of assuming the write took. main.gd:set_tile returns
##    early and silently whenever disableSetTile is set, which any open UI does — the exact
##    shape of the "placement silently no-opped" hour that produced G-077. That flag is
##    reported on every call.
##
## It writes the tilemap directly, so it does NOT run GameItemPlaceable._place() and awards
## no build xp. It is a setup verb; anything asserting the real placement chain still has to
## go through use_slot_data.
func _cmd_place_tile(args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var player := _player()
	if handler == null or player == null:
		return {"success": false, "message": "no TileMapHandler or player", "data": {}}

	var wanted: String = str(args.get("name", args.get("type", "")))
	var item := _item_by_name(wanted)
	if item == null:
		return {"success": false, "message": "unknown item '%s'" % wanted,
			"data": {"refused_reason": "unknown_item", "placeable": _placeable_names()}}
	if not item.is_placeable:
		return {"success": false, "message": "'%s' is not placeable" % item.name,
			"data": {"refused_reason": "not_placeable", "placeable": _placeable_names()}}

	var as_wall: bool = bool(args.get("as_wall", item is GameItemWall2))
	var force: bool = bool(args.get("force", false))

	var cell: Vector2i
	if bool(args.get("near", false)):
		var found = _free_cell_near(handler, player, as_wall)
		if found == null:
			return {"success": false, "message": "no free cell near the player",
				"data": {"refused_reason": "no_free_tile"}}
		cell = found
	else:
		cell = _cell_near_player(handler, args)

	var occupied: bool = handler.is_occupied(cell, true, as_wall)
	if occupied and not force:
		return {"success": false, "message": "cell %s is occupied (pass force to overwrite)" % cell,
			"data": {"refused_reason": "occupied", "cell": {"x": cell.x, "y": cell.y}}}

	handler.set_tile(cell, item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)

	var written_source: int = handler.tileMap.get_cell_source_id(item.layer, cell)
	var placed: bool = written_source == item.tile_source_id
	var position: Vector2 = handler.tileMap.to_global(handler.tileMap.map_to_local(cell))
	return {
		"success": placed,
		"message": ("placed %s at %s" % [item.name, cell]) if placed else
			("set_tile did not take at %s (disableSetTile=%s)" % [cell, handler.disableSetTile]),
		"data": {
			"item": item.name,
			"cell": {"x": cell.x, "y": cell.y},
			"position": {"x": position.x, "y": position.y},
			"layer": item.layer,
			"source": item.tile_source_id,
			"atlas": {"x": item.atlas_location.x, "y": item.atlas_location.y},
			"is_scene_tile": item.is_scene_tile,
			"as_wall": as_wall,
			"occupied_before": occupied,
			"placed": placed,
			"written_source": written_source,
			"set_tile_disabled": handler.disableSetTile,
		},
	}


## First unoccupied cell walking outward from the player. Shared with place_station's own
## ring search so the two cannot pick different squares.
func _free_cell_near(handler: TileMapHandler, player: Node2D, as_wall: bool):
	var origin: Vector2i = handler.tileMap.local_to_map(handler.tileMap.to_local(player.global_position))
	for ring in range(1, 9):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				var candidate: Vector2i = origin + Vector2i(dx, dy)
				if not handler.is_occupied(candidate, true, as_wall):
					return candidate
	return null


## Places one building tile at an offset from the player, through the REAL path the
## hotbar drives: InventoryData.use_slot_data → GameItemPlaceable.use → _place →
## PlayerManager.place_tile/place_wall. That is what makes the occupancy check run, the
## stack spend, and build xp pay — the old set_tile shortcut skipped all three, which is
## exactly the xp:0 symptom this closes (G-061, gather-15o).
##
## `dx`/`dy` name the target cell relative to where the player stood BEFORE the verb
## repositions them: the player is teleported one cell west of the target, facing it,
## because the game only ever builds on get_tile_in_front_of_player(). The item is
## granted (`granted: true`) when the player does not already hold one.
## cmd place_build --args '{"type":"woodwall","dx":1}'
func _cmd_place_build(args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var player := _player()
	if handler == null or player == null:
		return {"success": false, "message": "no TileMapHandler or player", "data": {}}

	var wanted: String = str(args.get("type", "")).to_lower()
	if not BUILD_ITEMS.has(wanted):
		return {
			"success": false,
			"message": "type must be one of %s" % [BUILD_ITEMS.keys()],
			"data": {"known": BUILD_ITEMS.keys()},
		}

	var type = BUILD_ITEMS[wanted]
	var item: GameItem = GameItems.get_item(type)
	var target := _cell_near_player(handler, args)

	# The real path spends a unit from a real stack, so the player must hold one.
	var granted := false
	var slot_index := _slot_index_of_type(player.inventory_data, type)
	if slot_index == -1:
		if not player.inventory_data.pick_up_slot_data(SlotData.new(item, 1)):
			return {"success": false, "message": "inventory full, cannot grant %s" % item.name, "data": {}}
		granted = true
		slot_index = _slot_index_of_type(player.inventory_data, type)
	if slot_index == -1:
		return {"success": false, "message": "%s never landed in the inventory" % item.name, "data": {}}

	# Stand beside the target facing it, so the game's own facing logic resolves the
	# requested cell. Same mechanics as goto_cell.
	_stand_facing(player, handler, target + Vector2i(-1, 0), target)
	var front = _front_cell(player)

	var level_up = _level_up_manager()
	var xp_before: int = level_up.xp if level_up else 0
	var cell_already_paid: bool = level_up != null and level_up.built_cells.has(target)
	var slot: SlotData = player.inventory_data.inventory_slot_datas[slot_index]
	var count_before: int = slot.count

	# The exact call a hotbar use press makes.
	player.inventory_data.use_slot_data(slot_index)

	# The SlotData object outlives the inventory nulling an emptied slot, so the count
	# delta is readable either way — and it is the only trace place_tile leaves when it
	# refuses an occupied cell.
	var placed: bool = slot.count < count_before
	var xp_after: int = level_up.xp if level_up else 0

	return {
		"success": placed,
		"message": "placed %s at %s" % [item.name, target] if placed
			else "refused: %s is occupied or not buildable" % target,
		"data": {
			"type": item.name,
			"cell": _xy(target),
			"tile_in_front": _xy(front) if front != null else null,
			"granted": granted,
			"consumed": count_before - slot.count,
			"xp_before": xp_before,
			"xp_after": xp_after,
			# False xp delta with placed=true is legitimate when the cell already paid
			# once — building pays per cell, ever (gather-5s5).
			"cell_already_paid": cell_already_paid,
		},
	}


## Index of the first inventory slot holding `type`, or -1. use_slot_data takes an
## index, so the real-path verbs need the slot's position, not just its SlotData.
func _slot_index_of_type(inventory: InventoryData, type) -> int:
	for index in inventory.inventory_slot_datas.size():
		var data = inventory.inventory_slot_datas[index]
		if data and data.item and data.item.type == type:
			return index
	return -1


## Reads back what is actually on the tilemap at a cell, plus how main.gd classifies
## it. `atlas` is the cell the terrain solver chose, which is the only evidence that
## autotiling ran at all - a wall that failed to connect sits on its blob's `base` cell
## forever.
##
## With no dx/dy the cell defaults to get_tile_in_front_of_player() — the cell every
## placement actually lands on — instead of the player's own cell, which a facing-left
## player was never standing on top of (G-062, gather-tfb). Explicit dx/dy keeps the
## old player-relative behavior.
## cmd tile_at            (the cell in front)
## cmd tile_at --args '{"dx":1,"dy":0}'
func _cmd_tile_at(args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var player := _player()
	if handler == null or player == null:
		return {"success": false, "message": "no TileMapHandler or player", "data": {}}

	var mode := "offset"
	var cell: Vector2i
	if args.has("dx") or args.has("dy"):
		cell = _cell_near_player(handler, args)
	else:
		mode = "in_front"
		var front = _front_cell(player)
		if front == null:
			return {"success": false, "message": "no tilemap to resolve the facing cell", "data": {}}
		cell = front
	var layer: int = int(args.get("layer", 1))
	var source: int = handler.tileMap.get_cell_source_id(layer, cell)
	var atlas: Vector2i = handler.tileMap.get_cell_atlas_coords(layer, cell)

	var wall := handler.wall_type_at(atlas, source)
	var wall_name := ""
	var is_base := false
	if not wall.is_empty():
		wall_name = GameItems.get_item(wall["item"]).name
		is_base = atlas == wall["base"]

	return {
		"success": true,
		"message": "layer %d at %s: source %d atlas %s" % [layer, cell, source, atlas],
		"data": {
			"cell": {"x": cell.x, "y": cell.y},
			"mode": mode,
			"facing_left": player.is_facing_left(),
			"layer": layer,
			"source": source,
			"atlas": {"x": atlas.x, "y": atlas.y},
			"wall_type": wall_name,
			# True means the solver never ran: the run is still flattened to its base.
			"is_unsolved_base": is_base,
			"tracked_runs": _wall_run_sizes(handler),
		},
	}


## How many cells main.gd is tracking per wall type. Two walls of different materials
## must stay in separate runs - a single merged run is what a shared terrain index
## would produce, and it is invisible in a screenshot.
func _wall_run_sizes(handler: TileMapHandler) -> Dictionary:
	var sizes := {}
	for wall in handler.WALL_TYPES:
		var name: String = GameItems.get_item(wall["item"]).name
		sizes[name] = (handler.wall_cells[wall["item"]] as Array).size() if handler.wall_cells.has(wall["item"]) else 0
	return sizes


## Read-only open/closed state of every panel in one call (G-047, gather-6l7). The
## skill_panel / land_panel / crafting_panel verbs route through set_open/toggle, so
## using them as readers CHANGES the state being read; this touches nothing.
##
## `raw` carries the fields each derived bool comes from (the G-033 pattern): a wrapper
## Control that is visible over a closed PanelFrame is a real failure mode, and it is
## invisible in the derived value alone.
## cmd panels_state
func _cmd_panels_state(_args: Dictionary) -> Dictionary:
	var skill := _skill_tree_ui()
	var land := _land_panel()
	var crafting := _crafting_panel()
	var inventory := _dev.get_tree().root.get_node_or_null("Main/UI/InventoryInterface")

	# The station the panel is bound to, as the index the other crafting verbs use.
	# Bound outlives open: a closed panel keeps its last station, and that is reported
	# honestly rather than blanked.
	var crafting_station = null
	if crafting and crafting.station:
		var index := _stations().find(crafting.station)
		if index != -1:
			crafting_station = index

	return {
		"success": true,
		"message": "ok",
		"data": {
			"skill": skill != null and skill.is_open(),
			"land": land != null and land.is_open(),
			"crafting": {
				"open": crafting != null and crafting.is_open(),
				"station": crafting_station,
			},
			# NewInventoryManager flips this Control's `visible` directly, so the flag
			# IS the open state — cheap enough to always include.
			"inventory": inventory != null and inventory.visible,
			"raw": {
				"skill_wrapper_visible": skill.visible if skill else null,
				"skill_frame_visible": skill._frame.visible if skill and skill._frame else null,
				"land_wrapper_visible": land.visible if land else null,
				"land_frame_visible": land._frame.visible if land and land._frame else null,
				"crafting_wrapper_visible": crafting.visible if crafting else null,
				"crafting_chrome_visible": crafting._chrome.visible if crafting and crafting._chrome else null,
				"inventory_visible": inventory.visible if inventory else null,
			},
		},
	}


## Every land region and whether it can actually be walked to.
##
## The pregenerated islands are reached by buying land until the home coastline grows out
## to meet them, and whether that ever happens is decided by a noise field - so it is a
## property of the seed, not of the code, and it cannot be settled by reading the diff.
## `count_land_tiles` is a single scalar and reads the same whether the world is one
## landmass or four, and a screenshot only ever shows the ~15x8 tiles around the player,
## which is less than the distance to the nearest island. Neither can answer the only
## question that matters: is this island connected?
##
## `connected_to_home` floods across walkable grass from the player's spawn, so it answers
## it for the world as it stands right now. `connects_at_max_land` re-runs the flood
## against the coastline the home island will have once every parcel is bought, which is
## the acceptance criterion for the placement code.
func _cmd_island_census(_args: Dictionary) -> Dictionary:
	var handler = _tile_map_handler()
	if handler == null:
		return {"success": false, "message": "no TileMapHandler in the scene", "data": {}}

	var reachable_now := handler.walkable_cells_from_home()

	# The home island as it will be at maximum size, so an island that is stranded today
	# but reachable after twelve parcels reads as a pass rather than a failure.
	var final_home := {}
	for cell in handler.land_cells_for_radius(LandManager.radius_for(LandManager.MAX_PARCELS)):
		final_home[cell] = true
	var reachable_at_max := handler.walkable_cells_from_home(final_home)

	var regions := {}
	var all_connected := true
	for region in handler.regions:
		var tiles: Array = handler.land_tiles_in(region)
		var now := 0
		var at_max := 0
		for cell in tiles:
			if reachable_now.has(cell):
				now += 1
			if reachable_at_max.has(cell):
				at_max += 1

		var connects: bool = at_max > 0 or tiles.is_empty()
		if region.id != "home" and not connects:
			all_connected = false

		regions[region.id] = {
			"centre": {"x": region.centre.x, "y": region.centre.y},
			"radius": region.radius,
			"land_tiles": tiles.size(),
			"resource_nodes": handler.count_resource_nodes_in(region),
			"cap": handler.resource_manager.resource_cap(region),
			"ambient_resources": region.ambient_resources,
			"ambient_enemies": region.ambient_enemies,
			"connected_to_home": now > 0,
			"connects_at_max_land": connects,
			# The gate, and deliberately reported next to the flood fill that decides it.
			# `opened` is what the game believes; `connected_to_home` is what the terrain
			# says. They agree unless something has failed to call refresh_connections, and
			# an island stuck closed next to open ground is otherwise indistinguishable from
			# one whose spawn rolls happen to be unlucky.
			"opened": region.connected,
			"stocking": {
				"resources": region.accepts_ambient_resources(),
				"enemies": region.accepts_ambient_enemies(),
			},
		}

	return {
		"success": true,
		"message": "every island connects at max land" if all_connected else "AN ISLAND IS STRANDED",
		"data": {
			"seed": handler.island_seed(),
			"islands_seed": handler.island_manager.islands_seed if handler.island_manager else 0,
			"home_radius": handler.radius,
			"all_connected_at_max_land": all_connected,
			"boss": _boss_report(handler),
			"regions": regions,
			"census_by_region": _census_by_region(handler),
		},
	}


## The arena's contents. A boss island with no boss on it and an empty reward chest is a
## bare patch of grass, and every other reading in this response looks identical either way.
func _boss_report(handler: TileMapHandler) -> Dictionary:
	var manager = handler.island_manager
	if manager == null:
		return {"present": false}

	var boss = manager._live_boss()
	var report := {
		"defeated": manager.boss_defeated,
		"alive": boss != null,
	}

	if boss:
		report["hp"] = boss.health_manager.current_health
		report["max_hp"] = boss.health_manager.max_health
		report["damage"] = boss.damage
		report["scale"] = boss.scale.x
		report["chase_speed"] = boss.get_node("StateMachine/EnemyFollow").move_speed

	if manager.islands.has(IslandManager.BOSS_ID):
		var chest = manager._chest_at(manager.islands[IslandManager.BOSS_ID]["centre"] + IslandManager.BOSS_CHEST_OFFSET)
		var contents := []
		if chest and chest.inventory_data:
			for slot in chest.inventory_data.inventory_slot_datas:
				contents.append("%s x%d" % [slot.item.name, slot.count] if slot else "empty")
		report["chest"] = contents

	return report


## What actually grew on each island. The whole point of a themed island is that its mix
## differs from the mainland's, and the global census sums them all into one bucket - so
## an ore island quietly full of trees reads exactly like a working one.
func _census_by_region(handler: TileMapHandler) -> Dictionary:
	var atlas_to_name := {}
	for key in handler.resources.GetAllTypes():
		var resource = handler.resources.Get(key)
		if not resource.is_scene_tile:
			atlas_to_name[resource.atlas_location] = resource.name

	var by_region := {}
	for region in handler.regions:
		by_region[region.id] = {}

	for cell in handler.tileMap.get_used_cells(1):
		var atlas = handler.tileMap.get_cell_atlas_coords(1, cell)
		if not atlas_to_name.has(atlas):
			continue
		var id: String = handler.region_for_cell(cell).id
		var resource_name = atlas_to_name[atlas]
		by_region[id][resource_name] = by_region[id].get(resource_name, 0) + 1

	for node in handler.tileMap.get_children():
		if node is GameSceneResource:
			var resource = handler.resources.get_item_or_resource_by_type(node.resource_type)
			var id: String = handler.region_for_cell(handler.tileMap.local_to_map(node.position)).id
			var resource_name = resource.name if resource else "Unknown"
			by_region[id][resource_name] = by_region[id].get(resource_name, 0) + 1

	return by_region


## The flood fill this census reads lives on TileMapHandler rather than here, because the
## game itself now runs it: it is what decides whether an island has opened. A debug copy
## would be free to drift from the one the gate uses, and the reading that matters most in
## this response is the two agreeing.


## --- Bone worker -------------------------------------------------------------
##
## The worker is an automation unit: place the base, drop a captured skull on it, and it
## chops nearby trees on a timer. Every step of that is unreachable from the generic
## primitives. Placing it needs set_tile's two Vector2i arguments (gather-6sp); loading it
## needs the player to have netted a skull and to be standing inside the base's WorkArea;
## and the thing worth asserting - that it found a tree and delivered wood somewhere - is
## a relationship between a node, a tilemap cell and a chest's inventory, which no single
## get-state can express.


## Every bone machine a skull can be dropped into, in a stable order. Turrets are here
## because they share the load path (GameItemBoneEnemy loads whichever is closest), so
## "the skull went to the right one" is not assertable against workers alone. Type-checked
## rather than indexed: SaveChunks holds chests and every other persisted prop too.
func _bone_machines() -> Array:
	var found := []
	for node in _dev.get_tree().get_nodes_in_group("SaveChunks"):
		if node is BoneWorker or node is BoneTurret:
			found.append(node)
	found.sort_custom(func(a, b):
		return a.position.y < b.position.y if a.position.y != b.position.y else a.position.x < b.position.x)
	return found


func _bone_workers() -> Array:
	var found := []
	for node in _bone_machines():
		if node is BoneWorker:
			found.append(node)
	return found


func _worker_at(args: Dictionary):
	var workers := _bone_workers()
	if workers.is_empty():
		return null
	var index: int = int(args.get("worker", 0))
	if index < 0 or index >= workers.size():
		return null
	return workers[index]


## The radius of the worker's WorkArea, read off the shape rather than assumed. The
## chopping behaviour is tuned by editing that circle, so a hardcoded number here would
## quietly start reporting trees the worker cannot actually reach.
func _work_radius(worker) -> float:
	var shape_node = worker.get_node_or_null("WorkArea/CollisionShape2D")
	var shape = shape_node.shape if shape_node else null
	if shape == null:
		return 0.0
	return float(shape.get("radius")) if shape.get("radius") != null else 0.0


## Tree cells within `radius` of a global position, nearest first. Trees are tilemap cells
## rather than nodes, so nothing in the scene tree reports them and an overlap query never
## sees one - the cells have to be read off layer 1 by atlas.
func _trees_near(handler: TileMapHandler, at: Vector2, radius: float) -> Array:
	var tree = handler.resources.Get(Types.Item.Tree)
	if tree == null or radius <= 0.0:
		return []

	var tile_map = handler.tileMap
	var local: Vector2 = tile_map.to_local(at)
	var origin: Vector2i = tile_map.local_to_map(local)
	var tile_size: int = maxi(1, tile_map.tile_set.tile_size.x)
	var reach: int = int(ceil(radius / float(tile_size))) + 1

	var found := []
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var cell: Vector2i = origin + Vector2i(dx, dy)
			if tile_map.get_cell_source_id(1, cell) != tree.tile_source_id:
				continue
			if tile_map.get_cell_atlas_coords(1, cell) != tree.atlas_location:
				continue
			var distance: float = tile_map.map_to_local(cell).distance_to(local)
			if distance <= radius:
				found.append({"cell": {"x": cell.x, "y": cell.y}, "distance": distance})

	found.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return found


## Chests within `radius`, with what is actually in them. Delivery is the end of the
## worker's loop and a counter on the worker only claims it happened; the chest's contents
## are the evidence.
func _chests_near(at: Vector2, radius: float) -> Array:
	var found := []
	for node in _dev.get_tree().get_nodes_in_group("external_inventory"):
		if not (node is TestChest):
			continue
		var distance: float = node.global_position.distance_to(at)
		if distance > radius:
			continue
		var contents := []
		if node.inventory_data:
			for slot in node.inventory_data.inventory_slot_datas:
				contents.append("%s x%d" % [slot.item.name, slot.count] if slot else "empty")
		found.append({
			"position": {"x": node.position.x, "y": node.position.y},
			"distance": distance,
			"contents": contents,
		})
	found.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return found


## Wood lying in the world within `radius` of a point. Delivery falls back to dropping a
## pickup when no chest will take the wood, so without this half a working worker with no
## chest beside it reads exactly like a worker that never chopped anything.
func _wood_pickups_near(at: Vector2, radius: float) -> int:
	var container := _dev.get_tree().root.get_node_or_null("Main/World/PickUps")
	if container == null:
		return 0
	var total := 0
	for child in container.get_children():
		var slot_data = child.get("slot_data")
		if slot_data == null or slot_data.item == null:
			continue
		if slot_data.item.type == Types.Item.Wood and child.global_position.distance_to(at) <= radius:
			total += slot_data.count
	return total


## Every variable the worker's script declares, whatever they happen to be called.
## The chopping behaviour lands separately from this verb, so naming its fields here would
## either guess wrong or need a follow-up edit; enumerating the script's own property list
## means a new `target` or `wood_produced` shows up the moment it exists.
func _script_vars(node: Object) -> Dictionary:
	var vars := {}
	for prop in node.get_property_list():
		if (int(prop.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		vars[prop["name"]] = _json_safe(node.get(prop["name"]))
	return vars


## JSON-shaped view of an arbitrary property. Vectors become {x, y} rather than the
## "(3, 4)" string Godot would otherwise serialise them as, and an object becomes its node
## path - a bare object id in a response tells a caller nothing.
func _json_safe(value):
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_ARRAY:
			var out := []
			for entry in value:
				out.append(_json_safe(entry))
			return out
		TYPE_DICTIONARY:
			var mapped := {}
			for key in value:
				mapped[str(key)] = _json_safe(value[key])
			return mapped
		TYPE_OBJECT:
			# A freed node still reads as an object here. Saying so beats a crash, and a
			# worker holding a freed tree target is itself worth seeing.
			if not is_instance_valid(value):
				return "<freed>"
			if value is Node:
				return str(value.get_path())
			return value.get_class()
	return value


func _worker_report(handler: TileMapHandler, worker) -> Dictionary:
	var radius := _work_radius(worker)
	var trees := _trees_near(handler, worker.global_position, radius) if handler else []
	var animation = worker.get_node_or_null("LoadedSprite")
	var timer = worker.get_node_or_null("WorkTimer")

	var report := {
		"loaded": worker.loaded,
		"position": {"x": worker.position.x, "y": worker.position.y},
		"work_radius": radius,
		"trees_in_range": trees.size(),
		"nearest_tree": trees[0] if not trees.is_empty() else null,
		"chests_in_range": _chests_near(worker.global_position, radius),
		# Wood that reached the world rather than a chest. Together with the chest
		# contents above this is the whole output side of the worker's loop.
		"wood_pickups_nearby": _wood_pickups_near(worker.global_position, radius * 2.0),
		# The chop animation is the only visible sign of work, and it is meant to run only
		# while the worker is actually chopping - a loaded-but-idle worker that animates
		# forever looks identical in every other reading.
		"animating": animation.is_playing() if animation else false,
		"animation_visible": animation.visible if animation else false,
		"timer_stopped": timer.is_stopped() if timer else true,
		"time_to_next_cycle": timer.time_left if timer else 0.0,
		# Whatever the chopping behaviour tracks - target, wood produced, last delivery -
		# without this verb having to know its field names in advance.
		"script_vars": _script_vars(worker),
	}

	if handler:
		var cell: Vector2i = handler.tileMap.local_to_map(handler.tileMap.to_local(worker.global_position))
		report["cell"] = {"x": cell.x, "y": cell.y}

	return report


## Places a bone worker base, by default on a free tile that actually has a tree in reach -
## a worker in empty grass runs its timer forever and proves nothing, which is the same
## trap goto_resource exists to avoid for gathering.
##
## `{"dx": 1, "dy": 0}` places at an exact offset from the player instead.
## `{"require_tree": false}` takes the first free tile whether or not trees are near.
## `{"move_player": false}` leaves the player where they are; by default the player is
## moved beside the base so that a later `load_worker --args '{"via":"item"}'` has the
## overlap it needs (give the areas a `wait-frames 2` to register it).
func _cmd_place_worker(args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var player := _player()
	if handler == null or player == null:
		return {"success": false, "message": "no TileMapHandler or player", "data": {}}

	var item: GameItem = GameItems.get_item(Types.Item.BoneWorker)
	if item == null:
		return {"success": false, "message": "no BoneWorker registered in GameItems", "data": {}}

	var require_tree: bool = bool(args.get("require_tree", true))
	# The base's own WorkArea is not instanced yet, so reach is taken from the scene's
	# shape via a placed worker when there is one, and from the tileset otherwise.
	var reach: float = float(args.get("radius", 40.0))
	var origin: Vector2i = handler.tileMap.local_to_map(handler.tileMap.to_local(player.global_position))

	var cell = null
	if args.has("dx") or args.has("dy"):
		cell = origin + Vector2i(int(args.get("dx", 0)), int(args.get("dy", 0)))
	else:
		for ring in range(1, 9):
			for dx in range(-ring, ring + 1):
				for dy in range(-ring, ring + 1):
					var candidate: Vector2i = origin + Vector2i(dx, dy)
					if handler.is_occupied(candidate, true):
						continue
					var at: Vector2 = handler.tileMap.to_global(handler.tileMap.map_to_local(candidate))
					if require_tree and _trees_near(handler, at, reach).is_empty():
						continue
					cell = candidate
					break
				if cell != null:
					break
			if cell != null:
				break

	if cell == null:
		return {
			"success": false,
			"message": "no free tile with a tree within %.0f px of the player" % reach,
			"data": {"trees_near_player": _trees_near(handler, player.global_position, reach).size()},
		}

	var position: Vector2 = handler.tileMap.to_global(handler.tileMap.map_to_local(cell))
	# atlas_location, not tile_atlas_location: the latter is the inventory icon cell, and
	# feeding it to a TileSetScenesCollectionSource writes a cell that instances nothing.
	handler.set_tile(cell, item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)

	if bool(args.get("move_player", true)):
		player.global_position = position + Vector2(6, 0)

	# The tilemap instances the scene on its own schedule, so the node does not exist on
	# this frame. Report the cell; worker_state picks it up next call.
	return {
		"success": true,
		"message": "placed a bone worker at %s" % cell,
		"data": {
			"cell": {"x": cell.x, "y": cell.y},
			"position": {"x": position.x, "y": position.y},
			"trees_in_range": _trees_near(handler, position, reach).size(),
			"workers_before": _bone_workers().size(),
			"player_position": {"x": player.position.x, "y": player.position.y},
		},
	}


## Loads a worker with a skull.
##
## `{"via": "direct"}` (the default) calls set_loaded(), the same call the item makes and
## the one that owns the sprite swap - writing `loaded` straight would leave the base
## sprite showing, a state the game itself cannot produce.
##
## `{"via": "item"}` drives the real chain instead - use_slot_data -> PlayerManager ->
## GameItemBoneEnemy.use() - which targets whatever the player overlaps. That is the only
## way to exercise the targeting, and it deliberately does not move the player: moving them
## would hide exactly the failure the verb is there to catch. `{"give": false}` skips
## handing the player a skull first, so the empty-handed path is assertable too.
##
## Skull counts are reported before and after either way. The stack used to be spent even
## when the use loaded nothing, and a boolean `success` cannot show that.
func _cmd_load_worker(args: Dictionary) -> Dictionary:
	var player := _player()
	if player == null:
		return {"success": false, "message": "no player in the scene", "data": {}}

	var worker = _worker_at(args)
	if worker == null:
		return {
			"success": false,
			"message": "no bone worker at that index (place_worker first)",
			"data": {"workers": _bone_workers().size()},
		}

	var handler := _tile_map_handler()
	var via: String = str(args.get("via", "direct")).to_lower()
	var loaded_before: bool = worker.loaded
	var skull: GameItem = GameItems.get_item(Types.Item.BoneEnemy)
	var skulls_before: int = player.inventory_data.count_of_type(Types.Item.BoneEnemy)
	var in_reach: bool = skull != null and skull.can_use()

	if via == "item":
		if skulls_before == 0 and bool(args.get("give", true)):
			player.inventory_data.pick_up_slot_data(SlotData.new(skull, 1))
		var index := _slot_index_of(player.inventory_data, Types.Item.BoneEnemy)
		if index < 0:
			return {
				"success": false,
				"message": "the player holds no skull to use",
				"data": {"skulls": player.inventory_data.count_of_type(Types.Item.BoneEnemy)},
			}
		player.inventory_data.use_slot_data(index)
	elif via == "direct":
		worker.set_loaded()
	else:
		return {"success": false, "message": "via must be \"direct\" or \"item\"", "data": {}}

	var skulls_after: int = player.inventory_data.count_of_type(Types.Item.BoneEnemy)
	return {
		"success": worker.loaded,
		"message": "worker loaded" if worker.loaded else "worker still unloaded",
		"data": {
			"via": via,
			"loaded_before": loaded_before,
			"loaded": worker.loaded,
			"skulls_before": skulls_before,
			"skulls_after": skulls_after,
			# The assertion for "a use that loads nothing must not eat the skull": with
			# via=item and no machine overlapped, this has to stay 0.
			"skulls_spent": maxi(0, skulls_before - skulls_after),
			# What GameItemBoneEnemy.use() would have targeted, read before the use ran.
			"had_target_in_reach": in_reach,
			"state": _worker_report(handler, worker),
		},
	}


## First slot holding `type`, or -1. use_slot_data works on an index, and nothing else
## reports which index a given item landed in.
func _slot_index_of(inventory: InventoryData, type: Types.Item) -> int:
	for index in inventory.inventory_slot_datas.size():
		var slot = inventory.inventory_slot_datas[index]
		if slot and slot.item and slot.item.type == type:
			return index
	return -1


## Every worker's state, or one with `{"worker": 0}`. Turrets ride along with their loaded
## flag because they share the skull's load path: when a use loads the wrong machine, the
## worker looks simply unloaded and this list is the only place the skull turns up.
func _cmd_worker_state(args: Dictionary) -> Dictionary:
	var handler := _tile_map_handler()
	var workers := _bone_workers()

	var turrets := []
	for machine in _bone_machines():
		if machine is BoneTurret:
			turrets.append({
				"position": {"x": machine.position.x, "y": machine.position.y},
				"loaded": machine.loaded,
			})

	var reports := []
	if args.has("worker"):
		var worker = _worker_at(args)
		if worker == null:
			return {
				"success": false,
				"message": "no bone worker at that index",
				"data": {"workers": workers.size()},
			}
		reports.append(_worker_report(handler, worker))
	else:
		for worker in workers:
			reports.append(_worker_report(handler, worker))

	var player := _player()
	return {
		"success": true,
		"message": "ok",
		"data": {
			"workers": workers.size(),
			"turrets": turrets,
			"skulls_held": player.inventory_data.count_of_type(Types.Item.BoneEnemy) if player else 0,
			"wood_held": player.inventory_data.count_of_type(Types.Item.Wood) if player else 0,
			"worker_states": reports,
		},
	}


## Starts a scripted README capture clip and returns immediately — the choreography runs
## inside the game as a coroutine (see devtools_ext/demo_director.gd for why it has to).
##
## Poll `demo_state` for the frame marks; under `--write-movie` those are output frame
## numbers, which is what lets the trim be exact rather than a stopwatch guess.
func _cmd_demo_clip(args: Dictionary) -> Dictionary:
	if _director == null:
		_director = DemoDirector.new(_dev)

	var wanted: String = str(args.get("name", args.get("clip", "turrets")))
	return _director.start(wanted)


func _cmd_demo_state(_args: Dictionary) -> Dictionary:
	if _director == null:
		return {
			"success": true,
			"message": "no clip has been started this session",
			"data": {"running": false, "clip": "", "beat": "idle", "marks": {}, "notes": []},
		}

	var state: Dictionary = _director.state()
	return {
		"success": true,
		"message": "clip '%s' %s at beat '%s'" % [
			state["clip"], "running" if state["running"] else "stopped", state["beat"],
		],
		"data": state,
	}
