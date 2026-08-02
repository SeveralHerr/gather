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


# Every branch is a straight four-node chain: one unlock or bonus per level, each
# gated on the one above it. Straight chains rather than a web are deliberate for
# the early game — the choice worth making is which branch to push, not which of
# five sibling nodes to take first.
#
# Tier 3 is the capstone row. Every branch ends on something the earlier tiers were
# building towards rather than on one more percentage: Industry ends on gold (the
# ore chain's last link), Combat on coin find, Building on cheaper land, and
# Foraging on a double bonus to the loop it has been compounding all along.
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
		]
	))
	# Iron veins arrive on the same node that can smelt them. Gating the ore one tier
	# below its bar is what used to leave a new player holding iron ore with nowhere to
	# take it for two full tiers; the resource unlock belongs here, not on "iron_age".
	_add(Skill.new(
		"smelting", INDUSTRY, 2,
		"Smelting",
		"Iron veins start appearing. Smelt iron bars, burn wood down to charcoal, craft the iron pickaxe, and build the bone worker.",
		"Iron + 4 recipes",
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
		],
		[Types.Item.IronResource]
	))
	# The last link in the ore chain. Gold is the only node that also pays coins, so
	# this is the node that feeds both the top pickaxe and the land purchase.
	_add(Skill.new(
		"gold_rush", INDUSTRY, 3,
		"Gold Rush",
		"Gold veins start appearing. Alloy gold bars, strike coins, and craft the gold pickaxe.",
		"Gold + 3 recipes",
		Types.Item.GoldBar, ["smelting"], {},
		[
			{"product": Types.Item.GoldBar, "station": Types.Item.Furnace},
			{"product": Types.Item.GoldPickaxe, "station": Types.Item.Sawmill},
			# The mint must sit on this node and no earlier one: gold ore is its input
			# and gold veins only start spawning from here, so unlocking it sooner
			# would hand the player a recipe with an unobtainable ingredient.
			{"product": Types.Item.Coin, "station": Types.Item.Furnace},
		],
		[Types.Item.GoldResource]
	))

	# --- Combat: bone_sword used to be a dead node that granted nothing at all
	# (gather-tsc). It is now the branch's damage step.
	_add(Skill.new(
		"bone_sword", COMBAT, 0,
		"Bone Sword",
		"+2 damage on every swing.",
		"+2 damage",
		Types.Item.Sword, [],
		{"damage_bonus": 2}
	))
	_add(Skill.new(
		"tough_hide", COMBAT, 1,
		"Tough Hide",
		"+5 max health, and heal for the difference now.",
		"+5 max HP",
		Types.Item.Bone, ["bone_sword"],
		{"max_health_bonus": 5}
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
	_add(Skill.new(
		"surveyor", BUILDING, 3,
		"Surveyor",
		"Every new parcel of land costs 25% less gold.",
		"-25% land cost",
		Types.Item.Ground, ["magnetism"],
		{"land_cost_mult": -0.25}
	))


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
