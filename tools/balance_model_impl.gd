extends RefCounted

## Derives the whole game economy from the live registries and writes it out as JSON.
##
## Run: godot --headless --path . --script res://tools/balance_model.gd
## Out: res://.devtools/balance_model.json
##
## ## Why this exists
##
## Every balance number in this game is data — `Resources.TUNING`, the `items.gd`
## constructor calls, `recipes.gd`, `skill_tree.gd`, `LevelUpManager`'s curve — but none of
## it is stated in the units the player experiences. A recipe says "8 gold bars"; what the
## player feels is "twenty minutes of mining". A skill says "-15% gather time"; what matters
## is whether it beats the tier of pickaxe it competes with for the same hour. Those
## conversions were being done by eye, in a spreadsheet, or not at all.
##
## So this reads the registries the game reads and prints the derived quantities:
## seconds-per-unit per resource per loadout, every recipe expanded to raw materials and
## priced in gather-seconds, the XP curve in nodes rather than points, the land curve in
## kills and veins, and the raid curve against the player's actual damage output.
##
## ## What it is NOT
##
## It is a model of the tuning tables, not a simulation of play. It assumes the player is
## always gathering, never backtracks, and takes the cheapest route to everything. Real
## numbers are therefore floors: a run will always be slower than this says. That is the
## right bias for a balance tool — a curve that is too long HERE is definitely too long in
## the game.
##
## The one place a model assumption is doing real work is `approach_seconds`, which prices
## walking to the next node of a given type off the spawn weights and the node density. It
## is a nearest-neighbour estimate over a Poisson field, and it is stated separately from
## the at-node time everywhere it is used, so a reader can discard it.

const OUT_PATH := "res://.devtools/balance_model.json"

## Node density and player walk speed, for the approach-time estimate.
const NODES_PER_TILE := 0.25   # ResourceManager2.RESOURCE_NODES_PER_LAND_TILE
const TILE_PX := 16.0
const WALK_SPEED := 50.0       # Player.MOVE_SPEED

## The swing. Player/AnimationPlayer's "Attack" is 0.2s and PlayerAttack exits on
## animation_finished, so this is the floor on time-between-swings for a mashing player.
const SWING_SECONDS := 0.2

## Timer defaults that are authored in scenes rather than in script, and so cannot be read
## from a bare registry. Each is checked against its scene by test_balance_model.gd.
const ENEMY_ATTACK_INTERVAL := 1.0   # enemies/*.tscn AttackTimer, unset == Godot's default
const STATION_CRAFT_SECONDS := 1.0   # crafting station output cadence
const RESOURCE_RESPAWN_SECONDS := 24.0  # main.tscn ResourceTimer

var items: Items
var resources: Resources
var recipes
var tree_def: SkillTree
var board: QuestBoard

## product type -> {station, costs}
var recipe_index: Dictionary = {}

## drop item type -> the resource node that drops it
var node_for_drop: Dictionary = {}


func run() -> int:
	_build_registries()

	var out := {
		"generated_by": "tools/balance_model.gd",
		"constants": _constants(),
		"loadouts": _loadouts(),
		"resources": _resources_table(),
		"gather_rates": _gather_rates(),
		"world_flow": _world_flow(),
		"recipes": _recipes_table(),
		"milestones": _milestones(),
		"xp_curve": _xp_curve(),
		"land": _land_curve(),
		"combat": _combat(),
		"raids": _raids(),
		"quests": _quests(),
		"skills": _skills(),
		"findings": _findings(),
	}

	var dir := DirAccess.open("res://")
	if dir != null and not dir.dir_exists(".devtools"):
		dir.make_dir(".devtools")

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("balance_model: cannot open %s" % OUT_PATH)
		return 2
	f.store_string(JSON.stringify(out, "  "))
	f.close()

	# A runtime error inside a method aborts it and hands back the type's default, so an
	# empty table looks exactly like a clean run (the gather-1t9 trap, one layer up). Every
	# section is checked for content before this reports success.
	var empty: Array = []
	for key in ["loadouts", "resources", "gather_rates", "recipes", "milestones", "xp_curve", "land", "raids", "quests", "skills"]:
		if out[key] == null or out[key].size() == 0:
			empty.append(key)
	if not empty.is_empty():
		push_error("balance_model: empty sections %s — something aborted mid-build" % str(empty))
		return 2

	print("balance_model: wrote %s" % OUT_PATH)
	print("resources=%d recipes=%d skills=%d quests=%d findings=%d" % [
		out["resources"].size(), out["recipes"].size(),
		out["skills"].size(), out["quests"].size(), out["findings"].size(),
	])
	return 0


# --- registries ---------------------------------------------------------------


func _build_registries() -> void:
	items = Items.new()
	items._ready()

	resources = Resources.new()
	resources.items = items
	resources._ready()

	recipes = load("res://crafting/recipes.gd").new()
	recipes.furnace_recipes()
	recipes.sawmill_recipes()

	tree_def = SkillTree.new()
	board = QuestBoard.new()

	for station in recipes.master:
		for recipe in recipes.master[station]:
			recipe_index[int(recipe.product)] = {
				"station": int(station),
				"cost_list": recipe.cost_list,
			}

	for type in resources.resources:
		var res: GameResource = resources.resources[type]
		# The berry bush drops berries when picked and itself when uprooted; the drop is
		# the one the loop pays out, which is what a cost is priced against.
		if not node_for_drop.has(int(res.drop)):
			node_for_drop[int(res.drop)] = int(type)


func item_name(type: int) -> String:
	var item := items.get_item(type)
	if item != null:
		return item.name
	var res = resources.resources.get(type)
	if res != null:
		return res.name
	return "type_%d" % type


func _constants() -> Dictionary:
	return {
		"day_length_seconds": WorldClock.DAY_LENGTH_SECONDS,
		"night_fraction": 1.0 - WorldClock.DUSK_END,
		"player_base_health": Player.BASE_MAX_HEALTH,
		"player_walk_speed": WALK_SPEED,
		"starting_sword_damage": (items.get_item(Types.Item.Sword) as GameItemSword).power,
		"min_gather_time": ResourceManager2.MIN_GATHER_TIME,
		"nodes_per_land_tile": NODES_PER_TILE,
		"resource_respawn_seconds": RESOURCE_RESPAWN_SECONDS,
		"xp_first_level": LevelUpManager.XP_FIRST_LEVEL,
		"xp_growth": LevelUpManager.XP_GROWTH,
		"xp_step_cap": LevelUpManager.XP_STEP_CAP,
		"xp_kill": LevelUpManager.XP_KILL,
		"xp_craft": LevelUpManager.XP_CRAFT,
		"xp_land_purchase": LandManager.XP_LAND_PURCHASE,
		"base_coin_drop": Enemy.BASE_COIN_DROP,
		"land_base_cost": LandManager.BASE_COST,
		"land_cost_growth": LandManager.COST_GROWTH,
		"land_max_parcels": LandManager.MAX_PARCELS,
		"skill_tree_total_cost": tree_def.total_cost(),
		"swing_seconds": SWING_SECONDS,
		"enemy_attack_interval": ENEMY_ATTACK_INTERVAL,
	}


# --- loadouts -----------------------------------------------------------------
#
# A loadout is a pickaxe plus a set of taken skills, i.e. everything that decides what one
# gather is worth. Named for the moment in the run they describe rather than for the tool,
# because that is the axis the report is read along.


func _loadout_defs() -> Array:
	return [
		{"id": "opening", "label": "Opening", "pickaxe": Types.Item.WoodPickaxe, "skills": []},
		{"id": "stone", "label": "First craft", "pickaxe": Types.Item.StonePickaxe, "skills": []},
		{"id": "swift", "label": "Swift Hands", "pickaxe": Types.Item.StonePickaxe, "skills": ["swift_hands"]},
		{"id": "copper", "label": "Copper Age", "pickaxe": Types.Item.CopperPickaxe, "skills": ["swift_hands", "bountiful"]},
		{"id": "bone", "label": "Bone tier", "pickaxe": Types.Item.BonePickaxe, "skills": ["swift_hands", "bountiful"]},
		{"id": "iron", "label": "Iron tier", "pickaxe": Types.Item.IronPickaxe, "skills": ["swift_hands", "bountiful"]},
		{"id": "iron_max", "label": "Iron + Motherlode", "pickaxe": Types.Item.IronPickaxe, "skills": ["swift_hands", "bountiful", "scholar", "motherlode"]},
		{"id": "gold", "label": "Gold tier", "pickaxe": Types.Item.GoldPickaxe, "skills": ["swift_hands", "bountiful"]},
		{"id": "gold_max", "label": "Gold + Motherlode", "pickaxe": Types.Item.GoldPickaxe, "skills": ["swift_hands", "bountiful", "scholar", "motherlode"]},
	]


func _stats_for(skill_ids: Array) -> PlayerStats:
	var stats := PlayerStats.new()
	var taken := {}
	for id in skill_ids:
		taken[id] = true
	stats.recompute(taken, tree_def)
	return stats


func _loadouts() -> Array:
	var out := []
	for def in _loadout_defs():
		var stats := _stats_for(def["skills"])
		var pickaxe := items.get_item(def["pickaxe"]) as GameItemPickaxe
		var gather_time: float = maxf(ResourceManager2.MIN_GATHER_TIME, pickaxe.power * stats.gather_speed_mult)
		# _bonus_yield_chance() sums the tool's chance and the player's, and roll_yield
		# spends it on ONE roll — so everything past 1.0 is discarded. Stated as a separate
		# field rather than folded in, because the discard is the finding.
		var raw_bonus: float = pickaxe.bonus_yield_chance + stats.bonus_yield_chance
		out.append({
			"id": def["id"],
			"label": def["label"],
			"pickaxe": pickaxe.name,
			"skills": def["skills"],
			"skill_points": _points_for(def["skills"], int(def["pickaxe"])),
			"level_required": 1 + _points_for(def["skills"], int(def["pickaxe"])),
			"pickaxe_gated_by": _skill_unlocking(int(def["pickaxe"])),
			"pickaxe_power": pickaxe.power,
			"gather_speed_mult": stats.gather_speed_mult,
			"gather_time": gather_time,
			"pickaxe_bonus": pickaxe.bonus_yield_chance,
			"skill_bonus": stats.bonus_yield_chance,
			"bonus_raw": raw_bonus,
			"bonus_effective": minf(raw_bonus, 1.0),
			"bonus_wasted": maxf(0.0, raw_bonus - 1.0),
			"xp_mult": stats.xp_mult,
			"move_speed_mult": stats.move_speed_mult,
		})
	return out


## What a loadout really costs in skill points: the union of the prerequisite closures of the
## skills it names AND of the skill that unlocks its pickaxe.
##
## Summing the named skills alone understates it badly and silently. An "iron tier + the two
## cheap Foraging nodes" loadout reads as 3 points, but the iron pickaxe's recipe is gated
## behind Industry's `smelting`, which is 6 points on its own — so the real ask is 9, and for
## the gold loadouts it is 13 more again. A points column that ignores the tool's own gate
## makes every ore-tier loadout look like an opening-hour purchase.
func _points_for(skill_ids: Array, pickaxe_type: int = -1) -> int:
	var needed := {}
	for id in skill_ids:
		_closure(id, needed)

	var gate := _skill_unlocking(pickaxe_type)
	if gate != "":
		_closure(gate, needed)

	var total := 0
	for id in needed:
		total += tree_def.get_skill(id).cost()
	return total


func _closure(id: String, into: Dictionary) -> void:
	var skill := tree_def.get_skill(id)
	if skill == null or into.has(id):
		return
	into[id] = true
	for requirement in skill.requires:
		_closure(requirement, into)


## The skill whose `recipes` list unlocks `product`, or "" for a day-one or ungated item.
func _skill_unlocking(product: int) -> String:
	if product < 0:
		return ""
	for id in tree_def.order:
		for unlock in tree_def.get_skill(id).recipes:
			if int(unlock["product"]) == product:
				return id
	return ""


# --- resources ----------------------------------------------------------------


## Share of one spawn roll this resource takes, against the set unlocked at `stage`.
func _spawn_shares(unlocked: Array) -> Dictionary:
	var total := 0.0
	for type in unlocked:
		total += (resources.resources[type] as GameResource).spawn_weight
	var shares := {}
	for type in unlocked:
		shares[type] = (resources.resources[type] as GameResource).spawn_weight / total
	return shares


func _unlocked_sets() -> Dictionary:
	var start: Array = ResourceManager2.STARTING_RESOURCES.duplicate()
	var with_iron: Array = start.duplicate()
	with_iron.append(Types.Item.IronResource)
	var with_gold: Array = with_iron.duplicate()
	with_gold.append(Types.Item.GoldResource)
	return {"start": start, "smelting": with_iron, "gold_rush": with_gold}


func _resources_table() -> Array:
	var sets := _unlocked_sets()
	var shares_start := _spawn_shares(sets["start"])
	var shares_gold := _spawn_shares(sets["gold_rush"])

	var out := []
	for type in resources.resources:
		var res: GameResource = resources.resources[type]
		var mean_yield: float = (float(res.yield_min) + float(res.yield_max)) / 2.0
		out.append({
			"type": int(type),
			"name": res.name,
			"drop": item_name(int(res.drop)),
			"xp": res.xp,
			"yield_min": res.yield_min,
			"yield_max": res.yield_max,
			"mean_yield": mean_yield,
			"spawn_weight": res.spawn_weight,
			"share_start": shares_start.get(type, 0.0),
			"share_endgame": shares_gold.get(type, 0.0),
			"is_scene_tile": res.is_scene_tile,
			"secondary_drop": item_name(int(res.secondary_drop)) if res.secondary_drop_chance > 0.0 else "",
			"secondary_chance": res.secondary_drop_chance,
			"unlocked_at_start": sets["start"].has(type),
		})
	out.sort_custom(func(a, b): return a["spawn_weight"] > b["spawn_weight"])
	return out


## Mean nearest-neighbour distance in a Poisson field of density `per_tile`, in seconds of
## walking. 0.5/sqrt(lambda) is the standard estimate; it is an approximation and is
## reported separately from at-node time everywhere it is used.
func _approach_seconds(share: float, move_mult: float) -> float:
	if share <= 0.0:
		return 0.0
	var density: float = NODES_PER_TILE * share
	var tiles: float = 0.5 / sqrt(density)
	return tiles * TILE_PX / (WALK_SPEED * move_mult)


func _gather_rates() -> Array:
	var sets := _unlocked_sets()
	var out := []

	for def in _loadout_defs():
		var stats := _stats_for(def["skills"])
		var pickaxe := items.get_item(def["pickaxe"]) as GameItemPickaxe
		var gather_time: float = maxf(ResourceManager2.MIN_GATHER_TIME, pickaxe.power * stats.gather_speed_mult)
		var bonus: float = minf(pickaxe.bonus_yield_chance + stats.bonus_yield_chance, 1.0)

		# Iron and gold veins only exist once their skill is bought, so the spawn shares a
		# loadout sees depend on the loadout. Anything holding an iron pickaxe has smelting.
		var stage := "start"
		if def["id"].begins_with("gold"):
			stage = "gold_rush"
		elif def["id"].begins_with("iron"):
			stage = "smelting"
		var shares := _spawn_shares(sets[stage])

		var per_resource := {}
		for type in resources.resources:
			var res: GameResource = resources.resources[type]
			if not sets[stage].has(type):
				continue
			var mean_yield: float = (float(res.yield_min) + float(res.yield_max)) / 2.0 + bonus
			var approach: float = _approach_seconds(shares.get(type, 0.0), stats.move_speed_mult)
			per_resource[res.name] = {
				"gather_seconds": gather_time,
				"approach_seconds": approach,
				"mean_yield": mean_yield,
				"seconds_per_unit_at_node": gather_time / mean_yield,
				"seconds_per_unit_with_walk": (gather_time + approach) / mean_yield,
				"units_per_minute": 60.0 / ((gather_time + approach) / mean_yield),
				"xp_per_minute": 60.0 / (gather_time + approach) * float(res.xp) * stats.xp_mult,
			}

		out.append({
			"loadout": def["id"],
			"label": def["label"],
			"stage": stage,
			"per_resource": per_resource,
		})
	return out


# --- world flow ---------------------------------------------------------------
#
# The section that changes how every other number here reads.
#
# Gathering is not what limits a resource. The world holds a fixed STOCK of nodes
# (`resource_cap` == 0.25 per land tile, seeded to 70%) and refills it at a fixed FLOW of
# exactly one node every `ResourceTimer.wait_time` seconds — one, globally, for the whole
# map and every region on it, whatever the player is doing. So the sustainable rate of any
# one resource is that interval divided by its share of the spawn roll, and for the scarce
# end of the table that is a far harder ceiling than anything a pickaxe does.
#
# `land_tiles` is a parameter rather than a constant because it is the one quantity here
# that generation decides: it is read off the running game with the `island_census` devtools
# verb and passed in, and it defaults to the measured home-island figure.


## Measured on the running game with `python tools/devtools.py cmd island_census`, at
## radius 10 (a fresh save) and at radius 34 (all 12 parcels bought). Noise-thresholded land
## is well under the disc area, so these are not pi*r^2 and cannot be derived here.
##
## AMBIENT_TILES is the denominator that actually matters: `ResourceManager2.pick_ambient_region`
## rolls the one respawning node against every region that accepts ambient resources, weighted
## by land tiles — so the mainland's share of the world's whole respawn budget is
## HOME_TILES / AMBIENT_TILES, and the rest is spent on the two small islands. The boss arena
## opts out and is excluded from both.
const HOME_TILES_AT_START := 94
const AMBIENT_TILES_AT_START := 226
const HOME_TILES_AT_MAX := 1644
const AMBIENT_TILES_AT_MAX := 1836


func _world_flow() -> Dictionary:
	var sets := _unlocked_sets()
	var per_stage := {}

	for stage in sets:
		var shares := _spawn_shares(sets[stage])
		var rows := {}
		for type in sets[stage]:
			var res: GameResource = resources.resources[type]
			var share: float = shares[type]
			# One node per interval, of which this type takes `share`.
			var seconds_between: float = RESOURCE_RESPAWN_SECONDS / share
			rows[res.name] = {
				"share": share,
				"seconds_between_spawns": seconds_between,
				# The same figure once the mainland's share of the respawn budget is applied,
				# i.e. what a player standing on their own island actually sees arrive.
				"mainland_seconds_between_spawns_at_start": seconds_between / (float(HOME_TILES_AT_START) / float(AMBIENT_TILES_AT_START)),
				"mainland_seconds_between_spawns_at_max": seconds_between / (float(HOME_TILES_AT_MAX) / float(AMBIENT_TILES_AT_MAX)),
				"nodes_per_hour": 3600.0 / seconds_between,
				# What a node is worth once broken, at the gold-tier bonus.
				"items_per_hour": 3600.0 / seconds_between * ((float(res.yield_min) + float(res.yield_max)) / 2.0 + 1.0),
				# Capped by LandRegion.min_resources (40), which BINDS at the starting radius:
				# 94 tiles * 0.25 is 23, so a fresh island is stocked to 28 nodes, not 16.
				"standing_stock_at_start": maxf(40.0, HOME_TILES_AT_START * NODES_PER_TILE) * 0.7 * share,
				"standing_stock_at_max": maxf(40.0, HOME_TILES_AT_MAX * NODES_PER_TILE) * 0.7 * share,
			}
		per_stage[stage] = rows

	var home_share_start: float = float(HOME_TILES_AT_START) / float(AMBIENT_TILES_AT_START)
	var home_share_max: float = float(HOME_TILES_AT_MAX) / float(AMBIENT_TILES_AT_MAX)

	return {
		"respawn_interval": RESOURCE_RESPAWN_SECONDS,
		# The two numbers the rest of this section is really about. A region already at its
		# node cap DISCARDS its tick rather than passing it on, so once the two small islands
		# have filled — which they do within the first ten minutes and stay that way while the
		# player is anywhere else — the share below is also the fraction of the world's
		# respawn budget that is not simply thrown away.
		"home_share_at_start": home_share_start,
		"home_share_at_max": home_share_max,
		"mainland_seconds_per_node_at_start": RESOURCE_RESPAWN_SECONDS / home_share_start,
		"mainland_seconds_per_node_at_max": RESOURCE_RESPAWN_SECONDS / home_share_max,
		"respawn_interval_in_rain": RESOURCE_RESPAWN_SECONDS * 0.55,
		"nodes_per_hour_total": 3600.0 / RESOURCE_RESPAWN_SECONDS,
		"home_tiles_at_start": HOME_TILES_AT_START,
		"ambient_tiles_at_start": AMBIENT_TILES_AT_START,
		"ambient_tiles_at_max": AMBIENT_TILES_AT_MAX,
		"home_tiles_at_max": HOME_TILES_AT_MAX,
		"cap_at_start": int(maxf(40.0, HOME_TILES_AT_START * NODES_PER_TILE)),
		"cap_at_max": int(maxf(40.0, HOME_TILES_AT_MAX * NODES_PER_TILE)),
		"seeded_at_start": int(maxf(40.0, HOME_TILES_AT_START * NODES_PER_TILE) * 0.7),
		"per_stage": per_stage,
	}


# --- recipes ------------------------------------------------------------------


## Expands `type` into raw inputs. Raw means: something a node drops, something an enemy
## drops, or something with no recipe at all. A recursion guard rather than a cycle check —
## the recipe graph is a DAG today and a cycle here would be a bug worth crashing on, but
## not worth hanging a headless run over.
func _raw_costs(type: int, multiplier: float, into: Dictionary, depth: int = 0) -> void:
	if depth > 12:
		into["OVERFLOW"] = true
		return

	# Node-sourced items are raw even when a recipe also exists (coal has charcoal, string
	# has twine). The recipe is the FLOOR under a bad roll, not the route the model prices —
	# see the charcoal comment in recipes.gd.
	if node_for_drop.has(type) or not recipe_index.has(type):
		into[type] = float(into.get(type, 0.0)) + multiplier
		return

	var costs: Dictionary = recipe_index[type]["cost_list"]
	for input in costs:
		_raw_costs(int(input), multiplier * float(costs[input]), into, depth + 1)


## What one unit of `raw` costs in gather-seconds under `loadout_id`, or -1 when it is not
## something a node hands out (bone, coins).
func _raw_seconds(raw: int, loadout: Dictionary, shares: Dictionary, stats: PlayerStats, gather_time: float, bonus: float) -> float:
	if not node_for_drop.has(raw):
		return -1.0
	var node_type: int = node_for_drop[raw]
	var res: GameResource = resources.resources[node_type]
	var mean_yield: float = (float(res.yield_min) + float(res.yield_max)) / 2.0 + bonus
	var approach: float = _approach_seconds(shares.get(node_type, 0.0), stats.move_speed_mult)
	return (gather_time + approach) / mean_yield


func _recipes_table() -> Array:
	var sets := _unlocked_sets()

	# Everything is priced at ONE reference loadout so recipes are comparable with each
	# other. Iron tier with the two cheap Foraging nodes is the middle of the run and the
	# point most of these recipes are actually crafted at.
	var ref := {"pickaxe": Types.Item.IronPickaxe, "skills": ["swift_hands", "bountiful"]}
	var stats := _stats_for(ref["skills"])
	var pickaxe := items.get_item(ref["pickaxe"]) as GameItemPickaxe
	var gather_time: float = maxf(ResourceManager2.MIN_GATHER_TIME, pickaxe.power * stats.gather_speed_mult)
	var bonus: float = minf(pickaxe.bonus_yield_chance + stats.bonus_yield_chance, 1.0)
	var shares := _spawn_shares(sets["gold_rush"])

	# Which skill unlocks each recipe, so a cost can be read against the tier it is gated at.
	var unlocked_by := {}
	for id in tree_def.order:
		var skill: Skill = tree_def.get_skill(id)
		for unlock in skill.recipes:
			unlocked_by[int(unlock["product"])] = id
	for entry in Recipes_day_one():
		unlocked_by[int(entry)] = "day_one"

	var out := []
	for product in recipe_index:
		var raws := {}
		# Expanded from the recipe's INPUTS rather than by calling _raw_costs on the product:
		# a product that is also node-sourced (charcoal makes Coal Ore, which is also a vein)
		# is raw when it is an input and is not raw when it is the thing being priced.
		for input in recipe_index[product]["cost_list"]:
			_raw_costs(int(input), float(recipe_index[product]["cost_list"][input]), raws)

		var direct := {}
		for input in recipe_index[product]["cost_list"]:
			direct[item_name(int(input))] = recipe_index[product]["cost_list"][input]

		var raw_named := {}
		var seconds := 0.0
		var kills := 0.0
		for raw in raws:
			if typeof(raw) == TYPE_STRING:
				continue
			var qty: float = raws[raw]
			raw_named[item_name(int(raw))] = qty
			var per: float = _raw_seconds(int(raw), ref, shares, stats, gather_time, bonus)
			if per < 0.0:
				# Bone is one per bone-enemy kill; string is 0.5 per spider. Both are
				# reported as kills rather than folded into seconds, because a kill is not
				# a gather and pricing it as one hides the whole combat half of the economy.
				kills += qty if int(raw) == int(Types.Item.Bone) else qty * 2.0
			else:
				seconds += qty * per

		out.append({
			"product": item_name(product),
			"product_type": product,
			"station": item_name(recipe_index[product]["station"]),
			"direct_costs": direct,
			"raw_costs": raw_named,
			"gather_seconds": seconds,
			"kills": kills,
			"unlocked_by": unlocked_by.get(product, "never"),
		})

	out.sort_custom(func(a, b): return a["gather_seconds"] + a["kills"] * 10.0 > b["gather_seconds"] + b["kills"] * 10.0)
	return out


func Recipes_day_one() -> Array:
	var out := []
	for entry in load("res://crafting/recipes.gd").DAY_ONE_RECIPES:
		out.append(entry["product"])
	return out


# --- milestones ---------------------------------------------------------------
#
# What a headline item actually costs in wall-clock minutes, under BOTH ceilings: the time
# spent swinging at nodes, and the time the world takes to grow the nodes in the first
# place. The second is almost always the binding one for anything made of ore, and it is
# invisible in every other table here — a recipe that reads as "48 seconds of gathering" is
# two hours of waiting if its inputs are 1.6% of the spawn roll.


const MILESTONE_ITEMS := [
	Types.Item.StonePickaxe,
	Types.Item.Furnace,
	Types.Item.CopperPickaxe,
	Types.Item.BonePickaxe,
	Types.Item.IronPickaxe,
	Types.Item.GoldPickaxe,
	Types.Item.IronSword,
	Types.Item.GoldSword,
	Types.Item.BoneWorker,
	Types.Item.BoneTurret,
]


func _milestones() -> Array:
	var sets := _unlocked_sets()
	var shares := _spawn_shares(sets["gold_rush"])
	var stats := _stats_for(["swift_hands", "bountiful"])
	var pickaxe := items.get_item(Types.Item.IronPickaxe) as GameItemPickaxe
	var gather_time: float = maxf(ResourceManager2.MIN_GATHER_TIME, pickaxe.power * stats.gather_speed_mult)
	var bonus: float = minf(pickaxe.bonus_yield_chance + stats.bonus_yield_chance, 1.0)
	var home_share: float = float(HOME_TILES_AT_MAX) / float(AMBIENT_TILES_AT_MAX)

	var out := []
	for product in MILESTONE_ITEMS:
		if not recipe_index.has(int(product)):
			continue
		var raws := {}
		for input in recipe_index[int(product)]["cost_list"]:
			_raw_costs(int(input), float(recipe_index[int(product)]["cost_list"][input]), raws)

		var swing_seconds := 0.0
		# The MAXIMUM over the inputs, not the sum. Every type respawns concurrently out of
		# the one global stream — waiting for gold produces coal and wood along the way — so
		# what the player waits for is the single scarcest input, not all of them in series.
		# Summing here overstated the gold pickaxe by a factor of two.
		var respawn_seconds := 0.0
		var binding_raw := ""
		var kills := 0.0
		var per_raw := {}
		for raw in raws:
			if typeof(raw) == TYPE_STRING:
				continue
			var qty: float = raws[raw]
			if not node_for_drop.has(int(raw)):
				kills += qty
				per_raw[item_name(int(raw))] = {"qty": qty, "source": "kills"}
				continue
			var node_type: int = node_for_drop[int(raw)]
			var res: GameResource = resources.resources[node_type]
			var per_node: float = (float(res.yield_min) + float(res.yield_max)) / 2.0 + bonus
			var nodes_needed: float = qty / per_node
			# Swinging: gather time plus the walk to the next one of that type.
			var swing: float = nodes_needed * (gather_time + _approach_seconds(shares.get(node_type, 0.0), stats.move_speed_mult))
			# Waiting: how long the world takes to grow that many of this node ON THE MAINLAND.
			var wait: float = nodes_needed * (RESOURCE_RESPAWN_SECONDS / shares.get(node_type, 1.0)) / home_share
			swing_seconds += swing
			if wait > respawn_seconds:
				respawn_seconds = wait
				binding_raw = item_name(int(raw))
			per_raw[item_name(int(raw))] = {
				"qty": qty,
				"source": res.name,
				"nodes_needed": nodes_needed,
				"swing_minutes": swing / 60.0,
				"respawn_minutes": wait / 60.0,
			}

		out.append({
			"item": item_name(int(product)),
			"raw_costs": per_raw,
			"swing_minutes": swing_seconds / 60.0,
			"respawn_minutes": respawn_seconds / 60.0,
			"kills": kills,
			"binding": "respawn" if respawn_seconds > swing_seconds else "swinging",
			"binding_raw": binding_raw,
			"ratio": (respawn_seconds / swing_seconds) if swing_seconds > 0.0 else 0.0,
			# The far more forgiving reading, and the one a FIRST build of the item actually
			# gets: the island is already stocked when the player arrives, so the opening ask
			# is "how many sweeps of the standing stock is this" rather than "how long until
			# it grows". Anything at or under 1.0 sweep is affordable by clearing the map
			# once; the respawn figure is what the SECOND one costs.
			"sweeps_of_standing_stock": _sweeps_for(raws, bonus, shares),
		})

	out.sort_custom(func(a, b): return a["respawn_minutes"] > b["respawn_minutes"])
	return out


## How many full clearances of the mainland's standing stock a recipe's rarest input costs.
## 1.0 means "exactly one sweep of the island"; above 1.0 means the player must wait for
## regrowth however fast they swing.
func _sweeps_for(raws: Dictionary, bonus: float, shares: Dictionary) -> float:
	var worst := 0.0
	for raw in raws:
		if typeof(raw) == TYPE_STRING or not node_for_drop.has(int(raw)):
			continue
		var node_type: int = node_for_drop[int(raw)]
		var res: GameResource = resources.resources[node_type]
		var per_node: float = (float(res.yield_min) + float(res.yield_max)) / 2.0 + bonus
		var nodes_needed: float = float(raws[raw]) / per_node
		var standing: float = maxf(40.0, HOME_TILES_AT_MAX * NODES_PER_TILE) * 0.7 * shares.get(node_type, 0.0)
		if standing <= 0.0:
			continue
		worst = maxf(worst, nodes_needed / standing)
	return worst


# --- progression --------------------------------------------------------------


func _xp_curve() -> Array:
	var out := []
	for level in range(2, 47):
		var step := LevelUpManager.cost_of_level(level)
		var threshold := LevelUpManager.xp_for_level(level)
		out.append({
			"level": level,
			"step": step,
			"threshold": threshold,
			# A node pays a flat 1 xp, so a step in xp IS a step in nodes for a pure
			# forager. Scholar's +25% is the only thing that moves it.
			"nodes_for_this_level": step,
			"nodes_with_scholar": int(ceil(float(step) / 1.25)),
			"kills_for_this_level": int(ceil(float(step) / float(LevelUpManager.XP_KILL))),
		})
	return out


func _land_curve() -> Array:
	var out := []
	var cumulative := 0
	var cumulative_discounted := 0
	for i in range(LandManager.MAX_PARCELS):
		var cost := LandManager.cost_for_parcel(i, 1.0)
		var discounted := LandManager.cost_for_parcel(i, 0.75)
		cumulative += cost
		cumulative_discounted += discounted
		out.append({
			"parcel": i + 1,
			"cost": cost,
			"cost_with_surveyor": discounted,
			"cumulative": cumulative,
			"cumulative_with_surveyor": cumulative_discounted,
			"radius_after": LandManager.radius_for(i + 1),
			# Every kill pays one coin; a gold vein pays one half the time.
			"kills_for_this_parcel": cost,
			"gold_veins_for_this_parcel": int(ceil(float(cost) / 0.5)),
		})
	return out


# --- combat -------------------------------------------------------------------


func _sword_ladder() -> Array:
	return [Types.Item.Sword, Types.Item.BoneSword, Types.Item.IronSword, Types.Item.GoldSword]


func _combat() -> Dictionary:
	var enemy_stats := {
		"Bone": {"health": 10, "damage": 3},
		"Spider": {"health": 10, "damage": 3},
		"ChargedBone": {"health": 30, "damage": 5},
		"Elite": {"health": 90, "damage": 6},
	}

	var swords := []
	for type in _sword_ladder():
		var sword := items.get_item(type) as GameItemSword
		# +2 from bone_sword is the only damage skill in the tree.
		for bonus in [0, 2]:
			var damage: int = sword.power + bonus
			var row := {
				"sword": sword.name,
				"damage_bonus": bonus,
				"damage": damage,
				"dps_mashing": float(damage) / SWING_SECONDS,
			}
			var ttk := {}
			for enemy in enemy_stats:
				var hits: int = int(ceil(float(enemy_stats[enemy]["health"]) / float(damage)))
				ttk[enemy] = {
					"hits": hits,
					"seconds": float(hits) * SWING_SECONDS,
					# What the enemy does back over that time, at one hit a second.
					"damage_taken_if_adjacent": int(floor(float(hits) * SWING_SECONDS / ENEMY_ATTACK_INTERVAL)) * int(enemy_stats[enemy]["damage"]),
				}
			row["time_to_kill"] = ttk
			swords.append(row)
		# Only the base sword is ever held without the bone_sword skill in practice, but
		# both rows are emitted so the +2's shrinking relevance is visible up the ladder.

	return {
		"enemies": enemy_stats,
		"swords": swords,
		"player_health": {
			"base": Player.BASE_MAX_HEALTH,
			"with_tough_hide": Player.BASE_MAX_HEALTH + 5,
		},
		"heals": {
			"Berry": (items.get_item(Types.Item.Berry) as GameItemConsumable).heal_value,
			"Food": (items.get_item(Types.Item.Food) as GameItemConsumable).heal_value,
			"Bandage": (items.get_item(Types.Item.Bandage) as GameItemConsumable).heal_value,
			"Cooked Food": (items.get_item(Types.Item.CookedFood) as GameItemConsumable).heal_value,
		},
	}


func _raids() -> Array:
	var out := []
	# The elite is 90 health; a raider is a 10-health skeleton scaled by the night.
	for day in range(RaidDirector.FIRST_RAID_NIGHT, 21):
		var size := RaidDirector.size_for_day(day)
		var mult := RaidDirector.health_mult_for_day(day)
		var per_raider := int(round(10.0 * mult))
		out.append({
			"day": day,
			"size": size,
			"health_mult": mult,
			"health_per_raider": per_raider,
			"total_health": size * per_raider,
			"reward_coins": RaidDirector.reward_for_size(size),
			"reward_xp": RaidDirector.xp_for_size(size),
			# Incoming: every raider standing next to the player hits for 3 once a second.
			"incoming_dps_if_all_adjacent": size * 3,
			"arrival_seconds": RaidDirector.TELEGRAPH_SECONDS + float(size - 1) * RaidDirector.SPAWN_STAGGER,
		})
	return out


# --- board and tree -----------------------------------------------------------


func _quests() -> Array:
	var out := []
	var total_coins := 0
	var total_xp := 0
	for id in board.order:
		var quest: Quest = board.get_quest(id)
		total_coins += quest.reward_coins
		total_xp += quest.reward_xp
		out.append({
			"id": quest.id,
			"name": quest.display_name,
			"kind": Quest.Kind.keys()[quest.kind],
			"amount": quest.amount,
			"item": item_name(int(quest.item)) if quest.kind == Quest.Kind.HAVE else "",
			"reward_coins": quest.reward_coins,
			"reward_xp": quest.reward_xp,
			"requires": quest.requires,
			"cumulative_coins": total_coins,
			"cumulative_xp": total_xp,
		})
	return out


func _skills() -> Array:
	var out := []
	for id in tree_def.order:
		var skill: Skill = tree_def.get_skill(id)
		var effects := {}
		for stat in skill.effects:
			effects[stat] = skill.effects[stat]
		out.append({
			"id": skill.id,
			"branch": skill.branch,
			"tier": skill.tier,
			"name": skill.display_name,
			"cost": skill.cost(),
			"cost_to_reach": tree_def.cost_to_reach(id),
			"effects": effects,
			"recipe_count": skill.recipes.size(),
			"resource_count": skill.resources.size(),
			# Which level a player who spends everything on the cheapest route reaches this
			# at: cost_to_reach points == cost_to_reach levels past 1.
			"level_required": 1 + tree_def.cost_to_reach(id),
			"xp_required": LevelUpManager.xp_for_level(1 + tree_def.cost_to_reach(id)),
		})
	return out


# --- the checks worth stating outright ----------------------------------------
#
# Each of these is a question the tables above answer but do not point at. They are emitted
# as data rather than printed so the report and the unit tests read the same values.


func _findings() -> Array:
	var out := []

	# 1. Bonus yield saturates at 1.0 because roll_yield spends it on a single roll.
	for def in _loadout_defs():
		var stats := _stats_for(def["skills"])
		var pickaxe := items.get_item(def["pickaxe"]) as GameItemPickaxe
		var raw: float = pickaxe.bonus_yield_chance + stats.bonus_yield_chance
		if raw > 1.0:
			out.append({
				"id": "bonus_saturation",
				"severity": "high",
				"subject": def["label"],
				"detail": "%s + %s = %.2f extra-drop chance, of which %.2f is discarded: roll_yield() spends it on one roll." % [
					pickaxe.name, str(def["skills"]), raw, raw - 1.0,
				],
			})

	# 2. Does the level the tree gates a skill at match the level a player reaches?
	for id in tree_def.order:
		var skill: Skill = tree_def.get_skill(id)
		var level: int = 1 + tree_def.cost_to_reach(id)
		out.append({
			"id": "skill_level_gate",
			"severity": "info",
			"subject": skill.display_name,
			"detail": "reachable at level %d (%d xp)" % [level, LevelUpManager.xp_for_level(level)],
		})

	# 3. Land against combat: can a player who only fights afford the map?
	var total_land := 0
	for i in range(LandManager.MAX_PARCELS):
		total_land += LandManager.cost_for_parcel(i, 1.0)
	out.append({
		"id": "land_by_combat",
		"severity": "info",
		"subject": "All 12 parcels",
		"detail": "%d coins == %d kills at one coin each, or %d cleared raids at night 9 (56 coins)." % [
			total_land, total_land, int(ceil(float(total_land) / 56.0)),
		],
	})

	return out
