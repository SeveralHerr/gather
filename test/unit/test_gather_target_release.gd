extends RefCounted

## Guards the one invariant behind the stuck-selector bug (gather-3zg): whenever
## ResourceManager2 stops pointing at a gather target, it must hand that target back
## with a `resource_removing_stop`.
##
## main.gd answers `resource_removing` by writing TWO cells for the target — the layer-3
## selector and a layer-1 swap to the resource's `gathering_atlas_location` — and
## `resource_removing_stop` is the only thing that undoes either. So a retarget that
## forgets to emit does not merely lose track of a dictionary: it leaves both cells on
## the map with nothing holding a reference to them. The mid-gather cells are animated
## in the tileset (source 4, 4:3 is four frames for Tree, 3:5 is five for StoneResource)
## and Godot loops a tile animation for as long as the cell holds that atlas coord, so
## the orphan reads to the player as a resource that mines itself forever.
##
## start_removing_resource() used to overwrite removing_info outright, which is exactly
## that. These tests drive _release_target() rather than the full gather, because
## ResourceManager2's other entry points need a TileMapHandler, a Player, a Camera and a
## LevelUpManager — none of which exist under the headless runner — while the invariant
## itself needs none of them.

var _T

var manager: ResourceManager2
var stops: Array = []


func setup() -> void:
	# Deliberately no _ready(): it reaches for tile_map_handler.resource_found and would
	# null-dereference. Every field these tests touch is a plain var.
	manager = ResourceManager2.new()
	manager.resource_removing_stop.connect(_on_stop)
	stops = []


func teardown() -> void:
	if manager != null and is_instance_valid(manager):
		manager.free()
	manager = null
	stops = []


func _on_stop(location, resource) -> void:
	stops.append({"location": location, "resource": resource})


## A stand-in for the { "resource": …, "location": … } dictionary the real lookup builds.
## Only the two keys the stop signal carries are needed.
func _target(location: Vector2i) -> Dictionary:
	return {"resource": null, "location": location}


func test_releasing_a_live_target_emits_the_stop() -> String:
	manager.removing_info = _target(Vector2i(3, 2))

	manager._release_target()

	var err: String = _T.assert_eq(stops.size(), 1, "one stop is emitted for the live target")
	if err != "":
		return err
	# The location has to be the one main.gd wrote the cells for, or the clear lands on
	# the wrong tile and the orphan survives anyway.
	return _T.assert_eq(stops[0]["location"], Vector2i(3, 2), "the stop names the tile that was highlighted")


func test_releasing_clears_the_target_fields() -> String:
	manager.removing_info = _target(Vector2i(1, 1))

	manager._release_target()

	var err: String = _T.assert_true(manager.removing_info == null, "removing_info is forgotten")
	if err != "":
		return err
	# removing_node is only ever set by the scene-tile branch. A stale one sent the next
	# tile-based gather down the scene path in _on_hold_timer_timeout, breaking a Tree
	# with a distant stone's particles and a 0.3s await it should never have entered.
	return _T.assert_true(manager.removing_node == null, "removing_node is forgotten too")


func test_releasing_with_no_target_emits_nothing() -> String:
	manager._release_target()

	return _T.assert_eq(stops.size(), 0, "an idle manager emits no stop")


func test_releasing_twice_emits_only_once() -> String:
	manager.removing_info = _target(Vector2i(4, 4))

	manager._release_target()
	manager._release_target()

	# The second stop is not harmless: main.gd answers a stop by rewriting the resource's
	# idle atlas cell, with no check that the cell still holds that resource. Emitting it
	# again for an already-cleared location resurrects a node that was gathered away.
	return _T.assert_eq(stops.size(), 1, "the second release is a no-op")


func test_retargeting_hands_back_the_previous_tile() -> String:
	# The bug in one test. Two gathers in a row on different tiles: the first tile's cells
	# are only ever undone if the retarget releases it first.
	manager.removing_info = _target(Vector2i(7, 7))

	manager._release_target()
	manager.removing_info = _target(Vector2i(9, 9))

	var err: String = _T.assert_eq(stops.size(), 1, "retargeting released the first tile")
	if err != "":
		return err
	return _T.assert_eq(stops[0]["location"], Vector2i(7, 7), "it released the tile it had, not the new one")
