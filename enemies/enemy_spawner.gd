extends Node2D
class_name EnemySpawner

## Continuous, Forager-style enemy spawning.
##
## There are no waves and no intensity ramp. Enemies trickle in forever at a
## steady (slightly jittered) cadence; the only thing that changes across a run
## is the population ceiling, which scales with how much land the player owns.
## Land is purchasable, so a flat MAX_LIVE_ENEMIES would either smother a starter
## island or leave a bought-out one empty.

var boneEnemy = preload("res://enemies/bone_enemy.tscn")
var spiderEnemy = preload("res://enemies/spider_enemy.tscn")

## The boss island's elite. An inherited scene rather than a bone enemy with its exports
## rewritten at spawn time, so a reload rebuilds it from the scene and every difference -
## health, damage, chase speed, size - comes back with it. Overriding at spawn time would
## mean persisting each of those separately and losing whichever one was forgotten.
var eliteEnemy = preload("res://enemies/elite_enemy.tscn")

@onready var player = $"../Player"
@onready var tilemap_handler: TileMapHandler = $"../.."
@onready var timer: Timer = $Timer

## Seconds between spawn attempts. The jitter is cosmetic — it only exists so the
## trickle does not read as a metronome — but it must stay well below the base or
## the cadence stops being predictable enough to balance against.
const SPAWN_INTERVAL := 7.0
const SPAWN_JITTER := 2.0
const MIN_INTERVAL := 0.5

## Live enemies allowed per plain-grass tile, and the bounds the density is
## clamped into. The floor keeps the opening island from being empty; the ceiling
## is the old MAX_LIVE_ENEMIES, and exists because enemies that are never killed
## otherwise accumulate until the frame rate collapses.
const ENEMIES_PER_LAND_TILE := 0.02
const MIN_ENEMY_CAP := 3
const MAX_ENEMY_CAP := 25

## Enemies never materialise in the player's lap. Tiles are 16px, so this is a
## six-tile exclusion radius around wherever the player is standing.
const MIN_SPAWN_DISTANCE := 96.0
const PLACEMENT_ATTEMPTS := 12

## The telegraph is longer than nothing but shorter than the interval; see
## pending_spawns below.
const TELEGRAPH_SECONDS := 2.0

## A spawn telegraphs for TELEGRAPH_SECONDS before the enemy exists as a node, and
## that window can overlap the next timeout — so in-flight spawns have to count
## against the cap too, or a burst slips past it.
var pending_spawns := 0

var enemies = [boneEnemy, spiderEnemy]


func _ready() -> void:
	add_to_group("SaveLoad")
	randomize()
	timer.timeout.connect(_timeout)
	timer.one_shot = false
	timer.start(next_interval())


# --- pure helpers (unit-tested; keep them free of node access) ----------------


## Population ceiling for an island of `land_tiles` grass tiles.
static func cap_for_land_tiles(land_tiles: int) -> int:
	return clampi(int(round(land_tiles * ENEMIES_PER_LAND_TILE)), MIN_ENEMY_CAP, MAX_ENEMY_CAP)


## `roll` is a 0..1 sample; the caller supplies randf() so this stays testable.
static func jittered_interval(roll: float) -> float:
	return maxf(MIN_INTERVAL, SPAWN_INTERVAL + (roll * 2.0 - 1.0) * SPAWN_JITTER)


static func is_too_close_to_player(spawn_pos: Vector2, player_pos: Vector2) -> bool:
	return spawn_pos.distance_to(player_pos) < MIN_SPAWN_DISTANCE


## One enemy's save payload. Deliberately carries no spawner-level state: `wave`
## and `wait_time` used to be written here (once per enemy!) and are gone.
## `target_is_null` / `attack_target_is_null` keep the original inverted sense so
## older saveFiles still read correctly.
static func enemy_save_entry(
	hp: int, target_is_null: bool, attack_target_is_null: bool, drop: int, pos: Vector2, type: String,
	max_hp: int = 10, damage: int = 3
) -> Dictionary:
	return {
		"hp": hp,
		"target": target_is_null,
		"attack_target": attack_target_is_null,
		"drop": drop,
		"x": pos.x,
		"y": pos.y,
		"type": type,
		# Carried explicitly because they are no longer constants. Without them a reload
		# rebuilds every enemy at the scene's defaults, which silently demotes anything
		# tougher back to a stock skeleton.
		"max_hp": max_hp,
		"damage": damage,
	}


## Which scene backs a saved enemy type. Reconstruction used to be
## `spiderEnemy if type == "Spider" else boneEnemy`, so every type that was not literally
## "Spider" came back a bone enemy - fine while those were the only two, and a silent
## downgrade for anything added later.
func scene_for_type(type: String) -> PackedScene:
	match type:
		"Spider":
			return spiderEnemy
		"Elite":
			return eliteEnemy
		_:
			return boneEnemy


## Fill in whatever a stored entry is missing. Saves written before this change
## carry extra `wave` / `wait_time` keys (ignored) and saves written after may be
## read by a future build that expects more, so every key goes through get().
static func normalize_enemy_entry(raw: Dictionary) -> Dictionary:
	return {
		"hp": int(raw.get("hp", 10)),
		"target": bool(raw.get("target", true)),
		"attack_target": bool(raw.get("attack_target", true)),
		"drop": int(raw.get("drop", 0)),
		"x": float(raw.get("x", 0.0)),
		"y": float(raw.get("y", 0.0)),
		"type": str(raw.get("type", "Bone")),
		"max_hp": int(raw.get("max_hp", 10)),
		"damage": int(raw.get("damage", 3)),
	}


# --- runtime -----------------------------------------------------------------


func next_interval() -> float:
	return jittered_interval(randf())


## Current spawn cadence, in seconds. Read by devtools.
func spawn_interval() -> float:
	return timer.wait_time if timer else SPAWN_INTERVAL


## Current population ceiling, scaled to the land enemies are actually allowed onto.
##
## Counting every grass tile on the map would let a region that opts out of ambient
## spawning still raise the ceiling - the boss arena would buy extra wandering enemies
## for the mainland while staying empty itself.
func enemy_cap() -> int:
	var land := 0
	if tilemap_handler:
		for region in tilemap_handler.regions:
			if region.ambient_enemies:
				land += tilemap_handler.count_land_tiles_in(region)
	return cap_for_land_tiles(land)


func count_live_enemies() -> int:
	var total = 0
	for child in get_children():
		if child is Enemy:
			total += 1
	return total


## A free land tile that is not in the player's lap, or null if none was found.
func _pick_spawn_tile():
	var player_pos = player.global_position if player else null

	for _attempt in PLACEMENT_ATTEMPTS:
		var tile = tilemap_handler.get_random_tile()
		if tile == null:
			return null

		# A region can refuse ambient enemies; the boss arena stays the boss's.
		if not tilemap_handler.region_for_cell(tile).ambient_enemies:
			continue

		if player_pos != null:
			var world_pos: Vector2 = tilemap_handler.tileMap.map_to_local(tile)
			if is_too_close_to_player(world_pos, player_pos):
				continue

		return tile

	return null


func _timeout() -> void:
	# Re-roll the cadence first: Timer decrements time_left before emitting, so a
	# wait_time assigned here would not take effect until the cycle after next.
	timer.start(next_interval())

	if count_live_enemies() + pending_spawns >= enemy_cap():
		return

	var tile = _pick_spawn_tile()
	if tile == null:
		return

	pending_spawns += 1

	var x = GameItems.get_item(Types.Item.X)
	tilemap_handler.tileMap.set_cell(x.layer, tile, x.tile_source_id, x.atlas_location)
	await get_tree().create_timer(TELEGRAPH_SECONDS).timeout
	tilemap_handler.tileMap.set_cell(1, tile, -1)

	var enemy_to_spawn = enemies[randi() % enemies.size()]
	var instance = enemy_to_spawn.instantiate()
	instance.position = tilemap_handler.tileMap.map_to_local(tile)
	add_child(instance)

	pending_spawns -= 1


func saveObject() -> Dictionary:
	var children = get_children()
	var enemies_to_save = {}

	for i in children.size():
		var child = children[i]
		if child is Enemy:
			enemies_to_save[i] = JSON.stringify(
				enemy_save_entry(
					child.health_manager.current_health,
					child.target == null,
					child.attack_target == null,
					child.drop,
					child.position,
					child.type,
					child.max_health,
					child.damage
				)
			)

	return {
		"filepath": get_path(),
		"enemies": enemies_to_save,
	}


func loadObject(loadedDict: Dictionary) -> void:
	for child in get_children():
		if child is Enemy:
			child.queue_free()

	var stored: Dictionary = loadedDict.get("enemies", {})

	for key in stored.keys():
		var json = JSON.new()
		if json.parse(str(stored[key])) != OK:
			continue

		var parsed = json.get_data()
		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		var node := normalize_enemy_entry(parsed)

		var scene := scene_for_type(node["type"])
		var instance = scene.instantiate()
		# Before add_child, because _ready is what turns max_health into a HealthManager.
		instance.max_health = node["max_hp"]
		instance.damage = node["damage"]
		instance.type = node["type"]
		add_child(instance)
		instance.position = Vector2(node["x"], node["y"])
		instance.health_manager.current_health = node["hp"]
		if node["target"] == false:
			instance.target = player
		if node["attack_target"] == false:
			instance.attack_target = player
		instance.drop = node["drop"]
