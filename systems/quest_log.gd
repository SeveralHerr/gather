extends Node
class_name QuestLog

## Which quests are done, and how far along the rest are.
##
## The registry is `systems/quest_board.gd`; this node is the runtime half. It draws nothing —
## `ui/quest_ui.gd` does — the same model/view split as `WorldClock`/`SkyLighting`,
## `RaidDirector`/`RaidBanner` and `RunStats`/`RunSummaryUi`.
##
## ## It persists exactly one thing
##
## The set of claimed ids. Nothing else, because nothing else is state: every quest's progress is
## derived on demand from whoever already owns the fact it measures — see the class comment on
## `QuestBoard`. That is what makes this file short and what makes it impossible for a quest's
## progress to be lost on a load, since there is none to lose.

## A quest was claimed. Carries the quest so a listener does not have to look it up.
signal quest_claimed(quest: Quest)

## Something changed that might have moved a quest's progress. Emitted on a coarse poll rather
## than per event, because the six things quests measure live in six different nodes and
## subscribing to all of them would be six connections that each have to be kept correct. See
## `_process`.
signal progress_changed

## How often the log re-checks whether anything is newly completable, in seconds.
##
## A poll rather than six signal connections, and the trade is deliberate. Progress is derived
## from six owners (inventory, RunStats, RaidDirector, WorldClock, LevelUpManager, LandManager);
## wiring each would be six connections to keep correct through loads and scene rebuilds, to buy
## sub-second latency on a badge. Half a second is imperceptible for "a quest went green" and the
## check itself is a dozen integer compares.
const POLL_SECONDS := 0.5

## Field initializer rather than built in `_ready()`, so anything that finds this node can read
## the definitions regardless of whose `_ready()` ran first — the same reason
## `LevelUpManager.tree` is built this way.
var board := QuestBoard.new()

## id -> true for every claimed quest. A Dictionary rather than an Array because every read is a
## membership test, and because that is the shape `LevelUpManager.taken` already uses.
var claimed: Dictionary = {}

var _poll_left := 0.0

## The last count of completable-but-unclaimed quests, so `progress_changed` fires on a change
## rather than twice a second forever.
var _last_ready_count := -1


func _enter_tree() -> void:
	# `_enter_tree`, not `_ready`: this node is under `Systems`, which main.tscn declares last, so
	# anything looking the group up from its own `_ready()` would find it empty. See the long
	# comment on `WorldClock._enter_tree`.
	add_to_group("QuestLog")


func _ready() -> void:
	add_to_group("SaveLoad")


func _process(delta: float) -> void:
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL_SECONDS

	var ready_now := ready_count()
	if ready_now == _last_ready_count:
		return
	_last_ready_count = ready_now
	progress_changed.emit()


## The single QuestLog, by group and type-checked. main.tscn's root used to belong to every group
## in the project, so `get_first_node_in_group` is never the right lookup here.
static func find(from: Node) -> QuestLog:
	if from == null:
		return null
	var tree := from.get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("QuestLog"):
		if node is QuestLog:
			return node
	return null


# --- progress -----------------------------------------------------------------


## How far along `id` is, capped at its target. Zero for an unknown id rather than an error: the
## UI asks about whatever the board lists, and a board and a log that disagree should draw an
## empty bar rather than raise inside a layout pass.
func progress_of(id: String) -> int:
	var quest: Quest = board.get_quest(id)
	if quest == null:
		return 0
	return mini(_raw_progress(quest), quest.amount)


## The uncapped reading. Split out so `progress_of` can cap without the two disagreeing about
## what the reading was.
func _raw_progress(quest: Quest) -> int:
	match quest.kind:
		Quest.Kind.HAVE:
			return _inventory_count(quest.item)
		Quest.Kind.KILL:
			var stats := RunStats.find(self)
			return stats.enemies_killed if stats != null else 0
		Quest.Kind.RAID:
			var raids := _raid_director()
			return raids.raids_cleared if raids != null else 0
		Quest.Kind.DAY:
			var clock := _clock()
			return clock.day if clock != null else 0
		Quest.Kind.LEVEL:
			var manager := LevelUpManager.find(self)
			return manager.level if manager != null else 0
		Quest.Kind.PARCEL:
			var land := _land_manager()
			return land.parcels_bought if land != null else 0
	return 0


func is_complete(id: String) -> bool:
	var quest: Quest = board.get_quest(id)
	if quest == null:
		return false
	return _raw_progress(quest) >= quest.amount


func is_claimed(id: String) -> bool:
	return claimed.has(id)


## Whether `id` can be claimed right now: offered, complete, and not already taken.
func can_claim(id: String) -> bool:
	return not is_claimed(id) and board.is_offered(id, claimed) and is_complete(id)


## Offered, unclaimed quests, in board order. What the panel draws.
func available() -> Array[String]:
	return board.available(claimed)


## How many of those are ready to hand in. Drawn on the toolbar button, so a player who is not
## looking at the panel still finds out that one went green.
func ready_count() -> int:
	var total := 0
	for id in available():
		if is_complete(id):
			total += 1
	return total


# --- claiming -----------------------------------------------------------------


## Hands in `id`. Returns false and changes nothing if it is not claimable or — for a HAVE quest
## — if the items could not actually be taken.
##
## The spend happens BEFORE the quest is marked claimed, and that order is the whole guard: a
## claim that marked first and spent second would, on a failed spend, leave the quest done and
## the items still in the bag. `spend_type` is what says whether the items were really there, and
## it is asked rather than assumed because `can_claim` reads the inventory a frame earlier and
## the player may have dropped something into a chest since.
func claim(id: String) -> bool:
	if not can_claim(id):
		return false

	var quest: Quest = board.get_quest(id)
	if quest == null:
		return false

	if quest.consumes():
		var inventory := _inventory()
		if inventory == null or not inventory.spend_type(quest.item, quest.amount):
			return false

	claimed[id] = true
	_pay(quest)

	# Forces the next poll to re-emit: claiming removes a quest from `available()` and may reveal
	# the one it gated, so the count the poll compares against is stale by construction.
	_last_ready_count = -1

	quest_claimed.emit(quest)
	return true


## Pays a claimed quest out into the world.
##
## Coins are dropped as ONE pickup carrying the whole purse rather than N pickups, for the reason
## `PickUpManager.create_pickup`'s `count` parameter exists: the largest reward on the board is
## 400, and 400 nodes at the player's feet is a frame-rate event followed by a vacuum that takes
## half a minute — the reward would arrive as lag.
##
## Dropped rather than added to the inventory directly, because the drop is the feedback: the
## pop, the arc and the sparkle are what say a reward was paid. A silent inventory increment
## looks like nothing happened.
func _pay(quest: Quest) -> void:
	var at := _player_position()

	if quest.reward_coins > 0:
		var coin := GameItems.get_item(Types.Item.Coin)
		if coin != null:
			PickUpManager.create_pickup(coin, at, quest.reward_coins)

	if quest.reward_xp > 0:
		var manager := LevelUpManager.find(self)
		if manager != null:
			manager.add_xp(quest.reward_xp, at)


# --- lookups ------------------------------------------------------------------


func _inventory() -> InventoryData:
	var player := PlayerManager.player
	return player.inventory_data if player != null else null


func _inventory_count(type: Types.Item) -> int:
	var inventory := _inventory()
	return inventory.count_of_type(type) if inventory != null else 0


func _player_position() -> Vector2:
	var player := PlayerManager.player
	return player.global_position if player != null else Vector2.ZERO


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


# --- save ---------------------------------------------------------------------


func saveObject() -> Dictionary:
	return {
		"filepath": get_path(),
		# The only state this node has. Keys rather than the Dictionary itself, matching
		# `LevelUpManager.taken` — a JSON round trip turns `{"a": true}` into a Dictionary with a
		# String key either way, and a list is what the payload reads as by eye.
		"claimed": claimed.keys(),
	}


## Every read is guarded: a raise inside `-> void` aborts the method and looks exactly like
## success, and a save written before quests existed has no entry for this node at all.
func loadObject(loadedDict: Dictionary) -> void:
	claimed = {}

	var stored: Variant = loadedDict.get("claimed", [])
	# A payload whose `claimed` is not a list — hand-edited, or a future build that made it a
	# Dictionary — must not take the rest of the method down with it.
	if not (stored is Array):
		push_warning("QuestLog: 'claimed' was %s, not a list; no quests restored" % typeof(stored))
		stored = []

	for id in stored:
		var key := str(id)
		# Ids this build does not have are dropped rather than kept. Keeping them would mean a
		# save from a build with more quests silently re-completing them if they ever came back
		# under the same id, and `available()` already treats an unknown id as not offered.
		if board.has_quest(key):
			claimed[key] = true

	_last_ready_count = -1
