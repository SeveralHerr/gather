extends RefCounted

## Guards BoneWorker (world/tile_scenes/bone_worker.gd), the automated wood farmer.
##
## WHAT THIS FILE CAN AND CANNOT REACH. The worker's headline behaviour — scan for a tree,
## fell it, hand the wood to the nearest chest — needs a TileMapHandler with a live TileMap
## and the GameItems / PickUpManager autoloads, none of which exist under the headless
## `--script` runner. Faking them would test the fake. So what is asserted here is the part
## that is genuinely reachable and, not by coincidence, the part where a bug is silent:
##
##  * The assembly latch. `loaded` is written in exactly one place and set_loaded() is
##    idempotent, because GameItemBoneEnemy spends the skull stack itself and cannot see
##    whether the target was already full. A second write path would eat a captured skull
##    with no feedback at all.
##  * The save contract. Chunk entries are matched back onto nodes by position and replayed
##    through JSON, and this project's documented worst case is a load that fails in total
##    silence. The round trip and the malformed-payload cases are here for that.
##  * The idle read. A loaded worker with nothing in reach must not animate, which is the
##    only thing that tells a player the worker has run out of trees.
##  * The cadence promise. bone_worker.gd's comment claims CHOP_SECONDS is slower than the
##    slowest pickaxe tier, i.e. that hand-gathering still beats automation per second. That
##    is a balance claim spread over two files with no compile-time link, so it is asserted
##    as a relationship rather than as literals.
##  * Reach and scan span. The authored CircleShape2D is the source of truth for reach, and
##    the tile scan has to walk far enough to actually cover it.
##
## Left to the runtime pass, because nothing below can reach it: _find_tree_cell() against a
## real TileMap (both the plain-cell and the is_scene_tile branch), _fell()'s clear_tile +
## roll_yield payout and the deliberate absence of xp, _deliver()'s merge-then-free-slot
## chest ordering, _chests_in_reach()'s nearest-first sort, and the chop animation actually
## playing. See the report accompanying this file.

var _T

const WORKER_SCENE := "res://world/tile_scenes/bone_worker.tscn"
const WORKER_SOURCE := "res://world/tile_scenes/bone_worker.gd"

var worker: BoneWorker
var items: Items


func setup() -> void:
	# instantiate_ui() is not UI-specific: it puts the node into a real SubViewport and
	# pumps frames, which is what fires _ready() and therefore initialises every @onready
	# field. A bare instantiate() leaves unloaded_sprite / work_timer null.
	worker = await _T.instantiate_ui(WORKER_SCENE, Vector2i(64, 64)) as BoneWorker


func teardown() -> void:
	_T.free_ui(worker)
	worker = null
	if items != null and is_instance_valid(items):
		items.free()
	items = null


## Registries are built directly rather than through the autoload, the way
## test_stone_building_set and test_ore_chain do it — there are no autoloads under the
## headless runner.
func _items() -> Items:
	if items == null:
		items = Items.new()
		items._ready()
	return items


func _pickaxes() -> Array:
	var found := []
	for type in _items().item_list:
		var item = _items().item_list[type]
		if item is GameItemPickaxe:
			found.append(item)
	return found


# --- Assembly latch -------------------------------------------------------------------

## A freshly placed base is the unassembled unit: one sprite visible, and the one that is
## visible is the headless base.
func test_a_fresh_worker_reads_as_unassembled() -> String:
	var ready_fired: String = _T.assert_true(worker.unloaded_sprite != null, "@onready fields initialised")
	if ready_fired != "":
		return ready_fired

	var unloaded: String = _T.assert_false(worker.loaded, "a placed worker starts unloaded")
	if unloaded != "":
		return unloaded

	var base: String = _T.assert_true(worker.unloaded_sprite.visible, "UnloadedSprite visible")
	if base != "":
		return base

	return _T.assert_false(worker.loaded_sprite.visible, "LoadedSprite hidden while unloaded")


## Exactly one sprite at a time, in both states. Two visible sprites draw on top of each
## other and read as a rendering glitch rather than as a state bug.
func test_set_loaded_swaps_to_the_assembled_sprite() -> String:
	worker.set_loaded()

	var latched: String = _T.assert_true(worker.loaded, "set_loaded() latches loaded")
	if latched != "":
		return latched

	var base: String = _T.assert_false(worker.unloaded_sprite.visible, "UnloadedSprite hidden once loaded")
	if base != "":
		return base

	return _T.assert_true(worker.loaded_sprite.visible, "LoadedSprite visible once loaded")


## The idempotency GameItemBoneEnemy leans on. It removes the skull stack unconditionally
## after set_loaded() returns, so a second call that did anything at all — reset the sprites,
## restart the animation, re-fire work — would be a skull spent on a full machine.
func test_set_loaded_is_idempotent() -> String:
	worker.set_loaded()
	var was_working: bool = worker._working

	worker.set_loaded()

	var still: String = _T.assert_true(worker.loaded, "still loaded after a second skull")
	if still != "":
		return still

	var base: String = _T.assert_false(worker.unloaded_sprite.visible, "second load does not restore the base sprite")
	if base != "":
		return base

	var assembled: String = _T.assert_true(worker.loaded_sprite.visible, "second load leaves the assembled sprite up")
	if assembled != "":
		return assembled

	return _T.assert_eq(worker._working, was_working, "second load does not disturb the working flag")


## `loaded` may be written in exactly one place. Read off the source rather than the running
## object because the failure this guards is a *new* assignment somewhere else in the file —
## a state you cannot observe from outside once it has been written.
func test_loaded_is_written_only_inside_set_loaded() -> String:
	var source: String = FileAccess.get_file_as_string(WORKER_SOURCE)
	var readable: String = _T.assert_gt(source.length(), 0, "could read %s" % WORKER_SOURCE)
	if readable != "":
		return readable

	var lines: PackedStringArray = source.split("\n")
	var writes: Array = []
	for i in lines.size():
		var text: String = lines[i].strip_edges()
		if text.begins_with("#"):
			continue
		var rest: String = ""
		if text.begins_with("self.loaded"):
			rest = text.substr("self.loaded".length()).strip_edges()
		elif text.begins_with("loaded"):
			rest = text.substr("loaded".length()).strip_edges()
		else:
			continue
		# `==` is a comparison; `:=`/`=` is the write being counted. The declaration is
		# `var loaded`, which never reaches here.
		if rest.begins_with("=") and not rest.begins_with("=="):
			writes.append(i)

	var single: String = _T.assert_eq(writes.size(), 1, "exactly one assignment to `loaded` in bone_worker.gd")
	if single != "":
		return single

	# ...and it is inside set_loaded(), not some other method that happens to be the only one.
	var owner_func := ""
	for i in range(int(writes[0]), -1, -1):
		var text: String = lines[i].strip_edges()
		if text.begins_with("func "):
			owner_func = text
			break

	return _T.assert_true(
		owner_func.begins_with("func set_loaded"),
		"the write to `loaded` lives in set_loaded(), found it in `%s`" % owner_func
	)


## Placement is only half the persistence link; the SaveChunks group is the other half, and
## a worker missing from it is saved as nothing at all with no error anywhere.
func test_a_worker_joins_the_save_chunks_group() -> String:
	var chunk: String = _T.assert_true(worker.is_in_group("SaveChunks"), "worker is in SaveChunks")
	if chunk != "":
		return chunk

	# devtools_ext and GameItemBoneEnemy both find workers through this group.
	return _T.assert_true(worker.is_in_group("BoneWorker"), "worker is in the BoneWorker group")


# --- Idle / working read --------------------------------------------------------------

## `_working` tracks the target, not `loaded`. With no TileMapHandler in the tree there is
## nothing in reach, so a freshly assembled worker must settle to idle rather than animate
## a chop against empty grass.
func test_a_loaded_worker_with_nothing_in_reach_reads_as_idle() -> String:
	var empty: String = _T.assert_true(worker._find_tree_cell().is_empty(), "no tree in reach without a handler")
	if empty != "":
		return empty

	worker.set_loaded()

	var idle: String = _T.assert_false(worker._working, "assembled with nothing to chop is idle")
	if idle != "":
		return idle

	return _T.assert_false(worker.loaded_sprite.is_playing(), "the chop animation is not running")


## The work cycle is a no-op in both of the ways it can find nothing, and neither may fault:
## an unloaded worker bails on `loaded`, a loaded one bails on the empty scan.
func test_a_work_cycle_with_nothing_to_do_changes_nothing() -> String:
	worker._on_work_timeout()

	var unloaded: String = _T.assert_false(worker.loaded, "an unloaded worker's timeout does not assemble it")
	if unloaded != "":
		return unloaded

	var base: String = _T.assert_true(worker.unloaded_sprite.visible, "unloaded worker still shows the base")
	if base != "":
		return base

	worker.set_loaded()
	worker._on_work_timeout()

	var still_loaded: String = _T.assert_true(worker.loaded, "a barren work cycle does not unload the worker")
	if still_loaded != "":
		return still_loaded

	return _T.assert_false(worker._working, "a barren work cycle leaves the worker idle")


# --- Cadence --------------------------------------------------------------------------

## CHOP_SECONDS is the only number that sets the cadence. WorkTimer used to carry an
## authored wait_time of 3.0 plus autostart, which start() silently overrode — two numbers
## for one thing, and the one you would find first was the dead one.
func test_the_work_timer_runs_on_chop_seconds() -> String:
	var cadence: String = _T.assert_float_eq(
		worker.work_timer.wait_time, BoneWorker.CHOP_SECONDS, 0.0001, "WorkTimer wait_time"
	)
	if cadence != "":
		return cadence

	var running: String = _T.assert_false(worker.work_timer.is_stopped(), "WorkTimer is started by _ready()")
	if running != "":
		return running

	return _T.assert_true(
		worker.work_timer.timeout.is_connected(Callable(worker, "_on_work_timeout")),
		"WorkTimer drives _on_work_timeout"
	)


## The balance promise in bone_worker.gd's own comment: a player swinging the worst tool in
## the game still out-earns a worker per second spent. The worker rolls the same yield with a
## flat 0.0 bonus chance, so "slower than every tier" is the whole of it. Asserted against
## the registry rather than against 2.0, so retuning a pickaxe is what fails this.
func test_chop_is_slower_than_every_pickaxe_tier() -> String:
	var tiers: Array = _pickaxes()
	var found: String = _T.assert_gt(tiers.size(), 0, "pickaxe tiers are registered")
	if found != "":
		return found

	for pickaxe in tiers:
		var slower: String = _T.assert_gt(
			BoneWorker.CHOP_SECONDS, pickaxe.power,
			"CHOP_SECONDS (%.2f) must stay slower than %s (%.2f)" % [
				BoneWorker.CHOP_SECONDS, pickaxe.name, pickaxe.power,
			]
		)
		if slower != "":
			return slower

	# The worker also carries no bonus-yield chance of its own, which is the other half of
	# "hand-gathering wins": even the wooden tier ties it on speed-adjusted yield only if the
	# tier itself rolls nothing extra.
	return ""


## bone_worker.gd's comment names the wooden pickaxe as "the slowest tier in items.gd" and
## reasons from it. If a later tier becomes slower, that reasoning is stale even though the
## inequality above still holds — this is the test that says so.
func test_the_wooden_pickaxe_is_still_the_slowest_tier() -> String:
	var wooden: GameItem = _items().get_item(Types.Item.WoodPickaxe)
	var exists: String = _T.assert_true(wooden != null, "the wooden pickaxe is registered")
	if exists != "":
		return exists

	for pickaxe in _pickaxes():
		var slowest: String = _T.assert_gte(
			wooden.power, pickaxe.power,
			"wooden pickaxe (%.2f) is the slowest tier, but %s is %.2f" % [
				wooden.power, pickaxe.name, pickaxe.power,
			]
		)
		if slowest != "":
			return slowest
	return ""


# --- Reach and scan span --------------------------------------------------------------

## The authored CircleShape2D is the source of truth, so the collision shape and the search
## radius cannot drift. DEFAULT_REACH happens to equal the authored radius today, which is
## exactly why the fallback has to be shown to be a fallback: a _work_reach() that ignored
## the shape entirely would look correct on the shipped scene.
func test_reach_is_read_off_the_authored_work_area() -> String:
	var shape_node: CollisionShape2D = worker.work_area.get_node_or_null("CollisionShape2D")
	var authored: String = _T.assert_true(shape_node != null and shape_node.shape is CircleShape2D, "WorkArea has a CircleShape2D")
	if authored != "":
		return authored

	var radius: float = (shape_node.shape as CircleShape2D).radius
	var matches: String = _T.assert_float_eq(worker._reach, radius, 0.0001, "_reach came from the authored shape")
	if matches != "":
		return matches

	# duplicate() rather than mutating in place: the shape is a sub-resource of the
	# PackedScene and is shared with every other instantiation of it.
	var resized: CircleShape2D = (shape_node.shape as CircleShape2D).duplicate()
	resized.radius = radius + 33.0
	shape_node.shape = resized
	var followed: String = _T.assert_float_eq(
		worker._work_reach(), radius + 33.0, 0.0001, "reach follows the authored radius"
	)
	if followed != "":
		return followed

	shape_node.shape = null
	return _T.assert_float_eq(
		worker._work_reach(), BoneWorker.DEFAULT_REACH, 0.0001, "DEFAULT_REACH is the no-shape fallback"
	)


## The tile scan walks a square of cells and has to reach at least as far as _reach, or the
## worker refuses trees that are inside its own collision shape. Read off the tileset rather
## than assuming 16px, and floored at one so a degenerate tile size cannot scan nothing.
func test_the_tile_scan_span_covers_the_whole_reach() -> String:
	var tile_map := TileMap.new()
	var failure := ""

	# No tileset: the 16px assumption, which is what the world actually uses.
	var default_span: int = worker._cell_span(tile_map)
	failure = _T.assert_gte(float(default_span) * 16.0, worker._reach, "16px span covers _reach")

	if failure == "":
		var tile_set := TileSet.new()
		tile_set.tile_size = Vector2i(32, 32)
		tile_map.tile_set = tile_set
		var coarse: int = worker._cell_span(tile_map)
		failure = _T.assert_gte(float(coarse) * 32.0, worker._reach, "32px span covers _reach")

		if failure == "":
			# A tile larger than the whole reach still has to look at its own cell.
			tile_set.tile_size = Vector2i(512, 512)
			failure = _T.assert_gte(worker._cell_span(tile_map), 1, "span is floored at one cell")

	tile_map.free()
	return failure


# --- Save / load ----------------------------------------------------------------------

## save() is stringified into the save file and parsed back out, so the round trip through
## JSON is the real contract — not the Dictionary save() hands back in memory. late_load()
## matches chunks on x/y, so those two have to survive it as well as `loaded` does.
func test_save_round_trips_through_json() -> String:
	worker.position = Vector2(112.0, -48.0)
	worker.set_loaded()

	var text: String = JSON.stringify(worker.save())
	var parsed = JSON.parse_string(text)

	var is_dict: String = _T.assert_eq(typeof(parsed), TYPE_DICTIONARY, "save() survives JSON")
	if is_dict != "":
		return is_dict

	var x: String = _T.assert_float_eq(parsed["x"], 112.0, 0.0001, "x is what late_load() matches on")
	if x != "":
		return x

	var y: String = _T.assert_float_eq(parsed["y"], -48.0, 0.0001, "y is what late_load() matches on")
	if y != "":
		return y

	# BoneTurret and TestChest use the same "343" marker; main.gd's chunk loader needs no
	# special case for the worker precisely because this string matches theirs.
	var filepath: String = _T.assert_eq(parsed["filepath"], "343", "chunk filepath marker")
	if filepath != "":
		return filepath

	var payload: String = _T.assert_eq(typeof(parsed["data"]), TYPE_DICTIONARY, "data is a dictionary")
	if payload != "":
		return payload

	return _T.assert_eq(parsed["data"]["loaded"], true, "a loaded worker saves as loaded")


## The other half: an unassembled worker must save as unassembled. Writing `loaded` only
## when true would leave the key absent, which load() reads as false — same outcome today,
## but it would make the payload shape depend on the state.
func test_an_unloaded_worker_saves_as_unloaded() -> String:
	var parsed = JSON.parse_string(JSON.stringify(worker.save()))
	var present: String = _T.assert_true(parsed["data"].has("loaded"), "the loaded key is always written")
	if present != "":
		return present

	return _T.assert_eq(parsed["data"]["loaded"], false, "an unloaded worker saves as unloaded")


## A saved-then-loaded worker comes back assembled, sprites included. Restoring the flag
## without the sprite swap is the failure that looks like a rendering bug.
func test_load_restores_a_loaded_worker() -> String:
	var donor := worker
	donor.set_loaded()
	var payload = JSON.parse_string(JSON.stringify(donor.save()))

	var fresh: BoneWorker = await _T.instantiate_ui(WORKER_SCENE, Vector2i(64, 64)) as BoneWorker
	fresh.load(payload)

	var latched: String = _T.assert_true(fresh.loaded, "loaded worker restored as loaded")
	var sprite := ""
	if latched == "":
		sprite = _T.assert_true(fresh.loaded_sprite.visible, "restored worker shows the assembled sprite")

	_T.free_ui(fresh)
	if latched != "":
		return latched
	return sprite


## The inverse, and the one that a `set_loaded()` called unconditionally would break: an
## unassembled worker in the save must come back unassembled, not fully built for free.
func test_load_leaves_an_unloaded_worker_unloaded() -> String:
	var payload = JSON.parse_string(JSON.stringify(worker.save()))
	worker.load(payload)

	var unloaded: String = _T.assert_false(worker.loaded, "an unloaded payload does not assemble the worker")
	if unloaded != "":
		return unloaded

	return _T.assert_true(worker.unloaded_sprite.visible, "still showing the base sprite")


## A load path that faults takes the rest of the SaveChunks replay down with it and the
## symptom is an empty world, not an error. TestChest.load() would fault on every one of
## these; the worker's guard is what this pins.
##
## The non-bool `loaded` cases below were once unsurvivable and had to be left out of this
## list: load() read `data.get("loaded", false) == true`, and GDScript does not return false
## for a mismatched type — it raises `Invalid operands '<type>' and 'bool'` and aborts. They
## are included now because load() type-checks instead of comparing.
##
## Note what this test can and cannot do. It proves the current code survives these, but it
## could NOT have caught the original defect and cannot catch a regression of it: a fault
## inside load() aborts this method, and a `-> String` method that aborts still yields "",
## which the runner scores as a PASS (gather-1t9). The guard itself is pinned statically by
## test_load_type_checks_before_comparing; this test covers the behaviour, that one covers
## the shape, and neither alone is enough.
func test_load_survives_a_malformed_payload() -> String:
	var payloads: Array = [
		{},
		{"x": 0, "y": 0},
		{"data": null},
		{"data": "loaded"},
		{"data": []},
		{"data": {}},
		{"data": {"loaded": null}},
		{"data": {"loaded": false}},
		# The four that used to fault.
		{"data": {"loaded": "true"}},
		{"data": {"loaded": 0}},
		{"data": {"loaded": 1}},
		{"data": {"loaded": []}},
		# And the outer level, which JSON.parse can hand back as anything at all.
		"not a dictionary",
		[],
		null,
	]

	for payload in payloads:
		worker.load(payload)
		# Reaching the next line at all is half the assertion: a fault inside load() would
		# abort this method, and the runner pre-records that as a failure.
		var untouched: String = _T.assert_false(
			worker.loaded, "malformed payload %s must not assemble the worker" % [payload]
		)
		if untouched != "":
			return untouched

	return _T.assert_true(worker.unloaded_sprite.visible, "still unassembled after every malformed payload")


## The one regression test the runner is capable of running for this defect.
##
## load() must decide on `loaded` with a typeof check, never by comparing the value against
## a bool. `"true" == true` raises rather than evaluating false, which aborts the SaveChunks
## replay partway and drops the worker's state — the silent save-corruption failure CLAUDE.md
## calls out, and one that a player only ever sees as "my world came back wrong".
##
## Asserted against source text because the behavioural version cannot fail: reintroducing
## `== true` makes load() fault, the faulting test method returns "", and the suite goes
## green while the bug is live. A source scan runs no game code, so it is the only form of
## this assertion that can actually go red.
func test_load_type_checks_before_comparing() -> String:
	var source: String = FileAccess.get_file_as_string(WORKER_SOURCE)
	var readable: String = _T.assert_gt(source.length(), 0, "could read %s" % WORKER_SOURCE)
	if readable != "":
		return readable

	var body := ""
	var inside := false
	for raw in source.split("\n"):
		var text: String = raw
		if text.begins_with("func load("):
			inside = true
			continue
		# Any other top-level func ends the body. Nested blocks are indented, so this only
		# fires on a real sibling declaration.
		if inside and text.begins_with("func "):
			break
		if inside and not text.strip_edges().begins_with("#"):
			body += text + "\n"

	var found: String = _T.assert_true(inside, "found `func load(` in bone_worker.gd")
	if found != "":
		return found

	var guarded: String = _T.assert_true(
		body.contains("TYPE_BOOL"), "load() decides `loaded` with a typeof check"
	)
	if guarded != "":
		return guarded

	return _T.assert_false(
		body.contains("== true"), "load() never compares a save value against a bool literal"
	)


# --- Cross-file coordinates -----------------------------------------------------------

## The inventory icon and the placed unassembled base are the same cell of tiles.png, agreed
## on by convention across items.gd and bone_worker.tscn with nothing linking them. A wrong
## coordinate in either shows a different sprite in the hotbar than the thing you place, and
## nothing anywhere reports it.
func test_the_inventory_icon_is_the_unassembled_base_sprite() -> String:
	var item: GameItem = _items().get_item(Types.Item.BoneWorker)
	var registered: String = _T.assert_true(item != null, "BoneWorker is registered in items.gd")
	if registered != "":
		return registered

	var texture: AtlasTexture = worker.unloaded_sprite.texture as AtlasTexture
	var atlas: String = _T.assert_true(texture != null, "UnloadedSprite draws from an AtlasTexture")
	if atlas != "":
		return atlas

	var cell := Vector2i(int(texture.region.position.x) / 16, int(texture.region.position.y) / 16)
	return _T.assert_eq(cell, item.tile_atlas_location, "icon cell matches the UnloadedSprite cell")
