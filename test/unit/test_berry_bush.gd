extends RefCounted

## The berry bush's two states and the clock between them.
##
## This is the only resource in the game a gather does not destroy, so almost everything here
## is about the half that has no equivalent anywhere else: a node that survives being
## harvested, remembers how far through refruiting it is, and has to come back from a save
## with that progress intact rather than restarted.

const BUSH_SCENE := "res://world/resource_nodes/berry_bush.tscn"

var _T

var _bush: BerryBush


func setup() -> void:
	BerryBush.clear_planted_marks()


func teardown() -> void:
	if _bush != null:
		_T.free_ui(_bush)
		_bush = null
	BerryBush.clear_planted_marks()


## A hosted bush. The scene has to actually enter a tree: the regrow Timer is created in
## _ready() and a Timer outside the tree never counts down, so a bush built with .new() would
## pass every assertion below by doing nothing at all.
func _host() -> BerryBush:
	_bush = await _T.instantiate_ui(BUSH_SCENE, Vector2i(64, 64)) as BerryBush
	return _bush


func test_a_wild_bush_starts_in_fruit() -> String:
	var bush := await _host()
	return _T.assert_true(bush.is_fruiting, "a bush nobody planted comes up carrying fruit")


func test_picking_strips_the_fruit_and_starts_the_clock() -> String:
	var bush := await _host()
	bush.pick()

	var err: String = _T.assert_false(bush.is_fruiting, "a picked bush has no fruit")
	if err != "":
		return err

	# Nonzero AND no more than the full interval: "it started" and "it started from the top"
	# are different claims and only the second one is the requirement.
	err = _T.assert_gt(bush.regrow_remaining(), 0.0, "the regrow clock is running")
	if err != "":
		return err

	return _T.assert_true(
		bush.regrow_remaining() <= BerryBush.REGROW_SECONDS,
		"the regrow is at most the full interval, not more"
	)


func test_the_regrow_is_the_fifteen_minutes_it_promises() -> String:
	var bush := await _host()
	bush.pick()

	var err: String = _T.assert_float_eq(
		BerryBush.REGROW_SECONDS, 900.0, 0.001, "a bush refruits after fifteen minutes"
	)
	if err != "":
		return err

	# Within a frame of the full interval rather than exactly it: hosting pumps frames, so a
	# little has already elapsed by the time this runs.
	return _T.assert_true(
		bush.regrow_remaining() > BerryBush.REGROW_SECONDS - 1.0,
		"picking starts the clock at the top, not part way through"
	)


func test_picking_an_already_picked_bush_does_not_extend_the_wait() -> String:
	var bush := await _host()
	bush.pick()

	# Restore a nearly-finished regrow, then try to pick again. If pick() were not idempotent
	# it would reset this to the full 900 and the player would have lost fourteen minutes by
	# holding the key a moment too long.
	bush._restart_regrow(5.0)
	bush.pick()

	return _T.assert_true(
		bush.regrow_remaining() <= 5.0,
		"a second pick left the clock where it was (%.1fs)" % bush.regrow_remaining()
	)


## The Timer.start() clobber CLAUDE.md calls out: start(t) ASSIGNS wait_time = t, so restoring
## a part-finished regrow with it silently puts that bush on a shorter cycle forever. Nothing
## about the bush looks wrong afterwards — it just refruits every few seconds from then on.
func test_restoring_a_part_finished_regrow_leaves_the_interval_alone() -> String:
	var bush := await _host()
	bush.pick()
	bush._restart_regrow(12.0)

	var timer: Timer = bush.get_node("RegrowTimer")
	return _T.assert_float_eq(
		timer.wait_time, BerryBush.REGROW_SECONDS, 0.001,
		"the interval is still fifteen minutes after restoring a 12-second remainder"
	)


func test_refruit_cancels_the_clock() -> String:
	var bush := await _host()
	bush.pick()
	bush.refruit()

	var err: String = _T.assert_true(bush.is_fruiting, "the bush is carrying fruit again")
	if err != "":
		return err

	return _T.assert_float_eq(bush.regrow_remaining(), 0.0, 0.001, "no regrow is left running")


func test_a_bush_that_finishes_regrowing_is_pickable_again() -> String:
	var bush := await _host()
	bush.pick()

	# A tenth of a second rather than fifteen minutes: the thing under test is that the
	# timeout re-fruits the bush, and the interval itself is asserted above.
	bush._restart_regrow(0.05)
	await bush.get_tree().create_timer(0.2).timeout

	return _T.assert_true(bush.is_fruiting, "the bush refruited when its timer ran out")


# --- save fidelity ------------------------------------------------------------------------

func test_a_picked_bush_reloads_still_picked_and_still_counting() -> String:
	var bush := await _host()
	bush.pick()
	bush._restart_regrow(123.0)

	var payload := bush.save()
	# Through JSON, because that is what the real path does and it is where an int/float or a
	# bool/String confusion would actually surface.
	var round_tripped = JSON.parse_string(JSON.stringify(payload))

	bush.refruit()
	bush.load(round_tripped)

	var err: String = _T.assert_false(bush.is_fruiting, "it came back picked, not in fruit")
	if err != "":
		return err

	return _T.assert_true(
		abs(bush.regrow_remaining() - 123.0) < 2.0,
		"it came back with its 123 seconds, not a fresh 900 (got %.1f)" % bush.regrow_remaining()
	)


func test_a_fruiting_bush_reloads_in_fruit() -> String:
	var bush := await _host()

	var round_tripped = JSON.parse_string(JSON.stringify(bush.save()))
	bush.pick()
	bush.load(round_tripped)

	return _T.assert_true(bush.is_fruiting, "a bush saved in fruit comes back in fruit")


func test_a_junk_payload_leaves_the_bush_alone_instead_of_raising() -> String:
	var bush := await _host()
	bush.pick()
	var before := bush.regrow_remaining()

	# Every shape a hand-edited or older save could produce. A raise in here would abort
	# load() silently — it returns void — and the bush would keep whatever state it had, which
	# is indistinguishable from this passing. The assertion is therefore that it did NOT
	# change, and the stderr is what proves nothing raised.
	bush.load(null)
	bush.load("not a dictionary")
	bush.load({})
	bush.load({"data": "not a dictionary either"})
	bush.load({"data": {"fruiting": "yes", "regrow_left": "soon"}})

	return _T.assert_true(
		not bush.is_fruiting and abs(bush.regrow_remaining() - before) < 2.0,
		"five malformed payloads changed nothing"
	)


func test_a_saved_bush_is_tagged_so_it_cannot_be_applied_to_a_chest() -> String:
	var bush := await _host()
	var payload := bush.save()

	var err: String = _T.assert_eq(
		str(payload.get(SaveLoad.CHUNK_KIND, "")), "BerryBush",
		"the payload names the kind that wrote it"
	)
	if err != "":
		return err

	# SaveLoad.late_load matches chunks onto nodes by position alone before this tag narrows
	# it, and a chest standing where a bush used to would otherwise be handed bush state.
	return _T.assert_true(
		payload.has("x") and payload.has("y") and payload.has("filepath"),
		"the payload carries the position keys and the dummy filepath every chunk needs"
	)


# --- planting -----------------------------------------------------------------------------

func test_a_planted_bush_comes_up_bare() -> String:
	# The anti-duplication rule. A bush can only be uprooted once it has been picked, so a
	# replant that came back in leaf would hand the berries straight back — pick, uproot,
	# replant, pick again, forever.
	BerryBush.mark_planted(Vector2i.ZERO)

	var bush := await _host()

	var err: String = _T.assert_false(bush.is_fruiting, "a planted bush has no fruit yet")
	if err != "":
		return err

	return _T.assert_true(bush.regrow_remaining() > 0.0, "and it is waiting out a full regrow")


func test_a_mark_is_spent_by_the_first_bush_that_claims_it() -> String:
	BerryBush.mark_planted(Vector2i.ZERO)

	var planted := await _host()
	var was_bare := not planted.is_fruiting
	_T.free_ui(planted)
	_bush = null

	# A second bush on the same cell — a wild one that grew there later — must not inherit
	# the first one's mark.
	var wild := await _host()

	var err: String = _T.assert_true(was_bare, "the planted bush claimed the mark")
	if err != "":
		return err

	return _T.assert_true(wild.is_fruiting, "the next bush on that cell grew normally")


func test_clearing_the_marks_makes_every_bush_wild_again() -> String:
	BerryBush.mark_planted(Vector2i.ZERO)
	BerryBush.clear_planted_marks()

	var bush := await _host()
	return _T.assert_true(bush.is_fruiting, "a cleared mark is not claimed")


# --- xp provenance ------------------------------------------------------------------------
#
# ResourceManager2 asks awards_gather_xp() on both of a bush's gathers, so these are the whole
# gate. Driving the real gather path instead would need a TileMap, a player and a pickaxe to
# assert one boolean, and would still be asserting this boolean.

func test_a_wild_bush_pays_xp() -> String:
	var bush := await _host()

	var err: String = _T.assert_false(bush.was_planted, "nobody planted it")
	if err != "":
		return err

	return _T.assert_true(bush.awards_gather_xp(), "finding a bush in the world is worth xp")


func test_a_planted_bush_pays_no_xp_on_either_gather() -> String:
	# The faucet: a replanted bush comes up already picked, so it can be uprooted again
	# immediately, and both gathers used to pay `xp`. Uproot, replant, uproot is a zero-material
	# loop, so the xp has to be gated on the bush's history rather than on its state.
	BerryBush.mark_planted(Vector2i.ZERO)

	var bush := await _host()

	var err: String = _T.assert_true(bush.was_planted, "the bush knows the player put it there")
	if err != "":
		return err

	err = _T.assert_false(bush.awards_gather_xp(), "uprooting it again pays nothing")
	if err != "":
		return err

	# The other half of the loop, fifteen minutes later: a farmed bush is a food supply, not a
	# second xp economy, so refruiting does not restore the payout either.
	bush.refruit()

	return _T.assert_false(bush.awards_gather_xp(), "and neither does picking it once it regrows")


func test_provenance_survives_a_save_and_load() -> String:
	# The only field in the payload that cannot be re-derived from the world: _planted_cells is
	# a session-lifetime static with a two-second TTL and main.gd clears it before a load
	# replays, so a dropped flag reopens the faucet on the first load and nothing reports it.
	BerryBush.mark_planted(Vector2i.ZERO)

	var planted := await _host()
	var round_tripped = JSON.parse_string(JSON.stringify(planted.save()))
	_T.free_ui(planted)
	_bush = null

	BerryBush.clear_planted_marks()
	var reloaded := await _host()
	reloaded.load(round_tripped)

	var err: String = _T.assert_true(reloaded.was_planted, "the reloaded bush is still a planted one")
	if err != "":
		return err

	return _T.assert_false(reloaded.awards_gather_xp(), "so it still pays no xp after a load")


func test_a_payload_without_the_flag_leaves_a_wild_bush_paying() -> String:
	# Every save written before the flag existed. Those worlds cannot say which bushes were
	# planted, and defaulting the other way would strip the xp from every wild bush on the map
	# — a silent loss, where this direction is a bounded one-off gain on bushes the player
	# already planted before this build.
	var bush := await _host()
	bush.load({"data": {"fruiting": false, "regrow_left": 120.0}})

	var err: String = _T.assert_false(bush.was_planted, "an absent flag loads as wild")
	if err != "":
		return err

	# And a payload this build cannot fully parse still applies the flag: load() RETURNS on an
	# unreadable `fruiting` rather than falling through, so provenance is read before that guard.
	# A bush whose state cannot be restored is still a bush the player planted, and the gate has
	# to survive the half-parse or a hand-edited save is a free xp faucet.
	bush.load({"data": {"fruiting": "yes", "planted": true}})

	return _T.assert_false(bush.awards_gather_xp(), "a half-parsed payload still applies provenance")
