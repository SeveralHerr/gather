extends RefCounted

## Covers the quest board's shape and the log's claiming and persistence.
##
## The board itself is a RefCounted registry, so most of this needs no SceneTree — the same shape
## as test_skill_tree.gd and for the same reason.
##
## The property most worth protecting is the one that makes the whole feature small: a quest has
## no state of its own. Progress is derived from whoever owns the fact it measures, and the log
## persists only which ids were claimed. A future edit that adds a per-quest counter would look
## like an optimisation and would be wrong on the first load — see the class comment on
## QuestBoard.

var _T


func _board() -> QuestBoard:
	return QuestBoard.new()


func _log() -> QuestLog:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var node := QuestLog.new()
	# saveObject() calls get_path(), which pushes an error on a detached node — reported as
	# stderr noise rather than as a failure, which is the worst of both.
	tree.root.add_child(node)
	return node


func _drop(node: QuestLog) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.remove_child(node)
	node.free()


# --- the board ----------------------------------------------------------------


func test_the_board_is_not_empty_and_has_no_duplicate_ids() -> String:
	var board := _board()

	var err: String = _T.assert_gt(
		float(board.order.size()), 0.0, "the board has quests on it")
	if err != "":
		return err

	# `order` is an Array and `quests` a Dictionary keyed by id, so a duplicated id silently
	# collapses two definitions into one and the board is quietly shorter than it reads.
	return _T.assert_eq(
		board.order.size(), board.quests.size(),
		"every id in the board's order is distinct")


## Every prerequisite must name a quest that exists. A typo makes the dependent quest
## permanently un-offered — it simply never appears, with no error anywhere.
func test_every_prerequisite_names_a_real_quest() -> String:
	var board := _board()

	for id in board.order:
		var quest: Quest = board.get_quest(id)
		for required in quest.requires:
			var err: String = _T.assert_true(
				board.has_quest(required),
				"'%s' requires '%s', which exists" % [id, required])
			if err != "":
				return err

	return ""


## A quest may not require one that comes after it in board order. The board is drawn in `order`,
## and a forward reference would be a card gated on something further down the same list — which
## works, but reads to the player as a quest that appeared out of sequence.
func test_no_quest_requires_one_that_comes_after_it() -> String:
	var board := _board()

	for i in board.order.size():
		var id: String = board.order[i]
		var quest: Quest = board.get_quest(id)
		for required in quest.requires:
			var err: String = _T.assert_true(
				board.order.find(required) < i,
				"'%s' requires '%s', which is listed before it" % [id, required])
			if err != "":
				return err

	return ""


func test_every_quest_asks_for_something_and_pays_for_it() -> String:
	var board := _board()

	for id in board.order:
		var quest: Quest = board.get_quest(id)

		# A zero target is instantly complete on a fresh save, which turns the opening board into
		# a pile of free rewards.
		var amount_err: String = _T.assert_gt(
			float(quest.amount), 0.0, "'%s' asks for a positive amount" % id)
		if amount_err != "":
			return amount_err

		var paid := quest.reward_coins > 0 or quest.reward_xp > 0
		var pay_err: String = _T.assert_true(paid, "'%s' pays something" % id)
		if pay_err != "":
			return pay_err

	return ""


## Priced against LandManager's curve rather than against taste: twelve parcels cost ~6950 coins
## in total. The board should be a real leg-up for a player who engages with it and nowhere near
## a replacement for mining gold — which is what the whole land economy is built on.
func test_the_whole_board_is_worth_some_land_but_not_the_land_economy() -> String:
	var board := _board()

	var coins := 0
	for id in board.order:
		coins += board.get_quest(id).reward_coins

	var err: String = _T.assert_gt(
		float(coins), 500.0, "clearing the board is worth several parcels (got %d)" % coins)
	if err != "":
		return err

	return _T.assert_true(
		coins < 3000,
		"...and is well under the ~6950 the land curve costs (got %d)" % coins)


func test_only_have_quests_take_anything_off_the_player() -> String:
	# The panel's button says "HAND IN" rather than "CLAIM" for these, and that promise is
	# `Quest.consumes()`. A kind that started consuming without the label following would take a
	# player's items with no warning at all.
	var board := _board()

	for id in board.order:
		var quest: Quest = board.get_quest(id)
		var expected := quest.kind == Quest.Kind.HAVE
		var err: String = _T.assert_eq(
			quest.consumes(), expected,
			"'%s' consumes only if it is a HAVE quest" % id)
		if err != "":
			return err

	return ""


# --- offering -----------------------------------------------------------------


func test_a_gated_quest_is_not_offered_until_its_prerequisite_is_claimed() -> String:
	var board := _board()

	# Find any gated quest rather than naming one, so retuning the board does not break this.
	var gated := ""
	for id in board.order:
		if not board.get_quest(id).requires.is_empty():
			gated = id
			break

	if gated == "":
		return "the board has no gated quest, so this test proves nothing"

	var err: String = _T.assert_false(
		board.is_offered(gated, {}), "'%s' is not offered on a fresh board" % gated)
	if err != "":
		return err

	var claimed := {}
	for required in board.get_quest(gated).requires:
		claimed[required] = true

	return _T.assert_true(
		board.is_offered(gated, claimed),
		"'%s' is offered once its prerequisites are claimed" % gated)


func test_a_claimed_quest_leaves_the_board() -> String:
	var board := _board()
	var first: String = board.order[0]

	var err: String = _T.assert_true(
		board.available({}).has(first), "the first quest is offered on a fresh board")
	if err != "":
		return err

	return _T.assert_false(
		board.available({first: true}).has(first), "a claimed quest is no longer offered")


# --- the log ------------------------------------------------------------------


## Progress is derived, not stored, so a quest measuring something the world has none of reads
## zero rather than raising. The log runs headless in these tests with no player, no clock and no
## land manager, which is exactly that case.
func test_progress_is_zero_when_the_world_has_nothing_to_measure() -> String:
	var log_node := _log()

	for id in log_node.board.order:
		var progress := log_node.progress_of(id)
		var err: String = _T.assert_eq(progress, 0, "'%s' reads zero with no world" % id)
		if err != "":
			_drop(log_node)
			return err

	var ready: String = _T.assert_eq(
		log_node.ready_count(), 0, "nothing is claimable with no world")
	_drop(log_node)
	return ready


func test_an_unknown_id_is_answered_rather_than_raising() -> String:
	# The panel asks about whatever the board lists, and a board and a log that disagree should
	# draw an empty row rather than raise inside a layout pass.
	var log_node := _log()

	var checks := [
		[log_node.progress_of("no_such_quest"), 0, "progress of an unknown id is zero"],
		[log_node.is_complete("no_such_quest"), false, "an unknown id is not complete"],
		[log_node.can_claim("no_such_quest"), false, "an unknown id cannot be claimed"],
		[log_node.claim("no_such_quest"), false, "claiming an unknown id changes nothing"],
	]

	for check in checks:
		var err: String = _T.assert_eq(check[0], check[1], check[2])
		if err != "":
			_drop(log_node)
			return err

	_drop(log_node)
	return ""


func test_an_incomplete_quest_cannot_be_claimed() -> String:
	var log_node := _log()
	var first: String = log_node.board.order[0]

	var err: String = _T.assert_false(
		log_node.claim(first), "a quest with no progress refuses to be claimed")
	if err != "":
		_drop(log_node)
		return err

	var untouched: String = _T.assert_false(
		log_node.is_claimed(first), "...and is not marked claimed")
	_drop(log_node)
	return untouched


# --- save fidelity ------------------------------------------------------------


func test_the_claimed_set_survives_a_round_trip() -> String:
	var log_node := _log()
	var ids: Array = [log_node.board.order[0], log_node.board.order[1]]
	for id in ids:
		log_node.claimed[id] = true

	var payload := log_node.saveObject()

	var restored := _log()
	restored.loadObject(payload)

	for id in ids:
		var err: String = _T.assert_true(
			restored.is_claimed(id), "'%s' is still claimed after a load" % id)
		if err != "":
			_drop(log_node)
			_drop(restored)
			return err

	var count: String = _T.assert_eq(
		restored.claimed.size(), ids.size(), "and nothing else came back claimed")

	_drop(log_node)
	_drop(restored)
	return count


func test_a_save_written_before_quests_existed_loads_quietly() -> String:
	var log_node := _log()
	log_node.loadObject({})

	var err: String = _T.assert_eq(
		log_node.claimed.size(), 0, "nothing is claimed")
	if err != "":
		_drop(log_node)
		return err

	# ...and the board is fully offered afterwards, which is the state such a player should be in.
	var offered: String = _T.assert_gt(
		float(log_node.available().size()), 0.0, "the board is offered from the start")
	_drop(log_node)
	return offered


## A `claimed` that is not a list can arrive from a hand-edited save or from a future build that
## changed its shape. A raise here aborts `loadObject` — which is `-> void`, so it looks exactly
## like success — and the player silently loses every claimed quest.
func test_a_malformed_claimed_list_does_not_raise() -> String:
	var log_node := _log()
	log_node.loadObject({"claimed": "first_timber"})

	var err: String = _T.assert_eq(
		log_node.claimed.size(), 0, "an unreadable claimed set restores nothing")
	_drop(log_node)
	return err


## Ids this build does not have are dropped rather than kept. `available()` already treats an
## unknown id as not offered, so keeping them would only mean a save from a build with more
## quests could silently re-complete one if the id ever came back.
func test_unknown_ids_in_a_save_are_dropped() -> String:
	var log_node := _log()
	var real: String = log_node.board.order[0]
	log_node.loadObject({"claimed": [real, "a_quest_from_the_future"]})

	var kept: String = _T.assert_true(log_node.is_claimed(real), "the real id came back")
	if kept != "":
		_drop(log_node)
		return kept

	var size: String = _T.assert_eq(
		log_node.claimed.size(), 1, "and the unknown one did not")
	_drop(log_node)
	return size
