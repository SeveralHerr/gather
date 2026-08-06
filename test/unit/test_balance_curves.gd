extends RefCounted

## Pins the balance CURVES — the numbers that decide how fast the game can be played and
## whether the things it sells are worth buying. Every other balance test in the suite asks
## whether a chain is connected (test_ore_chain) or whether a tier is better than the one
## below (test_progression). These ask a different question: whether the number a tuning edit
## writes is the number the player actually receives.
##
## The failure mode they guard is silent by construction. Nothing errors when a stat is
## bought and discarded, nothing errors when the respawn interval is retuned, and nothing
## errors when a price curve walks the map out of a combat player's reach. The game keeps
## running and simply stops paying for something the player was charged for.
##
## Two of these tests are EXPECTED TO FAIL against the current tuning. They are the finding,
## not a regression to be papered over — see test_no_loadout_wastes_extra_drop_chance and
## test_the_foraging_capstone_still_does_something. Weakening either of them deletes the only
## record that the Foraging capstone is half dead.

var _T

var items: Items
var resources: Resources
var recipes


## The pickaxe ladder in ascending order. Adding a tier means adding it here, which is the
## point — the invariants below then cover it without anyone remembering to write a test.
## test_progression covers the first three tiers pairwise; this list is the whole ladder,
## because the saturation question can only be asked of the tool at the TOP of it.
const PICKAXE_LADDER := [
	Types.Item.WoodPickaxe,
	Types.Item.StonePickaxe,
	Types.Item.CopperPickaxe,
	Types.Item.BonePickaxe,
	Types.Item.IronPickaxe,
	Types.Item.GoldPickaxe,
]

## Where the single extra-drop roll saturates. GameResource.roll_yield() spends the whole
## accumulated chance on one `randf() < bonus_chance`, and randf() returns [0.0, 1.0] — so
## 1.0 is already a guaranteed extra drop and every point past it buys exactly nothing.
const EXTRA_DROP_ROLL_CEILING := 1.0

## How many samples the mechanism proof draws. 400 is far past the point where a real
## difference between a 1.0 chance and a 2.0 chance would show up if there were one.
const ROLL_SAMPLES := 400

const MAIN_SCENE := "res://main.tscn"


func setup() -> void:
	# Autoloads do not exist under the headless --script runner, so the three registries are
	# built by hand the way test_progression and test_ore_chain do it.
	items = Items.new()
	items._ready()

	resources = Resources.new()
	resources.items = items
	resources._ready()

	recipes = load("res://crafting/recipes.gd").new()
	recipes.furnace_recipes()
	recipes.workbench_recipes()


func _pickaxe(type: Types.Item) -> GameItemPickaxe:
	return items.get_item(type) as GameItemPickaxe


## Every point of `bonus_yield_chance` a whole branch hands out, summed. Read off the tree
## rather than restated, so a skill retuned or added is covered without editing this.
func _branch_bonus_yield(tree: SkillTree, branch: String) -> float:
	var total := 0.0
	for skill in tree.branch_skills(branch):
		total += float(skill.effects.get("bonus_yield_chance", 0.0))
	return total


# --- 1. the saturation finding ------------------------------------------------


## The big one, and the reason this file exists.
##
## ResourceManager2._bonus_yield_chance() ADDS the pickaxe's bonus_yield_chance to the
## player's stats.bonus_yield_chance, and GameResource.roll_yield() then spends that single
## total on a single `randf() < bonus_chance`. There is no second roll and no overflow into
## a second extra drop, so the whole sum is clamped at 1.0 by the shape of the comparison —
## silently, with no warning, no log line and nothing on screen that looks different.
##
## Today the Foraging branch hands out 0.50 (Bountiful Harvest 0.25 + Motherlode 0.25) and a
## Gold Pickaxe carries 0.75, so a player who buys the branch they were sold as "compounds
## the gather loop" is holding 1.25 and receiving 1.00. A quarter of it is thrown away, and
## the discarded quarter is the four-point capstone at the end of the branch.
##
## THIS TEST IS EXPECTED TO FAIL. The failure is the deliverable. It can be made green by
## retuning (drop Motherlode's yield half, or lower the gold tier), or by making roll_yield
## spend chance above 1.0 on a second drop — but not by deleting the assertion, which is the
## only place the arithmetic is written down.
func test_no_loadout_wastes_extra_drop_chance() -> String:
	var tree := SkillTree.new()
	var branch_chance := _branch_bonus_yield(tree, SkillTree.FORAGING)

	for type in PICKAXE_LADDER:
		var pickaxe := _pickaxe(type)
		if pickaxe == null:
			return _T.assert_true(false, "a pickaxe tier is not registered in items.gd")

		var total: float = pickaxe.bonus_yield_chance + branch_chance
		if total > EXTRA_DROP_ROLL_CEILING:
			return _T.assert_true(false,
				("%s (%.2f) plus the whole Foraging branch (%.2f) is %.2f extra-drop chance, "
				+ "but roll_yield spends it on ONE randf() roll — %.2f of it is discarded. "
				+ "That is the branch's %d-point capstone buying nothing for this loadout.")
					% [
						pickaxe.name,
						pickaxe.bonus_yield_chance,
						branch_chance,
						total,
						total - EXTRA_DROP_ROLL_CEILING,
						tree.get_skill("motherlode").cost(),
					])
	return ""


## The mechanism the test above is about, proved directly rather than argued from the source.
##
## This one PASSES, and it is what makes the failure above readable: a reader who thinks
## "surely 1.25 chance means a 25% shot at a second extra drop" can see here that 1.0 and 2.0
## are literally the same number to roll_yield. If someone later teaches roll_yield to spend
## overflow on a second drop, THIS test goes red — which is the correct place for that change
## to be noticed, because it is a change to what every pickaxe in the game does.
func test_roll_yield_discards_chance_past_one() -> String:
	# A fixed-yield probe rather than a live resource: the point is the bonus roll, and a
	# node whose base yield varies would hide it in the noise. Iron happens to be 1/1 today,
	# which is exactly the kind of coincidence this should not lean on.
	var probe := GameResource.new(
		Vector2i.ZERO, 4, Types.Item.Tree, 1, false, "Probe", Vector2i.ZERO, false, Types.Item.Wood
	)
	probe.yield_min = 1
	probe.yield_max = 1

	for _i in ROLL_SAMPLES:
		var at_ceiling := probe.roll_yield(EXTRA_DROP_ROLL_CEILING)
		var past_ceiling := probe.roll_yield(EXTRA_DROP_ROLL_CEILING * 2.0)

		if at_ceiling != 2 or past_ceiling != 2:
			return _T.assert_true(false,
				("roll_yield on a 1/1 node returned %d at chance %.1f and %d at chance %.1f — "
				+ "both should be a guaranteed 2, i.e. identical")
					% [at_ceiling, EXTRA_DROP_ROLL_CEILING, past_ceiling, EXTRA_DROP_ROLL_CEILING * 2.0])

	return ""


# --- 2. the ladder, once saturation is accounted for ---------------------------


## Every rung of the pickaxe ladder has to be a real upgrade on BOTH axes, measured in what
## the player receives rather than in what the constructor was passed.
##
## test_progression already asserts the raw numbers climb across the first three tiers. The
## difference here is `minf(..., 1.0)`: a tier whose extra number lands past the roll ceiling
## is a sidegrade dressed as an upgrade, and the raw comparison cannot tell the two apart. It
## passes today because no pickaxe alone reaches 1.0 — the ceiling is only hit once skills are
## added on top — and that is worth pinning, because "the tool ladder is fine on its own" is
## precisely the fact that makes the failure above a SKILL TREE problem rather than a pickaxe
## one.
func test_every_pickaxe_tier_is_a_real_upgrade() -> String:
	for i in range(1, PICKAXE_LADDER.size()):
		var lower := _pickaxe(PICKAXE_LADDER[i - 1])
		var upper := _pickaxe(PICKAXE_LADDER[i])
		if lower == null or upper == null:
			return _T.assert_true(false, "a pickaxe tier is not registered in items.gd")

		# power is a gather TIME, so lower is better.
		if upper.power >= lower.power:
			return _T.assert_true(false,
				"%s gathers in %.2fs, no faster than %s at %.2fs"
					% [upper.name, upper.power, lower.name, lower.power])

		var lower_effective: float = minf(lower.bonus_yield_chance, EXTRA_DROP_ROLL_CEILING)
		var upper_effective: float = minf(upper.bonus_yield_chance, EXTRA_DROP_ROLL_CEILING)
		if upper_effective <= lower_effective:
			return _T.assert_true(false,
				("%s yields an effective %.2f extra-drop chance against %s's %.2f — "
				+ "no better once the single roll is capped at %.2f")
					% [upper.name, upper_effective, lower.name, lower_effective, EXTRA_DROP_ROLL_CEILING])
	return ""


# --- 3. the capstone --------------------------------------------------------


## Motherlode is the dearest node in the Foraging branch and the last thing a forager buys.
## Every stat it touches has to still be worth something to the player most likely to have
## reached it — the one holding the best pickaxe in the game.
##
## The weaker form of this rule ("it changes at least ONE stat that is not saturated") is
## satisfied today and is the version with no teeth: it stays green while half a four-point
## capstone pays nothing, which is exactly the state the branch is in. This is the same
## lesson as test_ore_chain's CRAFTED_HEAL_MULTIPLE — a bare "improves at all" bar passed for
## a recipe that improved by two points for a station, fuel and fifty kills.
##
## THIS TEST IS EXPECTED TO FAIL, on the yield half only. The message names both halves,
## because the fix is a retune of one of them and not a deletion of the node: -10% gather
## time on a 0.45s pickaxe is real and is doing its job.
func test_the_foraging_capstone_still_does_something() -> String:
	var tree := SkillTree.new()
	var capstone: Skill = tree.get_skill("motherlode")
	if capstone == null:
		return _T.assert_true(false, "the Foraging capstone 'motherlode' is not in the tree")

	var best := _pickaxe(PICKAXE_LADDER[PICKAXE_LADDER.size() - 1])
	if best == null:
		return _T.assert_true(false, "the top pickaxe tier is not registered in items.gd")

	# Everything in the branch except the capstone itself — i.e. what the player is already
	# carrying at the moment they consider buying it.
	var before := PlayerStats.new()
	var taken := {}
	for skill in tree.branch_skills(SkillTree.FORAGING):
		if skill.id != capstone.id:
			taken[skill.id] = true
	before.recompute(taken, tree)

	var yield_before: float = best.bonus_yield_chance + before.bonus_yield_chance
	var yield_gain: float = capstone.effects.get("bonus_yield_chance", 0.0)
	var yield_effective: float = minf(yield_before + yield_gain, EXTRA_DROP_ROLL_CEILING) \
		- minf(yield_before, EXTRA_DROP_ROLL_CEILING)

	var speed_gain: float = capstone.effects.get("gather_speed_mult", 0.0)
	# gather_speed_mult multiplies the pickaxe's gather time, and ResourceManager2 floors the
	# result at MIN_GATHER_TIME — so this half is dead too if the tool is already at the floor.
	var speed_before: float = maxf(best.power * before.gather_speed_mult, ResourceManager2.MIN_GATHER_TIME)
	var speed_after: float = maxf(
		best.power * (before.gather_speed_mult + speed_gain), ResourceManager2.MIN_GATHER_TIME
	)
	var speed_effective: float = speed_before - speed_after

	if yield_effective <= 0.0 or speed_effective <= 0.0:
		var dead: String = "%.0f%% gather time" % (speed_gain * 100.0)
		var alive: String = "+%.2f extra-drop chance" % yield_gain
		if yield_effective <= 0.0:
			dead = "+%.2f extra-drop chance" % yield_gain
			alive = "%.0f%% gather time (%.2fs -> %.2fs)" % [speed_gain * 100.0, speed_before, speed_after]
		return _T.assert_true(false,
			("%s costs %d points and half of it is dead for a %s player: its %s buys nothing, "
			+ "because the extra-drop chance is already %.2f before it (%s %.2f + the rest of "
			+ "the branch %.2f) and roll_yield caps a single roll at %.2f. The other half, %s, "
			+ "still works.")
				% [
					capstone.display_name,
					capstone.cost(),
					best.name,
					dead,
					yield_before,
					best.name,
					best.bonus_yield_chance,
					before.bonus_yield_chance,
					EXTRA_DROP_ROLL_CEILING,
					alive,
				])
	return ""


# --- 4. scarcity as the player meets it ---------------------------------------


## Rarity in descending order of how often the player should trip over the thing.
##
## Stated as an ordering rather than as numbers because spawn_weight is relative and means
## nothing on its own — "coal 1.05" is not a fact about the world until it is compared to
## what else is in the roll. The order has to track the crafting tier: the two starter
## building materials first, the berry bush (the free heal) next, then the ore ladder
## coal -> copper -> iron -> gold, which is the order the furnace and the skill tree meet
## them in. test_ore_chain pins the three metals against each other; this pins the whole
## table, including the non-ore entries the ore comparisons cannot see.
const SCARCITY_ORDER := [
	[Types.Item.Tree, Types.Item.StoneResource, Types.Item.StoneResourceTest],
	[Types.Item.BerryBush],
	[Types.Item.CoalResource],
	[Types.Item.CopperResource],
	[Types.Item.IronResource],
	[Types.Item.GoldResource],
]

## Stone's share of a spawn roll on a fresh island, as a floor.
##
## Stone is two entries in the table (StoneResource and the scene-backed StoneResourceTest)
## and neither number says anything alone, so this is the only form the fact takes: nearly
## half of everything a new player finds is stone. That is deliberate — stone is what the
## walls, floors and bricks are priced in, and the stone recipes assume the player is
## drowning in it. If a weight edit quietly drops this, those recipes become expensive
## without anyone having repriced them, and nothing else in the project would report it.
##
## Held as a lower bound rather than a band because the failure only points one way: more
## stone is a wasted roll, less stone silently reprices half the Building branch.
const STONE_SHARE_FLOOR := 0.40

## The stone entries, kept next to the constant they are about.
const STONE_TYPES := [Types.Item.StoneResource, Types.Item.StoneResourceTest]


func test_a_scarce_resource_is_scarce_in_the_world_not_just_in_the_table() -> String:
	# Part one: the ordering. Every tier has to be strictly rarer than the one above it,
	# and every entry within a tier equally common.
	for i in range(1, SCARCITY_ORDER.size()):
		var commoner: Array = SCARCITY_ORDER[i - 1]
		var rarer: Array = SCARCITY_ORDER[i]

		for common_type in commoner:
			for rare_type in rarer:
				# .resources.get() rather than .Get(): Get indexes the dictionary directly, so a
				# miss raises — and a raise inside a -> String test is scored as a pass.
				var common: GameResource = resources.resources.get(common_type)
				var rare: GameResource = resources.resources.get(rare_type)
				if common == null or rare == null:
					return _T.assert_true(false, "a resource in SCARCITY_ORDER is not registered")

				if common.spawn_weight <= rare.spawn_weight:
					return _T.assert_true(false,
						("%s spawns at weight %.2f and %s at %.2f — the crafting tier says %s "
						+ "should be the commoner of the two")
							% [common.name, common.spawn_weight, rare.name, rare.spawn_weight, common.name])

	# Part two: what that ordering is actually worth on a fresh island. Rolled against
	# ResourceManager2.STARTING_RESOURCES rather than the whole table, because iron and gold
	# are not in the world yet and including them would understate every early share.
	var total := 0.0
	var stone := 0.0
	for type in ResourceManager2.STARTING_RESOURCES:
		var resource: GameResource = resources.resources.get(type)
		if resource == null:
			return _T.assert_true(false, "a starting resource is not registered")
		total += resource.spawn_weight
		if STONE_TYPES.has(type):
			stone += resource.spawn_weight

	if total <= 0.0:
		return _T.assert_true(false, "the starting spawn roll has no weight in it at all")

	var share := stone / total
	return _T.assert_gte(share, STONE_SHARE_FLOOR,
		("stone is %.1f%% of a starting spawn roll (%.2f of %.2f weight), under the %.0f%% the "
		+ "stone recipes are priced against")
			% [share * 100.0, stone, total, STONE_SHARE_FLOOR * 100.0])


# --- 5. the flow the whole game runs at ---------------------------------------


## How often the world puts one node back PER AMBIENT REGION, in seconds. Read out of
## main.tscn rather than restated, so retuning the scene is what this test notices.
const RESPAWN_INTERVAL := 24.0

## Nodes per land tile, and the floor under a region's ceiling. Both are the stock side of
## the same equation: the interval above says how fast the world refills, these say how full
## it is allowed to get.
const NODES_PER_LAND_TILE := 0.25
const REGION_MIN_RESOURCES := 40


## The three numbers that decide how fast this game can be played, pinned together because
## they are only meaningful together.
##
## Everything the player does is bounded by how quickly nodes come back: the skill tree is
## priced in gathers, the recipes are priced in drops, and land is priced in coins that come
## out of gold veins. One node every 24 seconds is therefore the real ceiling on the whole
## run, and nothing else in the suite mentions it — the interval lives in main.tscn as a
## Timer property, which no test reads and no linter checks.
##
## That interval is now what the MAINLAND receives, not what the map receives. The tick used
## to be one node globally, rolled onto one region weighted by land tiles, so the island the
## player stands on saw roughly 24s / its share of the world's grass — about 58s on a fresh
## save, and the rest of the budget was spent on islands that were already full. It is one
## node per eligible region per tick now; see ResourceSpawnTimer._on_timeout, and the two
## tests below it for the behaviour that used to be wrong.
##
## The wait_time is PARSED OUT OF THE SCENE rather than hardcoded here. A hardcoded copy
## would assert that this file still says 24.0, which is a fact about this file; parsing is
## what makes it a fact about the game.
func test_the_respawn_flow_is_the_real_ceiling() -> String:
	var wait_time := _scene_timer_wait_time("ResourceTimer")
	if wait_time < 0.0:
		return _T.assert_true(false,
			"could not find a wait_time under [node name=\"ResourceTimer\"] in %s" % MAIN_SCENE)

	var err: String = _T.assert_float_eq(wait_time, RESPAWN_INTERVAL, 0.001,
		("World/ResourceTimer puts one node back per ambient region every %.1fs in main.tscn, "
		+ "not %.1fs — that is the ceiling on how fast the whole run can be played")
			% [wait_time, RESPAWN_INTERVAL])
	if err != "":
		return err

	err = _T.assert_float_eq(
		ResourceManager2.RESOURCE_NODES_PER_LAND_TILE, NODES_PER_LAND_TILE, 0.001,
		"the live-node density per land tile"
	)
	if err != "":
		return err

	# The default region's floor, not the home region's configured one: a region that never
	# sets min_resources gets this, and a small island capped generously is how a themed
	# grove erodes back into the mainland.
	var region := LandRegion.new()
	err = _T.assert_eq(region.min_resources, REGION_MIN_RESOURCES,
		"a region with no configured floor holds at least this many nodes")
	if err != "":
		return err

	# Two copies of the same number live in two files (ResourceManager2's constant and
	# LandRegion's default), and two copies can disagree. They are the same dial.
	return _T.assert_float_eq(
		region.resource_density, ResourceManager2.RESOURCE_NODES_PER_LAND_TILE, 0.001,
		"LandRegion's default density and ResourceManager2's constant are the same dial"
	)


## The `wait_time` of a named Timer in main.tscn, or -1.0 if there is no such node or it
## carries no wait_time. Reads the scene as text: a headless test cannot instance main.tscn
## (it would run world generation), and the value is a plain property line either way.
func _scene_timer_wait_time(node_name: String) -> float:
	var source: String = FileAccess.get_file_as_string(MAIN_SCENE)
	if source.length() == 0:
		return -1.0

	var inside := false
	for raw in source.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("["):
			# A new section header always ends the previous node's property block, so an
			# absent wait_time can never be answered with the next node's.
			inside = line.begins_with("[node") and line.contains('name="%s"' % node_name)
			continue
		if inside and line.begins_with("wait_time"):
			var parts: PackedStringArray = line.split("=")
			if parts.size() < 2:
				return -1.0
			return float(parts[1].strip_edges())
	return -1.0


# --- 5b. where that flow actually lands ---------------------------------------
#
# The interval above says how OFTEN a node comes back. These say WHERE, which turned out to
# be the half that was wrong: the tick was global, it was rolled onto one region weighted by
# land tiles, and a region already at its cap declined without the tick falling through to a
# region that had room. Both halves of that are silent — a discarded tick logs nothing and
# looks exactly like a world that regrows slowly.


const SPAWN_TIMER_SCRIPT := "res://world/resource_spawn_timer.gd"


## A TileMapHandler with the tilemap taken out.
##
## The real one answers count_land_tiles_in() by walking every used cell of a generated
## world, which a headless test has none of. Everything else the eligibility rule touches —
## `regions`, `home_region`, `island_regions`, LandRegion.accepts_ambient_resources() — is
## the live code, so what is under test here is the real filter and not a restatement of it.
class StubHandler extends TileMapHandler:
	## Land tiles per region id. A region absent from this reads as zero tiles, which is
	## itself one of the cases the filter has to reject.
	var tiles := {}

	func count_land_tiles_in(region: LandRegion) -> int:
		return int(tiles.get(region.id, 0))


## A ResourceManager2 that records what the tick offered it instead of writing to a tilemap.
##
## Only add_random_resource() is replaced. ambient_regions() is the shipping implementation,
## so a change that re-derived eligibility inside the timer — the thing that would quietly
## start restocking the boss arena — fails these rather than passing them.
class SpawnProbe extends ResourceManager2:
	## Region ids that are already at their node cap, i.e. that will decline.
	var full := {}

	## Region ids the tick called add_random_resource() for, and the subset that took a node.
	var offered: Array = []
	var placed: Array = []

	func add_random_resource(region: LandRegion = null) -> bool:
		# A null region here would mean the timer had fallen back to the global roll, which
		# is the behaviour these tests exist to rule out. Recorded rather than crashed on:
		# a raise inside a -> bool method returns false and would look like a full region.
		if region == null:
			offered.append("<global>")
			return false
		offered.append(region.id)
		if full.has(region.id):
			return false
		placed.append(region.id)
		return true


func _region(id: String, ambient: bool = true) -> LandRegion:
	var region := LandRegion.new()
	region.id = id
	region.ambient_resources = ambient
	return region


## Wires a probe onto a stub world and fires exactly one ResourceTimer timeout through the
## real _on_timeout(). Frees both nodes, including ResourceManager2's orphan hold_timer —
## it is created in a member initializer and never enters a tree here, so nothing else would.
func _tick_once(probe: SpawnProbe, handler: StubHandler) -> void:
	probe.tile_map_handler = handler

	var timer = load(SPAWN_TIMER_SCRIPT).new()
	timer.resourceManager = probe
	timer._on_timeout()
	timer.free()


func _release(probe: SpawnProbe, handler: StubHandler) -> void:
	if probe.hold_timer != null:
		probe.hold_timer.free()
	probe.free()
	handler.free()


## The bug this whole change was about, stated as behaviour rather than as arithmetic.
##
## An island at its cap declines — that part is correct and unchanged. What was wrong is that
## its decline ENDED THE TICK: add_random_resource() with no region picked one region weighted
## by land tiles and returned false if that region was full, with no fall-through. The two
## small islands fill up within about ten minutes and stay full, so from then on most of the
## world's respawn budget was being spent on ground that could not take it, and the mainland —
## the only region the player is ever standing on — went hungry for a reason no screen shows.
func test_a_full_region_does_not_eat_another_regions_respawn_tick() -> String:
	var handler := StubHandler.new()
	handler.home_region.id = "home"
	handler.island_regions.append(_region("forest"))
	handler.tiles = {"home": 94, "forest": 66}

	var probe := SpawnProbe.new()
	# The steady state of a real run: the small island is long since full.
	probe.full["forest"] = true

	_tick_once(probe, handler)
	var offered: Array = probe.offered.duplicate()
	var placed: Array = probe.placed.duplicate()
	_release(probe, handler)

	var err: String = _T.assert_true(not offered.has("<global>"),
		"the respawn tick fell back to the un-regioned global roll, which is what it is here to replace")
	if err != "":
		return err

	err = _T.assert_true(offered.has("forest") and offered.has("home"),
		("one respawn tick offered a node to %s — it has to offer one to EVERY region that "
		+ "accepts ambient resources, so that a full one declining costs the others nothing")
			% [str(offered)])
	if err != "":
		return err

	return _T.assert_eq(placed, ["home"],
		("the forest island was at its cap and the mainland was not, yet the tick placed %s. "
		+ "A full region must decline its own node without consuming the tick a region with "
		+ "room could have used")
			% [str(placed)])


## The other half of the rule, and the one a well-meant simplification would break.
##
## The boss arena is kept bare by LandRegion.accepts_ambient_resources() and by nothing else
## — there is no code anywhere that knows what a boss is. A region with no land under it is
## excluded for a duller reason: get_random_tile_in() has nothing to return, so offering it a
## node is a wasted call every 24 seconds forever.
func test_the_respawn_tick_never_offers_a_node_to_a_region_that_opted_out() -> String:
	var handler := StubHandler.new()
	handler.home_region.id = "home"
	handler.island_regions.append(_region("boss_arena", false))
	handler.island_regions.append(_region("unbuilt"))
	# The arena has plenty of grass, which is exactly why the flag rather than the tile count
	# has to be what excludes it. "unbuilt" is registered but has no cells yet.
	handler.tiles = {"home": 94, "boss_arena": 120, "unbuilt": 0}

	var probe := SpawnProbe.new()

	_tick_once(probe, handler)
	var offered: Array = probe.offered.duplicate()
	_release(probe, handler)

	var err: String = _T.assert_true(not offered.has("boss_arena"),
		("the respawn tick offered a node to the region that sets ambient_resources = false "
		+ "(it offered %s) — that flag is the only thing keeping the boss arena clear")
			% [str(offered)])
	if err != "":
		return err

	err = _T.assert_true(not offered.has("unbuilt"),
		"the respawn tick offered a node to a region with no land tiles, which can never take one")
	if err != "":
		return err

	return _T.assert_eq(offered, ["home"],
		"exactly the eligible regions get a tick, once each; got %s" % [str(offered)])


# --- 6. the second route to land ----------------------------------------------


## The whole map, bought entirely with coins dropped by kills.
##
## Land is the only thing in the game that gates content rather than convenience: the three
## pregenerated islands sit on a ring inside radius_for(MAX_PARCELS) and are reached by
## buying the coastline out to meet them, so a player who cannot afford the parcels cannot
## reach a third of the map at all. Mining gold is the fast route and is gated behind
## Industry's capstone; fighting is the route that is open from the first minute
## (Enemy.BASE_COIN_DROP), and it has to stay a route rather than a technicality.
##
## Stated as a ceiling on KILLS because that is the unit the player pays in. Today's curve
## (BASE_COST 20, COST_GROWTH 1.45) asks 3,795. A retune that pushes past this ceiling has
## not made land dearer; it has deleted the combat route to it, and nothing else in the
## project would report that.
##
## 5000 rather than the 8000 it was: 8000 was sized against the old 1.55 curve's ~6,955 and
## kept about 15% headroom over it. Growth came down to 1.45 and left the ceiling three
## thousand kills above anything the game can charge — a guard with that much slack passes
## for a curve nobody would ship. 5000 restores roughly the same proportion of headroom
## (~30%) against the curve that actually exists, so this still fails on a real runaway
## rather than only on an absurd one. It is a ceiling on *reachability*, not a target: land
## getting cheaper is never what this test is meant to catch.
const KILLS_FOR_THE_WHOLE_MAP := 5000


func test_land_is_reachable_by_fighting_as_well_as_mining() -> String:
	var err: String = _T.assert_gt(Enemy.BASE_COIN_DROP, 0,
		"every kill pays at least one coin, or there is no combat route to land at all")
	if err != "":
		return err

	# cost_mult 1.0: the honest, undiscounted price. Surveyor's -25% is a reward for having
	# gone down the Building branch and must not be assumed by the baseline.
	var total := 0
	for i in LandManager.MAX_PARCELS:
		total += LandManager.cost_for_parcel(i, 1.0)

	var kills := int(ceil(float(total) / float(Enemy.BASE_COIN_DROP)))

	return _T.assert_true(kills <= KILLS_FOR_THE_WHOLE_MAP,
		("all %d parcels cost %d coins, which is %d kills at %d coin per kill — past the %d "
		+ "this game considers a reachable map for a player who fights for it")
			% [LandManager.MAX_PARCELS, total, kills, Enemy.BASE_COIN_DROP, KILLS_FOR_THE_WHOLE_MAP])
