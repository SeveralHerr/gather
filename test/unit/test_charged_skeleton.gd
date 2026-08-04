extends RefCounted

## The charged skeleton: the enemy a bolt makes, and the skull it becomes (gather-8ft).
##
## The blue skeleton is a distinct enemy TYPE rather than a flag on an ordinary Bone. That is
## what makes most of this file registry reads: being blue, being tougher and being caught into
## a different item are all authored into charged_bone_enemy.tscn and into EnemyRegistry, so a
## saved charged enemy comes back charged through `type` alone with no code on the load path.
## The flag it replaced needed its own save key, its own normalize guard and its own
## re-application in _ready, and each of those was a place the fact could be dropped silently —
## which is why the save round-trip tests that used to live here are gone rather than ported.
##
## Everything below is a pure static, a registry read or a PackedScene read, so none of it needs
## a SceneTree. The parts that do — a bolt actually replacing a node mid-storm, a netted skull
## actually charging the worker it is dropped into — are asserted at runtime instead, because a
## headless test can observe neither.
##
## The rarity is the thing that makes should_charge worth testing rather than playing: at
## CHARGE_CHANCE 0.08 on near bolts only, driving a real storm until one connects would take
## minutes and would be flaky in exactly that proportion. should_charge() takes the roll as an
## argument for that reason, and these tests supply it.
##
## Anything here that reads through a value which could be missing or null asserts that it is
## PRESENT first. A runtime error inside a `-> String` method aborts it and still returns "",
## which the runner counts as a pass (gather-1t9) — so an unguarded read does not fail loudly,
## it disappears.

var _T


# --- when a bolt charges something -------------------------------------------


func test_a_near_bolt_on_a_winning_roll_charges() -> String:
	# The roll is strictly below CHARGE_CHANCE and the distance strictly inside
	# CHARGE_MAX_DISTANCE, so this is the case the whole feature exists for.
	return _T.assert_true(
		EnemySpawner.should_charge(0.0, EnemySpawner.CHARGE_CHANCE - 0.001),
		"an overhead bolt on a winning roll charges a skeleton"
	)


func test_a_distant_bolt_never_charges_however_lucky_the_roll() -> String:
	# A rumble on the horizon has no visible cause on screen. If it could charge something,
	# the player would see a skeleton turn blue for no reason they could point at, which reads
	# as a bug rather than as luck — that is why distance gates before the roll does.
	var err: String = _T.assert_false(
		EnemySpawner.should_charge(1.0, 0.0),
		"a horizon bolt does not charge even on a perfect roll"
	)
	if err != "":
		return err
	return _T.assert_false(
		EnemySpawner.should_charge(EnemySpawner.CHARGE_MAX_DISTANCE + 0.01, 0.0),
		"and neither does one just past the cutoff"
	)


func test_a_losing_roll_never_charges_however_close_the_bolt() -> String:
	return _T.assert_false(
		EnemySpawner.should_charge(0.0, EnemySpawner.CHARGE_CHANCE),
		"a roll AT the chance loses — the comparison is strict, so the odds are exactly 8%"
	)


func test_charging_is_rare_across_the_whole_distance_range() -> String:
	# Guards the tuning rather than the logic: a refactor that made distance stop gating, or
	# that inverted the roll comparison, would still pass every case above while turning a
	# rare event into a common one. 40 bolts x 40 rolls is a coarse grid, not a simulation.
	var charged := 0
	var total := 0
	for d in 40:
		for r in 40:
			total += 1
			if EnemySpawner.should_charge(d / 40.0, r / 40.0):
				charged += 1

	var rate := float(charged) / float(total)
	return _T.assert_true(
		rate > 0.0 and rate < 0.10,
		"a charge stays rare across the grid (got %.3f of bolts x rolls)" % rate
	)


# --- the enemy the bolt leaves behind -----------------------------------------


func test_the_charged_type_is_registered_and_resolves_to_a_scene() -> String:
	# EnemySpawner.charge_random_skeleton() instantiates EnemyRegistry.scene_for(CHARGED)
	# directly, and so does the load path when a save names the type. A missing entry falls back
	# to Bone with only a push_warning, so the bolt would appear to work and quietly hand back an
	# ordinary skeleton — the exact failure the registry was built to stop being silent.
	var err: String = _T.assert_true(
		EnemyRegistry.has_type(EnemyRegistry.CHARGED),
		"the charged skeleton is a declared enemy type, not a fallback to Bone"
	)
	if err != "":
		return err

	var scene: PackedScene = EnemyRegistry.scene_for(EnemyRegistry.CHARGED)
	return _T.assert_true(scene != null, "and its scene loads")


func test_the_charged_type_is_caught_by_the_net_into_its_own_item() -> String:
	# The whole acquisition route. player_net.on_hit() is entirely registry-driven — it asks
	# is_nettable(body.type) and then capture_item(body.type) — so a wrong entry here means the
	# net passes through the rare enemy catching nothing, with no error anywhere. Nothing else
	# in the codebase would report it.
	var err: String = _T.assert_true(
		EnemyRegistry.is_nettable(EnemyRegistry.CHARGED),
		"the charged skeleton is catchable — the net is the only way to collect one"
	)
	if err != "":
		return err

	var captured = EnemyRegistry.capture_item(EnemyRegistry.CHARGED)
	err = _T.assert_true(captured != null, "and it names a capture item")
	if err != "":
		return err

	# Its OWN item, not the plain skull's. Catching a blue skeleton into Types.Item.BoneEnemy
	# would look like a working net and silently pay out the ordinary reward.
	err = _T.assert_eq(
		captured, Types.Item.ChargedBoneEnemy, "and that item is the charged skull"
	)
	if err != "":
		return err
	return _T.assert_true(
		EnemyRegistry.capture_item(EnemyRegistry.BONE) != captured,
		"which is a different item from the plain skeleton's"
	)


func test_the_charged_type_is_never_ambiently_spawned() -> String:
	# The one that matters most. Lightning is this type's only source, and that IS the design:
	# an ambient charged enemy puts the rare reward on the ordinary spawn timer, so a player who
	# can simply wait for one has no reason to be outside in a storm. The storm would still flash
	# and rumble; it would just stop meaning anything. Nothing else in the game would report it —
	# the spawner would look healthy, the census would look busy, and the feature would be dead.
	var ambient := EnemyRegistry.ambient_types()

	var err: String = _T.assert_false(
		ambient.has(EnemyRegistry.CHARGED),
		"the charged skeleton is never rolled by the ambient spawner"
	)
	if err != "":
		return err
	# Guards the assertion above from passing for the wrong reason: an ambient_types() that
	# returned nothing at all would satisfy it while having broken every spawn in the game.
	return _T.assert_true(
		ambient.has(EnemyRegistry.BONE), "while the ordinary skeleton still is"
	)


func test_the_charged_scene_declares_the_type_the_net_reads() -> String:
	# player_net.on_hit() reads `body.type` off the live node, not off whatever spawned it, so
	# the string authored into charged_bone_enemy.tscn is what decides whether the net catches
	# this enemy at all. An inherited scene that forgot to override `type` would arrive
	# identifying as a Bone: blue, tough, and netting into the ordinary skull.
	var scene: PackedScene = EnemyRegistry.scene_for(EnemyRegistry.CHARGED)
	var err: String = _T.assert_true(scene != null, "the charged scene loads")
	if err != "":
		return err

	var made = scene.instantiate()
	# `made is Enemy` before any field read: instantiate() answering null or something else would
	# raise on the next line, and a raise here returns "" and counts as a pass.
	var is_enemy: bool = made is Enemy
	var declared: String = made.type if is_enemy else ""
	# Freed before the asserts, not after: an early return past a free() leaks the whole node
	# tree into the suite's orphan count, which is what orphan_growth_max gates on.
	if made != null:
		made.free()

	err = _T.assert_true(is_enemy, "and its root is an Enemy")
	if err != "":
		return err
	return _T.assert_eq(
		declared, EnemyRegistry.CHARGED, "and the scene declares the charged type"
	)


func test_the_charged_scene_is_tougher_than_a_plain_skeleton() -> String:
	# The stats live on the two scenes rather than in code, so the only honest way to compare
	# them is to build both and read them. instantiate() does not run _ready(), so this needs no
	# SceneTree — the @export values are already assigned by then, which is also why the spawner
	# must set them BEFORE add_child().
	var plain_scene: PackedScene = EnemyRegistry.scene_for(EnemyRegistry.BONE)
	var charged_scene: PackedScene = EnemyRegistry.scene_for(EnemyRegistry.CHARGED)

	var err: String = _T.assert_true(
		plain_scene != null and charged_scene != null, "both enemy scenes load"
	)
	if err != "":
		return err

	var plain = plain_scene.instantiate()
	var charged = charged_scene.instantiate()

	var both_are_enemies: bool = plain is Enemy and charged is Enemy
	var plain_hp: int = plain.max_health if both_are_enemies else -1
	var charged_hp: int = charged.max_health if both_are_enemies else -1
	var plain_damage: int = int(plain.damage) if both_are_enemies else -1
	var charged_damage: int = int(charged.damage) if both_are_enemies else -1

	# Both freed before any early return, for the orphan reason above.
	if plain != null:
		plain.free()
	if charged != null:
		charged.free()

	err = _T.assert_true(both_are_enemies, "and both roots are Enemies")
	if err != "":
		return err

	# Not merely "greater". A charged skeleton with 11 health where a plain one has 10 is a rare
	# enemy the player cannot tell apart from a common one in the only way that reaches them —
	# how long it takes to kill. That is the dead-content shape the chop-cadence test below
	# guards on the reward side, and it is the same failure here on the threat side.
	err = _T.assert_gte(
		float(charged_hp), float(plain_hp) * 1.5,
		"a charged skeleton is meaningfully tougher (%d health against %d)" % [charged_hp, plain_hp]
	)
	if err != "":
		return err

	# `>=` rather than `>` on purpose: the health is what makes it a hunt, and hitting exactly as
	# hard as a plain skeleton is a defensible tuning choice. Hitting SOFTER is not — a rarer,
	# tougher enemy that does less damage reads as a downgrade wearing the rare skin.
	return _T.assert_gte(
		charged_damage, plain_damage,
		"and never hits softer than a plain one (%d against %d)" % [charged_damage, plain_damage]
	)


func test_the_capture_item_resolves_to_a_registered_item() -> String:
	# get_item() is deliberately not total over Types.Item — the world resources live in
	# items/resources.gd — and player_net.on_hit() builds a SlotData around whatever it returns.
	# A null there empties the net and pays out nothing, with no error. This is the cheapest
	# possible guard against the id being added to the enum and never registered.
	var items := Items.new()
	items._ready()
	var skull = items.get_item(Types.Item.ChargedBoneEnemy)

	var err: String = _T.assert_true(skull != null, "ChargedBoneEnemy resolves to an item")
	if err != "":
		items.free()
		return err

	var is_right_class: bool = skull is GameItemChargedBoneEnemy
	var not_placeable: bool = not skull.is_placeable
	items.free()

	err = _T.assert_true(is_right_class, "and it is a GameItemChargedBoneEnemy")
	if err != "":
		return err
	return _T.assert_true(
		not_placeable, "and it is not placeable — it is fitted into a machine, not put down"
	)


# --- what the captured skull does to a worker ---------------------------------


func test_a_charged_worker_chops_faster() -> String:
	var plain := BoneWorker.chop_seconds_for(false)
	var charged := BoneWorker.chop_seconds_for(true)

	var err: String = _T.assert_float_eq(
		plain, BoneWorker.CHOP_SECONDS, 0.0001, "an ordinary worker keeps the authored cadence"
	)
	if err != "":
		return err
	return _T.assert_true(
		charged < plain, "a charged worker chops faster (%.1fs against %.1fs)" % [charged, plain]
	)


func test_the_charged_chop_is_worth_noticing() -> String:
	# The failure this guards is not "too fast", it is "imperceptible". CHOP_SECONDS is 20s by
	# design, so a 10% improvement is four seconds the player cannot detect without a
	# stopwatch — the dead-content shape that the Cooked Food repricing (gather-as9) was about.
	var ratio := BoneWorker.chop_seconds_for(true) / BoneWorker.chop_seconds_for(false)
	return _T.assert_true(
		ratio <= 0.75,
		"a skull takes at least a quarter off the chop (got %.2fx)" % ratio
	)
