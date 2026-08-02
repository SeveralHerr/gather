extends Control
class_name LevelUpManager

## Progression model. This node no longer draws anything — it owns xp, levels,
## banked skill points and the taken set, and SkillTreeUi renders it. It stays a
## Control at its original scene path because saveObject() keys off get_path() and
## every existing saveFile refers to it there.

signal added_xp(amount: int)
signal xp_changed(xp: int, next_level: int)
signal level_gained(level: int)
signal points_changed(points: int)
signal skill_learned(skill: Skill)

@onready var xp_bar: ProgressBar = $"../PlayerInfo/XpBar"
@onready var resource_manager: ResourceManager2 = $"../../../../../ResourceManager"

## XP needed to reach level 2, and the ratio between one threshold and the next.
## The old curve doubled (10/20/40/80...), which outran the 1-4 xp a node pays by
## about level 5 and left most of the tree unreachable.
##
## 1.35 was calibrated against a twelve-node tree. The tree is sixteen nodes now, and
## because the cost of the last level compounds, those four extra nodes doubled the
## price of clearing it: 1020 XP, against the 500 that
## test_player_stats.test_the_whole_tree_is_reachable_in_one_run treats as the edge of
## one session. 1.28 puts sixteen nodes at 465. The guard is the design intent and the
## growth rate is the dial, so the dial moved.
##
## 1.30 is that same dial turned back up a little: levels were arriving faster than the
## player found anything to spend them on, and the world now regrows more slowly, so a
## level should cost more of it. Clearing the tree goes 465 -> 561, still one run. The
## first level is untouched at 10 — the growth rate is what lengthens the run, and making
## the opening skill cost more would only delay the tree becoming visible at all.
const XP_FIRST_LEVEL := 10
const XP_GROWTH := 1.30

## XP award table for everything that is not a resource node. Node xp lives in
## Resources.TUNING — a flat 1 for every node now, ore included — and is meant to stay
## the dominant source; these are seasoning, not a second economy:
##
##   XP_KILL 3   - was 5, when enemies were scarce enough that a kill could be worth
##                 several common nodes. The spawn cadence tripled since, so a kill is
##                 rarer again and no longer needs to pay like an event; 3 keeps it worth
##                 more than a common node without making the spawner the xp faucet.
##   XP_CRAFT 2  - a crafted item always consumes gathered input, so crafting cannot be
##                 farmed independently of gathering. 2 makes running a sawmill feel
##                 worth watching without out-earning the pickaxe.
##   XP_BUILD 1  - placing a tile consumes an item that was itself gathered or crafted,
##                 so this is the tail end of a chain that has already paid out.
##   XP_PICKUP 1 every PICKUPS_PER_XP drops - a drop is worth ~0.33 xp. A common node
##                 pays 1 xp and drops 1-2 items, so gathering keeps ~2/3 of the income
##                 from its own loop; per-drop xp at 1 each would have inverted that and
##                 made vacuuming, not mining, the fastest way to level.
const XP_KILL := 3
const XP_CRAFT := 2
const XP_BUILD := 1
const XP_PICKUP := 1
const PICKUPS_PER_XP := 3

## Ids that were renamed when the flat upgrade list became a tree. Applied on load
## so saves written before the rework keep their progress.
const LEGACY_IDS := {
	"iron": "iron_age",
}

## Field initializer rather than built in _ready(), so anything that finds this
## node can read the definitions regardless of whose _ready() ran first.
var tree := SkillTree.new()

var xp := 0
var level := 1
var next_level := XP_FIRST_LEVEL

## Levels earned but not yet spent. Banking them means a burst of xp that crosses
## two thresholds still hands out two points instead of silently eating one, and
## the player can now walk away from a level-up without losing it.
var points := 0

var taken: Dictionary = {}


func _ready():
	add_to_group("LevelUpManager")
	add_to_group("SaveLoad")

	# The panel lives in the UI2 CanvasLayer now; this node is model-only.
	visible = false

	_refresh_xp_bar()


func _refresh_xp_bar() -> void:
	if xp_bar == null:
		return
	xp_bar.max_value = next_level
	xp_bar.value = xp


## The single LevelUpManager, found by group. main.tscn's root belongs to every group in
## the project, so the type check is mandatory - get_first_node_in_group() would hand
## back the root. Returns null when there is no tree (a bare node in a unit test).
static func find(from: Node) -> LevelUpManager:
	if from == null:
		return null
	var tree := from.get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("LevelUpManager"):
		if node is LevelUpManager:
			return node
	return null


## XP earned before the Scholar multiplier, as awarded by resources, enemies, crafting,
## building and pickups. `world_position` is where the "+N XP" splash pops; pass the
## thing that earned it (the node, the corpse, the station). Omit it and the splash
## falls back to the player, so no award is ever silently invisible. Returns the amount
## actually granted, after the multiplier.
##
## The "unset" default is Vector2.INF rather than null so the parameter stays statically
## typed; no real world position is ever non-finite.
func add_xp(amount: int, world_position: Vector2 = Vector2.INF) -> int:
	var player := PlayerManager.player
	var multiplier: float = player.stats.xp_mult if player else 1.0
	var granted := int(round(amount * multiplier))

	xp += granted
	# The corner XpLabel (ui/floating_text.gd) listens to this. The world splash below
	# is a second view of the same event, not a second award.
	added_xp.emit(granted)

	# Not necessarily a new label: SplashText.spawn_xp folds an award into the xp splash
	# already in the air when there is one nearby, so a gather and the pickups it throws
	# off read as one climbing number rather than a column of "+1 XP".
	var splash_at := world_position if world_position.is_finite() else _player_position()
	SplashText.spawn_xp(self, splash_at, granted)

	while xp >= next_level:
		level += 1
		points += 1
		next_level = next_threshold(next_level)
		_splash_level_up()
		level_gained.emit(level)
		points_changed.emit(points)

	_refresh_xp_bar()
	xp_changed.emit(xp, next_level)
	return granted


func _player_position() -> Vector2:
	var player := PlayerManager.player
	return player.global_position if player else Vector2.ZERO


## Level-ups are announced in the world, at the player, and nothing else happens: the
## panel is opened with K when the player chooses to. This deliberately does not restore
## the old behaviour of seizing the screen the instant a threshold is crossed.
func _splash_level_up() -> void:
	var at := _player_position()
	SplashText.spawn(self, at, "LEVEL %d!" % level, SplashText.COLOR_LEVEL, SplashText.Emphasis.BIG)
	SplashText.spawn(self, at, "+1 SKILL POINT", SplashText.COLOR_POINT, SplashText.Emphasis.BIG)


## The cumulative XP threshold that follows `current`. Static and shared with
## add_xp so a test of the curve exercises the arithmetic the game actually runs.
static func next_threshold(current: int) -> int:
	return int(ceil(current * XP_GROWTH))


## Total XP needed to reach `target_level` from a fresh start.
static func xp_for_level(target_level: int) -> int:
	var threshold := XP_FIRST_LEVEL
	for _i in range(max(0, target_level - 2)):
		threshold = next_threshold(threshold)
	return threshold


func is_available(skill_id: String) -> bool:
	return tree.is_available(skill_id, taken)


func has_available_skill() -> bool:
	return tree.has_any_available(taken)


func can_purchase(skill_id: String) -> bool:
	return points > 0 and is_available(skill_id)


## Spends a point on a skill. Returns false and changes nothing when the skill is
## already taken, still locked, or there is no point to spend.
func purchase(skill_id: String) -> bool:
	if not can_purchase(skill_id):
		return false

	taken[skill_id] = true
	points -= 1

	_apply_unlocks(tree.get_skill(skill_id))
	sync_player_stats()

	points_changed.emit(points)
	skill_learned.emit(tree.get_skill(skill_id))
	return true


## Recipes and spawnable resources are the half of a skill that lives outside
## PlayerStats. Deliberately NOT called from loadObject: Recipes and
## ResourceManager2 each save their own unlocked list, so replaying these on load
## would append every recipe a second time.
func _apply_unlocks(skill: Skill) -> void:
	if skill == null:
		return

	for unlock in skill.recipes:
		Recipes.add_recipe(unlock["product"], unlock["station"])

	for resource_type in skill.resources:
		resource_manager.add_resource(resource_type)


## Pushes the taken set into the player's stat totals. Safe to call before the
## Player exists; Player._ready() calls it again once PlayerManager is populated,
## because _ready() runs child-first and this node is a descendant of the Player.
func sync_player_stats() -> void:
	var player := PlayerManager.player
	if player == null:
		return
	player.stats.recompute(taken, tree)


func saveObject() -> Dictionary:
	var dict := {
		"filepath": get_path(),
		"taken": taken.keys(),
		"points": points,
		"level": level,
		"xp": xp,
		"next_level": next_level,
	}
	return dict


func loadObject(loadedDict: Dictionary) -> void:
	xp = loadedDict["xp"]
	next_level = loadedDict["next_level"]
	level = loadedDict.get("level", 1)

	# "pending_levels" is what banked levels were called before they became points.
	points = loadedDict.get("points", loadedDict.get("pending_levels", 0))

	taken = {}
	if loadedDict.has("taken"):
		for skill_id in loadedDict["taken"]:
			var id: String = LEGACY_IDS.get(skill_id, skill_id)
			if tree.has_skill(id):
				taken[id] = true
	else:
		_recover_taken_from_button_states(loadedDict)

	sync_player_stats()
	_refresh_xp_bar()

	points_changed.emit(points)
	xp_changed.emit(xp, next_level)


## Saves written before upgrades were tracked by name stored only the enabled state
## of the five buttons that used to be in main.tscn. A disabled button meant the
## upgrade was either taken or not yet unlocked, so this recovers what it can.
func _recover_taken_from_button_states(loadedDict: Dictionary) -> void:
	if loadedDict.get("bone_sword_button", true) == false:
		taken["bone_pickaxe"] = true
	if loadedDict.get("iron_button", true) == false:
		taken["bone_pickaxe"] = true
		taken["bone_sword"] = true
	if loadedDict.get("bone_turret_button", true) == true:
		taken["bone_turret"] = true
	if loadedDict.get("wood_decor_button", true) == true:
		taken["wood_decor"] = true
