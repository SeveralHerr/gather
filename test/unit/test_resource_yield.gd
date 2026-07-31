extends RefCounted

## Covers the gather reward maths on GameResource: how many items a node drops, how a
## pickaxe tier bonus lands on top of that, and the odds on the secondary drop.

var _T

var tree_node: GameResource


func _make_resource(drop: Types.Item) -> GameResource:
	# The sound argument is left at its default: it pulls from the GameSoundManager
	# autoload, which is not instantiated under the headless --script runner.
	return GameResource.new(
		Vector2i(1, 0), 4, Types.Item.Tree, 1, false, "Test Node",
		Vector2i.ZERO, false, drop
	)


func setup() -> void:
	seed(20240730)
	tree_node = _make_resource(Types.Item.Wood)


func test_default_yield_is_one() -> String:
	return _T.assert_eq(tree_node.roll_yield(), 1, "an untuned node drops a single item")


func test_yield_stays_inside_configured_range() -> String:
	tree_node.yield_min = 2
	tree_node.yield_max = 4

	for i in 200:
		var rolled := tree_node.roll_yield()
		if rolled < 2 or rolled > 4:
			return _T.assert_true(false, "roll %d landed outside 2..4" % rolled)

	return ""


func test_bonus_chance_can_exceed_the_base_maximum() -> String:
	tree_node.yield_min = 1
	tree_node.yield_max = 1

	# A guaranteed bonus must add exactly one item, never more.
	return _T.assert_eq(tree_node.roll_yield(1.0), 2, "a certain tool bonus adds one drop")


func test_zero_bonus_chance_never_adds_a_drop() -> String:
	tree_node.yield_min = 1
	tree_node.yield_max = 1

	for i in 200:
		if tree_node.roll_yield(0.0) != 1:
			return _T.assert_true(false, "a wood-tier tool granted a bonus drop")

	return ""


func test_better_tool_yields_more_on_average() -> String:
	tree_node.yield_min = 1
	tree_node.yield_max = 2

	var wood_total := 0
	var iron_total := 0
	for i in 2000:
		wood_total += tree_node.roll_yield(0.0)
		iron_total += tree_node.roll_yield(0.5)

	return _T.assert_gt(iron_total, wood_total, "iron tier out-yields wood tier over 2000 gathers")


func test_secondary_drop_is_off_by_default() -> String:
	for i in 100:
		if tree_node.roll_secondary_drop():
			return _T.assert_true(false, "a node with no secondary drop rolled one")

	return ""


func test_secondary_drop_fires_at_full_chance() -> String:
	tree_node.secondary_drop = Types.Item.Food
	tree_node.secondary_drop_chance = 1.0

	return _T.assert_true(tree_node.roll_secondary_drop(), "a certain secondary drop always fires")


func test_secondary_drop_rate_tracks_its_chance() -> String:
	tree_node.secondary_drop = Types.Item.Food
	tree_node.secondary_drop_chance = 0.2

	var hits := 0
	for i in 4000:
		if tree_node.roll_secondary_drop():
			hits += 1

	# 20% of 4000 is 800; allow a generous band so the test is not flaky.
	if hits < 600 or hits > 1000:
		return _T.assert_true(false, "expected roughly 800 hits in 4000 rolls, got %d" % hits)

	return ""
