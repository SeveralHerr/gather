extends RefCounted
class_name DemoDirector

## Scripted, self-driving gameplay choreography for the README capture clips.
##
## The clips are recorded with Godot's movie writer (`--write-movie`), which advances game
## time by exactly one frame per *rendered* frame. Anything driven from the CLI would
## therefore bake every file-bus round-trip into the footage as dead air of a length that
## varies from take to take, so the entire performance runs inside the game as one
## coroutine and the CLI only starts it and asks afterwards where the interesting frames
## were.
##
## `marks` is what makes the trim exact. Under the movie writer `Engine.get_frames_drawn()`
## *is* the output frame number, so recording it at the start and end of the performance
## lets ffmpeg cut on a frame the director chose rather than on a stopwatch that has to
## guess how long world generation took this time.
##
## Nothing here reaches past the game's own entry points. The player is walked by holding
## real input actions, the turret is placed by the hotbar's own use press, and wave enemies
## arrive behind the spawner's `X` telegraph tile — so the clip shows the game rather than a
## puppet show that merely resembles it. The two deliberate exceptions are marked at their
## call sites: `player.invulnerable` (the demo must not end with a respawn) and the second
## bank of turrets, which is written straight onto the tilemap because the placement beat
## has already been shown and repeating it five times is not footage anyone wants.

const BONE_ENEMY := preload("res://enemies/bone_enemy.tscn")

## The clip never changes zoom, and that is a finding rather than a simplification. A
## turret's LineOfSight is a 40px circle and a bullet crosses it in about a second, so the
## whole battle happens inside roughly nine tiles by seven — smaller than the 15x8.4 tiles
## the camera's shipped zoom of 8 already shows. Pulling back to fit "a bunch of turrets"
## framed mostly ocean (the starting island is only about 20x13 tiles) and shrank the
## bullets to specks. The engagement radius, not the turret count, is what sets the shot.
const CLOSE_ZOOM := Vector2(8, 8)

## Half-extents, in tiles, of the patch cleared of trees and rocks before the show. Wide
## enough for the turret ring and the lanes the wave arrives down, tight enough that the
## untouched treeline stays in frame — a fully cleared field reads as a test harness rather
## than as the game.
const ARENA_HALF := Vector2i(6, 4)

## Where the wave beat puts things, as offsets in tiles from the player.
##
## Every number here is set by the 40px turret LineOfSight: each enemy cell is within 2.3
## tiles of a turret cell, which is the only reason the turrets engage at all. Widen the
## ring and the skeletons stand around unshot. The vertical spread is capped at 3 because
## the camera only shows ±4.2 tiles at zoom 8 — a lane at y=±5 is off the bottom of frame.
const TURRET_RING := [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]
const WAVE_ONE := [Vector2i(-4, -1), Vector2i(4, -1), Vector2i(-4, 1), Vector2i(4, 1)]
const WAVE_TWO := [Vector2i(-4, -3), Vector2i(4, -3), Vector2i(-4, 3), Vector2i(4, 3)]

## Half-extents of the rectangle that actually has to be dry land: the turret ring, the two
## wave lanes and the ground between them, and nothing else.
##
## Deliberately smaller than ARENA_HALF, and the two started out as one constant. Scoring
## the *clearing* instead of the *battle* asked a 13x9 patch of an island only about 20x13
## across to be solid ground, which no seed reliably has, so the clip refused to start on
## worlds it could have filmed perfectly well. Coastline in shot is fine; coastline under a
## turret is not.
const BATTLE_HALF := Vector2i(4, 3)

## Half-extents of what the camera actually shows at zoom 8 (1920x1080 over a 16px tile),
## used only to break ties between candidate centres. Land under the turrets is a hard
## requirement; land across the rest of the frame is what stops the clip being shot with a
## coastline through the middle of it and half the picture open sea.
const VIEW_HALF := Vector2i(7, 4)

## How far out the arena search is willing to walk from wherever the player spawned, in
## tiles, looking for a battle rectangle that is entirely land.
const ARENA_SEARCH := 12

## Seconds the spawner shows its `X` before an enemy appears. Copied from
## EnemySpawner.TELEGRAPH_SECONDS rather than read from it: the constant is the *game's*
## pacing and this is the *clip's*, and the wave wants a shorter tell than a 21-second
## ambient cycle does.
const TELEGRAPH := 1.0

## Beat lengths in seconds. Everything the clip's pacing depends on is here so it can be
## retimed without reading the choreography.
const BEAT := {
	"settle": 0.8,
	"before_place": 0.5,
	"after_place": 0.9,
	"after_select": 0.45,
	"before_swing": 0.35,
	"after_capture": 1.0,
	"after_load": 1.2,
	"between_waves": 4.0,
	"wave_hold": 6.0,
	"tail": 0.8,
}

## How close the player has to be before the net swings, and it is reach rather than
## preference. `Net_Right` sweeps the area from (0,-3.6) to (5.2,2.4) over 0.2s and its
## circle is 4.7 across, so the far edge of the swing is about 15px from the player — with
## the skeleton's own 11x5 body that leaves a capture window of roughly 10 to 15 pixels.
## The first cut swung at 22 and missed every time, silently: a swing that connects with
## nothing is animated exactly like one that does.
const NET_REACH := 13.0

## Long enough for the 0.2s swing to play out before the catch is judged. Counted in
## seconds rather than frames on purpose — the game runs uncapped here and at 60fps under
## the movie writer, so "twelve frames" is two different durations.
const SWING_SETTLE := 0.35

## EnemyIdle only hands over to EnemyFollow inside 30px, so an enemy spawned any further
## out than this simply wanders. The net beat therefore walks the *player* to the skeleton
## rather than waiting for a skeleton that is never coming.
const AGGRO_RANGE := 30.0

var _dev: Node
var _running := false
var _clip := ""
var _beat := "idle"
var _marks: Dictionary = {}
var _notes: Array = []
var _held: Array = []


func _init(dev: Node) -> void:
	_dev = dev


# --- public surface -------------------------------------------------------------------

func is_running() -> bool:
	return _running


func state() -> Dictionary:
	return {
		"running": _running,
		"clip": _clip,
		"beat": _beat,
		"marks": _marks.duplicate(),
		"notes": _notes.duplicate(),
		"frames_drawn": Engine.get_frames_drawn(),
	}


func clips() -> Array:
	return ["turrets"]


## Starts a clip. Returns immediately — the performance continues as a coroutine, and the
## caller polls `state()` or simply waits out the clip's own running time.
func start(clip_name: String) -> Dictionary:
	if _running:
		return {"success": false, "message": "clip '%s' is already running" % _clip, "data": state()}
	if clip_name not in clips():
		return {"success": false, "message": "unknown clip '%s'" % clip_name, "data": {"clips": clips()}}

	_clip = clip_name
	_beat = "starting"
	_marks = {}
	_notes = []
	_running = true

	_run_turret_clip()
	return {"success": true, "message": "clip '%s' started" % clip_name, "data": state()}


# --- the turret clip ------------------------------------------------------------------

func _run_turret_clip() -> void:
	var handler := _handler()
	var player := _player()
	if handler == null or player == null:
		_fail("no TileMapHandler or player in the scene")
		return

	var centre = _stage(handler, player)
	if centre == null:
		_fail("found no all-land %sx%s battle rect within %s tiles of the player" % [
			BATTLE_HALF.x * 2 + 1, BATTLE_HALF.y * 2 + 1, ARENA_SEARCH,
		])
		return

	# Everything above this line is setup and is expected to be trimmed off the front of
	# the recording; everything below it is the clip.
	await _wait(BEAT["settle"])
	_mark("show_start")

	await _beat_place_turret(handler, player, centre)
	await _beat_net_capture(handler, player, centre)
	await _beat_load_turret(player)
	await _beat_wave(handler, player, centre)

	_mark("show_end")
	await _wait(BEAT["tail"])

	_release_all()
	_beat = "done"
	_running = false


## Beat A — the player places a bone turret with the hotbar, exactly as a key press would.
func _beat_place_turret(handler: TileMapHandler, player: Player, centre: Vector2i) -> void:
	_beat = "place_turret"
	_mark("place_turret")

	# Face left, and place to the left. The turret only ever goes into the cell the player
	# faces, so putting it behind him is what leaves the ground to his right clear for the
	# skeleton to be met on — and gives beat C a walk back to it rather than a standing use.
	await _hold("move_left", 0.2)
	await _wait(BEAT["before_place"])

	if not _select(Types.Item.BoneTurret):
		_note("no bone turret in the hotbar to place")
		return
	await _wait(BEAT["after_select"])

	var front := _front_cell(handler, player)
	await _use()
	await _frames(2)

	if handler.tileMap.get_cell_source_id(1, front) == -1:
		_note("the placement press left cell %s empty" % front)
	await _wait(BEAT["after_place"])


## Beat B — the player walks out to a bone skeleton and takes it with the net.
func _beat_net_capture(handler: TileMapHandler, player: Player, centre: Vector2i) -> void:
	_beat = "net_capture"
	_mark("net_capture")

	# Four tiles out: far enough to be a walk worth watching, close enough that the last
	# stretch of it is inside AGGRO_RANGE, so the skeleton turns and comes at the player
	# instead of being ambushed standing still.
	var enemy := _spawn_enemy(handler, centre + Vector2i(4, 0))
	if enemy == null:
		_note("could not spawn the enemy for the net beat")
		return

	if not _select(Types.Item.Net):
		_note("no net in the hotbar")
		return

	# Closing on the enemy rather than swinging on a timer: it wanders while idle and
	# charges once it notices, so where it is at any given second is not knowable from here.
	_press("move_right")
	var closed := await _until(func() -> bool:
		return not is_instance_valid(enemy) \
			or player.global_position.distance_to(enemy.global_position) < NET_REACH, 8.0)
	_release("move_right")

	if not closed or not is_instance_valid(enemy):
		_note("never got within net reach of the skeleton")
		return

	await _wait(BEAT["before_swing"])

	# Two swings at most. The first is the shot; the second only exists because the net's
	# Area2D is narrow and a skeleton that stepped aside on the swing frame would otherwise
	# end the clip with an empty hand and nothing to load.
	var caught := false
	for _attempt in 3:
		await _use()
		await _wait(SWING_SETTLE)
		caught = _has(player, Types.Item.BoneEnemy)
		if caught:
			break

	if not caught:
		_note("the net beat finished without a skull in the inventory")
		if is_instance_valid(enemy):
			enemy.queue_free()

	await _wait(BEAT["after_capture"])


## Beat C — the player carries the skull back to the turret, which lights up as loaded.
func _beat_load_turret(player: Player) -> void:
	_beat = "load_turret"
	_mark("load_turret")

	if not _select(Types.Item.BoneEnemy):
		_note("no skull in the hotbar to load")
		return

	# `GameItemBoneEnemy.use()` reads the player's overlapping areas, so the walk back is
	# not decoration — outside the turret's LineOfSight the press finds nothing and the
	# stack is (correctly) not spent, which on film is a player fumbling at nothing.
	var turret = _nearest_turret(player)
	if turret != null:
		_press("move_left")
		var arrived := await _until(func() -> bool:
			return player.global_position.distance_to(turret.global_position) < 20.0, 6.0)
		_release("move_left")
		if not arrived:
			_note("did not reach the turret to load it")

	await _wait(BEAT["after_select"])

	await _use()
	await _frames(4)

	if _loaded_turrets() == 0:
		_note("the load press did not light a turret")
	await _wait(BEAT["after_load"])


## Beat D — a ring of loaded turrets takes two waves of skeletons apart around the player.
func _beat_wave(handler: TileMapHandler, player: Player, _centre: Vector2i) -> void:
	_beat = "wave"
	_mark("wave")

	# Anchored on where beat C actually left the player, not on the arena centre: the
	# camera is a child of the player, so the ring has to be built around him or the shot
	# is of the ground beside the fight.
	var here: Vector2i = handler.tileMap.local_to_map(player.global_position)

	# The placement beat has already been shown once; four more identical presses would be
	# four seconds of the same shot. These are written straight onto the tilemap and lit,
	# which is the same end state the hotbar press reaches.
	for offset in TURRET_RING:
		_place_turret(handler, here + offset)
	await _frames(2)
	for turret in _turrets():
		turret.set_loaded()

	# Two waves rather than one: a single volley is over in about four seconds, which is
	# less footage than the beat needs and reads as a skirmish rather than as a defence.
	await _telegraph_wave(handler, _offset_cells(here, WAVE_ONE))
	await _wait(BEAT["between_waves"])
	await _telegraph_wave(handler, _offset_cells(here, WAVE_TWO))
	await _wait(BEAT["wave_hold"])


# --- staging --------------------------------------------------------------------------

## Puts the world into the state the clip opens on, and returns the arena centre.
##
## Returns null when the search never found a rectangle of solid land, which is a real
## outcome: `land_cells_for_radius` thresholds noise, so a maxed home island is routinely a
## lopsided crescent with no clear 15x9 patch anywhere near the spawn.
func _stage(handler: TileMapHandler, player: Player):
	_beat = "staging"

	var centre = _find_arena(handler, player)
	if centre == null:
		return null

	_freeze_ambient()
	_clear_enemies()
	_clear_arena(handler, centre)

	player.position = handler.tileMap.map_to_local(centre)
	player.velocity = Vector2.ZERO

	# The clip must not end on a respawn: the wave walks straight into the player, and a
	# death would teleport him out of frame and take the camera with him. This is a
	# recording-only lie and the only one in the file.
	player.invulnerable = true

	_set_zoom(player, CLOSE_ZOOM)
	_hide_fps()

	_stock(player)
	return centre


## The arena centre: the cell nearest the player whose BATTLE_HALF rectangle is entirely
## land. Ties break toward the player, so the camera moves as little as possible from
## wherever the world actually put him.
## Ranked on three keys in order: land under the battle rect, then land across the visible
## frame, then nearness to where the world put the player.
##
## The middle key is the one worth keeping. With only the first, every centre whose 9x7 was
## solid ground scored identically and the nearest won — which on the first take was a spot
## one tile inland, and the finished clip had the coastline running diagonally through it
## with a third of the frame open sea. The fight was on land the whole time; the shot was
## still wrong, and no assertion about the fight could have said so.
func _find_arena(handler: TileMapHandler, player: Player):
	var origin: Vector2i = handler.tileMap.local_to_map(player.global_position)
	var best = null
	var best_key := [-1, -1, -(1 << 30)]

	for dy in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
		for dx in range(-ARENA_SEARCH, ARENA_SEARCH + 1):
			var candidate := origin + Vector2i(dx, dy)
			var key := [
				_land_score(handler, candidate, BATTLE_HALF),
				_land_score(handler, candidate, VIEW_HALF),
				-(dx * dx + dy * dy),
			]
			if key > best_key:
				best = candidate
				best_key = key

	var needed := (BATTLE_HALF.x * 2 + 1) * (BATTLE_HALF.y * 2 + 1)
	if best_key[0] < needed:
		_note("best battle rect at %s was %s/%s land" % [best, best_key[0], needed])
		# A cell or two of coast at a corner costs at most one lane; a third of the rect
		# missing means the fight would happen in the sea.
		if best_key[0] < needed - 3:
			return null
	return best


func _land_score(handler: TileMapHandler, centre: Vector2i, half: Vector2i) -> int:
	var land := 0
	for y in range(centre.y - half.y, centre.y + half.y + 1):
		for x in range(centre.x - half.x, centre.x + half.x + 1):
			if handler.tileMap.get_cell_source_id(0, Vector2i(x, y)) != -1:
				land += 1
	return land


## Clears the object and floor layers inside the arena, and the scene-tile resources that
## live as TileMap children rather than as cells — resources are two representations and
## code that walks only one leaves half the trees standing.
func _clear_arena(handler: TileMapHandler, centre: Vector2i) -> void:
	for y in range(centre.y - ARENA_HALF.y, centre.y + ARENA_HALF.y + 1):
		for x in range(centre.x - ARENA_HALF.x, centre.x + ARENA_HALF.x + 1):
			handler.tileMap.set_cell(1, Vector2i(x, y), -1)
			handler.tileMap.set_cell(2, Vector2i(x, y), -1)
			handler.tileMap.set_cell(3, Vector2i(x, y), -1)

	for child in handler.tileMap.get_children():
		if not (child is GameSceneResource):
			continue
		var cell: Vector2i = handler.tileMap.local_to_map(child.position)
		if absi(cell.x - centre.x) <= ARENA_HALF.x and absi(cell.y - centre.y) <= ARENA_HALF.y:
			child.queue_free()


func _stock(player: Player) -> void:
	# Emptied first so the beats can count on finding their item inside the six hotbar
	# slots. `pick_up_slot_data` fills the first free slot, and the starting kit is enough
	# to push the net out of reach of `select_slot`.
	var slots: Array = player.inventory_data.inventory_slot_datas
	for index in mini(6, slots.size()):
		slots[index] = null

	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.BoneTurret), 1))
	player.inventory_data.pick_up_slot_data(SlotData.new(GameItems.get_item(Types.Item.Net), 1))
	player.inventory_data.inv_updated()


## Stops the world advancing on its own for the length of the take: an ambient skeleton
## strolling into the net beat, or a tree regrowing inside the cleared arena, is a reshoot.
func _freeze_ambient() -> void:
	var spawner := _spawner()
	if spawner != null and spawner.timer != null:
		spawner.timer.paused = true

	var respawn := _dev.get_tree().root.get_node_or_null("Main/World/ResourceTimer")
	if respawn is Timer:
		respawn.paused = true


func _clear_enemies() -> void:
	var spawner := _spawner()
	if spawner == null:
		return
	for child in spawner.get_children():
		if child is Enemy:
			child.queue_free()


func _hide_fps() -> void:
	var player := _player()
	if player == null:
		return
	var fps := player.get_node_or_null("Camera2D/HUD/FpsLabel")
	if fps != null:
		fps.visible = false


## Camera zoom plus the HUD resize that has to follow it. The diegetic HUD sizes itself to
## `viewport_size / zoom` on `_ready` and on `size_changed` only, so a zoom written without
## this leaves a full-screen HUD laid out for the old view.
func _set_zoom(player: Player, zoom: Vector2) -> void:
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.zoom = zoom

	var hud := camera.get_node_or_null("HUD")
	if hud != null and hud.has_method("_resize_to_view"):
		hud._resize_to_view()


# --- world pokes ----------------------------------------------------------------------

func _place_turret(handler: TileMapHandler, cell: Vector2i) -> void:
	var item: GameItem = GameItems.get_item(Types.Item.BoneTurret)
	handler.set_tile(cell, item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)


## Spawns a bone skeleton on `cell`, or nowhere if that cell is open water.
##
## The land check is not defensive tidying. The starting island is roughly 20x13 tiles and
## the first take put half the wave into the sea, where the skeletons bobbed about
## unreachable by any turret — and nothing anywhere reports that, because ocean is the
## absence of a ground tile rather than a tile of its own.
func _spawn_enemy(handler: TileMapHandler, cell: Vector2i) -> Enemy:
	var spawner := _spawner()
	if spawner == null:
		return null
	if handler.tileMap.get_cell_source_id(0, cell) == -1:
		_note("skipped a spawn at %s: no ground there" % cell)
		return null

	var enemy := BONE_ENEMY.instantiate() as Enemy
	enemy.position = handler.tileMap.map_to_local(cell)
	spawner.add_child(enemy)
	return enemy


## Shows the spawner's `X` on each cell, then swaps it for a skeleton — the same two steps
## `EnemySpawner._timeout` takes, so the wave arrives the way the game announces a spawn
## instead of popping into the middle of the shot.
func _telegraph_wave(handler: TileMapHandler, cells: Array) -> void:
	var x: GameItem = GameItems.get_item(Types.Item.X)
	var live := []
	for cell in cells:
		if handler.tileMap.get_cell_source_id(0, cell) == -1:
			continue
		live.append(cell)
		handler.tileMap.set_cell(x.layer, cell, x.tile_source_id, x.atlas_location)

	await _wait(TELEGRAPH)

	for cell in live:
		handler.tileMap.set_cell(x.layer, cell, -1)
		_spawn_enemy(handler, cell)


func _offset_cells(origin: Vector2i, offsets: Array) -> Array:
	var cells := []
	for offset in offsets:
		cells.append(origin + offset)
	return cells


func _nearest_turret(player: Player):
	var closest = null
	var closest_distance := INF
	for turret in _turrets():
		var distance: float = player.global_position.distance_to(turret.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = turret
	return closest


func _turrets() -> Array:
	var found := []
	for node in _dev.get_tree().get_nodes_in_group("SaveChunks"):
		if node is BoneTurret:
			found.append(node)
	return found


func _loaded_turrets() -> int:
	var count := 0
	for turret in _turrets():
		if turret.loaded:
			count += 1
	return count


# --- input ----------------------------------------------------------------------------

## `Input.action_press` only moves the polled state, which is enough for movement (the
## InputManager polls it) and useless for the use press (the InputManager reads that one off
## the event). Both are driven, so both paths see the same input a key would produce.
func _press(action: String) -> void:
	Input.action_press(action)
	_dispatch(action, true)
	if action not in _held:
		_held.append(action)


func _release(action: String) -> void:
	Input.action_release(action)
	_dispatch(action, false)
	_held.erase(action)


func _dispatch(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _release_all() -> void:
	for action in _held.duplicate():
		_release(action)


func _hold(action: String, seconds: float) -> void:
	_press(action)
	await _wait(seconds)
	_release(action)


## One hotbar use press, held for `seconds` before release.
##
## The hold is load-bearing and cost a debugging session to find. Releasing `gather` runs
## `Player._gather_input_release`, which calls `animation_player.stop()` — so a two-frame
## tap killed the 0.2s net swing about fifteen milliseconds in, before the net had swept
## anywhere near the skeleton. Nothing reported it: `stop()` does not emit
## `animation_finished`, so `PlayerNet` never exited either, and the only trace was a
## second swing complaining that `body_entered` was already connected. A held key is also
## simply what a person does, which is why the game never had this problem.
func _use(seconds: float = 0.3) -> void:
	_press("gather")
	await _wait(seconds)
	_release("gather")


## Selects the hotbar slot holding `type`, moving the stack into the hotbar if the
## inventory put it out of reach. False when the player is not carrying one at all.
func _select(type: Types.Item) -> bool:
	# Plain `var`: _hot_bar() has an untyped return because the hotbar has no class_name,
	# and `:=` cannot infer from that.
	var hot_bar = _hot_bar()
	var player := _player()
	if hot_bar == null or player == null:
		return false

	var slots: Array = player.inventory_data.inventory_slot_datas
	var index := -1
	for i in slots.size():
		if slots[i] != null and slots[i].item != null and slots[i].item.type == type:
			index = i
			break
	if index == -1:
		return false

	if index >= 6:
		for i in 6:
			if slots[i] == null:
				slots[i] = slots[index]
				slots[index] = null
				index = i
				break
		player.inventory_data.inv_updated()
	if index >= 6:
		return false

	hot_bar.select_slot(index)
	return true


func _has(player: Player, type: Types.Item) -> bool:
	return player.inventory_data.count_of_type(type) > 0


# --- lookups and plumbing -------------------------------------------------------------

func _player() -> Player:
	for node in _dev.get_tree().get_nodes_in_group("Player"):
		if node is Player:
			return node
	return null


func _handler() -> TileMapHandler:
	for node in _dev.get_tree().get_nodes_in_group("TileMapHandler"):
		if node is TileMapHandler:
			return node
	return null


func _spawner() -> EnemySpawner:
	for node in _dev.get_tree().get_nodes_in_group("SaveLoad"):
		if node is EnemySpawner:
			return node
	return null


## Untyped: hot_bar_inventory.gd declares no `class_name`, and the player's own `@onready`
## reach into `UI/HotBarInventory` is the single place the path is written down.
func _hot_bar():
	var player := _player()
	return player.hot_bar_inventory if player != null else null


func _front_cell(handler: TileMapHandler, player: Player) -> Vector2i:
	var cell: Vector2i = handler.tileMap.local_to_map(player.global_position)
	return cell + (Vector2i(-1, 0) if player.is_facing_left() else Vector2i(1, 0))


func _wait(seconds: float) -> void:
	await _dev.get_tree().create_timer(seconds).timeout


func _frames(count: int) -> void:
	for _i in count:
		await _dev.get_tree().process_frame


## Polls `condition` once a frame until it holds or `timeout` game-seconds pass, and
## reports which. Timed off the frame clock rather than a wall clock because the whole
## point of the movie writer is that those two are not the same thing during a recording.
func _until(condition: Callable, timeout: float) -> bool:
	var waited := 0.0
	while waited < timeout:
		if condition.call():
			return true
		await _dev.get_tree().process_frame
		waited += _dev.get_process_delta_time()
	return condition.call()


## The output frame number this moment lands on. Under the movie writer `frames_drawn` is
## the frame index in the file, which is the whole reason the trim can be exact.
func _mark(label: String) -> void:
	_marks[label] = Engine.get_frames_drawn()


func _note(text: String) -> void:
	_notes.append(text)
	push_warning("DemoDirector: %s" % text)


func _fail(message: String) -> void:
	_note(message)
	_beat = "failed"
	_running = false
	_release_all()
