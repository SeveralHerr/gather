extends RefCounted

## Lightning-struck skeletons and the skull they leave behind (gather-8ft).
##
## Everything here is either a pure static or a save-payload round trip, so none of it needs a
## SceneTree. The parts that do — the blue tint actually reaching a sprite, a charged worker's
## timer actually re-arming — are asserted at runtime instead, because a headless test can
## observe neither.
##
## The rarity is the thing that makes this worth testing rather than playing: at
## CHARGE_CHANCE 0.08 on near bolts only, driving a real storm until one connects would take
## minutes and would be flaky in exactly that proportion. should_charge() takes the roll as an
## argument for that reason, and these tests supply it.

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


# --- what a charged skull does to a worker ------------------------------------


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


# --- the save round trip ------------------------------------------------------


func test_a_charged_skeleton_survives_the_save() -> String:
	# Routed through enemy_save_entry and normalize_enemy_entry together, so a key written by
	# one and not read by the other fails here. Being lightning-struck cannot be re-derived
	# from anything else in the file — the storm is over and the bolt is gone — so losing it
	# silently downgrades the skull the player was about to collect.
	var payload := EnemySpawner.enemy_save_entry(
		7, true, true, 0, Vector2(12.0, -4.0), EnemyRegistry.BONE, 10, 3, true
	)

	var err: String = _T.assert_true(payload.has("charged"), "the charged flag is written")
	if err != "":
		return err

	var restored := EnemySpawner.normalize_enemy_entry(payload)
	return _T.assert_true(bool(restored["charged"]), "and it comes back charged")


func test_an_ordinary_skeleton_does_not_come_back_charged() -> String:
	var payload := EnemySpawner.enemy_save_entry(
		7, true, true, 0, Vector2.ZERO, EnemyRegistry.BONE, 10, 3, false
	)
	var restored := EnemySpawner.normalize_enemy_entry(payload)
	return _T.assert_false(bool(restored["charged"]), "an ordinary skeleton stays ordinary")


func test_a_save_from_before_charged_skeletons_reads_as_ordinary() -> String:
	# Every enemy in every existing save has no `charged` key at all. Defaulting it to true,
	# or raising on the absent key, would either hand out free skulls or abort the entry.
	var restored := EnemySpawner.normalize_enemy_entry({"type": "Bone", "hp": 10})
	return _T.assert_false(bool(restored["charged"]), "an older save loads an ordinary skeleton")


func test_a_string_where_the_flag_should_be_does_not_raise() -> String:
	# `raw.get("charged") == true` against a String RAISES in GDScript rather than evaluating
	# false, and a raise inside this static aborts the whole entry — which is how a hand-edited
	# or corrupted save loses an enemy silently. The typeof guard is what this pins.
	#
	# The `has` check below is load-bearing and is NOT redundant with the assert after it.
	# Measured: swapping the typeof guard for `raw.get("charged", false) == true` and running
	# this file gave `Total: 540 | Passed: 11 | Failed: 0` with two SCRIPT ERRORs on stderr and
	# nothing else — the raise aborted the static, `-> Dictionary` handed back an empty one,
	# and reading a missing key aborted this test too, which for a `-> String` method returns
	# "" and counts as a pass (gather-1t9). Asserting the dictionary came back POPULATED is
	# what turns that silent stderr-only signal into a real red.
	var restored := EnemySpawner.normalize_enemy_entry({"type": "Bone", "charged": "yes"})

	var err: String = _T.assert_true(
		restored.has("charged"),
		"normalize returned a populated entry — an empty one means it raised and aborted"
	)
	if err != "":
		return err

	return _T.assert_false(
		bool(restored["charged"]), "a non-bool reads as not charged instead of raising"
	)


# --- the skull itself ---------------------------------------------------------


func test_the_charged_skull_is_a_registered_item() -> String:
	# get_item() is deliberately not total over Types.Item, and Enemy._drop_charged_skull runs
	# on the death path where a null would mean a charged kill paid nothing. This is the
	# cheapest possible guard against the id being added to the enum and never registered.
	var items := Items.new()
	items._ready()
	var skull := items.get_item(Types.Item.ChargedSkull)
	var err: String = _T.assert_true(skull != null, "ChargedSkull resolves to an item")
	if err != "":
		items.free()
		return err

	var is_right_class: bool = skull is GameItemChargedSkull
	var not_placeable: bool = not skull.is_placeable
	items.free()

	err = _T.assert_true(is_right_class, "and it is a GameItemChargedSkull")
	if err != "":
		return err
	return _T.assert_true(
		not_placeable, "and it is not placeable — it is fitted onto a machine, not put down"
	)
