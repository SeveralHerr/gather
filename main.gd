extends Node
class_name TileMapHandler

signal resource_found(resource, location)  

@export var player: Player
@export var tileMap: TileMap
@export var items: Items
@export var specialTiles = []
@export var resource_manager: ResourceManager2
@export var resources: Resources
@export var sound_manager: SoundManager
@onready var input_manager = $Systems/InputManager
@onready var save_load: SaveLoad = $Systems/SaveLoad
@onready var destroy_manager = $Systems/DestroyManager
var chest = preload("res://world/tile_scenes/chest.tscn")

## Every autotiling wall. A placed wall is identified by its atlas SOURCE plus the
## rect its 47-tile blob occupies on that sheet - neither half is sufficient alone.
## The source alone is not, because the wood blob shares tiles.png with every other
## hand-drawn tile; the rect alone is not, because the generated stone sheet starts
## its blob at (0, 0) and those coordinates are already stone, plank and wood-floor
## on the hand-drawn sheet.
##
## `base` is the blob's top-left cell, which is what a whole run is reset to before
## set_cells_terrain_connect recomputes the joins, and it is also the coordinate the
## matching GameItem is registered under in items.gd. `terrain` is the index in
## terrain set 0, and it is per wall type on purpose: two terrains means a stone wall
## meeting a wood wall reads as two walls butting together rather than one blended run.
const WALL_TYPES := [
	{
		"item": Types.Item.WoodWall,
		"source": 4,
		"rect": Rect2i(0, 7, 12, 5),
		"terrain": 0,
		"base": Vector2i(0, 11),
	},
	{
		"item": Types.Item.StoneWall,
		"source": GameItem.STONE_BUILD_SOURCE_ID,
		"rect": Rect2i(0, 0, 12, 5),
		"terrain": 2,
		"base": Vector2i(0, 4),
	},
]

## Placed wall cells per wall type, keyed by Types.Item. Filled lazily by
## _wall_cells_for so a wall type that has never been built carries no entry.
var wall_cells := {}

var ground_tiles_min = Vector2(0,15)
var ground_tiles_max = Vector2(11,18)

var radius = 10
var noise_scale = 1
var noise_threshold = 0.0
var noise = FastNoiseLite.new() # Instance of OpenSimplexNoise
var tile_index = 0 # You should set this to the appropriate tile index

## Owns the island radius from the moment land becomes purchasable. Created in
## _ready() rather than placed in main.tscn.
var land_manager: LandManager

## Owns the pregenerated islands. Created in _ready() for the same reason, and after
## land_manager so that its save entry is written after this node's - main.gd's tile
## replay has to run before anything re-asserts land on top of it.
var island_manager: IslandManager

## Paints the day/night tint into the world, the sea and the HUD. Created in _ready() for
## the same reason as the two above, and additionally because it has to reach across three
## separate canvases — there is no one node in the tree that is a natural parent for it.
## Persists nothing: everything it draws is derived from Systems/WorldClock.
var sky_lighting: SkyLighting

## The rain sheet. Lives under `World` rather than beside the node above, so the day/night
## tint reaches it. Persists nothing either — whether it is raining is the clock's business.
var rain_vfx: RainVfx

var late_load = false

var disableSetTile = false
@export var save_data2 = {}

var crack = preload("res://assets/materials/crack_material.tres")
func _ready():
	randomize()
	add_to_group("SaveLoad")
	add_to_group("TileMapHandler")
	resource_manager.connect("resource_added", Callable(self, "_on_resource_added"))
	resource_manager.connect("resource_removed", Callable(self, "_on_resource_removed"))
	resource_manager.connect("resource_removing", Callable(self, "_on_resource_removing"))
	resource_manager.connect("resource_removing_stop", Callable(self, "_on_resource_removing_stop"))
	destroy_manager.connect("destroy_added", Callable(self, "_on_destroy_added"))
	destroy_manager.connect("destroy_removed", Callable(self, "_on_destroy_removed"))
	destroy_manager.connect("destroy_removing", Callable(self, "_on_destroy_removing"))
	destroy_manager.connect("destroy_removing_stop", Callable(self, "_on_destroy_removing_stop"))
	input_manager.connect("mouse_button_left", Callable(self, "_on_mouse_left"))
	noise.set_noise_type(FastNoiseLite.TYPE_PERLIN)
	_setup_ocean_backdrop()

	var tile_grid = tileMap.get_used_cells(0)
	
	for cell in tile_grid:
		tileMap.set_cell(0, cell, -1)
	#noise.set_frequency(0.5)	
	noise.set_seed(randi())
	var lands := land_cells_for_radius(radius)
	tileMap.set_cells_terrain_connect(0, lands, 0, 1)
	_sync_home_region()

	var spawn_cell = cell_nearest_to(lands, HOME_CENTRE)
	if spawn_cell != null:
		PlayerManager.player.position = tileMap.map_to_local(spawn_cell)
		PlayerManager.player.set_spawn_position(PlayerManager.player.position)

	_setup_land_purchase()
	_setup_islands()
	_setup_weather()
	_setup_debug_panel()
	_setup_hud_toolbar()


## The day/night tint and the rain. Created after the world exists, because the lighting
## captures the sea's base colour on first use and both of them read the player.
##
## The clock itself is NOT created here — it is a model, it is authored into main.tscn under
## Systems with the rest of them, and its save entry is keyed on that path. These two only
## draw what it says, and persist nothing.
func _setup_weather() -> void:
	var clock := get_node_or_null("Systems/WorldClock") as WorldClock
	if clock == null:
		push_warning("TileMapHandler: no Systems/WorldClock, so the world will not light itself")
		return

	sky_lighting = SkyLighting.new()
	sky_lighting.name = "SkyLighting"
	sky_lighting.clock = clock
	sky_lighting.main = self
	add_child(sky_lighting)

	# Into World, not here: the rain has to be inside the root canvas so the day/night
	# CanvasModulate tints it along with everything it is falling on. A screen-space rain
	# layer would keep its daylight brightness and glow against a dark world.
	var world := get_node_or_null("World")
	if world == null:
		push_warning("TileMapHandler: no World node, so it will never rain")
		return

	rain_vfx = RainVfx.new()
	rain_vfx.name = "RainVfx"
	rain_vfx.clock = clock
	world.add_child(rain_vfx)


## The BAG / SKILLS / LAND buttons. Built last on purpose: the strip hides itself
## while any panel is open, and it discovers those panels by walking UI for
## PanelFrames — so it has to be created after the land and debug panels put theirs
## in the tree.
func _setup_hud_toolbar() -> void:
	var ui_layer := get_node_or_null("UI")
	if ui_layer == null:
		push_warning("TileMapHandler: no UI CanvasLayer, the HUD toolbar has nowhere to live")
		return

	var toolbar := HudToolbar.new()
	toolbar.name = "HudToolbar"
	ui_layer.add_child(toolbar)


## The manual-testing panel, on F3. Built here rather than placed in main.tscn for the
## same reason as the land panel, and behind OS.is_debug_build() so it does not exist
## at all in an export - the panel can hand out items and land, so shipping it would
## hand the same buttons to a player.
func _setup_debug_panel() -> void:
	if not OS.is_debug_build():
		return

	var ui_layer := get_node_or_null("UI")
	if ui_layer == null:
		push_warning("TileMapHandler: no UI CanvasLayer, the debug panel has nowhere to live")
		return

	var panel := DebugPanelUi.new()
	panel.name = "DebugPanelUI"
	panel.input_manager = input_manager
	ui_layer.add_child(panel)


## The home island's centre, and the origin every radius in the game is measured from.
const HOME_CENTRE := Vector2i.ZERO


## The cell in `cells` closest to `centre`, or null if there are none.
##
## The player's start and respawn point used to be `lands[0]` — the first cell in
## x-then-y order, so whichever corner of the coastline the noise happened to leave
## standing. That was merely arbitrary while the home island was the only land in the
## world. With islands elsewhere on the map it is a bug: any island at negative x sorts
## ahead of home and takes the spawn with it.
static func cell_nearest_to(cells: Array, centre: Vector2i):
	var best = null
	var best_distance := INF
	for cell in cells:
		var distance := Vector2(cell - centre).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = cell
	return best


## Every offset within Chebyshev radius `radius` of a cell, excluding the cell itself.
## The devtools verbs pair it with cell_nearest_to to find the free cell NEAREST the
## player, instead of the first one a ring scan happens to visit — the old scan started
## at the ring's far corner and put stations 48px away (gather-7y9).
static func cells_within(radius: int) -> Array:
	var offsets := []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if dx != 0 or dy != 0:
				offsets.append(Vector2i(dx, dy))
	return offsets


## The sea the islands sit in. It used to be a painted layer-5 rectangle, which had two
## problems: it spanned only x -24..26, so anything further out sat on the bare clear
## colour, and its ~1600 cells were in `get_used_rect()` for `loadObject` to walk and for
## `saveObject` to write back as Water entries.
##
## A ColorRect on its own CanvasLayer is behind everything at any window size, extends
## as far as the camera ever goes, and persists nothing.
const OCEAN_COLOR := Color("0098dc")

func _setup_ocean_backdrop() -> void:
	var ocean := CanvasLayer.new()
	ocean.name = "Ocean"
	ocean.layer = -100
	add_child(ocean)

	var water := ColorRect.new()
	water.name = "Water"
	water.color = OCEAN_COLOR
	# ...and_offsets_, not set_anchors_preset alone: that leaves the offsets at zero and
	# the rect 0x0, so the sea is anchored perfectly to a viewport it does not cover.
	water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Without this the sea swallows every click before the world sees it.
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ocean.add_child(water)


## The land cells of an island of `island_radius`, straight out of the noise field.
## Deterministic for a given seed, so the same call at a larger radius returns a
## superset of the smaller one — which is what lets the island grow without the
## coastline the player already owns changing shape.
func land_cells_for_radius(island_radius: int) -> Array[Vector2i]:
	var lands: Array[Vector2i] = []
	for x in range(-island_radius, island_radius + 1):
		for y in range(-island_radius, island_radius + 1):
			if Vector2(x, y).length() > island_radius:
				continue
			if noise.get_noise_2d(x * noise_scale, y * noise_scale) < noise_threshold:
				lands.append(Vector2i(x, y))
	return lands


## Grows the island out to `new_radius` and returns how many land cells that
## revealed. Non-destructive, and the two things that make it so are worth
## spelling out:
##
##  - The noise instance and its seed are left alone. Reseeding would give the
##    already-owned half of the island a different shape, stranding buildings in
##    the sea.
##  - Only layer 0 is written. Resources, walls and buildings live on layers 1
##    and 2 and are never touched.
##
## The *whole* land set is handed to set_cells_terrain_connect, not just the new
## ring: the old coastline tiles need to be re-solved as interior now that there
## is land beyond them, and that only happens if they are in the set.
func expand_island(new_radius: int) -> int:
	if new_radius <= radius:
		return 0

	var before := land_cells_for_radius(radius).size()
	radius = new_radius

	var lands := land_cells_for_radius(radius)
	tileMap.set_cells_terrain_connect(0, lands, 0, 1)
	_sync_home_region()

	return lands.size() - before


## The seed the island's shape comes out of. randomize()d per session, so it has
## to be saved alongside the land purchases: re-expanding a loaded island against
## a fresh seed would grow a coastline that has nothing to do with the one the
## player bought.
func island_seed() -> int:
	return noise.seed


func set_island_seed(new_seed: int) -> void:
	noise.set_seed(new_seed)


## A bought parcel is stocked immediately rather than trickling in over the next ten
## minutes — the land is what was paid for, and empty grass does not read as a purchase.
func _on_land_purchased(_new_radius: int, _tiles_added: int) -> void:
	resource_manager.seed_island()

	# Buying land is the only thing that ever grows the coastline, so it is the only thing
	# that can put an island within walking distance — and an island is stocked when it opens.
	# Null on the first parcels of a session only in principle: _setup_land_purchase runs
	# before _setup_islands, so the signal is connected while island_manager is still absent.
	if island_manager != null:
		island_manager.refresh_connections()


## The land economy and its panel. Both are created here rather than placed in
## main.tscn so the scene file stays untouched; the panel goes in the UI
## CanvasLayer (screen space) and never under Player/Camera2D/HUD, which is world
## space at 0.23 scale for the diegetic HUD.
func _setup_land_purchase() -> void:
	land_manager = LandManager.new()
	land_manager.name = "LandManager"
	land_manager.tile_map_handler = self
	add_child(land_manager)

	# Stock the island the player is standing on, and every parcel they buy after it.
	# ResourceManager2's own _ready() runs before this one — children are readied
	# before their parent — so at that point there is no land to put anything on yet.
	resource_manager.seed_island()
	land_manager.land_purchased.connect(_on_land_purchased)

	var ui_layer := get_node_or_null("UI")
	if ui_layer == null:
		push_warning("TileMapHandler: no UI CanvasLayer, the land panel has nowhere to live")
		return

	var panel := LandPurchaseUi.new()
	panel.name = "LandPurchaseUI"
	panel.land_manager = land_manager
	panel.tile_map_handler = self
	panel.input_manager = input_manager
	ui_layer.add_child(panel)


## The forest, ore and boss islands. Drawn after the home island is stocked, because
## placement reads the home island's finished shape and because seeding home first is what
## keeps its own region's budget scaled to home alone.
func _setup_islands() -> void:
	island_manager = IslandManager.new()
	island_manager.name = "IslandManager"
	island_manager.tile_map_handler = self
	island_manager.resource_manager = resource_manager
	add_child(island_manager)

	island_manager.generate()
	# Draws them empty and opens nothing: a starting coastline of radius 8 is nowhere near
	# the nearest island at 20. It runs anyway rather than being skipped, because "open and
	# stock whatever is already reachable" is the same question after generation, after a
	# purchase and after a load, and one answer to it is easier to trust than three.
	island_manager.refresh_connections()

	# Screen space, so it goes in UI rather than under Player/Camera2D/HUD - that Control
	# is world space at 0.23 scale for the diegetic HUD.
	var ui_layer := get_node_or_null("UI")
	if ui_layer == null:
		return

	var compass := IslandCompass.new()
	compass.name = "IslandCompass"
	compass.tile_map_handler = self
	compass.island_manager = island_manager
	ui_layer.add_child(compass)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if late_load == true:
		late_load = false
		_finish_load()

	GetPlayerPosition()


## The second half of loading, once the engine has caught up with the replay.
##
## The frame of waiting is load-bearing. A scene tile - a chest, a crafting station, the
## scene-backed stone node - is instantiated by the engine a frame after its cell is
## written, so the chests the replay has just recreated do not exist yet. late_load()
## matches saved chunk payloads onto nodes by position, and a node that is not there yet
## simply never matches: it walks an empty SaveChunks group, finds nothing, reports
## nothing, and every chest in the world comes back empty. Restoring the boss island's
## reward chest is what finally made that visible.
func _finish_load() -> void:
	await get_tree().process_frame
	save_load.late_load()

	# After the replay rather than before, because the replay is what clears layer 1 across
	# the map - an island restocked any earlier would be stripped again a moment later.
	if island_manager != null:
		island_manager.reassert_after_load()


func add_highlight(location):
	tileMap.set_cell(3, tileMap.local_to_map(location), 4, Vector2i(7, 1))

	
func remove_highlight():
	var tiles = tileMap.get_used_cells(3)
	for tile in tiles:
		tileMap.set_cell(3, tile, -1)


## The cell the interact highlight currently occupies, or null when there is none.
##
## Layer 3 is shared by the gather selector and the chest/station interact highlight, and
## remove_highlight() above wipes the *whole* layer. player.gd used to call that pair every
## frame while any chest was in range, so the gather selector was overwritten within one
## frame of being drawn and was simply invisible near any chest or crafting station
## (gather-3zg.6). It also masked a stranded selector, which is why the stuck highlight only
## ever showed up early game — before the player had built anything to stand next to.
##
## Tracking the one cell this system owns lets it clean up after itself without touching
## anything else drawn on the layer.
var _interact_highlight_cell = null


## Moves the interact highlight to `location`, clearing only its own previous cell.
##
## Idempotent: player.gd calls this every frame from _process, and re-stamping the same cell
## would be a pointless tilemap write per frame per chest.
func set_interact_highlight(location) -> void:
	var cell: Vector2i = tileMap.local_to_map(location)
	if _interact_highlight_cell != null and _interact_highlight_cell == cell:
		return

	clear_interact_highlight()
	_interact_highlight_cell = cell
	tileMap.set_cell(3, cell, 4, Vector2i(7, 1))


func clear_interact_highlight() -> void:
	if _interact_highlight_cell == null:
		return

	tileMap.set_cell(3, _interact_highlight_cell, -1)
	_interact_highlight_cell = null

	
func _on_destroy_removing(location: Vector2i, _item: GameItem):
	# Add highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), 4, Vector2i(7, 1))
	
	#tileMap.set_tile(tileMap.local_to_map(location),item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)
	
func _on_destroy_added(location: Vector2i, item: GameItem):
	set_tile(location,item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)

func _on_destroy_removed(location: Vector2i, item: GameItem):
	tileMap.set_cell(item.layer,tileMap.local_to_map(location), -1)
	tileMap.set_cell(3, tileMap.local_to_map(location), -1)

	var wall := wall_type_at(item.atlas_location, item.tile_source_id)
	if wall.is_empty():
		return

	var cells: Array = _wall_cells_for(wall)
	var index = cells.find(tileMap.local_to_map(location))
	if index != -1:
		cells.remove_at(index)

	# Only the type that lost a cell needs re-solving; the other wall's run is on its
	# own terrain and cannot have changed shape.
	reconnect_walls(wall)


## The wall type a tile belongs to, or an empty Dictionary. Both halves of the match
## matter - see WALL_TYPES. Empty rather than null so callers can subscript the result
## without GDScript's analyser collapsing the return type to null.
func wall_type_at(atlas_location: Vector2i, source_id: int) -> Dictionary:
	for wall in WALL_TYPES:
		if wall["source"] == source_id and wall["rect"].has_point(atlas_location):
			return wall
	return {}


func _wall_cells_for(wall: Dictionary) -> Array:
	if not wall_cells.has(wall["item"]):
		wall_cells[wall["item"]] = []
	return wall_cells[wall["item"]]


## Resets one wall type's run to its blob's top-left cell and lets the terrain solver
## recompute every join. Both steps are needed: set_cells_terrain_connect only looks at
## which cells are in the run, so a cell still showing a previously-solved corner keeps
## drawing that corner if it is not flattened back to `base` first.
func reconnect_walls(wall: Dictionary) -> void:
	var cells: Array = _wall_cells_for(wall)
	for tile in cells:
		tileMap.set_cell(1, tile, wall["source"], wall["base"])
	tileMap.set_cells_terrain_connect(1, cells, 0, wall["terrain"], false)


func _on_destroy_removing_stop(location: Vector2i, _item: GameItem):
	# Remove highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), -1)
	#set_tile(location,item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)
	
	
func _on_mouse_left(isUiOpen: bool):
	disableSetTile = isUiOpen

func _on_resource_added(location: Vector2i, resource: GameResource):
	set_tile(location,resource.tile_source_id, resource.atlas_location, resource.layer, resource.is_scene_tile)

## Every ore node breaks with the same stone crack; only tree and the scene-based
## nodes sound different.
const STONE_SOUNDED_RESOURCES := [
	Types.Item.StoneResource,
	Types.Item.CoalResource,
	Types.Item.IronResource,
	Types.Item.CopperResource,
	Types.Item.GoldResource,
]

func _on_resource_removed(location: Vector2i, resource: GameResource):
	if resource.type in STONE_SOUNDED_RESOURCES:
		sound_manager.play_sound(SoundManager.SoundType.STONE)

	clear_tile(tileMap.local_to_map(location))

func _on_resource_removing(location: Vector2i, resource: GameResource):
	# Add highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), 4, Vector2i(7, 1))

	# The mid-gather frame lives on the same sheet as the node itself, so the source
	# id has to come from the resource. It used to be hardcoded to 4, which drew
	# whatever happened to sit at those coordinates on the hand-drawn sheet for any
	# resource registered against another source.
	if resource.gathering_atlas_location != Vector2i.ZERO:
		tileMap.set_cell(1, tileMap.local_to_map(location), resource.tile_source_id, resource.gathering_atlas_location)

func _on_resource_removing_stop(location: Vector2i, resource: GameResource):
	# Remove highlight
	var cell := tileMap.local_to_map(location)
	tileMap.set_cell(3, cell, -1)

	if resource.gathering_atlas_location != Vector2i.ZERO:
		# Only put the idle frame back if the cell is still showing the mid-gather one.
		# This used to write unconditionally, so a stop that arrived for a location whose
		# cell had already been cleared *recreated* the resource tile — a node that looked
		# alive with nothing behind it.
		if tileMap.get_cell_atlas_coords(1, cell) == resource.gathering_atlas_location:
			tileMap.set_cell(1, cell, resource.tile_source_id, resource.atlas_location)

func clear_tile(location: Vector2i):
	# Remove highlight
	tileMap.set_cell(3, location, -1)
	tileMap.set_cell(1, location, -1)
	
## Places `item`'s tile at `location`.
##
## atlas_location, NOT tile_atlas_location. The latter is the inventory ICON cell, which
## GameItem.get_atlas() prefers — and feeding it to a TileSetScenesCollectionSource writes a
## cell that instances nothing at all while set_cell() still reports success. A devtools verb
## that copied the old body produced a sawmill that never appeared (gather-w41).
## player_manager.place_tile:29 is the path the game itself uses, and it passes
## atlas_location; this now matches it.
func set_tile_item(location: Vector2i, item: GameItem):
	set_tile(location, item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)
	
func set_tile(location: Vector2i, tile_source_id: int, atlas_location: Vector2i, layer: int, is_scene: bool = false):
	if disableSetTile == true:
		return
	
	play_audio(location, tile_source_id, atlas_location, layer, is_scene)
	tileMap.set_cell(layer, location, tile_source_id, atlas_location, is_scene)

	var wall := wall_type_at(atlas_location, tile_source_id)
	if not wall.is_empty():
		var cells: Array = _wall_cells_for(wall)
		if not cells.has(location):
			cells.append(location)
		reconnect_walls(wall)

func is_wall_tile(atlas_location, source_id: int) -> bool:
	return not wall_type_at(atlas_location, source_id).is_empty()


## Things built out of stone land with the stone sound rather than the wood one, which
## is the only place the two building sets differ in behaviour rather than in art.
const STONE_SOUNDED_BUILDS := [Types.Item.StoneWall, Types.Item.StoneFloor]

func play_audio(_location: Vector2i, tile_source_id: int, atlas_location: Vector2i, _layer: int, _is_scene: bool = false):
	var item = items.get_item_by_data(atlas_location, tile_source_id)

	var wall := wall_type_at(atlas_location, tile_source_id)
	if not wall.is_empty():
		sound_manager.play_sound(
			sound_manager.SoundType.STONE if wall["item"] in STONE_SOUNDED_BUILDS
			else sound_manager.SoundType.WOOD_PLACE
		)
	elif item and item.type in STONE_SOUNDED_BUILDS:
		sound_manager.play_sound(sound_manager.SoundType.STONE)
	elif item and ( item.type == Types.Item.Chest or item.type == Types.Item.WoodDoor or item.type == Types.Item.Sawmill or item.type == Types.Item.WoodFloor):
			sound_manager.play_sound(sound_manager.SoundType.WOOD_PLACE)
	
## Whether a cell refuses a build. `include_resources` widens the check to the floor
## layer; `is_wall` narrows it to exactly one exemption — a wall may stand on a floor the
## player has already laid, and on nothing else.
##
## `is_wall` used to `return false` here, which made walls the one placeable with no rules
## at all: they went down on open water, straight over a tree or an ore vein, and on top of
## each other, spending the stack every time. Everything else routes through
## PlayerManager.place_tile and was refused correctly, so the bug was invisible unless you
## happened to have a wall selected (gather-llu). The ground check below is what keeps
## building on the island.
func is_occupied(tilePos: Vector2i, include_resources = false, is_wall: bool = false)-> bool:
	var occupied = false

	var tile = tileMap.get_cell_tile_data(1, tilePos)
	if tile != null:
		occupied = true

	# Floors are the one thing a wall is allowed to be built on top of.
	tile = tileMap.get_cell_tile_data(2, tilePos)
	if tile != null and include_resources == true and not is_wall:
		occupied = true

	# Check if trying to spawn on anything that is not grass
	if tileMap.get_cell_atlas_coords(0, tilePos) != GRASS_ATLAS:
		occupied = true
	
	
	var atlas_location = tileMap.get_cell_atlas_coords(1, tilePos)
	var source_id = tileMap.get_cell_source_id (1, tilePos)
	var item = resources.get_item_or_resource(atlas_location, source_id)
	
	if item != null and item.is_scene_tile:
		occupied = true
			

	return occupied
		
func RemoveResource(location):
	tileMap.set_cell(1, location, -1)

## Identity of a tile-based resource, as the pair that actually distinguishes one.
##
## An atlas coordinate ALONE does not. The hand-drawn sheet, the generated placeholder sheet
## and the generated stone sheet are separate sources whose coordinate spaces all start at
## (0, 0), so (0, 3) is a copper vein on source 10 and something else entirely on source 4.
## items/resources.gd carries a comment telling the next author to keep coordinates unique
## across every source precisely because these lookups ignored the source id — a rule no code
## enforces and the next ore tier on a new sheet would have broken (gather-54s).
static func resource_key(atlas_location: Vector2i, source_id: int) -> String:
	return "%d:%d,%d" % [source_id, atlas_location.x, atlas_location.y]


## The registered resource occupying layer-1 cell `cell`, or null.
##
## One place that answers "what resource is this cell", so the lookups that used to each
## open-code a coordinate comparison cannot drift apart again. Public because it is also the
## only honest way to ask whether an occupied cell is merely *grown over* - a tree that can
## be cleared - rather than something the player built there.
func resource_at(cell: Vector2i) -> GameResource:
	var atlas := tileMap.get_cell_atlas_coords(1, cell)
	var source := tileMap.get_cell_source_id(1, cell)
	if source == -1:
		return null

	for key in resources.GetAllTypes():
		var resource: GameResource = resources.Get(key)
		if resource.atlas_location == atlas and resource.tile_source_id == source:
			return resource
	return null


## Live gatherable nodes on the island broken down by resource name, covering both
## tile-based resources and the scene-based ones parented to the tilemap.
func resource_node_census() -> Dictionary:
	var atlas_to_name = {}
	for key in resources.GetAllTypes():
		var resource = resources.Get(key)
		if not resource.is_scene_tile:
			atlas_to_name[resource_key(resource.atlas_location, resource.tile_source_id)] = resource.name

	var census = {}
	for cell in tileMap.get_used_cells(1):
		var cell_key := resource_key(tileMap.get_cell_atlas_coords(1, cell), tileMap.get_cell_source_id(1, cell))
		if atlas_to_name.has(cell_key):
			var resource_name = atlas_to_name[cell_key]
			census[resource_name] = census.get(resource_name, 0) + 1

	for node in tileMap.get_children():
		if node is GameSceneResource:
			var resource = resources.get_item_or_resource_by_type(node.resource_type)
			var resource_name = resource.name if resource else "Unknown"
			census[resource_name] = census.get(resource_name, 0) + 1

	return census


## Plain grass. This exact tile is what "walkable, buildable land" means everywhere
## in the project — spawn placement, occupancy and the island size all key off it.
const GRASS_ATLAS := Vector2i(9, 17)


## Every plain-grass ground cell anywhere on the map, in tilemap coordinates.
func land_tiles() -> Array:
	var tiles := []
	for cell in tileMap.get_used_cells(0):
		if tileMap.get_cell_atlas_coords(0, cell) == GRASS_ATLAS:
			tiles.append(cell)
	return tiles


## How much land there is in total. Grows as parcels are bought and as islands are
## revealed. Prefer count_land_tiles_in() for anything that stocks the world - a ceiling
## scaled against this number lets one island's grass inflate every other island's budget.
func count_land_tiles() -> int:
	return land_tiles().size()


## Every cell the player can actually walk to from the spawn, as a lookup.
##
## Walkable means plain grass: every other terrain variant the solver produces is coastline
## and carries a collision polygon, so it is a wall in practice. That distinction is the
## whole reason this cannot be "is there land there" - an island and the mainland can be a
## single tile apart, look joined, and be separated by two coastlines.
##
## For the hypothetical - reachable once every parcel is bought, rather than reachable now -
## use walkable_cells_given_land(). This one reads the world as it stands.
func walkable_cells_from_home() -> Dictionary:
	var walkable := {}
	for cell in land_tiles():
		walkable[cell] = true

	# Untyped: cell_nearest_to returns null for an empty set, so it has no inferable type.
	var start = TileMapHandler.cell_nearest_to(walkable.keys(), HOME_CENTRE)
	if start == null:
		return {}

	var seen := {start: true}
	var frontier := [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if walkable.has(next) and not seen.has(next):
				seen[next] = true
				frontier.append(next)

	return seen


## The hypothetical: what the player could walk to if `extra` land also existed, on top of
## every land cell that exists now.
##
## `extra` is RAW land - the noise-thresholded cell set - and the whole point of this
## function is that raw land cannot simply be dropped into the walkable set. The terrain
## solver turns the outer ring of any land set into a coastline variant, and coastline
## carries a collision polygon, so a raw set is optimistic by one ring in every direction.
## Answering the max-land question that way promised connections the running game then
## refused, which is how a seed could strand the boss arena forever while every check said
## it was fine (gather-37z). IslandManager.walkable_body applies the solver's own rule -
## grass is a cell whose eight neighbours are all land - to the union before flooding it.
##
## Layer 0 rather than land_tiles(): this needs the coastline ring too, because a cell that
## is coastline today is plain grass the moment there is land beyond it.
func walkable_cells_given_land(extra: Dictionary) -> Dictionary:
	var land := {}
	for cell in tileMap.get_used_cells(0):
		land[cell] = true
	for cell in extra:
		land[cell] = true
	return IslandManager.walkable_body(land, HOME_CENTRE)


## The home island as a region, so that every stretch of land in the game is one and
## nothing has to special-case "the island the player started on". Its radius tracks the
## purchased radius; see _sync_home_region.
var home_region := LandRegion.new()

## Islands other than home, in the order IslandManager registered them.
var island_regions: Array[LandRegion] = []


## Every region, islands first - which is also the order region_for_cell resolves them in.
var regions: Array[LandRegion]:
	get:
		var all: Array[LandRegion] = island_regions.duplicate()
		all.append(home_region)
		return all


func _sync_home_region() -> void:
	home_region.id = "home"
	home_region.centre = HOME_CENTRE
	home_region.radius = radius


## Registering an id that is already present replaces it rather than being ignored: a
## reload re-derives an island's cells from its saved centre, and that fresh region is the
## authority over the one built at world generation.
func register_region(region: LandRegion) -> void:
	for i in island_regions.size():
		if island_regions[i].id == region.id:
			island_regions[i] = region
			return
	island_regions.append(region)


## Which region a cell belongs to. Islands win over home where they overlap, and anything
## outside every island falls to home - so this never returns null and callers never have
## to handle a homeless cell.
func region_for_cell(cell: Vector2i) -> LandRegion:
	for region in island_regions:
		if region.has_cell(cell):
			return region
	return home_region


## Every plain-grass cell belonging to one region.
func land_tiles_in(region: LandRegion) -> Array:
	if region == null:
		return land_tiles()
	var tiles := []
	for cell in tileMap.get_used_cells(0):
		if tileMap.get_cell_atlas_coords(0, cell) != GRASS_ATLAS:
			continue
		if region_for_cell(cell) == region:
			tiles.append(cell)
	return tiles


func count_land_tiles_in(region: LandRegion) -> int:
	return land_tiles_in(region).size()


## Live gatherable nodes in one region. resource_node_census() cannot answer this - it is
## name-to-count with no positions - so this walks the same two representations itself.
func count_resource_nodes_in(region: LandRegion) -> int:
	var resource_atlases := {}
	for key in resources.GetAllTypes():
		var resource = resources.Get(key)
		if not resource.is_scene_tile:
			resource_atlases[resource_key(resource.atlas_location, resource.tile_source_id)] = true

	var count := 0
	for cell in tileMap.get_used_cells(1):
		if not resource_atlases.has(resource_key(tileMap.get_cell_atlas_coords(1, cell), tileMap.get_cell_source_id(1, cell))):
			continue
		if region_for_cell(cell) == region:
			count += 1

	for node in tileMap.get_children():
		if node is GameSceneResource and region_for_cell(tileMap.local_to_map(node.position)) == region:
			count += 1

	return count


## Total live resource nodes. Used to cap spawning.
func count_resource_nodes() -> int:
	var census = resource_node_census()
	var total = 0
	for resource_name in census:
		total += census[resource_name]
	return total

func get_random_position_within_rect(rect):
	var random_x = randi() % rect.size.x + rect.position.x
	var random_y = randi() % rect.size.y + rect.position.y
	return Vector2(random_x, random_y)
	
func get_mouse_tile_position():
	var mouse_pos = get_viewport().get_mouse_position()
	var tile_pos = tileMap.local_to_map(mouse_pos)
	var tile_center_global = tileMap.map_to_local(tile_pos) - Vector2(8, 8)

	tile_center_global = tileMap.map_to_local(tile_pos)
	tile_center_global -= Vector2(16, 16) / 2
	tile_center_global = mouse_pos
	
	return tile_center_global
	
func get_tile_in_front_of_player():
		var tile_pos = tileMap.local_to_map(PlayerManager.player.get_global_position())
		if PlayerManager.player.is_facing_left():
			tile_pos += Vector2i(-1, 0)
			pass
		else:
			tile_pos += Vector2i(1, 0)
			pass
			
		#var tile_center_global = tileMap.map_to_local(tile_pos) - Vector2(8, 8)

		return tileMap.map_to_local(tile_pos) - Vector2(8, 8)
	
func _find_nearest_tile_and_resource(location: Vector2):
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP + Vector2i.LEFT, Vector2i.UP + Vector2i.RIGHT, Vector2i.DOWN + Vector2i.LEFT, Vector2i.DOWN + Vector2i.RIGHT, Vector2i.ZERO]
	var nearestDistance = 1000000
	var nearestPos = null

	for neighbor in neighbors:
		var tilePos = tileMap.local_to_map(location) + neighbor
		var tile = tileMap.get_cell_atlas_coords(1, tilePos)
		if tile == Vector2i(-1,-1):
			continue
		
		var dir = player.global_position - tileMap.map_to_local(tilePos)
		var dist = dir.length()
		if dist < nearestDistance:
			nearestDistance = dist
			nearestPos = tilePos
			
	if nearestPos == null:
		return
			
	var direction = location - tileMap.map_to_local(nearestPos)
	var distance = direction.length()
	var activation_distance = 20
	
	if distance < activation_distance and distance > 0:
		# Source id as well as coordinate — see resource_key() (gather-54s).
		return resource_at(nearestPos)

func find_nearest_resource_to_location(location: Vector2):
	var nearest_resource_info = get_location_of_nearby_resource(location)
	if nearest_resource_info:
		emit_signal("resource_found", nearest_resource_info.resource, nearest_resource_info.location)

func get_location_of_nearby_item_to_destroy(location):
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP + Vector2i.LEFT, Vector2i.UP + Vector2i.RIGHT, Vector2i.DOWN + Vector2i.LEFT, Vector2i.DOWN + Vector2i.RIGHT, Vector2i.ZERO]
	var nearestDistance = 1000000
	var nearestPos = null
	
	for neighbor in neighbors:
		var tilePos = tileMap.local_to_map(location) + neighbor
		var tile_atlas = tileMap.get_cell_atlas_coords(1, tilePos)
		
		if tile_atlas == Vector2i(-1,-1):
			continue

		var dir = player.global_position - tileMap.map_to_local(tilePos)
		var dist = dir.length()
		if dist < nearestDistance:
			nearestDistance = dist
			nearestPos = tilePos

	if nearestPos == null:
		return
	
	var direction = location - tileMap.map_to_local(nearestPos)
	var distance = direction.length()
	var activation_distance = 20
	
	if distance < activation_distance and distance > 0:
		var tile_atlas = tileMap.get_cell_atlas_coords(1, nearestPos)
		var tile_source_id = tileMap.get_cell_source_id(1, nearestPos)

		# A placed wall is showing whichever of its 47 cells the terrain solver chose,
		# and only the blob's top-left cell is registered as an item - so normalise
		# back to it before looking the item up.
		var wall := wall_type_at(tile_atlas, tile_source_id)
		if not wall.is_empty():
			tile_atlas = wall["base"]

		for key in items.get_all_types():
			if items.get_item(key).atlas_location == tile_atlas and items.get_item(key).tile_source_id == tile_source_id:
				return { "item": items.get_item(key),  "location": tileMap.map_to_local(nearestPos) }

			
func get_location_of_nearby_resource(location):
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP + Vector2i.LEFT, Vector2i.UP + Vector2i.RIGHT, Vector2i.DOWN + Vector2i.LEFT, Vector2i.DOWN + Vector2i.RIGHT, Vector2i.ZERO]
	var nearestDistance = 1000000
	var nearestPos = null
	
	for neighbor in neighbors:
		var tilePos = tileMap.local_to_map(location) + neighbor
		var tile = tileMap.get_cell_atlas_coords(1, tilePos)

		if tile == Vector2i(-1,-1):
			continue

		# Source id as well as coordinate — see resource_key(). Matching on the coordinate
		# alone made every lookup on the gather path depend on no two resources on different
		# sheets ever sharing one (gather-54s).
		if resource_at(tilePos) == null:
			continue

		var dir = player.global_position - tileMap.map_to_local(tilePos)
		var dist = dir.length()
		if dist < nearestDistance:
			nearestDistance = dist
			nearestPos = tilePos

	if nearestPos == null:
		return

	var direction = location - tileMap.map_to_local(nearestPos)
	var distance = direction.length()
	var activation_distance = 20

	if distance < activation_distance and distance > 0:
		var resource = resource_at(nearestPos)
		if resource != null:
			return { "resource": resource,  "location": tileMap.map_to_local(nearestPos), "tile_data": tileMap.get_cell_tile_data(resource.layer, nearestPos ) }

func get_nearest_scene_tile():
	var nearestDistance = 1000000
	var nearest = null
	var nodes = tileMap.get_children()
	for i in nodes.size():
		if nodes[i] is GameSceneResource:
					
			var dir = player.global_position - nodes[i].position
			var dist = dir.length()
			if dist < nearestDistance:
					nearestDistance = dist
					nearest = nodes[i]
					
	return nearest

func place_auto_tile( atlas_location):
	# Set the tile at the specified cell position.
	tileMap.set_cell(3, Vector2i(1, 1), 4, atlas_location) 
	tileMap.set_cell(3, Vector2i(1, 2), 4, atlas_location ) 
	tileMap.set_cell(3, Vector2i(0, 2), 4, atlas_location) 
	# Update the bitmasks to apply auto-tiling rules.
	#tileMap.bitma(cell_position - Vector2(1, 1), cell_position + Vector2(1, 1))
	tileMap.set_cells_terrain_connect(3, _wall_cells_for(WALL_TYPES[0]), 0, WALL_TYPES[0]["terrain"])


func get_random_tile():
	return get_random_tile_in(null)


## A free grass cell in one region, or anywhere if `region` is null. Retries because the
## pick is uniform over the region's land and most of that land is already occupied once
## the island is stocked.
func get_random_tile_in(region: LandRegion):
	var used_tiles = land_tiles_in(region)

	if not used_tiles:
		return

	var max_retries = 100
	var try = 1


	# Optionally, if you want to keep trying random positions until you find a non-empty tile
	while try < max_retries:
		var random_index = randi() % used_tiles.size()
		var random_tile = used_tiles[random_index]
		
		if is_occupied(Vector2i(random_tile.x, random_tile.y), true):
			try += 1
			continue
		
			
		try += 1
		return Vector2i(random_tile.x, random_tile.y)
	return null

func GetPlayerPosition():
	return tileMap.local_to_map(player.global_position)
	
func saveObject() -> Dictionary:
	var tile_layers = []
	var layers = tileMap.get_layers_count()
	var tile_grid = tileMap.get_used_cells(0)
	
	for layer in layers:
		for cell in tile_grid:
			var atlas_location = tileMap.get_cell_atlas_coords(layer, cell)
			var source_id = tileMap.get_cell_source_id (layer, cell)
			var item = resources.get_item_or_resource(atlas_location, source_id)
			var wall := wall_type_at(atlas_location, source_id)
			if not wall.is_empty():
				# Saved as the wall type itself, never as the solved cell: the joins are
				# recomputed from the run on load, so which of the 47 it happens to be
				# showing right now is not worth persisting.
				item = items.get_item(wall["item"])
			elif  atlas_location.x >= ground_tiles_min.x and atlas_location.y >= ground_tiles_min.y and atlas_location.x <= ground_tiles_max.x and atlas_location.y <= ground_tiles_max.y:
				item = items.get_item(Types.Item.Ground)
			
			# Water is a backdrop now, not tiles. Old saves still hold one entry per cell
			# of the rect it used to be painted over — 170 of the 340 entries in a
			# starting save — and writing them back would keep that debt alive forever.
			if item == null or item.type == Types.Item.Water:
				continue

			var json = {
				"type": item.type,
				"x": cell.x,
				"y": cell.y
			}

			# A plain dictionary, not JSON.stringify of one: SaveLoad stringifies the whole
			# payload anyway, so the inner layer only cost a JSON parser per tile on load —
			# thousands of them per save (gather-usv). SaveLoad.decode_entries reads both
			# shapes, so files written before this still load.
			tile_layers.append(json)
			
	var dict := {
		"filepath": get_path(),
		"tiles": tile_layers
	}
	
	return dict
			
## The saved tile entries that are structurally sound, as {"type": int, "x": int, "y": int}.
##
## Static and registry-free so it can be tested headless: the crash paths this guards are
## exactly the ones a full scene tree makes expensive to reach. Each saved entry is itself a
## JSON string inside the already-JSON payload (gather-usv tracks removing that layer), so a
## corrupt line is a real possibility rather than a theoretical one.
##
## An entry that cannot be parsed, is not a dictionary, or is missing any of type/x/y is
## dropped with a warning. Dropping one tile is the correct cost; the alternative — which is
## what this replaced — was raising mid-replay and losing the whole world.
static func parse_tile_payload(saved_tiles: Array) -> Array:
	var out: Array = []

	# decode_entries owns the shape question: entries written before gather-usv are JSON
	# strings, entries written after are dictionaries, and it drops anything unreadable with
	# a warning rather than raising. What is left here is the tile-specific check.
	for node in SaveLoad.decode_entries(saved_tiles):
		if not (node.has("type") and node.has("x") and node.has("y")):
			push_warning("TileMapHandler: skipping a malformed tile entry (%s)" % [node])
			continue

		# JSON has one number type, so every one of these parses back as a float.
		out.append({"type": int(node["type"]), "x": int(node["x"]), "y": int(node["y"])})

	return out


## Replays the saved tilemap.
##
## Parse first, destroy second (gather-5my). This used to clear layers 1-3 across every
## used cell before reading a single saved tile, then index straight into the payload:
## `loadedDict.tiles`, an unchecked `json.parse`, and `node["type"]` off what could be
## null. Any one of those raises, and a raise in a `-> void` aborts the method silently —
## indistinguishable from a clean return. The layers were already wiped by then, and
## `late_load = true` at the bottom was never reached, so `_finish_load()` never ran and
## every chest, station and turret payload waiting in `SaveLoad.loads` was dropped along
## with them. One malformed line cost the player every building they had ever placed.
##
## So: nothing touches the tilemap until the whole payload has been parsed into `parsed`,
## and every path reaches `late_load = true` — a partial replay must still let the chunk
## payloads and the island reassert run.
func loadObject(loadedDict: Dictionary) -> void:
	var ground_tiles: Array = []
	# Each entry is {"item": <registry entry>, "location": Vector2i}, already validated.
	var parsed: Array = []

	var saved_tiles: Variant = loadedDict.get("tiles", null)
	if saved_tiles is Array:
		for node in parse_tile_payload(saved_tiles):
			var item = resources.get_item_or_resource_by_type(node["type"])
			if item == null:
				continue

			# Saves written before the ocean became a backdrop carry one Water entry per
			# cell of the old painted rect, and Water is registered on layer 0 — replaying
			# them would drop blue tiles over the island itself.
			if item.type == Types.Item.Water:
				continue

			var location := Vector2i(node["x"], node["y"])
			if item.type == Types.Item.Ground:
				ground_tiles.append(location)

			parsed.append({"item": item, "location": location})
	else:
		# No usable tile list. Fall through rather than returning: the clear below is
		# skipped (so the generated world survives), but late_load still has to be set or
		# this becomes the silent-abort bug in a politer costume.
		push_warning("TileMapHandler: save entry carries no 'tiles' array, the tilemap was not replayed")

	# A payload that listed tiles but yielded none is a corrupt or truncated file, not an
	# empty world. Clearing on that reading would hand the player exactly the outcome this
	# rewrite exists to prevent — everything gone — just by a tidier route. An array that
	# was *legitimately* empty has size 0 and still falls through to the clear below,
	# because saving an empty world and then loading it has to empty the world.
	var corrupt: bool = saved_tiles is Array and not saved_tiles.is_empty() and parsed.is_empty()
	if corrupt:
		push_warning("TileMapHandler: %d tile entries and none were readable, keeping the current world rather than clearing it" % [saved_tiles.size()])

	# Everything above is read-only. From here on the world is being rewritten, and every
	# remaining step is total.
	if saved_tiles is Array and not corrupt:
		wall_cells.clear()
		var layers := tileMap.get_layers_count()
		var tile_grid := tileMap.get_used_cells(0)
		for layer in layers:
			if layer == 0:
				continue

			for cell in tile_grid:
				tileMap.set_cell(layer, cell, -1)

		# Layer 0 as well, and it used to be the one layer this skipped (gather-mcl).
		#
		# _ready() has ALREADY generated a whole world by the time a load runs - a home
		# island at a random noise seed, plus three islands at a random islands_seed - and
		# set_cells_terrain_connect below only ever *writes* the cells it is given. It
		# cannot remove one. So the ground the player ended up on was the union of two
		# unrelated worlds: loading test/fixtures/demo_homestead_save left the startup
		# world's islands sitting in the sea at x=11,y=18 and x=32,y=-3, 106 cells of land
		# from a game nobody played, and put the home region 202 grass tiles above what the
		# save recorded. Neither is cosmetic - resource_cap() and enemy_cap() both scale
		# against count_land_tiles_in(), so a loaded world quietly ran a larger budget than
		# the same world did before it was saved, and loading a second save in one session
		# stacked its leftovers on top again.
		#
		# Guarded on there being ground to put back, not merely on `parsed`. Every layer-0
		# cell is saved as Types.Item.Ground (see saveObject), so a payload with none is a
		# save this build cannot reconstruct a world from - and clearing on that reading
		# hands the player an empty sea, which is the failure the `corrupt` check above
		# exists to prevent, reached by a tidier route.
		if not ground_tiles.is_empty():
			for cell in tile_grid:
				tileMap.set_cell(0, cell, -1)
		else:
			push_warning("TileMapHandler: the save carries no ground tiles, keeping the generated terrain rather than clearing it")

		for entry in parsed:
			var item = entry["item"]
			set_tile(entry["location"], item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)

	# Solved once, on the finished set. This used to sit inside the loop, re-solving a
	# growing array on every saved tile — O(n²), and the reason land far from origin
	# was unaffordable rather than merely untested.
	tileMap.set_cells_terrain_connect(0, ground_tiles, 0, 1)
	late_load = true

