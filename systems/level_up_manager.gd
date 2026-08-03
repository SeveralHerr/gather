extends Node
class_name LevelUpManager

## Progression model. This node draws nothing — it owns xp, levels, banked skill
## points and the taken set, and SkillTreeUi renders it.
##
## It lived under Player/Camera2D/UI as an invisible Control until `gather-ue3`,
## purely because saveObject() keys off get_path() and every saveFile written before
## then referred to it there. SaveLoad.LEGACY_PATHS carries that history now, so the
## node sits in `Systems` with the rest of the model and is a plain Node again.

signal added_xp(amount: int)
signal xp_changed(xp: int, next_level: int)
signal level_gained(level: int)
signal points_changed(points: int)
signal skill_learned(skill: Skill)

@onready var resource_manager: ResourceManager2 = $"../ResourceManager"

## The HUD's XP bar. Resolved lazily rather than with an @onready sibling path: the
## bar hangs off the camera (Player/Camera2D/HUD/PlayerInfo) and this node no longer
## does, so there is no fixed relative path between them — and the player may not
## exist yet when this readies. Cached once found.
var _xp_bar: ProgressBar


func _xp_bar_node() -> ProgressBar:
	if is_instance_valid(_xp_bar):
		return _xp_bar
	var player := PlayerManager.player
	if player == null:
		return null
	_xp_bar = player.get_node_or_null("Camera2D/HUD/PlayerInfo/XpBar") as ProgressBar
	return _xp_bar

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
##
## That last sentence was wrong, and 10/1.30 is what it cost (`gather-1n2`). A new player
## banked six skill points within minutes of starting: the thresholds are cumulative — xp
## is never reset — so they ran 10, 13, 17, 23, 30, 39, and a node pays a flat 1 xp. Six
## points for under forty nodes reads as confetti, not progression, and the tree was fully
## visible before the player had learned what any of it did.
##
## Every previous pass turned the growth rate because that was the dial that fixed the
## tail. The opening is the other end of the curve and growth barely touches it, so this
## pass moves the base instead — and *lowers* growth to pay for it, because compounding is
## what would otherwise turn a high base into a four-figure tree. 40 with 1.19:
##
##   first point  10 -> 40 XP     the tree now appears after a real stretch of mining
##   sixth point   39 -> 100 XP   2.6x slower, which is the whole point of this pass
##   whole tree   561 -> 578 XP   +3%, i.e. still the same one long run it was
##
## 35/1.20 was the first proposal and lands the six-point mark at 90 (2.3x) — the tail is
## equivalent, the opening is the thing being fixed, and 100 sits in the middle of the
## intended band rather than under it. The whole-tree figure is what is actually being
## held constant here; test_the_whole_tree_is_reachable_in_one_run's bound is unmoved at
## 650 because 578 did not need it moved, and a bound that only ever follows the dial is
## not a guard.
const XP_FIRST_LEVEL := 40
const XP_GROWTH := 1.19

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
##   A PICKUP pays NOTHING. It used to pay 1 xp every third drop, on the reasoning that
##   loot is part of a gather's income. That was wrong twice over. The drop was already
##   paid for when the node was broken, so collecting it paid a second time for one act;
##   and PickUpManager mints drops from more than node yields - crafted products, enemy
##   loot, and DestroyManager handing back the very tile a build just paid for. Worse, it
##   was the wrong FEEL: the vacuum sweeps a yield in about a second, so the xp splash
##   spent a gather counting items off the floor rather than reacting to the swing that
##   earned them. See items/pick_up.gd, where the award used to live.
##
## `gather-1n2` raised the thresholds and deliberately left this table alone. Every value
## here is priced against a node's 1 xp, so scaling the curve scales all five together and
## the ratios above still say what they said — retuning them as well would have been two
## dials moving at once for one symptom.
##
## Place-destroy-repeat was the other faucet this table used to leak through: DestroyManager
## hands the tile back, so a cycle cost nothing and paid XP_BUILD every time. `gather-5s5`
## fixed it where it lived rather than by retuning here - building pays per CELL now, once
## ever (see built_cells) - and dropping the pickup award closed the second half of it.
const XP_KILL := 3
const XP_CRAFT := 2
const XP_BUILD := 1

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

## Cells that have already paid XP_BUILD, as a set of Vector2i. Saved.
##
## XP_BUILD's premise is that a placed tile is the tail end of a chain that has already
## paid out — it was gathered or crafted first. DestroyManager breaks that premise by
## handing the tile straight back as a pickup, so place/destroy/repeat on one cell minted
## ~1.33 xp a cycle (1 for the placement, ~0.33 amortised for the returned drop) off a
## single item, forever, with no gathering at all. `gather-5s5`.
##
## Paying per cell rather than per placement is the narrowest fix that keeps building
## worth xp: the first tile on a given cell pays, and re-placing there never does again.
## Rebuilding elsewhere still pays, because that is a player expanding rather than
## farming a loop.
##
## Deliberately NOT cleared when a tile is destroyed — a cleared entry is exactly the
## exploit. The set only grows, and it is bounded by the buildable area: LandManager caps
## the island at radius_for(MAX_PARCELS), a few thousand cells, so this cannot run away.
var built_cells: Dictionary = {}


func _ready():
	add_to_group("LevelUpManager")
	add_to_group("SaveLoad")

	# Push the skill totals into the player. This node used to be a descendant of
	# Player and therefore readied first, so player.gd:_ready had to pull them
	# instead; from `Systems` it readies *after* Player and can push directly.
	# Both halves are kept on purpose — together they are order-independent, and
	# the ordering here is a property of sibling declaration order in main.tscn,
	# which is exactly the kind of thing a later edit changes without noticing.
	sync_player_stats()

	_refresh_xp_bar()


func _refresh_xp_bar() -> void:
	var bar := _xp_bar_node()
	if bar == null:
		return
	bar.max_value = next_level
	bar.value = xp


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
	# "An award happened", as distinct from xp_changed's "the total moved". Nothing listens
	# to it today: the corner XpLabel that used to was a second "+N xp" on screen competing
	# with the world splash, and it was deleted rather than restyled. The signal stays
	# because a single award is a genuinely different event from a total, and the splash
	# below is the one view of it.
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


## Awards XP_BUILD for a tile placed on `cell`, once ever per cell. Returns the xp
## actually granted, so 0 means "this cell has been built on before".
##
## Every placement still costs the player an item whether or not it pays — the stack is
## decremented by PlayerManager.place_tile long before this is reached. Building on a
## used cell is not blocked, it just stops being an xp source.
func award_build_xp(cell: Vector2i, world_position: Vector2 = Vector2.INF) -> int:
	if built_cells.has(cell):
		return 0
	built_cells[cell] = true
	return add_xp(XP_BUILD, world_position)


func _player_position() -> Vector2:
	var player := PlayerManager.player
	return player.global_position if player else Vector2.ZERO


## Level-ups are announced in the world, at the player, and the player keeps control: the
## panel is opened with K when they choose to. This deliberately does not restore the old
## behaviour of seizing the screen the instant a threshold is crossed.
##
## It does now cost more than two labels, because the event costs more than it used to. The
## curve retune (`gather-1n2`) moved the sixth skill point from 39 XP to 100, so a banked
## point went from something that arrived every couple of minutes to a genuine milestone —
## and a milestone announced exactly as loudly as a "+1 XP" is a milestone the player learns
## to ignore.
func _splash_level_up() -> void:
	var at := _player_position()
	SplashText.spawn(self, at, "LEVEL %d!" % level, SplashText.COLOR_LEVEL, SplashText.Emphasis.BIG)

	Juice.shake(self, Juice.Shake.MEDIUM)
	# Screen space, so the UI CanvasLayer. Gold, brief and low-alpha: this washes over a game
	# a child is looking directly at, so it announces rather than blinds.
	ScreenFlash.flash(self, Juice.LEVEL_UP_FLASH_COLOR, Juice.LEVEL_UP_FLASH_ALPHA, Juice.LEVEL_UP_FLASH_TIME)

	_splash_skill_point()


## The second half of the announcement, a beat later. Both labels used to spawn on the same
## frame and were told apart only by SplashText's vertical stagger, which made one event with
## two consequences read as one two-line block of text. Landing them in sequence is what makes
## the point feel *earned by* the level rather than printed alongside it.
##
## A SceneTreeTimer rather than an `await` in _splash_level_up, because that method is called
## from inside add_xp's threshold loop: making it a coroutine would suspend the loop, and a
## burst of xp crossing two thresholds has to award both points on the same frame.
func _splash_skill_point() -> void:
	var tree := get_tree()
	if tree == null:
		return

	var timer := tree.create_timer(Juice.LEVEL_UP_POINT_DELAY)
	timer.timeout.connect(_on_skill_point_splash_due)


func _on_skill_point_splash_due() -> void:
	# The timer outlives this node in principle (scene change, a load between the two halves),
	# and SplashText.spawn needs a source that is still in the tree.
	if not is_inside_tree():
		return
	SplashText.spawn(self, _player_position(), "+1 SKILL POINT", SplashText.COLOR_POINT, SplashText.Emphasis.BIG)


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
		# "x,y" strings rather than the Vector2i keys themselves: entries are
		# JSON-stringified individually (see SaveLoad), and JSON has no vector type — a
		# raw key would come back as the string "(3, -7)" and never match a cell again,
		# silently re-opening the faucet on the first load.
		"built_cells": _built_cells_saved(),
	}
	return dict


func _built_cells_saved() -> Array:
	var out := []
	for cell in built_cells:
		out.append("%d,%d" % [cell.x, cell.y])
	return out


func loadObject(loadedDict: Dictionary) -> void:
	# The only two raw indexes left in an otherwise fully-defaulted method. Both keys have
	# existed since the beginning, but an abort here happens BEFORE sync_player_stats()
	# below, so the player would load with the saved skill set applying none of its effects
	# (gather-xc0).
	xp = int(loadedDict.get("xp", 0))
	next_level = int(loadedDict.get("next_level", next_level))
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

	# Absent in every save written before gather-5s5, which loads as an empty ledger. That
	# is the right default: it hands a returning player one more xp per cell they have
	# already built on, which is bounded and one-off, where defaulting the other way would
	# need a list of cells the save does not contain.
	built_cells = {}
	for key in loadedDict.get("built_cells", []):
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() == 2:
			built_cells[Vector2i(int(parts[0]), int(parts[1]))] = true

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
