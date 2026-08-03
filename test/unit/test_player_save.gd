extends RefCounted

## Covers the Player save payload: the shape it writes now, and the shape it still has
## to be able to read.
##
## WHAT THIS FILE CAN REACH. Player is scene-backed — its @onready fields resolve
## ../../Systems/SoundManager, ../../UI/HotBarInventory and a HUD several levels down a
## Camera2D — so an instance cannot be stood up headless, and GameItems is an autoload,
## which the `--script` runner does not instantiate either. So saveObject()/loadObject()
## are deliberately thin wrappers over four static functions that take plain values, and
## those are what is asserted here. What is left to the running game is the last hop of
## loadObject(): GameItems.get_item(type) turning the saved enum back into a GameItem, and
## the item_list.has() guard in front of it.
##
## Every round trip below goes through JSON.stringify + JSON.parse_string, because that
## is what SaveLoad does to the returned dictionary and it is where types quietly
## change — ints come back as floats, and anything JSON cannot express comes back as
## something else entirely.

var _T


## Stand-ins for the GameItems registry, built directly the way test_land_manager.gd
## does it. Only `type` matters to the payload.
func _item(item_type: Types.Item, item_name: String) -> GameItem:
	return GameItem.new(Vector2i.ZERO, 0, item_type, 1, false, item_name)


func _slot(item_type: Types.Item, item_name: String, count: int) -> SlotData:
	return SlotData.new(_item(item_type, item_name), count)


## An inventory with a hole in the middle, which is the interesting case: slot order is
## the only thing that makes the hotbar stable across a save.
func _sample_slots() -> Array:
	return [
		_slot(Types.Item.WoodPickaxe, "Wood Pickaxe", 1),
		null,
		_slot(Types.Item.Wood, "Wood", 42),
		null,
		_slot(Types.Item.Coin, "Gold Coin", 7),
	]


## What SaveLoad does between saveObject() and loadObject().
func _through_json(payload: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(payload))
	if parsed is Dictionary:
		return parsed
	return {}


## The old payload, reconstructed by hand — saveFile is gitignored, so there is no
## historical save in the repo to read. Position split into two loose floats, every slot
## its own JSON string, empties written as the 1337 sentinel.
func _legacy_payload(pos: Vector2, hp: int, slots: Array) -> Dictionary:
	var inv := []
	for slot_data in slots:
		if slot_data == null:
			inv.append(JSON.stringify({"type": 1337, "count": 1337}))
		else:
			inv.append(JSON.stringify({"type": slot_data.item.type, "count": slot_data.count}))

	return {
		"filepath": "/root/Main/World/Player",
		"px": pos.x,
		"py": pos.y,
		"hp": hp,
		"inv_json": inv,
	}


func test_a_new_payload_round_trips_the_inventory() -> String:
	var payload := _through_json(
		Player.build_payload("/root/Main/World/Player", Vector2(12.5, -3.25), 6, _sample_slots())
	)
	var slots := Player.read_slots(payload)

	var err: String = _T.assert_eq(slots.size(), 5, "every slot comes back, holes included")
	if err != "":
		return err

	err = _T.assert_eq(slots[0]["type"], int(Types.Item.WoodPickaxe), "slot 0 keeps its item type")
	if err != "":
		return err

	err = _T.assert_eq(slots[2]["type"], int(Types.Item.Wood), "slot 2 keeps its item type")
	if err != "":
		return err

	err = _T.assert_eq(slots[2]["count"], 42, "slot 2 keeps its stack size")
	if err != "":
		return err

	return _T.assert_eq(slots[4]["type"], int(Types.Item.Coin), "slot 4 keeps its item type")


func test_a_new_payload_round_trips_position_and_health() -> String:
	var payload := _through_json(
		Player.build_payload("/root/Main/World/Player", Vector2(12.5, -3.25), 6, _sample_slots())
	)

	var pos := Player.read_position(payload)
	var err: String = _T.assert_float_eq(pos.x, 12.5, 0.0001, "x survives")
	if err != "":
		return err

	err = _T.assert_float_eq(pos.y, -3.25, 0.0001, "y survives")
	if err != "":
		return err

	# loadObject() reads "hp" straight off the payload, so the assertion is on the value
	# JSON handed back: a whole number, not 6.0-as-a-float that a typed int field would
	# have to narrow.
	return _T.assert_eq(int(payload["hp"]), 6, "health survives")


func test_the_slot_entries_are_dictionaries_not_strings() -> String:
	# The regression this change is about, pinned directly. If a future edit puts the
	# inner JSON.stringify() back, everything above still passes — read_slot() accepts
	# both shapes on purpose — and only this fails.
	var payload := Player.build_payload("/root/Main/World/Player", Vector2.ZERO, 6, _sample_slots())
	var inv: Array = payload["inv_json"]

	var err: String = _T.assert_true(inv[0] is Dictionary, "a filled slot is written as a dictionary")
	if err != "":
		return err

	err = _T.assert_true(inv[1] == null, "an empty slot is written as a real null")
	if err != "":
		return err

	# Vector2 is stored through JSON.from_native, which writes {"type": ..., "args": ...}.
	# Asserting to_native() reads it back is what the round-trip tests do; this is only
	# that px/py are gone, so nothing keeps reading them by habit.
	err = _T.assert_false(payload.has("px"), "the hand-split px is gone")
	if err != "":
		return err

	return _T.assert_false(payload.has("py"), "the hand-split py is gone")


func test_the_payload_never_carries_top_level_x_and_y() -> String:
	# save_load.gd's _load() sends any entry holding BOTH "x" and "y" at the top level to
	# the position-keyed SaveChunks bucket instead of calling loadObject() on the node. A
	# position flattened to x/y would therefore stop the player ever being restored — with
	# no error, for every save. That is what the old px/py naming was quietly buying, and
	# what the nested "pos" key buys now. This is the guard, because the next reader of
	# those two names will see redundant prefixes and tidy them.
	var payload := Player.build_payload("/root/Main/World/Player", Vector2(12.5, -3.25), 6, _sample_slots())

	return _T.assert_false(
		payload.has("x") and payload.has("y"),
		"the payload would be routed to SaveChunks and never reach Player.loadObject"
	)


func test_a_slot_holding_no_item_is_saved_as_an_empty_slot() -> String:
	# A live SlotData whose .item is null. `if not item:` is FALSE for it, so the old code
	# fell through to item.item.type and raised — and because saveObject() is typed
	# `-> Dictionary`, the raise handed SaveLoad an empty {} rather than failing loudly:
	# position, health and the entire inventory gone, one blank line in saveFile.
	var slots: Array = [
		_slot(Types.Item.Wood, "Wood", 3),
		SlotData.new(null, 1),
		_slot(Types.Item.Stone, "Stone", 2),
	]
	var payload := Player.build_payload("/root/Main/World/Player", Vector2.ZERO, 6, slots)

	var err: String = _T.assert_true(payload.has("inv_json"), "the payload was built at all")
	if err != "":
		return err

	var read := Player.read_slots(_through_json(payload))
	err = _T.assert_eq(read.size(), 3, "the item-less slot did not take the payload down with it")
	if err != "":
		return err

	err = _T.assert_true(read[1] == null, "the item-less slot reads back as empty")
	if err != "":
		return err

	return _T.assert_eq(read[2]["type"], int(Types.Item.Stone), "the slot after it still saves")


func test_an_old_save_still_loads() -> String:
	var payload := _through_json(_legacy_payload(Vector2(12.5, -3.25), 6, _sample_slots()))

	var pos := Player.read_position(payload)
	var err: String = _T.assert_float_eq(pos.x, 12.5, 0.0001, "px is still read")
	if err != "":
		return err

	err = _T.assert_float_eq(pos.y, -3.25, 0.0001, "py is still read")
	if err != "":
		return err

	var slots := Player.read_slots(payload)
	err = _T.assert_eq(slots.size(), 5, "every slot of an old save comes back")
	if err != "":
		return err

	err = _T.assert_eq(slots[0]["type"], int(Types.Item.WoodPickaxe), "the embedded JSON string is parsed")
	if err != "":
		return err

	return _T.assert_eq(slots[2]["count"], 42, "the old stack size is parsed")


func test_both_shapes_decode_to_the_same_thing() -> String:
	# The whole backward-compatibility claim in one assertion: a save written before this
	# change and one written after describe the same inventory.
	var slots := _sample_slots()
	var new_payload := _through_json(
		Player.build_payload("/root/Main/World/Player", Vector2(12.5, -3.25), 6, slots)
	)
	var old_payload := _through_json(_legacy_payload(Vector2(12.5, -3.25), 6, slots))

	var from_new := Player.read_slots(new_payload)
	var from_old := Player.read_slots(old_payload)

	# Compared field by field rather than with a single Array ==, so a mismatch names the
	# slot that diverged instead of printing two arrays side by side.
	var err: String = _T.assert_eq(from_old.size(), from_new.size(), "the same number of slots")
	if err != "":
		return err

	for index in from_new.size():
		if from_new[index] == null or from_old[index] == null:
			err = _T.assert_true(
				from_new[index] == null and from_old[index] == null, "slot %d agrees on being empty" % index
			)
			if err != "":
				return err
			continue

		err = _T.assert_eq(from_old[index]["type"], from_new[index]["type"], "slot %d agrees on type" % index)
		if err != "":
			return err

		err = _T.assert_eq(from_old[index]["count"], from_new[index]["count"], "slot %d agrees on count" % index)
		if err != "":
			return err

	return _T.assert_eq(
		Player.read_position(old_payload), Player.read_position(new_payload), "the positions match"
	)


func test_empty_slots_survive_both_shapes() -> String:
	# Positional, not just counted: an empty slot that collapses shifts every item after
	# it one place down the hotbar, which is the behaviour the 1337 sentinel existed to
	# prevent and which a null has to keep preventing.
	var slots := _sample_slots()
	var new_slots := Player.read_slots(
		_through_json(Player.build_payload("/root/Main/World/Player", Vector2.ZERO, 6, slots))
	)
	var old_slots := Player.read_slots(_through_json(_legacy_payload(Vector2.ZERO, 6, slots)))

	var err: String = _T.assert_true(new_slots[1] == null, "the new shape keeps slot 1 empty")
	if err != "":
		return err

	err = _T.assert_true(new_slots[3] == null, "the new shape keeps slot 3 empty")
	if err != "":
		return err

	err = _T.assert_true(old_slots[1] == null, "the 1337 sentinel still reads as empty")
	if err != "":
		return err

	err = _T.assert_true(old_slots[3] == null, "the 1337 sentinel still reads as empty at slot 3")
	if err != "":
		return err

	# And the slots either side of the hole are untouched.
	err = _T.assert_eq(new_slots[2]["type"], int(Types.Item.Wood), "the item after a hole stays put")
	if err != "":
		return err

	return _T.assert_eq(old_slots[4]["type"], int(Types.Item.Coin), "the last item of an old save stays put")


func test_an_all_empty_inventory_is_not_mistaken_for_a_missing_one() -> String:
	var slots: Array = [null, null, null]
	var payload := _through_json(Player.build_payload("/root/Main/World/Player", Vector2.ZERO, 6, slots))
	var read := Player.read_slots(payload)

	var err: String = _T.assert_eq(read.size(), 3, "three empty slots come back as three slots")
	if err != "":
		return err

	return _T.assert_true(read[0] == null and read[1] == null and read[2] == null, "all three are empty")


func test_an_unreadable_entry_leaves_one_empty_slot_not_a_lost_inventory() -> String:
	# GDScript has no exceptions, so a malformed entry that raised would abort loadObject()
	# part-way and drop every slot after it — silently, which is this project's documented
	# worst case for a load. A junk entry becomes one empty slot instead.
	#
	# EXPECTED STDERR: this test makes read_slot() push two warnings, one per junk entry.
	# WARNING lines here are the assertion passing, not the run going wrong — read_slot()
	# parses through JSON.new().parse() precisely so a bad line does not raise an engine
	# ERROR as well.
	var payload := {
		"filepath": "/root/Main/World/Player",
		"pos": JSON.from_native(Vector2.ZERO),
		"hp": 6,
		"inv_json": [
			{"type": int(Types.Item.Wood), "count": 3},
			"{not json at all",
			{"count": 5},
			null,
			{"type": int(Types.Item.Stone), "count": 2},
		],
	}
	var read := Player.read_slots(_through_json(payload))

	var err: String = _T.assert_eq(read.size(), 5, "the array keeps its length")
	if err != "":
		return err

	err = _T.assert_eq(read[0]["type"], int(Types.Item.Wood), "the entry before the junk survives")
	if err != "":
		return err

	err = _T.assert_true(read[1] == null, "unparseable text becomes an empty slot")
	if err != "":
		return err

	err = _T.assert_true(read[2] == null, "a dictionary missing 'type' becomes an empty slot")
	if err != "":
		return err

	return _T.assert_eq(read[4]["type"], int(Types.Item.Stone), "the entry after the junk still loads")


func test_a_payload_with_no_inventory_key_loads_the_rest() -> String:
	# A truncated or hand-edited save must still restore position and health rather than
	# taking the whole entry down with it.
	#
	# EXPECTED STDERR: read_slots() pushes one warning here. A save that comes back holding
	# less than it stored is exactly the thing this project's save notes say must never
	# happen quietly, so the absence of an inventory is announced rather than shrugged off.
	var payload := _through_json({
		"filepath": "/root/Main/World/Player",
		"pos": JSON.from_native(Vector2(8.0, 9.0)),
		"hp": 4,
	})

	var err: String = _T.assert_eq(Player.read_slots(payload).size(), 0, "no inventory, no slots")
	if err != "":
		return err

	return _T.assert_float_eq(Player.read_position(payload).x, 8.0, 0.0001, "the position still reads")
