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
	COMBAT: "Survive what the waves send",
	BUILDING: "Shelter, speed and reach",
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


# Every branch is a straight three-node chain: one unlock or bonus per level, each
# gated on the one above it. Straight chains rather than a web are deliberate for
# the early game — the choice worth making is which branch to push, not which of
# five sibling nodes to take first.
func _build() -> void:
	# --- Foraging: the gathering loop is the most-used path in the game, so this
	# branch compounds it. Speed first because it is felt immediately, yield
	# second, and xp last so it pays off over the rest of the run.
	_add(Skill.new(
		"swift_hands", FORAGING, 0,
		"Swift Hands",
		"Gather 15% faster with every pickaxe.",
		"-15% gather time",
		Types.Item.WoodPickaxe, [],
		{"gather_speed_mult": -0.15}
	))
	_add(Skill.new(
		"bountiful", FORAGING, 1,
		"Bountiful Harvest",
		"+25% chance of an extra drop from every node.",
		"+25% extra drops",
		Types.Item.Wood, ["swift_hands"],
		{"bonus_yield_chance": 0.25}
	))
	_add(Skill.new(
		"scholar", FORAGING, 2,
		"Scholar",
		"Earn 25% more XP from everything.",
		"+25% XP",
		Types.Item.Plank, ["bountiful"],
		{"xp_mult": 0.25}
	))

	# --- Industry: the original recipe ladder, unchanged in content. Bone pickaxe
	# opens the tier, iron makes the ore worth mining, smelting turns it into gear.
	_add(Skill.new(
		"bone_pickaxe", INDUSTRY, 0,
		"Bone Pickaxe",
		"Craft the bone pickaxe at the sawmill.",
		"Unlocks a recipe",
		Types.Item.BonePickaxe, [], {},
		[{"product": Types.Item.BonePickaxe, "station": Types.Item.Sawmill}]
	))
	_add(Skill.new(
		"iron_age", INDUSTRY, 1,
		"Iron Age",
		"Coal and iron start appearing. Craft the furnace.",
		"New ore + furnace",
		Types.Item.IronOre, ["bone_pickaxe"], {},
		[{"product": Types.Item.Furnace, "station": Types.Item.Sawmill}],
		[Types.Item.CoalResource, Types.Item.IronResource]
	))
	_add(Skill.new(
		"smelting", INDUSTRY, 2,
		"Smelting",
		"Smelt iron bars, and craft the iron pickaxe.",
		"Unlocks 2 recipes",
		Types.Item.IronBar, ["iron_age"], {},
		[
			{"product": Types.Item.IronBar, "station": Types.Item.Furnace},
			{"product": Types.Item.IronPickaxe, "station": Types.Item.Sawmill},
		]
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
	_add(Skill.new(
		"light_step", BUILDING, 1,
		"Light Step",
		"Move 15% faster.",
		"+15% move speed",
		Types.Item.WoodFloor, ["wood_decor"],
		{"move_speed_mult": 0.15}
	))
	_add(Skill.new(
		"magnetism", BUILDING, 2,
		"Magnetism",
		"Drops are vacuumed in from 60% further away.",
		"+60% pickup range",
		Types.Item.Chest, ["light_step"],
		{"pickup_radius_mult": 0.6}
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
