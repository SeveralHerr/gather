extends RefCounted

## What the themed islands are actually made of.
##
## IslandManager.ISLANDS carries a spawn-weight override per island, and reading that table
## is a poor way to know what the island plays like. Two things make the printed numbers
## misleading. The roll only ever considers UNLOCKED resources, so an island whose theme
## leans on copper and gold is unthemed for the whole stretch before the mining skills are
## bought - which is most of the time the player spends reaching it. And weight is relative,
## so a type listed once but present twice counts twice: stone is two entries
## (StoneResource and the scene-backed StoneResourceTest), and a "modest" 4.0 on each
## outweighed every ore on the ore island put together.
##
## So these sample ResourceManager2.get_random itself - the same function the seeder and the
## respawn timer call - rather than re-deriving the arithmetic, and they do it once for the
## starting unlocked set and once for the fully unlocked one.

const SAMPLES := 4000

## Copper and gold sit behind skills; everything else is available from the first frame.
const FULLY_UNLOCKED := [Types.Item.CopperResource, Types.Item.GoldResource]

var _T

var manager: ResourceManager2


func setup() -> void:
	seed(20260802)
	manager = ResourceManager2.new()


func teardown() -> void:
	if manager:
		manager.free()
		manager = null


## A stand-in node carrying the one field the roll reads. Only `type` and `spawn_weight`
## matter here; the sound argument is left at its default because it would otherwise pull
## from the GameSoundManager autoload, which the headless runner does not instantiate.
func _resource(type: Types.Item) -> GameResource:
	var resource := GameResource.new(
		Vector2i.ZERO, 0, type, 1, false, "Test Node", Vector2i.ZERO, false, Types.Item.X
	)
	resource.spawn_weight = float(Resources.TUNING.get(type, {}).get("spawn_weight", 1.0))
	return resource


## Populates the manager's unlocked set directly. ResourceManager2 is built with .new() and
## never enters the tree, so _ready has not run and curent_resources starts empty - which is
## what makes the unlocked set a parameter of the test rather than a fixed fact.
func _unlock(types: Array) -> void:
	manager.curent_resources = []
	for type in types:
		manager.curent_resources.append(_resource(type))


## How often SAMPLES rolls on `island` come up as one of `wanted`.
func _share_of(island: String, wanted: Array) -> float:
	var weights: Dictionary = IslandManager._definition_for(island)["weights"]
	var hits := 0

	for i in SAMPLES:
		var rolled: GameResource = manager.get_random(weights)
		if rolled != null and wanted.has(rolled.type):
			hits += 1

	return float(hits) / float(SAMPLES)


func _theme_of(island: String) -> Array:
	return IslandManager.ISLAND_THEMES[island]


func test_forest_island_is_overwhelmingly_trees() -> String:
	_unlock(ResourceManager2.STARTING_RESOURCES)
	var share := _share_of("forest", _theme_of("forest"))

	return _T.assert_gte(
		share, IslandManager.ISLAND_THEME_SHARE,
		"the forest island rolled trees %.1f%% of the time, under the %.1f%% it promises"
			% [share * 100.0, IslandManager.ISLAND_THEME_SHARE * 100.0]
	)


## The case that regressed: before copper and gold are unlocked the ore island's only ores
## are coal and iron, and it is stone that has to stay out of their way.
func test_ore_island_is_overwhelmingly_ore_before_any_mining_skill() -> String:
	_unlock(ResourceManager2.STARTING_RESOURCES)
	var share := _share_of("ore", _theme_of("ore"))

	return _T.assert_gte(
		share, IslandManager.ISLAND_THEME_SHARE,
		"the ore island rolled ore %.1f%% of the time with only coal and iron unlocked, under the %.1f%% it promises"
			% [share * 100.0, IslandManager.ISLAND_THEME_SHARE * 100.0]
	)


func test_ore_island_stays_ore_once_copper_and_gold_unlock() -> String:
	_unlock(ResourceManager2.STARTING_RESOURCES + FULLY_UNLOCKED)
	var share := _share_of("ore", _theme_of("ore"))

	return _T.assert_gte(
		share, IslandManager.ISLAND_THEME_SHARE,
		"the fully unlocked ore island rolled ore only %.1f%% of the time" % [share * 100.0]
	)


## A weight of 0.0 has to mean never, not rarely - it is the only thing keeping ordinary
## trees off the ore island and ore out of the grove.
func test_zeroed_types_never_appear() -> String:
	_unlock(ResourceManager2.STARTING_RESOURCES + FULLY_UNLOCKED)

	var trees_on_ore := _share_of("ore", [Types.Item.Tree])
	var failure: String = _T.assert_eq(trees_on_ore, 0.0, "a tree spawned on the ore island")
	if failure != "":
		return failure

	return _T.assert_eq(
		_share_of("forest", _theme_of("ore")), 0.0, "an ore node spawned in the forest grove"
	)


## IslandManager.theme_share is what the tuning comments claim; this is the claim being
## held to the function the game actually rolls with, so the two cannot drift apart.
func test_declared_share_matches_what_the_roll_does() -> String:
	for island in IslandManager.ISLAND_THEMES:
		var unlocked: Array = ResourceManager2.STARTING_RESOURCES + FULLY_UNLOCKED
		_unlock(unlocked)

		var declared := IslandManager.theme_share(island, unlocked)
		var sampled := _share_of(island, _theme_of(island))
		var failure: String = _T.assert_true(
			abs(declared - sampled) < 0.03,
			"%s declares a %.1f%% themed share but rolls %.1f%%"
				% [island, declared * 100.0, sampled * 100.0]
		)
		if failure != "":
			return failure

	return ""
