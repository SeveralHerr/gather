extends Node
class_name RunStats

## What this run amounted to, and the fact that it is over.
##
## The game had no finish. A player maxed the island, killed the boss, and then kept playing an
## identical game forever — so there was nothing to be good at and nothing to beat. Killing the
## boss now ends the run and shows a score card (`ui/run_summary_ui.gd`), and the card is what
## turns a sandbox into something you replay.
##
## ## What this node owns, and what it deliberately does not
##
## It owns only the numbers nothing else in the game keeps: kills, nodes gathered, deaths, and
## how long the run has been running. Everything else on the card — level, gold, land, days,
## raids cleared, skills learned — is read from whoever already owns it at the moment the card
## is built (`summary()`).
##
## That split is the whole design, and it is the repo's own rule about two copies of a fact:
## `LevelUpManager` owns the level, `LandManager` owns the parcels, `RaidDirector` owns the
## clears. A counter here that shadowed any of them would be a second copy that can disagree —
## and would disagree, because a load restores theirs and would have to remember to restore this
## one too. Reading at summary time cannot drift.
##
## ## The view is somewhere else
##
## Same split as `WorldClock`/`SkyLighting` and `RaidDirector`/`RaidBanner`, for the same three
## reasons: a model that draws cannot be tested headless, cannot be driven from devtools without
## a viewport, and grows a second copy of its state inside whatever it draws into.

## The run is over. `summary` is the finished card's contents, passed along so the UI never has
## to re-derive it from a world that has already started moving again.
signal run_ended(summary: Dictionary)

## What ended the run, for the card's heading. A String rather than an enum because it is
## persisted, and because the next ending (starving, a timer, a quest chain) should be an entry
## here and not a save migration.
const CAUSE_BOSS := "boss"

## Real seconds the run has been going.
##
## Accumulated from `_process` delta rather than from a wall clock, which means `Juice.hit_stop`
## and a devtools `set-game-speed` both distort it slightly. That is the right trade: the
## alternative counts the minutes a paused, backgrounded or debugger-halted game spent doing
## nothing, and the number on the card is meant to say how long the player *played*. `days` on
## the card is the honest measure of run length anyway; this is the human-readable one beside it.
var play_seconds := 0.0

## Things nothing else counts.
var enemies_killed := 0
var resources_gathered := 0
var deaths := 0

## Set the moment the run ends and never cleared by anything but a new run. Idempotent by
## construction: `end_run` returns early on it, so a second boss (or a second call from a
## reloaded save) cannot re-show the card or re-freeze the day it ended on.
var run_ended_flag := false
var ended_cause := ""

## The day, level and gold the run ENDED on, frozen at that moment.
##
## These three are the exception to the read-it-live rule above, and the exception is the point:
## once the run is over the world keeps going — the player may choose KEEP PLAYING, gather
## another thousand gold and level up twice. A card rebuilt from live values afterwards would
## quietly rewrite the score. What the run scored is a historical fact, so it is recorded.
var ended_day := 0
var ended_level := 0
var ended_gold := 0


func _enter_tree() -> void:
	# `_enter_tree`, not `_ready`, for the reason WorldClock documents at length: this node is
	# under `Systems`, which main.tscn declares last, so anything looking the group up from its
	# own `_ready()` would find it empty.
	add_to_group("RunStats")


func _ready() -> void:
	add_to_group("SaveLoad")

	var resource_manager := _resource_manager()
	if resource_manager != null and not resource_manager.resource_removed.is_connected(_on_resource_removed):
		resource_manager.resource_removed.connect(_on_resource_removed)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	# Kept running after the run ends. A player who chooses KEEP PLAYING is still playing, and
	# the card's own time is frozen in `summary()` at the moment it was built.
	play_seconds += delta


## The single RunStats, by group and type-checked. main.tscn's root used to belong to every
## group in the project, so `get_first_node_in_group` is never the right lookup here — and an
## index encodes how many members a group happens to have today.
static func find(from: Node) -> RunStats:
	if from == null:
		return null
	var tree := from.get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("RunStats"):
		if node is RunStats:
			return node
	return null


# --- the counters -------------------------------------------------------------


## Called from `Enemy._on_died`. One call site rather than a signal, because there is no global
## "an enemy died" signal to connect to and adding one to every enemy would be a connection per
## spawn — the allocation-per-event shape `HealthManager` was fixed for.
func record_kill() -> void:
	enemies_killed += 1


## Called from `Player.die`. Deaths are not punished in this game (respawn is free), so this is
## on the card as texture rather than as a score: "day 14, never died" is a different run from
## "day 14, died nine times", and nothing else anywhere records the difference.
func record_death() -> void:
	deaths += 1


func _on_resource_removed(_location: Vector2i, _resource) -> void:
	resources_gathered += 1


## Wired from `TileMapHandler._setup_islands()`. The boss is what the whole progression points
## at — every parcel of land is bought on the way to reaching its island — so killing it is the
## thing that ends the run.
##
## The island id is carried but not used: today there is one boss, and a build with several
## would have to decide whether the *first* or the *last* ends things. That decision belongs
## here when it exists rather than being pre-empted now with a guess.
func _on_boss_killed(_island_id: String) -> void:
	end_run(CAUSE_BOSS)


# --- ending the run -----------------------------------------------------------


## Ends the run and emits the card. Returns whether it actually ended anything, so a caller (or
## a devtools verb) can tell "the run ended" from "it was already over" — those are different
## answers and a bare `true` cannot say which.
##
## Idempotent on purpose. `IslandManager` re-asserts its bosses after a save is replayed, and a
## build with a second boss would call this again; neither may re-show the card or rewrite the
## day the run scored.
func end_run(cause: String = CAUSE_BOSS) -> bool:
	if run_ended_flag:
		return false

	run_ended_flag = true
	ended_cause = cause

	# Frozen here, not read at card-build time. See the field comments.
	var clock := _clock()
	ended_day = clock.day if clock != null else 0

	var manager := LevelUpManager.find(self)
	ended_level = manager.level if manager != null else 1
	ended_gold = _gold()

	run_ended.emit(summary())
	return true


## Everything the card shows, in one Dictionary.
##
## Built on demand and read live from the owners of each fact, except the three frozen in
## `end_run` — see those fields. Public and returning plain data so the devtools verb and the UI
## are looking at exactly the same numbers rather than each assembling their own.
func summary() -> Dictionary:
	var manager := LevelUpManager.find(self)
	var raids := _raid_director()
	var land := _land_manager()

	return {
		"cause": ended_cause,
		"ended": run_ended_flag,
		# The run's own numbers.
		"day": ended_day,
		"level": ended_level,
		"gold": ended_gold,
		"play_seconds": play_seconds,
		"enemies_killed": enemies_killed,
		"resources_gathered": resources_gathered,
		"deaths": deaths,
		# Read from whoever owns them. A zero here means that system is absent, which is a
		# truthful reading in a test scene and impossible in the real game.
		"raids_cleared": raids.raids_cleared if raids != null else 0,
		"skills_learned": manager.taken.size() if manager != null else 0,
		"parcels_bought": land.parcels_bought if land != null else 0,
		"land_radius": land.radius if land != null else 0,
	}


## `play_seconds` as `1h 04m` or `7m 12s`. Static and pure so the card's formatting is testable
## without a viewport, and so the devtools verb prints the same string the player sees.
static func format_duration(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var secs := total % 60
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm %02ds" % [minutes, secs]


# --- lookups ------------------------------------------------------------------


func _clock() -> WorldClock:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("WorldClock"):
		if node is WorldClock:
			return node
	return null


func _raid_director() -> RaidDirector:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("RaidDirector"):
		if node is RaidDirector:
			return node
	return null


func _land_manager() -> LandManager:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("LandManager"):
		if node is LandManager:
			return node
	return null


func _resource_manager() -> ResourceManager2:
	return get_node_or_null("../ResourceManager") as ResourceManager2


func _gold() -> int:
	var player := PlayerManager.player
	if player == null or player.inventory_data == null:
		return 0
	return player.inventory_data.count_of_type(Types.Item.Coin)


# --- save ---------------------------------------------------------------------


func saveObject() -> Dictionary:
	return {
		"filepath": get_path(),
		# Progress, every one of them. A run's tally is exactly the kind of thing that looks
		# correct in a diff and silently resets on every load if it is not written down.
		"play_seconds": play_seconds,
		"enemies_killed": enemies_killed,
		"resources_gathered": resources_gathered,
		"deaths": deaths,
		"run_ended": run_ended_flag,
		"ended_cause": ended_cause,
		"ended_day": ended_day,
		"ended_level": ended_level,
		"ended_gold": ended_gold,
	}


## Every read is `get` with a default and nothing indexes: a raise inside `-> void` aborts the
## method and looks exactly like success, and a save written before this node existed has no
## entry for it at all.
func loadObject(loadedDict: Dictionary) -> void:
	play_seconds = maxf(0.0, float(loadedDict.get("play_seconds", 0.0)))
	enemies_killed = maxi(0, int(loadedDict.get("enemies_killed", 0)))
	resources_gathered = maxi(0, int(loadedDict.get("resources_gathered", 0)))
	deaths = maxi(0, int(loadedDict.get("deaths", 0)))

	# `typeof(...) == TYPE_BOOL` rather than `== true`: comparing a String to a bool raises
	# instead of evaluating false, and every field below this line would be lost with it.
	var stored_ended: Variant = loadedDict.get("run_ended", false)
	run_ended_flag = stored_ended if typeof(stored_ended) == TYPE_BOOL else false

	ended_cause = str(loadedDict.get("ended_cause", ""))
	ended_day = int(loadedDict.get("ended_day", 0))
	ended_level = int(loadedDict.get("ended_level", 0))
	ended_gold = int(loadedDict.get("ended_gold", 0))

	# Deliberately does NOT emit run_ended. Loading a save whose run is already over must not
	# throw the score card in the player's face — they saved and quit having already seen it, and
	# what they asked for by loading is the world, not the epitaph. The flag is what matters, and
	# it is restored: it is what stops the boss ending the run a second time.
