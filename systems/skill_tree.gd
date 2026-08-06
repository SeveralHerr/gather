class_name SkillTree
# RefCounted so tests can build the whole tree with SkillTree.new() without a
# SceneTree. LevelUpManager owns the one instance the game uses.
extends RefCounted

## Branch ids. Order here is the left-to-right column order in the panel.
const FORAGING := "Foraging"
const INDUSTRY := "Industry"
const COMBAT := "Combat"
const BUILDING := "Building"

const BRANCHES := [FORAGING, INDUSTRY, COMBAT, BUILDING]

## One colour per branch, used for node borders, titles and the connector lines.
const BRANCH_COLORS := {
	FORAGING: Color("6fcf6a"),
	INDUSTRY: Color("e0a33c"),
	COMBAT: Color("e05a4f"),
	BUILDING: Color("58a8e0"),
}

## Blurb under each branch title in the panel.
const BRANCH_TAGLINES := {
	FORAGING: "Gather faster, gather more",
	INDUSTRY: "Ore, fire and better tools",
	# Combat used to promise surviving "what the waves send". Waves are gone, and the
	# branch now ends on coin find, so it reads as damage-and-loot instead.
	COMBAT: "Hit harder, loot richer",
	BUILDING: "Shelter, speed and new land",
}

var skills: Dictionary = {}

## Insertion order, so the UI and the tests iterate the tree deterministically
## rather than in Dictionary hash order.
var order: Array[String] = []


func _init():
	_build()


func _add(skill: Skill) -> void:
	skills[skill.id] = skill
	order.append(skill.id)


# Every branch is a straight chain: one unlock or bonus per tier, each gated on the one
# above it. Straight chains rather than a web are deliberate for the early game — the
# choice worth making is which branch to push, not which of five sibling nodes to take
# first. Three branches are four nodes deep; Industry is five, because the mint was split
# off gold_rush (see there).
#
# A skill's tier is also its price: Skill.cost() is tier+1, so a capstone is four points
# and Industry's mint is five. Depth is the dial this tree is paced on — the XP curve was
# deliberately left alone, so the opening (one point, 40 XP, any tier-0 node) is unchanged
# and only the far end got expensive.
#
# Tier 3 is the capstone row. Every branch ends on something the earlier tiers were
# building towards rather than on one more percentage: Industry ends on gold and then the
# coins struck from it, Combat on coin find, Building on cheaper land, and Foraging on a
# double bonus to the loop it has been compounding all along.
#
# Prerequisites are normally the node directly above. gold_rush is the one exception and
# names a second, cross-branch one; the panel cannot draw a connector for that, so anything
# reading this tree must treat `requires` as a set rather than as "the node above".
func _build() -> void:
	# --- Foraging: the gathering loop is the most-used path in the game, so this
	# branch compounds it. Speed first because it is felt immediately, yield
	# second, and xp last so it pays off over the rest of the run.
	_add(Skill.new(
		"swift_hands", FORAGING, 0,
		"Swift Hands",
		"Gather 15% faster with every pickaxe, and build a second sawmill.",
		"-15% gather time",
		Types.Item.WoodPickaxe, [],
		{"gather_speed_mult": -0.15},
		# A station produces one item per second, so a second sawmill is throughput,
		# not decoration. It hangs off the branch's first node because the player is
		# handed exactly one sawmill at the start and nothing else ever grants another.
		[{"product": Types.Item.Sawmill, "station": Types.Item.Sawmill}]
	))
	_add(Skill.new(
		"bountiful", FORAGING, 1,
		"Bountiful Harvest",
		"+25% chance of an extra drop from every node, and spin twine from wood.",
		"+25% extra drops",
		Types.Item.Wood, ["swift_hands"],
		{"bonus_yield_chance": 0.25},
		# String otherwise drops from spiders and nowhere else, which left the whole
		# Combat tier-2 unlock hostage to which enemy the spawner rolled.
		[{"product": Types.Item.String, "station": Types.Item.Sawmill}]
	))
	_add(Skill.new(
		"scholar", FORAGING, 2,
		"Scholar",
		"Earn 25% more XP from everything.",
		"+25% XP",
		Types.Item.Plank, ["bountiful"],
		{"xp_mult": 0.25}
	))
	# The capstone deliberately repeats the two stats this branch opened with rather
	# than introducing a fourth one. Foraging's whole pitch is the gather loop, and a
	# second helping of speed and drops on top of the first is what "compounding"
	# means here — by this point the player is holding an iron or gold pickaxe, so the
	# percentages land on a much bigger number than they did at tier 0.
	_add(Skill.new(
		"motherlode", FORAGING, 3,
		"Motherlode",
		"Gather another 10% faster, and another 25% chance of an extra drop.",
		"Faster + more drops",
		Types.Item.Stone, ["scholar"],
		{"gather_speed_mult": -0.10, "bonus_yield_chance": 0.25}
	))

	# --- Industry: the recipe ladder. Bone pickaxe opens the tier, the furnace turns the
	# copper already on the island into gear, and smelting is what puts iron on the map.
	_add(Skill.new(
		"bone_pickaxe", INDUSTRY, 0,
		"Bone Pickaxe",
		"Craft the bone pickaxe at the sawmill.",
		"Unlocks a recipe",
		Types.Item.BonePickaxe, [], {},
		[{"product": Types.Item.BonePickaxe, "station": Types.Item.Sawmill}]
	))
	# The id stays "iron_age" — it is in LEGACY_IDS and in every save's taken set, so
	# renaming it would silently drop the skill on load. Its *content* is repointed:
	# coal and copper spawn from the first frame (see ResourceManager2), so this node
	# no longer opens a resource at all. It is the furnace and the copper gear to put
	# through it — the ore is already lying on the island when the player gets here.
	_add(Skill.new(
		"iron_age", INDUSTRY, 1,
		"Copper Age",
		"Build the furnace, smelt the copper you have been mining into bars, and cut a copper pickaxe.",
		"Furnace + copper gear",
		Types.Item.CopperOre, ["bone_pickaxe"], {},
		[
			{"product": Types.Item.Furnace, "station": Types.Item.Sawmill},
			{"product": Types.Item.CopperBar, "station": Types.Item.Furnace},
			{"product": Types.Item.CopperPickaxe, "station": Types.Item.Sawmill},
			# Cooking arrives with the furnace, because it is the first reason to visit one
			# that is not metal (gather-cte).
			{"product": Types.Item.CookedFood, "station": Types.Item.Furnace},
		]
	))
	# Iron veins arrive on the same node that can smelt them. Gating the ore one tier
	# below its bar is what used to leave a new player holding iron ore with nowhere to
	# take it for two full tiers; the resource unlock belongs here, not on "iron_age".
	_add(Skill.new(
		"smelting", INDUSTRY, 2,
		"Smelting",
		"Iron veins start appearing. Smelt iron bars, burn wood down to charcoal, craft the iron pickaxe, and build the bone and stone workers.",
		"Iron + 5 recipes",
		Types.Item.IronBar, ["iron_age"], {},
		[
			{"product": Types.Item.IronBar, "station": Types.Item.Furnace},
			{"product": Types.Item.IronPickaxe, "station": Types.Item.Sawmill},
			# Charcoal lands here rather than at the furnace's own tier because this is
			# the node that doubles coal consumption: from now on a bad roll on coal
			# veins stalls the branch, and wood is the one thing never in short supply.
			{"product": Types.Item.CoalOre, "station": Types.Item.Furnace},
			# The bone worker rides this node instead of getting one of its own, the way
			# the stone set rides light_step: every branch is a four-node chain and
			# Industry's four slots are the ore ladder, which the worker is not part of.
			# Tier 2 is nonetheless the right rung for it. It is the branch's first piece
			# of automation and three points deep, so it cannot be an opening-hour buy;
			# and pricing it in iron bars here means the recipe and its material arrive on
			# the same purchase, rather than the hidden cross-tier dependency the bone
			# turret's costs had to be repriced to escape.
			{"product": Types.Item.BoneWorker, "station": Types.Item.Sawmill},
			# Both workers ride the one node. They are the same machine pointed at different
			# resources, so splitting them across two purchases would price a pair the player
			# will always want together as though it were two decisions.
			{"product": Types.Item.StoneWorker, "station": Types.Item.Sawmill},
			# The iron bar had exactly one buyer (the pickaxe) for the whole branch, and the
			# brick gives fired stone a home on the tier that already doubles coal use
			# (gather-cte).
			{"product": Types.Item.IronSword, "station": Types.Item.Sawmill},
			{"product": Types.Item.StoneBrick, "station": Types.Item.Furnace},
		],
		[Types.Item.IronResource]
	))
	# The last link in the ore chain, and the node the whole tree used to be rushed for.
	#
	# It sat four points deep in a single branch, every one of them priced at one point, so
	# a player who spent their first four levels here had gold veins — and therefore the
	# coins land is bought with — inside 68 XP. Two things now stand in the way, and they
	# are deliberately different in kind (`gather-7p4`):
	#
	#   - Depth costs. Skill.cost() is tier+1, so this branch alone is 1+2+3+4 = 10 points.
	#   - Breadth is required. `light_step` is the cross-branch prerequisite: Building is
	#     the branch about new land, and gold is what land is paid for, so the player who
	#     wants the map to grow has to have started growing it. That is another 1+2 points
	#     and, more to the point, another branch's opening tier.
	#
	# `light_step` rather than `surveyor` (the land-cost node) on purpose — requiring a
	# tier-3 capstone as a prerequisite for a tier-3 capstone would be 10 points of
	# Building, and the gate is meant to force breadth, not a second full branch.
	#
	# Note this is NOT a lock on the land economy: every enemy kill drops a coin
	# (Enemy.BASE_COIN_DROP), so land stays buyable from the first minute by fighting for
	# it. What this gates is the *fast* route — mining the currency directly.
	_add(Skill.new(
		"gold_rush", INDUSTRY, 3,
		"Gold Rush",
		"Gold veins start appearing. Alloy gold bars and craft the gold pickaxe and sword.",
		"Gold + 3 recipes",
		Types.Item.GoldBar, ["smelting", "light_step"], {},
		[
			{"product": Types.Item.GoldBar, "station": Types.Item.Furnace},
			{"product": Types.Item.GoldPickaxe, "station": Types.Item.Sawmill},
			# Same reasoning as the iron sword one tier down: the gold bar fed only the
			# pickaxe and the mint, and the capstone should arm the player as well as tool
			# them.
			{"product": Types.Item.GoldSword, "station": Types.Item.Sawmill},
		],
		[Types.Item.GoldResource]
	))
	# The mint is its own tier, one rung past the ore that feeds it.
	#
	# It used to ride gold_rush, which meant the purchase that put gold veins on the map
	# was the same purchase that turned them into currency — find a vein, mint a coin, buy
	# land, all off one node. Splitting them puts a gap in between where the player is
	# mining gold and spending it on bars and tools while land is still bought the hard
	# way, which is the pacing this whole pass is for.
	#
	# It is the only tier-4 node in the tree, so Industry's column runs one card longer
	# than the other three. That raggedness is intentional and is why
	# test_skill_tree.EXPECTED_TIERS became a per-branch minimum: the ore ladder is the
	# game's spine and it earns the extra rung.
	_add(Skill.new(
		"minting", INDUSTRY, 4,
		"Minting",
		"Strike gold coins at the furnace, so the land you buy is mined rather than fought for.",
		"Strike coins",
		Types.Item.Coin, ["gold_rush"], {},
		[
			# Gold ore is the input and gold veins only spawn from the tier above, so this
			# recipe cannot be unlocked any earlier without handing the player a recipe
			# whose ingredient does not exist yet.
			{"product": Types.Item.Coin, "station": Types.Item.Furnace},
		]
	))

	# --- Combat: bone_sword used to be a dead node that granted nothing at all
	# (gather-tsc). It is now the branch's damage step.
	_add(Skill.new(
		"bone_sword", COMBAT, 0,
		"Bone Sword",
		"+2 damage on every swing, and craft the bone sword itself.",
		"+2 damage, a sword",
		Types.Item.Sword, [],
		{"damage_bonus": 2},
		# The node was named for a sword the player could never make (gather-cte). Combat had
		# no craftable of its own at all — every node was a stat bump or a turret — so the
		# branch that fights crafted nothing at its own stations.
		[{"product": Types.Item.BoneSword, "station": Types.Item.Sawmill}]
	))
	_add(Skill.new(
		"tough_hide", COMBAT, 1,
		"Tough Hide",
		"+5 max health, heal for the difference now, and bind bandages from string.",
		"+5 max HP, bandages",
		Types.Item.Bone, ["bone_sword"],
		{"max_health_bonus": 5},
		# Sustain lands on the survivability node, and costs string — which spiders drop — so
		# the branch that fights is the branch that heals.
		[{"product": Types.Item.Bandage, "station": Types.Item.Sawmill}]
	))
	_add(Skill.new(
		"bone_turret", COMBAT, 2,
		"Bone Turret",
		"Craft turrets and nets at the sawmill.",
		"Unlocks 2 recipes",
		Types.Item.BoneTurret, ["tough_hide"], {},
		[
			{"product": Types.Item.BoneTurret, "station": Types.Item.Sawmill},
			{"product": Types.Item.Net, "station": Types.Item.Sawmill},
		]
	))
	# Combat's payout tier. Killing things is otherwise the one loop that does not
	# feed the economy, and coins are what land costs — so this is the branch's answer
	# to "why fight instead of mine".
	_add(Skill.new(
		"plunder", COMBAT, 3,
		"Plunder",
		"+25% chance of an extra gold coin from anything that drops one.",
		"+25% coin find",
		Types.Item.Coin, ["bone_turret"],
		{"coin_find_bonus": 0.25}
	))

	# --- Building: shelter first, then the two quality-of-life passives that make
	# roaming between nodes cheaper.
	_add(Skill.new(
		"wood_decor", BUILDING, 0,
		"Wood Decor",
		"Craft wooden floors, walls and doors.",
		"Unlocks 3 recipes",
		Types.Item.WoodWall, [], {},
		[
			{"product": Types.Item.WoodFloor, "station": Types.Item.Sawmill},
			{"product": Types.Item.WoodWall, "station": Types.Item.Sawmill},
			{"product": Types.Item.WoodDoor, "station": Types.Item.Sawmill},
		]
	))
	# The stone set hangs off this node rather than getting one of its own: the branch
	# only has four slots and the wall/floor pair is a material upgrade to what tier 0
	# already unlocked, not a new capability. It lands here rather than on wood_decor
	# so the first purchase still teaches planks before stone makes them optional.
	_add(Skill.new(
		"light_step", BUILDING, 1,
		"Light Step",
		"Move 15% faster, and build in stone as well as wood.",
		"+15% speed, stone set",
		Types.Item.StoneWall, ["wood_decor"],
		{"move_speed_mult": 0.15},
		[
			{"product": Types.Item.StoneFloor, "station": Types.Item.Sawmill},
			{"product": Types.Item.StoneWall, "station": Types.Item.Sawmill},
		]
	))
	_add(Skill.new(
		"magnetism", BUILDING, 2,
		"Magnetism",
		"Drops are vacuumed in from 60% further away.",
		"+60% pickup range",
		Types.Item.Chest, ["light_step"],
		{"pickup_radius_mult": 0.6}
	))
	# land_cost_mult multiplies the price of the next parcel, so the effect is a
	# NEGATIVE delta on a base of 1.0 — PlayerStats sums deltas onto BASE, giving
	# 0.75. Written as +0.25 it would make land more expensive.
	#
	# What the 25% is worth moves with LandManager.COST_GROWTH, and it moved: buying all
	# twelve parcels behind this node saves ~950 coins at 1.45, where it saved ~1740 at
	# 1.55. Still the largest single coin saving in the tree and still most of a late
	# parcel, but the retune flattened the tail this node was mostly discounting, so it is
	# no longer a node that pays for itself several times over on its own.
	_add(Skill.new(
		"surveyor", BUILDING, 3,
		"Surveyor",
		"Every new parcel of land costs 25% less gold.",
		"-25% land cost",
		Types.Item.Ground, ["magnetism"],
		{"land_cost_mult": -0.25}
	))


## What every skill in the tree costs put together — the number of skill points, and so
## the number of levels, a run needs to clear it. Derived rather than stated so it cannot
## drift from the definitions above; test_player_stats prices the run off this.
func total_cost() -> int:
	var total := 0
	for id in order:
		total += skills[id].cost()
	return total


## What the cheapest route to `id` costs in points, including the prerequisites it drags
## in — the honest price of a node, as opposed to the number on its own card.
##
## Walks `requires` transitively and sums each distinct skill once, which is what makes a
## cross-branch prerequisite show up in the figure at all: gold_rush's own card says 4, and
## the chain behind it (Industry 1+2+3 plus Building 1+2) makes the real ask 13.
func cost_to_reach(id: String) -> int:
	var needed := {}
	_collect_prerequisites(id, needed)

	var total := 0
	for skill_id in needed:
		total += skills[skill_id].cost()
	return total


func _collect_prerequisites(id: String, into: Dictionary) -> void:
	if into.has(id) or not skills.has(id):
		return
	into[id] = true
	for requirement in skills[id].requires:
		_collect_prerequisites(requirement, into)


func get_skill(id: String) -> Skill:
	return skills.get(id)


func has_skill(id: String) -> bool:
	return skills.has(id)


## Skills in one branch, ordered by tier — the panel's column contents.
func branch_skills(branch: String) -> Array:
	var result: Array = []
	for id in order:
		if skills[id].branch == branch:
			result.append(skills[id])
	result.sort_custom(func(a, b): return a.tier < b.tier)
	return result


## Not taken, and every prerequisite already taken.
func is_available(id: String, taken: Dictionary) -> bool:
	if not skills.has(id) or taken.has(id):
		return false

	for requirement in skills[id].requires:
		if not taken.has(requirement):
			return false

	return true


func has_any_available(taken: Dictionary) -> bool:
	for id in order:
		if is_available(id, taken):
			return true
	return false


## The prerequisites of `id` that are still missing, as display names — what the
## detail pane shows instead of a bare "locked".
func missing_requirements(id: String, taken: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	if not skills.has(id):
		return missing

	for requirement in skills[id].requires:
		if not taken.has(requirement) and skills.has(requirement):
			missing.append(skills[requirement].display_name)

	return missing
