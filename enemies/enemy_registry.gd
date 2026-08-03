class_name EnemyRegistry
# RefCounted and never instantiated: everything here is static, so a test can ask the
# registry questions without a SceneTree, the same way SkillTree can be built standalone.
extends RefCounted

## What an enemy type IS, in one place.
##
## The type is a bare String because that is what every save file already stores
## (enemy_spawner.enemy_save_entry writes `type`), and it stays a String for that reason.
## What changes is that the string now resolves to a record rather than being re-matched by
## hand in three unrelated files: enemy_spawner.scene_for_type() had its own `match`,
## island_manager hardcoded "Elite", and player_net.on_hit() tested `body.type == "Bone"`.
## Three places that had to agree, with nothing making them (gather-33f).
##
## Fields:
##  * `scene`     — the .tscn backing this type. Reconstruction on load goes through it.
##  * `ambient`   — whether the spawn timer may trickle this type in. False for anything
##                  placed deliberately: a boss is spawned by IslandManager, and letting the
##                  ambient roll produce one would put elites on the mainland.
##  * `nettable`  — whether the Net captures it, and into which item. A type with no
##                  `capture_item` cannot be caught however the flag reads.
##  * `loot`      — EXTRA drops rolled on death, on top of `Enemy.drop` and the coin every
##                  kill already pays. Entries are {item, chance, min, max}; see loot_from().
##
## `drop` deliberately stays an @export on the Enemy scene rather than moving in here. It is
## persisted per enemy, so a saved enemy's drop must come back from the save and not be
## re-derived from a table that may have changed underneath it.
const BONE := "Bone"
const SPIDER := "Spider"
const ELITE := "Elite"

## The fallback for a save that names a type this build does not have. Bone was already the
## silent fallback in scene_for_type's `_:` arm; it stays the answer, but scene_for() now
## says so out loud instead of quietly demoting an elite to a skeleton.
const DEFAULT_TYPE := BONE

const TYPES := {
	BONE: {
		"scene": "res://enemies/bone_enemy.tscn",
		"ambient": true,
		"nettable": true,
		"capture_item": Types.Item.BoneEnemy,
		"loot": [],
	},
	SPIDER: {
		"scene": "res://enemies/spider_enemy.tscn",
		"ambient": true,
		"nettable": false,
		# String's only world source. It is craftable from wood as well (Foraging tier 1),
		# which exists precisely so the Net and the Bone Turret are not hostage to this roll —
		# stating it here is what makes that relationship visible from the enemy's side.
		"loot": [{"item": Types.Item.String, "chance": 0.5, "min": 1, "max": 1}],
	},
	ELITE: {
		"scene": "res://enemies/elite_enemy.tscn",
		# Never trickled in. The boss island's guard is placed by IslandManager, once.
		"ambient": false,
		"nettable": false,
		# The boss pays out on the body as well as in its chest. Kept modest on purpose: the
		# chest is the reward, and this is the part the player picks up standing over the
		# corpse. Bone is guaranteed because the elite IS a bone enemy underneath and its
		# `drop` is one bone; this is the "it was a big one" bonus on top.
		"loot": [
			{"item": Types.Item.Bone, "chance": 1.0, "min": 2, "max": 4},
			{"item": Types.Item.Coin, "chance": 1.0, "min": 3, "max": 6},
			{"item": Types.Item.IronBar, "chance": 0.5, "min": 1, "max": 2},
		],
	},
}


## The record for `type`, or the default type's record. Never null, so callers do not each
## grow their own fallback.
static func record(type: String) -> Dictionary:
	if TYPES.has(type):
		return TYPES[type]
	push_warning("EnemyRegistry: unknown enemy type '%s', falling back to %s" % [type, DEFAULT_TYPE])
	return TYPES[DEFAULT_TYPE]


static func has_type(type: String) -> bool:
	return TYPES.has(type)


## The scene backing `type`.
##
## load() rather than preload(): the paths live in a const Dictionary, and Godot caches the
## resource after the first call, so a spawn costs one dictionary lookup and a cache hit.
static func scene_for(type: String) -> PackedScene:
	return load(record(type)["scene"]) as PackedScene


## Types the ambient spawn timer may roll, in declaration order.
static func ambient_types() -> Array:
	var out := []
	for type in TYPES:
		if TYPES[type].get("ambient", false):
			out.append(type)
	return out


## Whether the Net captures this type at all.
static func is_nettable(type: String) -> bool:
	return TYPES.get(type, {}).get("nettable", false) and TYPES.get(type, {}).has("capture_item")


## The inventory item a netted `type` becomes, or null if it cannot be caught.
static func capture_item(type: String):
	if not is_nettable(type):
		return null
	return TYPES[type]["capture_item"]


static func loot_table(type: String) -> Array:
	return record(type).get("loot", [])


## The items a loot table yields, given one 0..1 sample per decision.
##
## Pure, and takes its randomness as an argument, for the same reason
## EnemySpawner.jittered_interval(roll) does: a drop table is exactly the kind of thing that
## is wrong in a way nobody notices for months, and a test cannot assert anything about it
## while randf() is buried inside. Each entry consumes two samples — one for whether it drops
## at all, one for how many — so the mapping from samples to result is fixed and readable.
##
## A missing sample reads as "did not drop" for the chance roll and as the minimum for the
## count, so a short array degrades to nothing rather than raising.
static func loot_from(table: Array, samples: Array) -> Array:
	var out := []

	for i in table.size():
		var entry: Dictionary = table[i]

		var chance: float = float(entry.get("chance", 1.0))
		var chance_roll: float = float(samples[i * 2]) if i * 2 < samples.size() else 1.0
		# `<` not `<=`, so a chance of 0.0 can never drop and a chance of 1.0 always does.
		if not (chance_roll < chance):
			continue

		var low: int = int(entry.get("min", 1))
		var high: int = maxi(low, int(entry.get("max", low)))
		var count_roll: float = float(samples[i * 2 + 1]) if i * 2 + 1 < samples.size() else 0.0
		var count: int = clampi(low + int(count_roll * float(high - low + 1)), low, high)

		for _n in count:
			out.append(entry["item"])

	return out


## The live roll. Draws the samples loot_from() needs and hands them over, so the only
## untested part is randf() itself.
static func roll_loot(type: String) -> Array:
	var table := loot_table(type)
	var samples := []
	for _i in table.size():
		samples.append(randf())
		samples.append(randf())
	return loot_from(table, samples)
