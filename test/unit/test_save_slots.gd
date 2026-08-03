extends RefCounted

## The save-slot API (gather-8uy), over real files on disk.
##
## Everything here runs against a SaveLoad that was never added to the tree. That is not a
## shortcut, it is the interesting case: slot_info(), list_slots() and delete_slot() must
## never touch the tree at all — the Load screen is drawn while the current game is still
## running underneath it — and the writer has to be able to describe a save without a
## LevelUpManager or a LandManager to ask, or a unit test could not exercise it and a save
## during a scene teardown would raise. A node outside the tree is the sharpest version of
## both conditions, so the guards are tested rather than assumed.
##
## Every file written here lives under a throwaway directory in user://, reached through the
## `saves_dir` and `single_save_path` seams. Nothing touches user://saves or user://saveFile:
## this machine holds a real game in both, and a test that can eat it is a test nobody dares
## run. Same reasoning as pick_load_path() taking its candidates as arguments.

var _T

const TMP_DIR := "user://test_save_slots"

## The stand-in for user://saveFile — the single pre-slot save the migration reads.
const LEGACY_FILE := "user://test_save_slots/pre_slot_save"

var _save_load: SaveLoad


func setup() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_save_load = SaveLoad.new()
	_save_load.saves_dir = TMP_DIR
	_save_load.single_save_path = LEGACY_FILE


func teardown() -> void:
	if _save_load != null:
		# Never entered the tree, so free() rather than queue_free(): an orphan here would
		# show up in the performance gate's orphan-growth check, miles from its cause.
		_save_load.free()
		_save_load = null

	var dir := DirAccess.open(TMP_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [TMP_DIR, file])
	DirAccess.remove_absolute(TMP_DIR)


## Writes JSON lines exactly as the writer does — one object per line, store_line's newline
## included — so the reader under test meets the real format rather than an in-memory array.
func _write_lines(path: String, lines: Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	for line in lines:
		file.store_line(JSON.stringify(line))
	file.close()


## Writes raw text, for the cases that are not JSON at all.
func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_every_slot_has_a_path_and_nothing_outside_the_range_does() -> String:
	var seen: Dictionary = {}
	for slot in range(1, SaveLoad.SLOT_COUNT + 1):
		var path := SaveLoad.slot_path(slot)
		if not path.begins_with(SaveLoad.SAVES_DIR + "/"):
			return "slot_path(%d) gave '%s', which is not under %s" % [slot, path, SaveLoad.SAVES_DIR]
		if seen.has(path):
			return "slot_path(%d) collides with an earlier slot at '%s'" % [slot, path]
		seen[path] = true

	# The empty string rather than a plausible path: a caller handed "slot_0.save" would
	# create a file that list_slots() can never see again.
	var below: String = _T.assert_eq(
		SaveLoad.slot_path(0), "", "there is no slot 0"
	)
	if below != "":
		return below

	var above: String = _T.assert_eq(
		SaveLoad.slot_path(SaveLoad.SLOT_COUNT + 1), "",
		"and no slot past SLOT_COUNT"
	)
	if above != "":
		return above

	# The whole point of gather-2rb, inherited: a relative path resolves against the process
	# working directory, which in an exported build is often unwritable.
	return _T.assert_true(
		SaveLoad.SAVES_DIR.begins_with("user://"), "the slots live under user://"
	)


func test_list_slots_answers_for_every_slot_with_every_key() -> String:
	# A caller must be able to branch on a value, never on has(): the keys that go missing
	# are exactly the ones an ancient or corrupt file lacks, i.e. the rows that matter.
	var infos := _save_load.list_slots()

	var count: String = _T.assert_eq(
		infos.size(), SaveLoad.SLOT_COUNT, "one entry per slot, empty slots included"
	)
	if count != "":
		return count

	var expected_keys := ["slot", "exists", "readable", "version", "saved_at", "level", "land_radius"]
	for i in infos.size():
		var info: Dictionary = infos[i]
		var slot: String = _T.assert_eq(int(info["slot"]), i + 1, "slot 1 first, in order")
		if slot != "":
			return slot
		for key in expected_keys:
			if not info.has(key):
				return "slot %d's info is missing '%s': %s" % [i + 1, key, info]

	return ""


func test_an_empty_slot_reports_every_field_at_its_zero() -> String:
	var info := _save_load.slot_info(2)

	var exists: String = _T.assert_false(bool(info["exists"]), "nothing has been written to slot 2")
	if exists != "":
		return exists

	var readable: String = _T.assert_false(bool(info["readable"]), "and there is nothing to describe")
	if readable != "":
		return readable

	var version: String = _T.assert_eq(int(info["version"]), SaveLoad.PRE_VERSION, "version")
	if version != "":
		return version

	var saved_at: String = _T.assert_eq(int(info["saved_at"]), 0, "saved_at")
	if saved_at != "":
		return saved_at

	var level: String = _T.assert_eq(int(info["level"]), 0, "level")
	if level != "":
		return level

	return _T.assert_eq(int(info["land_radius"]), 0, "land_radius")


func test_a_written_slot_round_trips_its_metadata() -> String:
	# The real writer, not a hand-built file: this is what proves the header slot_info() reads
	# is the header save_to_slot() writes. With no tree there are no SaveLoad-group nodes to
	# enumerate, so the file is header-only — which is exactly the part under test.
	var wrote: String = _T.assert_true(
		_save_load.save_to_slot(2), "save_to_slot reports that the file landed"
	)
	if wrote != "":
		return wrote

	var slot_moved: String = _T.assert_eq(
		_save_load.current_slot, 2, "a successful save moves the slot [ and ] act on"
	)
	if slot_moved != "":
		return slot_moved

	var info := _save_load.slot_info(2)

	var exists: String = _T.assert_true(bool(info["exists"]), "the slot now holds a save")
	if exists != "":
		return exists

	var readable: String = _T.assert_true(bool(info["readable"]), "and it can be described")
	if readable != "":
		return readable

	var version: String = _T.assert_eq(
		int(info["version"]), SaveLoad.FORMAT_VERSION,
		"a file this build wrote declares the current format version"
	)
	if version != "":
		return version

	# The one field that is never zero in a real save. If the header were written without
	# metadata the row would still render, just as "level 0, saved at the epoch" — a menu that
	# lies quietly rather than one that fails.
	var saved_at: String = _T.assert_gt(
		int(info["saved_at"]), 0, "saved_at is a real unix time"
	)
	if saved_at != "":
		return saved_at

	# No LevelUpManager and no LandManager to ask, so both must read as 0 rather than raise
	# inside the writer and take the whole save with them.
	var level: String = _T.assert_eq(
		int(info["level"]), 0, "with no LevelUpManager in the tree the level reads as 0"
	)
	if level != "":
		return level

	return _T.assert_eq(
		int(info["land_radius"]), 0, "and the land radius does too"
	)


func test_a_slot_whose_header_is_garbage_is_reported_unreadable() -> String:
	# This is what lets the UI grey a corrupt slot out instead of offering to load it and
	# handing the player a half-restored world.
	_write_text(SaveLoad.slot_path_in(TMP_DIR, 3), "{ this was never a save")

	var info := _save_load.slot_info(3)

	var exists: String = _T.assert_true(bool(info["exists"]), "the file is there")
	if exists != "":
		return exists

	var readable: String = _T.assert_false(bool(info["readable"]), "but nothing about it can be read")
	if readable != "":
		return readable

	# A zero-length file is the other shape of the same failure: an interrupted rename, or a
	# disk that filled between open and write.
	_write_text(SaveLoad.slot_path_in(TMP_DIR, 1), "")
	var empty := _save_load.slot_info(1)

	var empty_exists: String = _T.assert_true(bool(empty["exists"]), "an empty file still exists")
	if empty_exists != "":
		return empty_exists

	return _T.assert_false(bool(empty["readable"]), "and is just as unreadable")


func test_a_headerless_save_is_still_offered() -> String:
	# Every save written before gather-8rs looks like this, and the pre-slot file migrated
	# into slot 1 can be one of them. Reporting it unreadable would grey out the only game a
	# returning player has — `version` is what carries the distinction, not `readable`.
	_write_lines(SaveLoad.slot_path_in(TMP_DIR, 1), [
		{"filepath": "/root/Main/World/Player", "x_pos": 3.0},
	])

	var info := _save_load.slot_info(1)

	var readable: String = _T.assert_true(
		bool(info["readable"]), "a headerless save is old, not corrupt"
	)
	if readable != "":
		return readable

	return _T.assert_eq(
		int(info["version"]), SaveLoad.PRE_VERSION,
		"and it reports itself as the pre-version format"
	)


func test_delete_slot_empties_it_and_deleting_twice_is_not_an_error() -> String:
	var wrote: String = _T.assert_true(_save_load.save_to_slot(1), "something to delete")
	if wrote != "":
		return wrote

	var deleted: String = _T.assert_true(_save_load.delete_slot(1), "delete_slot reports success")
	if deleted != "":
		return deleted

	var info := _save_load.slot_info(1)
	var gone: String = _T.assert_false(bool(info["exists"]), "the slot is empty afterwards")
	if gone != "":
		return gone

	# Idempotent on purpose: a menu that deletes an already-empty slot has nothing to tell
	# the player about, so this must not read as a failure.
	return _T.assert_true(
		_save_load.delete_slot(1), "deleting an empty slot is a no-op, not an error"
	)


func test_the_pre_slot_save_migrates_into_slot_1_exactly_once() -> String:
	# A v1 header on purpose: the migration copies bytes rather than re-serialising, so the
	# file must still declare version 1 afterwards. Restamping it FORMAT_VERSION would be a
	# claim about a payload this build never rewrote.
	_write_lines(LEGACY_FILE, [
		{"save_format_version": 1},
		{"filepath": "/root/Main/World/Player", "x_pos": 7.0},
	])
	var original := _read_text(LEGACY_FILE)

	var first: String = _T.assert_true(
		_save_load.migrate_single_save(), "the pre-slot save moves into slot 1"
	)
	if first != "":
		return first

	var info := _save_load.slot_info(1)
	var exists: String = _T.assert_true(bool(info["exists"]), "slot 1 now holds it")
	if exists != "":
		return exists

	var verbatim: String = _T.assert_eq(
		_read_text(SaveLoad.slot_path_in(TMP_DIR, 1)), original,
		"the bytes are copied, not re-serialised"
	)
	if verbatim != "":
		return verbatim

	var version: String = _T.assert_eq(
		int(info["version"]), 1,
		"so a v1 save still declares v1 in its new home"
	)
	if version != "":
		return version

	# The second run is the one that matters. By now the player may have saved over slot 1,
	# and re-running the migration would hand them back the game they had before slots
	# existed — a silent rollback of everything since.
	var second: String = _T.assert_false(
		_save_load.migrate_single_save(), "migrating a second time does nothing"
	)
	if second != "":
		return second

	_write_lines(SaveLoad.slot_path_in(TMP_DIR, 1), [SaveLoad.make_header({"level": 9})])
	var third: String = _T.assert_false(
		_save_load.migrate_single_save(), "and does nothing once the slot has been played on"
	)
	if third != "":
		return third

	return _T.assert_eq(
		int(_save_load.slot_info(1)["level"]), 9,
		"the newer save in slot 1 is untouched"
	)


func test_the_migration_leaves_the_pre_slot_save_where_it_is() -> String:
	_write_lines(LEGACY_FILE, [SaveLoad.make_header(), {"filepath": "/root/Main"}])

	var migrated: String = _T.assert_true(_save_load.migrate_single_save(), "migrated")
	if migrated != "":
		return migrated

	# Deleting it would make the change irreversible on a build rollback, and it costs one
	# file that is never read again.
	return _T.assert_true(
		FileAccess.file_exists(LEGACY_FILE),
		"the pre-slot save is still on disk after being copied"
	)


func test_collect_metadata_survives_a_tree_with_no_managers() -> String:
	# The writer calls this on every save. A raise here aborts the save silently — the method
	# is typed, so it returns as if it had worked — and the player loses the world for the
	# sake of a number on a menu row.
	var metadata := _save_load.collect_metadata()

	var saved_at: String = _T.assert_gt(
		int(metadata[SaveLoad.HEADER_SAVED_AT]), 0, "saved_at is filled in from the clock"
	)
	if saved_at != "":
		return saved_at

	var level: String = _T.assert_eq(
		int(metadata[SaveLoad.HEADER_LEVEL]), 0, "no LevelUpManager reachable, so level 0"
	)
	if level != "":
		return level

	return _T.assert_eq(
		int(metadata[SaveLoad.HEADER_LAND_RADIUS]), 0, "no LandManager reachable, so radius 0"
	)


func test_the_header_carries_its_metadata_through_json() -> String:
	var bare := SaveLoad.make_header()
	var version: String = _T.assert_eq(
		SaveLoad.header_version(bare), SaveLoad.FORMAT_VERSION,
		"a header with no metadata is still a header"
	)
	if version != "":
		return version

	# JSON has one number type, so every int in the header parses back as a float. Without the
	# coercion in header_int() a level of 7 would read as 0 and every slot row would say 0.
	var stamped := SaveLoad.make_header({
		SaveLoad.HEADER_SAVED_AT: 1700000000,
		SaveLoad.HEADER_LEVEL: 7,
		SaveLoad.HEADER_LAND_RADIUS: 12,
	})
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(stamped))

	var level: String = _T.assert_eq(
		SaveLoad.header_int(parsed, SaveLoad.HEADER_LEVEL), 7, "level survives the round trip"
	)
	if level != "":
		return level

	var radius: String = _T.assert_eq(
		SaveLoad.header_int(parsed, SaveLoad.HEADER_LAND_RADIUS), 12, "and so does land_radius"
	)
	if radius != "":
		return radius

	var missing: String = _T.assert_eq(
		SaveLoad.header_int({SaveLoad.HEADER_KEY: 1}, SaveLoad.HEADER_LEVEL), 0,
		"a v1 header has no metadata at all and must read as 0, not raise"
	)
	if missing != "":
		return missing

	# The metadata must not make the header look like something to hand to a node.
	return _T.assert_false(
		SaveLoad.is_node_entry(stamped), "a header with metadata is still not a node entry"
	)


func test_a_slot_stages_its_write_through_a_neighbouring_temp_file() -> String:
	# The rename that finishes a save is only atomic within one filesystem, so the temp file
	# has to sit beside its destination. It is also what keeps the pre-slot write unchanged.
	var legacy: String = _T.assert_eq(
		SaveLoad.temp_path_for(SaveLoad.SAVE_PATH), SaveLoad.TEMP_SAVE_PATH,
		"the pre-slot save still stages through TEMP_SAVE_PATH"
	)
	if legacy != "":
		return legacy

	var slot_file := SaveLoad.slot_path(1)
	return _T.assert_eq(
		SaveLoad.temp_path_for(slot_file).get_base_dir(), slot_file.get_base_dir(),
		"a slot's temp file shares its directory"
	)
