extends Node
class_name RaidDirector

## Night raids: from a fixed night onward, dark is something that comes for you.
##
## ## Why this exists
##
## Night already did something — `EnemySpawner.NIGHT_CAP_MULT` and `NIGHT_INTERVAL_MULT` make
## the trickle a little heavier and a little faster — but the trickle spawns *anywhere* and
## `EnemyIdle` only notices the player within `hunt_range`, which is two tiles. So night was
## more enemies standing around somewhere else. Nothing on the island was ever at stake, which
## is why walls, doors and turrets were decoration: there was nothing to keep out.
##
## A raid is the other half. It is a sized, escalating group that spawns at the far edge of the
## land and walks at the player, announced before it lands and counted down while it runs. The
## turret the player built now has something to shoot, and the wall now has a reason to be
## between them and it.
##
## ## The split, and why this node draws nothing
##
## Same split as `WorldClock` / `SkyLighting` and `LevelUpManager` / `SkillTreeUi`, for the same
## three reasons: a model that renders cannot be tested, cannot be driven from devtools without
## a viewport, and quietly grows a second copy of its state inside whatever it draws into.
## `ui/raid_banner.gd` is the view. Everything here is numbers and enemies.
##
## ## Why there is no Timer in this file
##
## `WorldClock`'s class comment states the rule this follows: `Timer.start(t)` *assigns*
## `wait_time = t`, so restoring a partially elapsed timer silently reschedules every later
## cycle to the remaining time (gather-9x0). `_spawn_cooldown` is a plain float advanced by
## delta, it is progress, it is what gets saved, and restoring it is assignment and nothing
## else.
##
## ## Why "how many raiders are left" is counted, never tracked
##
## The obvious implementation keeps `raiders_alive` and decrements it from each raider's
## `died` signal. That number is wrong the moment the player quicksaves mid-raid: the enemies
## come back through `EnemySpawner.loadObject`, which rebuilds them from the scene and connects
## nothing, so every later kill would be invisible and the raid would never clear. The count is
## therefore derived from the live enemies every time it is asked for (`live_raiders()`), which
## is correct across a load by construction rather than by remembering to re-wire something.
## `RAIDER_TYPES` being real registry types instead of a flag is what makes that possible.

## The raid has been announced and the first raider is on its way.
signal raid_started(day: int, size: int)

## The number of raiders still standing (or still to arrive) changed. Emitted only on a change,
## never per frame — the banner redraws from it.
signal raid_progress(remaining: int, total: int)

## Every raider is down and it is still night. `reward_coins` is what the clear paid on top of
## whatever the bodies dropped.
signal raid_cleared(day: int, reward_coins: int)

## The raid is over without having been cleared: dawn arrived with raiders still standing. Not
## a failure state — nothing is taken away — but it is deliberately a different signal, because
## surviving until morning and clearing the field are different things and the score card in
## `RunStats` counts only the second.
signal raid_survived(day: int, remaining: int)

# --- tuning ------------------------------------------------------------------

## The first night that raids. Nights 1 and 2 are quiet on purpose: a new player needs to have
## seen a night, built something and found the hotbar before the game asks them to defend any
## of it. It is also long enough that the first raid lands on a player who has a sword.
const FIRST_RAID_NIGHT := 3

## Raiders on the first raid night, and how many more each night after it adds.
##
## 0.75 rather than 1.0 so the ramp is felt as a slope rather than a step: night 3 is three,
## night 5 is four, night 9 is seven, night 15 is twelve. A player who is losing ground has a
## couple of nights to notice before the next one is materially worse.
const BASE_SIZE := 3
const SIZE_GROWTH := 0.75

## The most raiders one night may send.
##
## This is a frame-rate bound before it is a difficulty one. `EnemySpawner.MAX_ENEMY_CAP` is 25
## and raiders are spawned *outside* that ceiling — deliberately, since a raid that counted
## against the ambient cap would simply stop the trickle and feel like nothing had changed — so
## the real worst case on screen is this plus that. 12 keeps it under 40 live enemies, which is
## the number the spawner's own ceiling was chosen against.
const MAX_SIZE := 12

## What a raider's health is multiplied by, per night past the first raid night, and the ceiling
## on it.
##
## Health rather than damage, and that asymmetry is the design. Scaling damage makes a late
## raid one-shot a player who has not found armour (there is none), which is a difficulty
## setting the game has no dial to answer. Scaling health makes a raider take longer to put
## down, which is answered by every dial the player *does* have: a better sword, the Combat
## branch, a turret, a wall to fight behind.
const HEALTH_GROWTH := 0.08
const MAX_HEALTH_MULT := 2.5

## Seconds between raiders arriving.
##
## A raid does not pop into existence. Staggering the arrivals is what makes it read as
## something walking in from the dark — and it gives the player time to fall back to whatever
## they built, which is the decision the whole feature exists to create. Twelve raiders at 1.6s
## is a 19-second arrival, comfortably inside the three-minute night.
const SPAWN_STAGGER := 1.6

## How long after the announcement the first raider lands. The banner and the horn need a beat
## to be read and heard before anything is on the map.
const TELEGRAPH_SECONDS := 3.0

## How far from the player a raider may spawn, in world pixels. Tiles are 16px and the camera
## shows roughly 15x8 of them, so 200 is comfortably off-screen: raiders are *seen arriving*
## rather than seen appearing.
const MIN_SPAWN_DISTANCE := 200.0

## Attempts at finding a spawn cell before giving up on one raider. Higher than
## `EnemySpawner.PLACEMENT_ATTEMPTS` because this is a much narrower ask — far from the player
## rather than merely not on top of them — and on a small starting island a random tile clears
## 200px only sometimes.
const PLACEMENT_ATTEMPTS := 30

## The distance the fallback relaxes to when PLACEMENT_ATTEMPTS finds nothing.
##
## Without it, a maxed-out player standing in the middle of a small home island could stall a
## raid entirely: every candidate cell is inside MIN_SPAWN_DISTANCE, no raider ever spawns, and
## the banner counts down to a fight that never arrives. Six tiles is still outside the
## `EnemySpawner.MIN_SPAWN_DISTANCE` exclusion, so a raider never materialises in the player's
## lap; it just does not get to make an entrance.
const FALLBACK_SPAWN_DISTANCE := 96.0

## The clear bonus, per raider that was in the raid.
##
## Coins because land is what the player is saving for and a night spent defending should move
## that number; xp because the raid is the hardest thing they do and the level curve should
## notice. Priced against `LandManager`'s curve — twelve parcels cost ~6950 coins in total — so
## a night-9 clear at 7 raiders pays 56, i.e. a couple of early parcels across a good run and
## nowhere near an alternative to mining gold.
##
## Paid ONCE, on the clear, and never for a raid that merely expired at dawn. A bonus that paid
## out either way would make letting the raid run the optimal play.
const REWARD_COINS_PER_RAIDER := 8
const REWARD_XP_PER_RAIDER := 4

# --- state -------------------------------------------------------------------

## Whether a raid is running right now.
var raid_active := false

## The day the running raid belongs to, and how big it was declared. `raid_size` is held rather
## than recomputed from `raid_day` so the banner's "4 of 8" cannot disagree with itself if the
## curve above is ever retuned mid-save.
var raid_day := 0
var raid_size := 0

## Raiders declared but not yet spawned. Progress, so it is saved: a player who quicksaves four
## raiders into an eight-raider night and reloads should be owed four, not eight and not none.
var raiders_pending := 0

## Seconds until the next raider arrives. Progress again, and a plain float for the reason in
## the class comment.
var _spawn_cooldown := 0.0

## The last day a raid was *started*. Guards against a second raid on one night — `night_started`
## can be emitted again by a devtools time jump, and a load that lands in the dark must not open
## a fresh raid on a night the player has already fought.
var last_raid_day := 0

## Raids cleared, for the run summary. Counts clears only; see `raid_survived`.
var raids_cleared := 0

## The last remaining-count emitted, so `raid_progress` fires on changes rather than per frame.
var _last_remaining := -1

## Set false by tests and by devtools that want to drive raids by hand without the clock
## opening one underneath them.
var running := true


## Registered in `_enter_tree` for the same reason `WorldClock` does it: this node lives under
## `Systems`, which `main.tscn` declares last, so anything looking the group up from its own
## `_ready()` would find it empty. See the long comment on `WorldClock._enter_tree`.
func _enter_tree() -> void:
	add_to_group("RaidDirector")


func _ready() -> void:
	add_to_group("SaveLoad")
	randomize()

	var clock := _clock()
	if clock != null and not clock.night_started.is_connected(_on_night_started):
		clock.night_started.connect(_on_night_started)


# --- pure helpers (unit-tested; keep them free of node access) ----------------


## Whether the night of `day` sends a raid.
static func raids_on_night(day: int) -> bool:
	return day >= FIRST_RAID_NIGHT


## How many raiders the night of `day` sends. Zero for a night that does not raid, which is what
## lets a caller ask this without first asking `raids_on_night`.
static func size_for_day(day: int) -> int:
	if not raids_on_night(day):
		return 0
	var nights_in := day - FIRST_RAID_NIGHT
	return mini(BASE_SIZE + int(floor(float(nights_in) * SIZE_GROWTH)), MAX_SIZE)


## What a raider's `max_health` is multiplied by on the night of `day`.
static func health_mult_for_day(day: int) -> float:
	if not raids_on_night(day):
		return 1.0
	var nights_in := day - FIRST_RAID_NIGHT
	return minf(1.0 + float(nights_in) * HEALTH_GROWTH, MAX_HEALTH_MULT)


## The coin bonus a cleared raid of `size` pays.
static func reward_for_size(size: int) -> int:
	return maxi(0, size) * REWARD_COINS_PER_RAIDER


## The xp bonus a cleared raid of `size` pays, before the Scholar multiplier `add_xp` applies.
static func xp_for_size(size: int) -> int:
	return maxi(0, size) * REWARD_XP_PER_RAIDER


# --- lookups -----------------------------------------------------------------


func _clock() -> WorldClock:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("WorldClock"):
		if node is WorldClock:
			return node
	return null


## The spawner, which is also where raiders are parented — see `_spawn_raider`.
func _spawner() -> EnemySpawner:
	var handler := _handler()
	if handler == null:
		return null
	return handler.get_node_or_null("World/EnemySpawner") as EnemySpawner


func _handler() -> TileMapHandler:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("TileMapHandler"):
		if node is TileMapHandler:
			return node
	return null


## Raiders currently on the map. Derived rather than tracked; see the class comment.
func live_raiders() -> int:
	var spawner := _spawner()
	if spawner == null:
		return 0
	var total := 0
	for child in spawner.get_children():
		if child is Enemy and EnemyRegistry.is_raider(child.type):
			total += 1
	return total


## Raiders still to be dealt with: the ones standing plus the ones still to arrive. This is the
## number the banner draws and the number a clear tests against zero.
func remaining() -> int:
	return live_raiders() + raiders_pending


# --- the raid ----------------------------------------------------------------


func _on_night_started(day: int) -> void:
	if not running or raid_active:
		return
	if not raids_on_night(day):
		return
	# One raid per night. A devtools time jump can emit night_started for a day already fought,
	# and re-opening that night's raid would double the enemies and the payout.
	if day <= last_raid_day:
		return
	start_raid(day)


## Opens a raid for `day`. Public so devtools and the debug panel can force one without waiting
## for nightfall, and so a test can drive it without a clock.
##
## Returns the number of raiders declared, or 0 if the day does not raid — a verb that reported
## only "ok" could not tell "the raid started" from "that night is quiet", and those two live in
## different places.
func start_raid(day: int) -> int:
	var size := size_for_day(day)
	if size <= 0:
		return 0

	raid_active = true
	raid_day = day
	raid_size = size
	raiders_pending = size
	last_raid_day = day
	# The telegraph, not the stagger: nothing is on the map until the announcement has been read.
	_spawn_cooldown = TELEGRAPH_SECONDS
	_last_remaining = -1

	raid_started.emit(day, size)
	_announce()
	_emit_progress()
	return size


## The announcement. Deliberately loud, and deliberately in three registers at once — a splash
## the player reads, a flash they see with the screen looked away from, and a shake they feel —
## because this is the one event in the game that asks them to stop what they are doing and go
## somewhere. Anything quieter gets missed while the player is holding the gather key.
func _announce() -> void:
	var at := _player_position()
	SplashText.spawn(self, at, "NIGHT %d — RAID" % raid_day, Juice.RAID_SPLASH_COLOR, SplashText.Emphasis.BIG)
	ScreenFlash.flash(self, Juice.RAID_FLASH_COLOR, Juice.RAID_FLASH_ALPHA, Juice.RAID_FLASH_TIME)
	Juice.shake(self, Juice.Shake.HEAVY)
	GameSoundManager.play_sound(GameSoundManager.SoundType.THUNDER)


func _player_position() -> Vector2:
	var player := PlayerManager.player
	return player.global_position if player else Vector2.ZERO


func _process(delta: float) -> void:
	if not raid_active or delta <= 0.0:
		return

	# The invariant, checked here rather than driven off `phase_changed`, and that choice is
	# load-bearing. `WorldClock.loadObject` emits `phase_changed` while replaying a save, and
	# this node's own entry may be restored either side of that — so a signal-driven end would
	# depend on which order SaveLoad happened to walk two nodes in. Asking the clock every frame
	# has no order to get wrong.
	var clock := _clock()
	if clock != null and not clock.is_night():
		_end_raid_at_dawn()
		return

	if raiders_pending > 0:
		_spawn_cooldown -= delta
		if _spawn_cooldown <= 0.0:
			_spawn_cooldown = SPAWN_STAGGER
			_spawn_raider()

	_emit_progress()

	# Cleared: nothing left to arrive and nothing left standing. Tested after the spawn above so
	# a raid cannot clear on the frame it opened, before its first raider exists.
	if raiders_pending <= 0 and live_raiders() <= 0:
		_clear_raid()


## Emits `raid_progress` when the count has actually moved. Called every frame of a raid, so it
## has to be cheap on the common path — `remaining()` walks the spawner's children, which is at
## most a few dozen, and the emit is guarded.
func _emit_progress() -> void:
	var left := remaining()
	if left == _last_remaining:
		return
	_last_remaining = left
	raid_progress.emit(left, raid_size)


## Puts one raider on the map.
##
## Parented to the `EnemySpawner` rather than to this node, which buys the entire enemy
## save/load path for nothing — the same trick, and the same comment, as
## `IslandManager._spawn_boss`. It costs nothing either: the spawner's own cap counts only what
## it spawned against what it wants to spawn, and a raider is neither.
func _spawn_raider() -> void:
	var spawner := _spawner()
	var handler := _handler()
	if spawner == null or handler == null:
		# No world to raid (a unit test, a teardown mid-frame). The raider is not owed — dropping
		# it keeps `raiders_pending` falling so the raid can still clear rather than hanging with
		# a countdown that never reaches zero.
		raiders_pending -= 1
		return

	var cell = _pick_spawn_cell(handler)
	if cell == null:
		# Do NOT decrement: this is a transient failure (the player is standing in the middle of
		# a small island), and the next tick may well find a cell. The stagger has already been
		# re-armed, so this costs one interval rather than one raider.
		return

	raiders_pending -= 1

	var type: String = EnemyRegistry.RAIDER_TYPES[randi() % EnemyRegistry.RAIDER_TYPES.size()]
	var raider := EnemyRegistry.scene_for(type).instantiate() as Enemy

	# BEFORE add_child, without exception: `Enemy._ready` is what turns `max_health` into a
	# HealthManager, and a value written after it is a number nobody reads. `max_hp` is persisted
	# per enemy, so the night's scaling comes back from the save rather than being re-derived
	# from a curve that may have been retuned since.
	raider.max_health = int(round(float(raider.max_health) * health_mult_for_day(raid_day)))

	spawner.add_child(raider)
	raider.position = handler.tileMap.map_to_local(cell)

	# What makes it a raid rather than a spawn. `Enemy.create_path()` returns early on a null
	# target, so without this the raider paths nowhere and `EnemyIdle` wanders it in a circle —
	# the wide `hunt_range` in the raider scenes is what gets it into EnemyFollow, and this is
	# what gives that state somewhere to walk. Persisted: `enemy_save_entry` stores whether the
	# target was null and `loadObject` puts the player back, so a reloaded raider is still coming.
	raider.target = PlayerManager.player


## A land cell far enough from the player to be off-screen, or null if none was found.
##
## ## Why this is scoped to the player's own region
##
## The obvious implementation picks any land tile that is far enough away and refuses regions
## that decline ambient enemies. It was the first implementation, and it did not work: on a
## fresh island the home coastline is 160px across, so *no* home cell clears MIN_SPAWN_DISTANCE
## and every candidate that did was on one of the pregenerated islands. Raiders spawned there
## dutifully pathed at the player, walked into the sea's collider and stopped — velocity set,
## position unchanged. A raid that never arrives is worse than no raid: the banner counts seven
## enemies the player cannot find, and it hangs there until dawn.
##
## Nothing about that is visible headless, and nothing about it is visible in a screenshot
## either — the raiders exist, they are the right type, they are the right toughness, and their
## navigation agents return sensible next positions. It took reading one raider's position twice
## eight seconds apart to see that it had moved 0.13 pixels.
##
## So raiders come from the player's OWN region, which is the one piece of land they are
## guaranteed to be able to walk across. It also reads better than the general version: the raid
## comes out of the dark at the edge of the island you are standing on.
##
## `accepts_ambient_enemies` is deliberately NOT consulted. That flag exists so the global
## respawn timer cannot trickle wanderers onto the boss arena or onto an island the coastline
## has not reached — both cases about land the player is *not* on. A raid is aimed at the player
## and is time-boxed, so if they are standing in the arena at midnight, that is where it comes
## from.
##
## ## The two passes
##
## The first insists on MIN_SPAWN_DISTANCE, which is what makes raiders arrive from off-screen;
## the second relaxes to FALLBACK_SPAWN_DISTANCE so a player standing in the middle of a small
## island cannot stall the raid entirely. On a starting island the first pass essentially always
## fails — 160px of coastline against a 200px demand — and that is expected rather than
## degraded: an island that small has no off-screen to arrive from.
func _pick_spawn_cell(handler: TileMapHandler):
	if handler.tileMap == null:
		return null

	var player_pos := _player_position()
	var region := handler.region_for_cell(handler.tileMap.local_to_map(player_pos))

	for distance in [MIN_SPAWN_DISTANCE, FALLBACK_SPAWN_DISTANCE]:
		for _attempt in PLACEMENT_ATTEMPTS:
			var cell = handler.get_random_tile_in(region)
			# The region has no free cell at all — every tile of it is built on or occupied.
			# Trying the second distance would ask the same question again, so give up on this
			# tick and let the next one retry.
			if cell == null:
				return null

			if handler.tileMap.map_to_local(cell).distance_to(player_pos) < distance:
				continue

			return cell

	return null


## Every raider is down. Pays the clear bonus and closes the raid.
func _clear_raid() -> void:
	var day := raid_day
	var size := raid_size
	var coins := reward_for_size(size)

	raids_cleared += 1
	_close()

	var at := _player_position()
	SplashText.spawn(self, at, "RAID REPELLED", Juice.RAID_CLEARED_COLOR, SplashText.Emphasis.BIG)
	GameSoundManager.play_sound(GameSoundManager.SoundType.POP)

	# One pickup carrying the whole purse rather than `coins` separate drops. At a night-15 clear
	# that is 96 coins, and 96 nodes thrown at the player's feet is a frame-rate event and a
	# vacuum that takes ten seconds to finish — the reward would arrive as lag.
	var coin_item := GameItems.get_item(Types.Item.Coin)
	if coin_item != null and coins > 0:
		PickUpManager.create_pickup(coin_item, at, coins)

	var manager := LevelUpManager.find(self)
	if manager != null:
		manager.add_xp(xp_for_size(size), at)

	raid_cleared.emit(day, coins)


## Dawn arrived with raiders still standing. Nothing is taken away and nothing is paid; the
## raiders are deliberately LEFT ALIVE rather than despawned, because a wave of enemies
## evaporating at sunrise reads as the game cleaning up after itself and cancels the whole
## night's tension in one frame. They keep hunting; they are simply no longer a raid.
func _end_raid_at_dawn() -> void:
	var day := raid_day
	var left := remaining()
	# Anything that never arrived does not arrive. The night is over.
	raiders_pending = 0
	_close()
	raid_survived.emit(day, left)


## The bookkeeping every ending shares. `last_raid_day` deliberately survives it — it is what
## stops a second raid opening on the same night.
func _close() -> void:
	raid_active = false
	raid_size = 0
	raid_day = 0
	raiders_pending = 0
	_spawn_cooldown = 0.0
	_last_remaining = -1
	raid_progress.emit(0, 0)


# --- save --------------------------------------------------------------------


func saveObject() -> Dictionary:
	return {
		"filepath": get_path(),
		"raid_active": raid_active,
		"raid_day": raid_day,
		"raid_size": raid_size,
		# Progress, not configuration: how many of this night's raiders are still owed, and how
		# far through the wait for the next one we are. Saving the stagger interval instead would
		# restore a raid that had one raider left to send as a fresh full one.
		"raiders_pending": raiders_pending,
		"spawn_cooldown": _spawn_cooldown,
		"last_raid_day": last_raid_day,
		"raids_cleared": raids_cleared,
	}


## Every read is `get` with a default and nothing indexes: a raise inside a `-> void` aborts the
## method and is indistinguishable from success, and a save written before raids existed has no
## entry for this node at all.
func loadObject(loadedDict: Dictionary) -> void:
	# `typeof(...) == TYPE_BOOL` rather than `== true`: comparing a String to a bool raises
	# rather than evaluating false, and a hand-edited or older payload can hold either.
	var stored_active: Variant = loadedDict.get("raid_active", false)
	raid_active = stored_active if typeof(stored_active) == TYPE_BOOL else false

	raid_day = int(loadedDict.get("raid_day", 0))
	raid_size = int(loadedDict.get("raid_size", 0))
	raiders_pending = maxi(0, int(loadedDict.get("raiders_pending", 0)))
	_spawn_cooldown = maxf(0.0, float(loadedDict.get("spawn_cooldown", 0.0)))
	last_raid_day = int(loadedDict.get("last_raid_day", 0))
	raids_cleared = int(loadedDict.get("raids_cleared", 0))

	# A raid restored with no size is a raid this build cannot draw a progress bar for, and it
	# would never clear because `raid_size` is what the banner counts against. Treat it as over
	# rather than carrying a half-state forward.
	if raid_active and raid_size <= 0:
		raid_active = false
		raiders_pending = 0

	_last_remaining = -1
	_emit_progress()
