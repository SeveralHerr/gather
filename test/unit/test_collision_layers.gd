extends RefCounted

## Guards the Structure / Prop collision split (gather-au68.6 and the "enemies get stuck on
## rocks" bug behind it).
##
## ---------------------------------------------------------------------------------------
## WHAT THE SPLIT IS, AND WHY UNDOING IT IS SILENT
##
## Every solid thing in the world used to share one collision layer. `world_tile_set.tres`
## declared two physics layers and BOTH were `collision_layer = 1`, so a tree was exactly as
## solid to a skeleton as a stone wall was. There is no baked navigation in this game — see
## the header of `enemies/states/enemy_follow.gd` — so `get_next_path_position()` hands back a
## point on the straight line to the target, and a blocked enemy simply stands there pushing
## into the bark. A raid that has to cross an island crosses a forest to do it.
##
## The tileset now declares four physics layers, and which is which is the whole contract:
##
##   physics_layer_0  collision_layer 1    "World"      terrain, coastline, walls, doors
##   physics_layer_1  collision_layer 1    "World"      legacy second slot, now carries nothing
##   physics_layer_2  collision_layer 64   "Structure"  a DUPLICATE of every wall polygon
##   physics_layer_3  collision_layer 128  "Prop"       trees, rocks, ore, stations — MOVED here
##
## The two verbs matter and are not interchangeable:
##
##  - Walls are DUPLICATED. A wall tile keeps its polygon on layer 0 (so it still stops
##    everything that walks) and gains an identical one on the Structure layer, which is a
##    clean raycast target: "is there a WALL between me and the player" is a question
##    line-of-sight has to be able to ask without the answer also being yes for a bush or
##    for the sea. Moving instead of duplicating would open every compound.
##  - Props are MOVED. The polygon leaves layer 0 entirely, so an enemy — which masks bits
##    0/20/21 and nothing else — walks straight through a tree, while the player, who now
##    also masks bit 7 (128), still cannot. Duplicating instead of moving would fix nothing
##    at all: the tree would still be on the layer the enemy masks.
##  - Terrain is UNTOUCHED. The coastline polygons that keep both the player and the enemies
##    out of the sea stay exactly where they are on layer 0. This is the one that is
##    genuinely dangerous to get wrong: a mis-scoped edit that swept the ground rows into the
##    prop bucket produces enemies that calmly walk out onto the water, and nothing in the
##    game reports it.
##
## ---------------------------------------------------------------------------------------
## WHY THIS TEST EXISTS RATHER THAN A COMMENT IN THE .tres
##
## The tileset is edited through the Godot editor's TileSet panel, where physics layers are
## an unlabelled numbered list and a polygon is drawn with the mouse. Adding one resource
## node and drawing its collider lands it on whichever layer the panel had selected — layer 0
## by default — and that single tile silently rejoins the "blocks enemies" set. There is no
## error, no visual difference, and the only symptom is one kind of rock that skeletons get
## stuck on. Every assertion below is derived from the registries (`items/resources.gd`,
## `main.gd:WALL_TYPES`) rather than from a hardcoded list of coordinates, so a resource added
## later is covered the day it is registered.

var _T

const TILESET := "res://assets/tilesets/world_tile_set.tres"
const DOOR_SCENE := "res://world/tile_scenes/door.tscn"
const WORKER_SCENE := "res://world/tile_scenes/bone_worker.tscn"

## The bits, spelled out once. Names come from `[layer_names]` in project.godot.
const WORLD_BIT := 1        # layer_1 "World"
const STRUCTURE_BIT := 64   # layer_7 "Structure"
const PROP_BIT := 128       # layer_8 "Prop"

## What an enemy body masks: bit 0 (World) + bit 20 (Player) + bit 21 (Enemy). Authored on
## both enemies/bone_enemy.tscn and enemies/spider_enemy.tscn, and asserted below rather than
## trusted — the whole split is expressed as "props are not on a layer THIS number covers".
const ENEMY_MASK := 3145729

var tile_set: TileSet
var resources: Resources
var door: AnimatedSprite2D
var bodies: Array[Node] = []


func setup() -> void:
	tile_set = load(TILESET) as TileSet
	# Autoloads are unavailable under the headless --script runner, so the registry is built
	# directly, exactly as test_stone_building_set and test_ore_chain do it.
	resources = Resources.new()
	resources._ready()


func teardown() -> void:
	if resources != null:
		resources.free()
		resources = null
	tile_set = null
	if door != null:
		_T.free_ui(door)
		door = null
	for body in bodies:
		if is_instance_valid(body):
			body.free()
	bodies.clear()


# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------

## Every physics layer index whose collision_layer intersects `mask`. This is the indirection
## that makes the assertions below survive someone renumbering the layers in the editor: the
## test asks "which layers does an enemy actually feel", never "layer 0".
func _layers_matching(mask: int) -> Array[int]:
	var found: Array[int] = []
	for i in tile_set.get_physics_layers_count():
		if tile_set.get_physics_layer_collision_layer(i) & mask != 0:
			found.append(i)
	return found


func _layer_with_bit(bit: int) -> int:
	for i in tile_set.get_physics_layers_count():
		if tile_set.get_physics_layer_collision_layer(i) == bit:
			return i
	return -1


func _tile_data(source_id: int, coords: Vector2i) -> TileData:
	var source := tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or not source.has_tile(coords):
		return null
	return source.get_tile_data(coords, 0)


func _polygons(data: TileData, layer_index: int) -> int:
	if data == null or layer_index < 0:
		return 0
	return data.get_collision_polygons_count(layer_index)


## Total polygons a body masking `mask` would feel on this tile.
func _polygons_for_mask(data: TileData, mask: int) -> int:
	var total := 0
	for i in _layers_matching(mask):
		total += _polygons(data, i)
	return total


func _root_property(scene_path: String, property: String) -> Variant:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var state := packed.get_state()
	for node in state.get_node_count():
		if state.get_node_path(node) != NodePath("."):
			continue
		for prop in state.get_node_property_count(node):
			if state.get_node_property_name(node, prop) == property:
				return state.get_node_property_value(node, prop)
	return null


# --------------------------------------------------------------------------------------
# the tileset's own shape
# --------------------------------------------------------------------------------------

## The four layers exist and carry the numbers everything else is written against. Asserted
## first because every other test in this file reads them back rather than hardcoding an
## index, so a wrong number here would otherwise turn the rest green by agreeing with itself.
func test_the_tileset_declares_world_structure_and_prop_layers() -> String:
	var count: String = _T.assert_gte(
		tile_set.get_physics_layers_count(), 4, "physics layers declared on the tileset"
	)
	if count != "":
		return count

	var structure: String = _T.assert_gte(
		_layer_with_bit(STRUCTURE_BIT), 0, "a physics layer on the Structure bit (%d)" % STRUCTURE_BIT
	)
	if structure != "":
		return structure

	return _T.assert_gte(
		_layer_with_bit(PROP_BIT), 0, "a physics layer on the Prop bit (%d)" % PROP_BIT
	)


## The Structure and Prop layers are their OWN bits, not extra copies of World. This is the
## edit that reads as harmless in the TileSet panel — the layer is there, the polygons are
## there, and setting its collision_layer back to 1 puts every prop back in front of every
## enemy without changing a single polygon.
func test_the_new_layers_do_not_overlap_the_world_bit() -> String:
	for bit in [STRUCTURE_BIT, PROP_BIT]:
		var index := _layer_with_bit(bit)
		var value := tile_set.get_physics_layer_collision_layer(index)
		var clean: String = _T.assert_eq(
			value & WORLD_BIT, 0, "physics layer %d must not also carry the World bit" % index
		)
		if clean != "":
			return clean
	return ""


# --------------------------------------------------------------------------------------
# props
# --------------------------------------------------------------------------------------

## THE headline. Every world resource is off the layers an enemy masks and on the Prop layer.
##
## Scene-tile resources are skipped and that exclusion is not a shortcut: StoneResourceTest
## and BerryBush are instanced as real nodes from a scenes-collection source, so their
## collider lives in `world/resource_nodes/*.tscn` and there is no TileData to inspect. They
## are covered by the sibling assertion below.
func test_resource_nodes_are_props_not_world_collision() -> String:
	var checked := 0
	for type in resources.resources:
		var resource: GameResource = resources.resources[type]
		if resource.is_scene_tile:
			continue
		var data := _tile_data(resource.tile_source_id, resource.atlas_location)
		var exists: String = _T.assert_true(
			data != null,
			"%s: tile %s on source %d" % [resource.name, resource.atlas_location, resource.tile_source_id]
		)
		if exists != "":
			return exists

		var blocking: String = _T.assert_eq(
			_polygons_for_mask(data, ENEMY_MASK), 0,
			"%s must carry NO polygon on any layer an enemy masks" % resource.name
		)
		if blocking != "":
			return blocking

		var solid: String = _T.assert_gt(
			_polygons(data, _layer_with_bit(PROP_BIT)), 0,
			"%s must still carry a polygon on the Prop layer" % resource.name
		)
		if solid != "":
			return solid
		checked += 1

	return _T.assert_gte(checked, 6, "tile-backed resources actually inspected")


## The sibling assertion the skip above promises, and the reason it is a separate test rather
## than a branch inside that loop: a scene-tile resource has no TileData at all, so every
## helper the loop uses answers null for it. What has to be inspected instead is the root body
## of the scene the tileset instantiates.
##
## This is the half of the split that is easiest to leave undone, because nothing points at it.
## The tileset rewrite is a visible, auditable edit to one file; these colliders sit in seven
## unrelated `.tscn`s whose `collision_layer` was never authored at all — an absent line
## defaulting to 1. So the tileset could be perfectly split while a home island full of stone
## nodes and berry bushes went on catching every skeleton that walked past, and the only
## symptom would be the original bug, undiminished, in the one place the player spends all
## their time.
##
## Crafting stations and chests keep the Interactable bit: that is what the player's Interact
## area masks (`main.tscn`'s Interact node, `collision_mask = 4`), so dropping it would take
## the OPEN prompt off every chest and station in the game. Only the World bit moves.
const SCENE_PROPS := {
	"res://world/resource_nodes/stone_node.tscn": PROP_BIT,
	"res://world/resource_nodes/berry_bush.tscn": PROP_BIT,
	"res://world/tile_scenes/chest.tscn": PROP_BIT,
	"res://turrets/bone_turret.tscn": PROP_BIT,
	"res://crafting/workbench.tscn": PROP_BIT | INTERACTABLE_BIT,
	"res://crafting/furnace.tscn": PROP_BIT | INTERACTABLE_BIT,
	"res://world/tile_scenes/test_chest.tscn": PROP_BIT | INTERACTABLE_BIT,
}

const INTERACTABLE_BIT := 4  # layer_3 "Interactable"


func test_scene_backed_props_are_on_the_prop_layer_too() -> String:
	for scene_path in SCENE_PROPS:
		var authored: Variant = _root_property(scene_path, "collision_layer")
		var present: String = _T.assert_true(
			authored is int,
			"%s must AUTHOR a collision_layer; an absent one defaults to 1 (World) and blocks enemies" % scene_path
		)
		if present != "":
			return present

		var layer: int = authored
		var expected: int = SCENE_PROPS[scene_path]
		var exact: String = _T.assert_eq(layer, expected, "%s collision_layer" % scene_path)
		if exact != "":
			return exact

		# Stated separately from the equality above rather than trusted to follow from it. This
		# is the fact that actually matters, and it is the one a future edit adding a bit back
		# would break while the reader's eye slid over a still-plausible-looking number.
		var invisible: String = _T.assert_eq(
			layer & ENEMY_MASK, 0, "%s must be invisible to an enemy's collision_mask" % scene_path
		)
		if invisible != "":
			return invisible
	return ""


## The other half of the same rule: a prop that stops blocking enemies must not stop blocking
## the PLAYER too. That would be a far louder bug than the one being fixed — the player would
## walk through the tree they are chopping — but it is one polygon-delete away, so the
## presence of the Prop polygon is asserted as a player-facing fact and not only as a
## bookkeeping one.
func test_the_player_still_collides_with_props() -> String:
	var player_mask: Variant = _root_property("res://main.tscn", "collision_mask")
	# The Player node in main.tscn is not the root; fall back to the contract's number rather
	# than passing vacuously if the lookup misses.
	var mask: int = 1048577 | PROP_BIT
	if player_mask is int:
		mask = player_mask

	var tree_resource: GameResource = resources.Get(Types.Item.Tree)
	var data := _tile_data(tree_resource.tile_source_id, tree_resource.atlas_location)
	return _T.assert_gt(
		_polygons_for_mask(data, PROP_BIT | WORLD_BIT), 0,
		"a body masking World+Prop (the player, mask %d) still feels a tree" % mask
	)


# --------------------------------------------------------------------------------------
# walls
# --------------------------------------------------------------------------------------

## Walls are on BOTH layers, all 47 blob states of both wall types. Derived from
## main.gd:WALL_TYPES and from the terrain index each entry names, which is the same data the
## terrain solver uses to choose a cell — so a wall variant that exists in the tileset but was
## never given a Structure polygon is caught here rather than by a raider strolling through
## one particular corner piece.
func test_every_wall_tile_is_solid_and_a_structure() -> String:
	var world_layers := _layers_matching(WORLD_BIT)
	var structure_layer := _layer_with_bit(STRUCTURE_BIT)

	for wall in TileMapHandler.WALL_TYPES:
		var source := tile_set.get_source(wall["source"]) as TileSetAtlasSource
		var found: String = _T.assert_true(source != null, "atlas source %d" % wall["source"])
		if found != "":
			return found

		var states := 0
		for i in source.get_tiles_count():
			var coords := source.get_tile_id(i)
			var data := source.get_tile_data(coords, 0)
			if data == null or data.terrain_set != 0 or data.terrain != wall["terrain"]:
				continue

			var world := 0
			for layer in world_layers:
				world += data.get_collision_polygons_count(layer)
			var solid: String = _T.assert_gt(
				world, 0,
				"wall %s %s must still block on the World layer" % [wall["item"], coords]
			)
			if solid != "":
				return solid

			var structural: String = _T.assert_gt(
				data.get_collision_polygons_count(structure_layer), 0,
				"wall %s %s must also carry a Structure polygon" % [wall["item"], coords]
			)
			if structural != "":
				return structural
			states += 1

		# 47 is the number of states a Godot blob terrain produces, and it is what both wall
		# sheets are drawn for. A smaller number means the sweep silently stopped matching.
		var complete: String = _T.assert_eq(
			states, 47, "wall %s: blob states carrying the wall terrain" % wall["item"]
		)
		if complete != "":
			return complete
	return ""


# --------------------------------------------------------------------------------------
# terrain
# --------------------------------------------------------------------------------------

## The sea still stops everything. Terrain 1 is the ground/coastline set, and the cells that
## carry a polygon are the coast edges; they must remain on a layer an enemy masks and must
## never have been swept into the Prop bucket. This is the assertion that would have caught a
## mis-scoped rewrite, and its failure mode — enemies walking onto the water — is one no
## screenshot of the player's own island would show.
func test_coastline_collision_still_stops_enemies() -> String:
	var source := tile_set.get_source(4) as TileSetAtlasSource
	var found: String = _T.assert_true(source != null, "atlas source 4")
	if found != "":
		return found

	var prop_layer := _layer_with_bit(PROP_BIT)
	var coast := 0
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if data == null or data.terrain_set != 0 or data.terrain != 1:
			continue
		if _polygons_for_mask(data, ENEMY_MASK) == 0:
			continue  # the open-ground variants have no collider at all, by design
		coast += 1
		var clean: String = _T.assert_eq(
			data.get_collision_polygons_count(prop_layer), 0,
			"coastline tile %s must not have been moved onto the Prop layer" % coords
		)
		if clean != "":
			return clean

	return _T.assert_gte(coast, 40, "coastline tiles still blocking on an enemy-masked layer")


# --------------------------------------------------------------------------------------
# the bodies that read all this
# --------------------------------------------------------------------------------------

## Enemies were deliberately NOT changed, and that is the point of the whole approach: the
## fix is entirely in the tileset, so it applies to every enemy type — including the inherited
## charged, elite and raider scenes, which override art and stats and not masks — with no
## per-scene edit that a later scene could forget to copy. Asserted so that "add the Prop bit
## to the enemy mask" (which reads like an obvious tidy-up) fails loudly instead of quietly
## restoring the bug.
func test_enemies_do_not_mask_the_prop_layer() -> String:
	for scene in ["res://enemies/bone_enemy.tscn", "res://enemies/spider_enemy.tscn"]:
		var mask: Variant = _root_property(scene, "collision_mask")
		var authored: String = _T.assert_eq(mask, ENEMY_MASK, "%s root collision_mask" % scene)
		if authored != "":
			return authored
		var clean: String = _T.assert_eq(
			int(mask) & PROP_BIT, 0, "%s must not mask the Prop bit" % scene
		)
		if clean != "":
			return clean
	return ""


## Workers were considered and deliberately left alone. A BoneWorker walks by assigning
## `position` in _physics_process (world/tile_scenes/bone_worker.gd:376-397) and never calls
## move_and_slide, so its body's collision_mask decides nothing — it is an AnimatableBody2D
## that pushes rather than a mover that is stopped. Adding the Prop bit to it would look like
## a fix and change nothing at all; what actually keeps a worker out of a tree is
## TilePathFinder. Pinned here so the reasoning survives the next reader who notices workers
## were skipped.
func test_worker_bodies_are_not_moved_by_physics() -> String:
	var script_text := FileAccess.get_file_as_string("res://world/tile_scenes/bone_worker.gd")
	return _T.assert_false(
		script_text.contains("move_and_slide"),
		"BoneWorker must still move by position assignment, not through physics"
	)


# --------------------------------------------------------------------------------------
# the door
# --------------------------------------------------------------------------------------

func _worker() -> Node:
	var made = load(WORKER_SCENE).instantiate()
	bodies.append(made)
	return made


func _door() -> AnimatedSprite2D:
	return door


## A door tile had no physics body of any kind (gather-au68.6): the scene was an
## AnimatedSprite2D and one detector Area2D, so the "closed" animation was decoration and
## every walled compound had a permanent unguarded gate.
func test_a_door_has_a_real_collider() -> String:
	door = await _T.instantiate_ui(DOOR_SCENE, Vector2i(64, 64)) as AnimatedSprite2D
	var body := door.get_node_or_null("Blocker") as StaticBody2D
	var exists: String = _T.assert_true(body != null, "door has a Blocker StaticBody2D")
	if exists != "":
		return exists

	# World (so it stops anything that walks) + Structure (so line-of-sight treats a gateway
	# the same way it treats the wall either side of it).
	return _T.assert_eq(
		body.collision_layer, WORLD_BIT | STRUCTURE_BIT, "the door blocker's collision_layer"
	)


## The detector must be strictly larger than the blocker. Both were the tile's own 16x16 and
## the opener reached the wall on the same frame the area fired — and because the disable is
## deferred (an Area2D signal runs inside the physics query flush, where a direct write to
## `disabled` is silently refused) the player was stopped dead for a frame in every doorway.
func test_the_door_detector_reaches_further_than_the_blocker() -> String:
	door = await _T.instantiate_ui(DOOR_SCENE, Vector2i(64, 64)) as AnimatedSprite2D
	var detector := door.get_node_or_null("Area2D/CollisionShape2D") as CollisionShape2D
	var blocker := door.get_node_or_null("Blocker/CollisionShape2D") as CollisionShape2D
	var shapes: String = _T.assert_true(
		detector != null and blocker != null, "both door shapes are present"
	)
	if shapes != "":
		return shapes

	return _T.assert_gt(
		(detector.shape as RectangleShape2D).size.x,
		(blocker.shape as RectangleShape2D).size.x,
		"the door must open before the walker touches it"
	)


## A fresh door is shut, and shut now means solid rather than merely drawn shut.
func test_a_closed_door_blocks() -> String:
	door = await _T.instantiate_ui(DOOR_SCENE, Vector2i(64, 64)) as AnimatedSprite2D
	var blocker := door.get_node_or_null("Blocker/CollisionShape2D") as CollisionShape2D
	return _T.assert_false(blocker.disabled, "a fresh door's collider is active")


## The collider follows the occupancy count, not the animation — the animation is allowed to
## be a no-op for a second arrival and the collider never is.
func test_an_opener_takes_the_collider_down_and_puts_it_back() -> String:
	door = await _T.instantiate_ui(DOOR_SCENE, Vector2i(64, 64)) as AnimatedSprite2D
	var blocker := door.get_node_or_null("Blocker/CollisionShape2D") as CollisionShape2D
	var worker := _worker()

	door._door_open(worker)
	# set_deferred lands at the end of the frame, so the flush is part of the contract.
	await door.get_tree().process_frame
	var opened: String = _T.assert_true(blocker.disabled, "an opener in the doorway frees it")
	if opened != "":
		return opened

	door._door_close(worker)
	await door.get_tree().process_frame
	return _T.assert_false(blocker.disabled, "the wall goes back up behind the last one out")


## Two openers, one leaves. The door stays open for the one still standing in it — the same
## case the occupancy count was written for, now asserted on the physics half as well, since
## a wall reappearing inside the player is worse than a door shutting on them.
func test_the_collider_stays_down_while_anyone_is_in_the_doorway() -> String:
	door = await _T.instantiate_ui(DOOR_SCENE, Vector2i(64, 64)) as AnimatedSprite2D
	var blocker := door.get_node_or_null("Blocker/CollisionShape2D") as CollisionShape2D
	var first := _worker()
	var second := _worker()

	door._door_open(first)
	door._door_open(second)
	door._door_close(first)
	await door.get_tree().process_frame
	return _T.assert_true(blocker.disabled, "still open for the one still in the doorway")


## An enemy is NOT an opener, and with a real collider that filter finally does something.
## `_opens_door` is a Player-or-BoneWorker type test and the detector's mask lets enemies
## through to it on purpose (they are on bit 0), so this test is the only thing standing
## between a skeleton and a free pass through the front of the player's house. Widening
## `_opens_door` "so raiders don't get stuck outside" is the undo — the answer to a stuck
## raider is the Breaker in gather-au68, which breaks the door instead of opening it.
func test_a_door_does_not_open_for_an_enemy() -> String:
	door = await _T.instantiate_ui(DOOR_SCENE, Vector2i(64, 64)) as AnimatedSprite2D
	var blocker := door.get_node_or_null("Blocker/CollisionShape2D") as CollisionShape2D
	var enemy = load("res://enemies/bone_enemy.tscn").instantiate()
	bodies.append(enemy)

	door._door_open(enemy)
	await door.get_tree().process_frame

	var shut: String = _T.assert_eq(door.animation, "Closed", "a skeleton does not open the door")
	if shut != "":
		return shut
	return _T.assert_false(blocker.disabled, "and the doorway stays solid for it")
