extends RefCounted

## Covers enemies/enemy_registry.gd (gather-33f).
##
## The registry exists because an enemy type was a bare String re-matched by hand in three
## unrelated files — enemy_spawner.scene_for_type(), island_manager's BOSS_TYPE, and
## player_net.on_hit()'s `body.type == "Bone"` — with nothing making them agree. Adding an
## enemy meant finding all three. The tests that matter here are therefore the *consistency*
## ones: every declared type resolves to a real scene, and nothing spawnable is something
## that should only ever be placed.
##
## The loot roller takes its randomness as an argument for exactly this reason. A drop table
## is the kind of thing that is wrong for months without anyone noticing, and none of it is
## assertable while randf() is buried inside.

var _T


func test_every_declared_type_points_at_a_scene_that_exists() -> String:
	# The registry's whole job. A path typo here is a type that loads as null and crashes on
	# instantiate(), and the enemy it names would be one nobody spawns until late.
	for type in EnemyRegistry.TYPES:
		var path: String = EnemyRegistry.TYPES[type]["scene"]
		if not ResourceLoader.exists(path):
			return _T.assert_true(false, "enemy type '%s' names a missing scene: %s" % [type, path])
	return ""


func test_the_boss_is_not_ambiently_spawnable() -> String:
	# The failure this prevents is quiet and expensive: an elite added to the old `enemies`
	# array — the obvious move when adding a boss — would have had the trickle putting boss
	# enemies on the starting island, and nothing would have reported it.
	var ambient := EnemyRegistry.ambient_types()

	var err: String = _T.assert_false(ambient.has(EnemyRegistry.ELITE),
		"the elite is never rolled by the ambient spawner")
	if err != "":
		return err
	return _T.assert_gt(ambient.size(), 0, "something is still spawnable")


func test_an_unknown_type_falls_back_without_raising() -> String:
	# A save naming a type this build does not have must load as SOMETHING. It already did —
	# the old `match` had a silent `_:` arm — but silently, which is how a saved elite came
	# back a skeleton with no trace. record() warns and still answers.
	var fallback := EnemyRegistry.record("NoSuchEnemy")

	var err: String = _T.assert_true(fallback == EnemyRegistry.TYPES[EnemyRegistry.DEFAULT_TYPE],
		"an unknown type resolves to the default record")
	if err != "":
		return err
	return _T.assert_false(EnemyRegistry.has_type("NoSuchEnemy"),
		"but has_type still reports the truth, so callers can tell")


func test_only_types_with_a_capture_item_are_nettable() -> String:
	var err: String = _T.assert_true(EnemyRegistry.is_nettable(EnemyRegistry.BONE),
		"the skeleton is what the net is for")
	if err != "":
		return err
	err = _T.assert_false(EnemyRegistry.is_nettable(EnemyRegistry.SPIDER),
		"the spider is not catchable")
	if err != "":
		return err
	# The pair has to agree, or on_hit() builds a SlotData around a null item and empties a
	# net for nothing.
	for type in EnemyRegistry.TYPES:
		if EnemyRegistry.is_nettable(type) and EnemyRegistry.capture_item(type) == null:
			return _T.assert_true(false, "'%s' is nettable with no capture item" % type)
	return _T.assert_true(EnemyRegistry.capture_item(EnemyRegistry.SPIDER) == null,
		"a type that is not nettable has no capture item")


# --- the loot roller ---------------------------------------------------------


func test_a_certain_drop_always_drops_and_a_zero_chance_never_does() -> String:
	# The two boundaries, which are the ones a `<=` instead of a `<` gets wrong. A sample is
	# a 0..1 roll, so 0.0 is the luckiest possible one and must still not defeat chance 0.0.
	var table := [
		{"item": Types.Item.Bone, "chance": 1.0, "min": 1, "max": 1},
		{"item": Types.Item.Coin, "chance": 0.0, "min": 1, "max": 1},
	]
	# Luckiest possible rolls for both entries.
	var got := EnemyRegistry.loot_from(table, [0.0, 0.0, 0.0, 0.0])

	return _T.assert_eq(str(got), str([Types.Item.Bone]),
		"the certain drop dropped and the impossible one did not")


func test_the_count_range_is_respected_at_both_ends() -> String:
	var table := [{"item": Types.Item.Coin, "chance": 1.0, "min": 3, "max": 6}]

	# Sample 0.0 picks the bottom of the range, 0.999 the top. Anything outside 3..6 means
	# the arithmetic is wrong in a way that only shows up on a rare roll in a real game.
	var low := EnemyRegistry.loot_from(table, [0.0, 0.0])
	var high := EnemyRegistry.loot_from(table, [0.0, 0.999])
	var mid := EnemyRegistry.loot_from(table, [0.0, 0.5])

	var err: String = _T.assert_eq(low.size(), 3, "the lowest roll yields min")
	if err != "":
		return err
	err = _T.assert_eq(high.size(), 6, "the highest roll yields max")
	if err != "":
		return err
	return _T.assert_true(mid.size() >= 3 and mid.size() <= 6, "a middling roll stays in range")


func test_a_short_sample_array_drops_nothing_rather_than_raising() -> String:
	# roll_loot() always supplies two samples per entry, but loot_from is public and pure, and
	# an index off the end of an Array raises — which inside `-> void` would abort the death
	# handler part-way, after the guaranteed drop and before the coins.
	var table := [{"item": Types.Item.Bone, "chance": 1.0, "min": 1, "max": 1}]

	return _T.assert_eq(EnemyRegistry.loot_from(table, []).size(), 0,
		"no samples means no drops, not an error")


func test_the_boss_table_pays_out_on_every_kill() -> String:
	# The elite is the reason loot tables exist: several items, two of them guaranteed, which
	# a single Types.Item could never express. Rolled with the unluckiest samples that still
	# clear a chance of 1.0, so this asserts the guaranteed half only.
	var table := EnemyRegistry.loot_table(EnemyRegistry.ELITE)
	var err: String = _T.assert_gt(table.size(), 1, "the boss has a real table, not one item")
	if err != "":
		return err

	var samples := []
	for _i in table.size():
		samples.append(0.999)  # unlucky: only chance 1.0 entries survive
		samples.append(0.0)    # minimum count
	var got := EnemyRegistry.loot_from(table, samples)

	return _T.assert_gt(got.size(), 0, "an unlucky boss kill still pays its guaranteed drops")
