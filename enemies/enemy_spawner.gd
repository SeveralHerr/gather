extends Node2D
class_name EnemySpawner

## Continuous, Forager-style enemy spawning.
##
## There are no waves and no intensity ramp. Enemies trickle in forever at a
## steady (slightly jittered) cadence; the only thing that changes across a run
## is the population ceiling, which scales with how much land the player owns.
## Land is purchasable, so a flat MAX_LIVE_ENEMIES would either smother a starter
## island or leave a bought-out one empty.

## Which scenes back which types, which of them the trickle may roll, and what each drops,
## all live in EnemyRegistry now. This file used to hold three preloads, an `enemies` array
## and a `match` that had to be kept in step with them by hand (gather-33f).
##
## The elite is an inherited scene rather than a bone enemy with its exports rewritten at
## spawn time, so a reload rebuilds it from the scene and every difference - health, damage,
## chase speed, size - comes back with it. Overriding at spawn time would mean persisting
## each of those separately and losing whichever one was forgotten.

@onready var player = $"../Player"
@onready var tilemap_handler: TileMapHandler = $"../.."
@onready var timer: Timer = $Timer

## Seconds between spawn attempts. The jitter is cosmetic — it only exists so the
## trickle does not read as a metronome — but it must stay well below the base or
## the cadence stops being predictable enough to balance against.
##
## 7s filled the cap faster than the player could clear it, so the island read as a
## siege rather than a trickle; 21s lets a cleared area stay cleared for a while. The
## cap is unchanged — this changes how fast the population refills, not how big it gets.
const SPAWN_INTERVAL := 21.0
const SPAWN_JITTER := 5.0
const MIN_INTERVAL := 0.5

## How often a bolt that lands near the player also lands ON a skeleton (gather-8ft).
##
## Deliberately small. The charged skull is the best upgrade a worker or a turret can get and
## it costs nothing but being outside in a storm, so the price is rarity — a storm is roughly
## LIGHTNING_MIN_GAP..MAX apart per bolt, and at 8% a player stands in a long storm and sees
## maybe one. Raising this does not make the game more generous so much as it makes the blue
## skeleton ordinary, and the whole effect is that it is not.
const CHARGE_CHANCE := 0.08

## How close a bolt has to be to hit anything. WorldClock's `distance` is 0.0 overhead to 1.0
## at the horizon, so this keeps strikes to bolts that flashed brightly and cracked almost at
## once — the ones the player actually saw land. A skeleton charging on a distant rumble is
## an event with no visible cause, which reads as a bug rather than as luck.
const CHARGE_MAX_DISTANCE := 0.35

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

## What night does to the trickle (gather-bqn): more of them, arriving sooner.
##
## Night is the negative half of the day/night cycle — rain is the positive half, and a
## cycle where both halves are a bonus is just a light show. Both numbers are deliberately
## modest: the population ceiling is what actually governs how dangerous a place feels, and
## a 1.6x ceiling on an island the player has cleared is a noticeable but survivable change
## rather than a siege. The old 7s cadence was already found to read as a siege at the
## *day* cap, so this leans on the ceiling rather than on the cadence.
##
## Applied in the instance methods below, never inside the statics: `cap_for_land_tiles` and
## `jittered_interval` are pure and unit-tested as pure, and folding a clock read into them
## would make them untestable without a SceneTree and silently change what
## test_enemy_spawner.gd is asserting.
const NIGHT_CAP_MULT := 1.6
const NIGHT_INTERVAL_MULT := 0.7

## A spawn telegraphs for TELEGRAPH_SECONDS before the enemy exists as a node, and
## that window can overlap the next timeout — so in-flight spawns have to count
## against the cap too, or a burst slips past it.
var pending_spawns := 0


func _ready() -> void:
	add_to_group("SaveLoad")
	randomize()
	timer.timeout.connect(_timeout)
	timer.one_shot = false
	timer.start(next_interval())

	# Connected here rather than polled, because a bolt IS an event — unlike the tint, which
	# changes every frame of a twilight and is why SkyLighting polls instead. WorldClock
	# registers its group in _enter_tree precisely so a consumer can find it from _ready
	# regardless of tree order (see the long comment on WorldClock._enter_tree; the resource
	# respawn timer connecting from _ready is the bug that lesson came from).
	var clock := _clock()
	if clock != null and not clock.lightning_struck.is_connected(_on_lightning_struck):
		clock.lightning_struck.connect(_on_lightning_struck)


## A bolt landed. Rarely, and only if it was close, it landed on a skeleton.
##
## Spiders are deliberately excluded rather than merely unlikely: the reward is a SKULL, and a
## charged spider dropping one would be the kind of detail that reads as a copy-paste rather
## than as a rule. EnemyRegistry.BONE is the test, so the elite — which is a bone enemy
## underneath but is the boss island's guard — is excluded too.
func _on_lightning_struck(distance: float) -> void:
	if not should_charge(distance, randf()):
		return
	charge_random_skeleton()


## Charges one live, uncharged skeleton and returns it, or null if there were none.
##
## Public and returning the enemy so devtools can force the effect and say what it hit — a
## verb that charged something and reported only "ok" cannot tell "there were no skeletons"
## apart from "it worked", and those live in different files.
func charge_random_skeleton() -> Enemy:
	var candidates: Array[Enemy] = []
	for child in get_children():
		if child is Enemy and child.type == EnemyRegistry.BONE and not child.is_charged:
			candidates.append(child)

	if candidates.is_empty():
		return null

	var struck: Enemy = candidates[randi() % candidates.size()]
	struck.make_charged()
	return struck


# --- pure helpers (unit-tested; keep them free of node access) ----------------


## Population ceiling for an island of `land_tiles` grass tiles.
static func cap_for_land_tiles(land_tiles: int) -> int:
	return clampi(int(round(land_tiles * ENEMIES_PER_LAND_TILE)), MIN_ENEMY_CAP, MAX_ENEMY_CAP)


## `roll` is a 0..1 sample; the caller supplies randf() so this stays testable.
static func jittered_interval(roll: float) -> float:
	return maxf(MIN_INTERVAL, SPAWN_INTERVAL + (roll * 2.0 - 1.0) * SPAWN_JITTER)


static func is_too_close_to_player(spawn_pos: Vector2, player_pos: Vector2) -> bool:
	return spawn_pos.distance_to(player_pos) < MIN_SPAWN_DISTANCE


## Whether a bolt at `distance` charges a skeleton, given a 0..1 `roll`.
##
## Static and roll-injected like jittered_interval above, so the decision is testable without
## a storm, a skeleton or a SceneTree — the alternative is a test that fires bolts until one
## happens to connect, which is slow and flaky in exactly the proportion CHARGE_CHANCE is
## small.
static func should_charge(distance: float, roll: float) -> bool:
	return distance <= CHARGE_MAX_DISTANCE and roll < CHARGE_CHANCE


## One enemy's save payload. Deliberately carries no spawner-level state: `wave`
## and `wait_time` used to be written here (once per enemy!) and are gone.
## `target_is_null` / `attack_target_is_null` keep the original inverted sense so
## older saveFiles still read correctly.
static func enemy_save_entry(
	hp: int, target_is_null: bool, attack_target_is_null: bool, drop: int, pos: Vector2, type: String,
	max_hp: int = 10, damage: int = 3, charged: bool = false
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
		# Being lightning-struck is progress, not configuration: it happened to THIS skeleton
		# during THIS storm and nothing can re-derive it. A reload that dropped it would take
		# the skull with it and report nothing (gather-8ft).
		"charged": charged,
	}


## Which scene backs a saved enemy type.
##
## Reconstruction was once `spiderEnemy if type == "Spider" else boneEnemy`, so every type
## that was not literally "Spider" came back a bone enemy - fine while those were the only
## two, and a silent downgrade for anything added later. That became a `match` with the same
## silent default arm, and is now one registry lookup that WARNS before falling back
## (gather-33f). Kept as a method rather than inlined at the call sites because
## island_manager.gd calls it too.
func scene_for_type(type: String) -> PackedScene:
	return EnemyRegistry.scene_for(type)


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
		# typeof rather than `== true`: comparing a String to a bool RAISES in GDScript, and a
		# raise inside this static aborts the whole entry. Saves written before charged
		# skeletons existed have no key at all and must read as an ordinary one.
		"charged": typeof(raw.get("charged", false)) == TYPE_BOOL and raw.get("charged", false),
	}


# --- runtime -----------------------------------------------------------------


func next_interval() -> float:
	var interval := jittered_interval(randf())
	if is_night():
		# maxf against the same floor the static uses: the night multiplier must not be able
		# to push the cadence below the bound that exists to stop it becoming a stream.
		interval = maxf(MIN_INTERVAL, interval * NIGHT_INTERVAL_MULT)
	return interval


## The clock, by group — this node is under `World` and the clock under `Systems`, so there
## is no stable relative path. Null in any scene that is not the full game, which is what
## keeps the spawner usable in a test.
func _clock() -> WorldClock:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("WorldClock"):
		if node is WorldClock:
			return node
	return null


## Whether the world is currently dark. Dusk does not count — see WorldClock.is_dark.
func is_night() -> bool:
	var clock := _clock()
	return clock != null and clock.is_night()


## Current spawn cadence, in seconds. Read by devtools.
func spawn_interval() -> float:
	return timer.wait_time if timer else SPAWN_INTERVAL


## Current population ceiling, scaled to the land enemies are actually allowed onto.
##
## Counting every grass tile on the map would let a region that opts out of ambient
## spawning still raise the ceiling - the boss arena would buy extra wandering enemies
## for the mainland while staying empty itself. An island the home coastline has not yet
## reached is excluded for the same reason: until it opens, its grass is scenery.
func enemy_cap() -> int:
	var land := 0
	if tilemap_handler:
		for region in tilemap_handler.regions:
			if region.accepts_ambient_enemies():
				land += tilemap_handler.count_land_tiles_in(region)

	var cap := cap_for_land_tiles(land)
	if is_night():
		# MAX_ENEMY_CAP still binds. That ceiling exists because enemies the player never
		# kills accumulate until the frame rate collapses, and nightfall is not a reason to
		# suspend it — on a bought-out island the day cap is already the ceiling, so there
		# night is felt as the faster cadence rather than as a bigger crowd.
		cap = mini(int(round(cap * NIGHT_CAP_MULT)), MAX_ENEMY_CAP)
	return cap


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

		# A region can refuse ambient enemies; the boss arena stays the boss's, and an island
		# the player cannot reach yet stays empty.
		if not tilemap_handler.region_for_cell(tile).accepts_ambient_enemies():
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

	# Only types the registry marks `ambient`. The old `enemies` array happened to hold
	# exactly the two wanderers, but nothing said so — adding the elite to it, which is the
	# obvious thing to do when adding a boss, would have put elites on the mainland.
	var ambient := EnemyRegistry.ambient_types()
	var type: String = ambient[randi() % ambient.size()]
	var instance = EnemyRegistry.scene_for(type).instantiate()
	instance.position = tilemap_handler.tileMap.map_to_local(tile)
	add_child(instance)

	pending_spawns -= 1


func saveObject() -> Dictionary:
	var children = get_children()
	var enemies_to_save = {}

	for i in children.size():
		var child = children[i]
		if child is Enemy:
			enemies_to_save[i] = (
				enemy_save_entry(
					child.health_manager.current_health,
					child.target == null,
					child.attack_target == null,
					child.drop,
					child.position,
					child.type,
					child.max_health,
					child.damage,
					child.is_charged
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

	# decode_entries reads both the pre-gather-usv JSON strings and the nested dictionaries
	# written now, and drops anything unreadable rather than raising.
	for parsed in SaveLoad.decode_entries(stored):
		var node := normalize_enemy_entry(parsed)

		var scene := scene_for_type(node["type"])
		var instance = scene.instantiate()
		# Before add_child, because _ready is what turns max_health into a HealthManager.
		instance.max_health = node["max_hp"]
		instance.damage = node["damage"]
		instance.type = node["type"]
		# Alongside max_health and for the same reason: _ready is what turns these into
		# something visible, and for `is_charged` that something is the blue tint.
		instance.is_charged = node["charged"]
		add_child(instance)
		instance.position = Vector2(node["x"], node["y"])
		instance.health_manager.current_health = node["hp"]
		if node["target"] == false:
			instance.target = player
		if node["attack_target"] == false:
			instance.attack_target = player
		instance.drop = node["drop"]
