extends RefCounted

## The save file's reader, over real files on disk.
##
## SaveLoad._load() itself needs a live scene tree — it resolves every entry with has_node()
## against /root/Main — and headless pumps no frames, so these tests drive the static half:
## read_save(), which owns everything that knows about the format, plus the pure helpers
## around it. The tree-dependent half of _load() is now only "hand each entry to its node".
##
## Every file written here lives under a throwaway directory in user://. Nothing touches
## user://saveFile: these tests must not be able to eat the developer's own game.

var _T

const TMP_DIR := "user://test_save_load"


func setup() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)


func teardown() -> void:
	var dir := DirAccess.open(TMP_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [TMP_DIR, file])
	DirAccess.remove_absolute(TMP_DIR)


## Writes the lines exactly as _save() would: one JSON object per line, store_line's newline
## included. Going through the file rather than calling read_save on an in-memory array is
## the point — JSON is the real contract, and it is what turns the header's int into a float.
func _write_save(name: String, lines: Array) -> String:
	var path := "%s/%s" % [TMP_DIR, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	for line in lines:
		file.store_line(JSON.stringify(line))
	file.close()
	return path


func _entry(filepath: String, extra: Dictionary = {}) -> Dictionary:
	var out := {"filepath": filepath}
	out.merge(extra)
	return out


func test_a_versioned_file_round_trips() -> String:
	var path := _write_save("versioned", [
		SaveLoad.make_header(),
		_entry("/root/Main/World/Player", {"x_pos": 12.0}),
		_entry("/root/Main/Systems/LevelUpManager", {"xp": 40}),
		# A chunk payload: keyed on position, deferred to late_load(). It carries a dummy
		# "filepath" for the entry guard, exactly as bone_worker.save() does.
		{"filepath": "343", "x": 112.0, "y": -48.0, "data": {"loaded": true}},
	])

	var save := SaveLoad.read_save(path)
	var entries: Array = save["entries"]
	var chunks: Array = save["chunks"]

	var version: String = _T.assert_eq(
		int(save["version"]), SaveLoad.FORMAT_VERSION,
		"a file this build wrote should report the current format version"
	)
	if version != "":
		return version

	var entry_count: String = _T.assert_eq(
		entries.size(), 2, "both node entries survived the round trip"
	)
	if entry_count != "":
		return entry_count

	var chunk_count: String = _T.assert_eq(
		chunks.size(), 1, "the x/y payload went to chunks, not to the node entries"
	)
	if chunk_count != "":
		return chunk_count

	# late_load() matches on these two floats; if they came back as anything else, every
	# chest in the world would load empty and nothing would report an error.
	var chunk: Dictionary = chunks[0]
	var cx: String = _T.assert_float_eq(chunk["x"], 112.0, 0.0001, "chunk x")
	if cx != "":
		return cx

	var first: Dictionary = entries[0]
	return _T.assert_eq(
		str(first["filepath"]), "/root/Main/World/Player",
		"entries keep their order and their filepath"
	)


func test_a_pre_version_file_still_loads() -> String:
	# Every save on any player's disk today looks like this: no header, entries only.
	# Refusing to read it, or reading it as version 1, both lose the game.
	var path := _write_save("headerless", [
		_entry("/root/Main/World/Player", {"x_pos": 3.0}),
		_entry("/root/Main/World/EnemySpawner", {"enemies": []}),
	])

	var save := SaveLoad.read_save(path)
	var entries: Array = save["entries"]

	var version: String = _T.assert_eq(
		int(save["version"]), SaveLoad.PRE_VERSION,
		"a file with no header is the pre-version format, not the current one"
	)
	if version != "":
		return version

	return _T.assert_eq(entries.size(), 2, "and its entries all still load")


func test_the_header_is_not_mistaken_for_a_node_entry() -> String:
	# The failure this guards: the header reaching the entry loop, where it either trips the
	# no-filepath warning or — worse, if it ever grew a "filepath" key — gets handed to a
	# node as state.
	var path := _write_save("header_only_first", [
		SaveLoad.make_header(),
		_entry("/root/Main/World/Player"),
	])

	var save := SaveLoad.read_save(path)
	var entries: Array = save["entries"]

	var count: String = _T.assert_eq(
		entries.size(), 1, "the header must not be counted as an entry"
	)
	if count != "":
		return count

	for entry in entries:
		if entry.has(SaveLoad.HEADER_KEY):
			return "a header line was handed through as a node entry: %s" % [entry]

	return _T.assert_false(
		SaveLoad.is_node_entry(SaveLoad.make_header()),
		"the header is not a node entry"
	)


func test_header_version_reads_a_header_and_ignores_an_entry() -> String:
	var header: String = _T.assert_eq(
		SaveLoad.header_version(SaveLoad.make_header()), SaveLoad.FORMAT_VERSION,
		"header_version reads the version out of a header"
	)
	if header != "":
		return header

	# JSON has one number type, so a version written as an int parses back as a float. If
	# that were not coerced, the version would compare unequal to FORMAT_VERSION forever.
	var parsed: Variant = JSON.parse_string(JSON.stringify(SaveLoad.make_header()))
	var round_tripped: String = _T.assert_eq(
		SaveLoad.header_version(parsed), SaveLoad.FORMAT_VERSION,
		"a header that has been through JSON still reads as the current version"
	)
	if round_tripped != "":
		return round_tripped

	var entry: String = _T.assert_eq(
		SaveLoad.header_version({"filepath": "/root/Main"}), SaveLoad.NOT_A_HEADER,
		"an ordinary entry is not a header"
	)
	if entry != "":
		return entry

	return _T.assert_eq(
		SaveLoad.header_version(null), SaveLoad.NOT_A_HEADER,
		"a line that did not parse is not a header either"
	)


func test_an_entry_with_no_filepath_is_skipped_and_the_rest_still_read() -> String:
	# A saveObject() whose body raises still returns {} because it is typed `-> Dictionary`.
	# Reading ["filepath"] off that used to raise a second error and stop the file being
	# read at all, so one broken node took the whole save with it. The push_warning this
	# produces on stderr is expected.
	var path := _write_save("broken_entry", [
		SaveLoad.make_header(),
		{},
		_entry("/root/Main/World/Player"),
	])

	var save := SaveLoad.read_save(path)
	var entries: Array = save["entries"]

	return _T.assert_eq(
		entries.size(), 1,
		"the entry after the broken one must still be read"
	)


func test_migrate_path_maps_every_legacy_path() -> String:
	# LEGACY_PATHS is the only thing standing between a tree rename and a wiped save, and
	# nothing else in the project exercises it.
	for key in SaveLoad.LEGACY_PATHS.keys():
		var old_path: String = key
		var expected: String = SaveLoad.LEGACY_PATHS[key]
		var mapped := SaveLoad.migrate_path(old_path)
		if mapped != expected:
			return "migrate_path('%s') gave '%s', expected '%s'" % [old_path, mapped, expected]

		# The new path must be a fixed point, or a save written after the rename would be
		# migrated a second time to somewhere that does not exist.
		var again := SaveLoad.migrate_path(expected)
		if again != expected:
			return "migrate_path('%s') moved an already-current path to '%s'" % [expected, again]

	return _T.assert_eq(
		SaveLoad.migrate_path("/root/Main/World/PickUps"), "/root/Main/World/PickUps",
		"a path with no legacy entry is returned unchanged"
	)


func test_the_user_save_wins_over_the_legacy_one() -> String:
	# gather-2rb: the old working-directory-relative save is read only while nothing has
	# been written to user:// yet. If the precedence inverted, a player who kept playing
	# would load a stale file every launch and never notice.
	var primary := _write_save("primary", [SaveLoad.make_header()])
	var legacy := _write_save("legacy", [])

	var both: String = _T.assert_eq(
		SaveLoad.pick_load_path(primary, legacy), primary,
		"with both present the user:// save is the one loaded"
	)
	if both != "":
		return both

	DirAccess.remove_absolute(primary)
	var only_legacy: String = _T.assert_eq(
		SaveLoad.pick_load_path(primary, legacy), legacy,
		"with only the legacy save present it is loaded rather than lost"
	)
	if only_legacy != "":
		return only_legacy

	DirAccess.remove_absolute(legacy)
	return _T.assert_eq(
		SaveLoad.pick_load_path(primary, legacy), "",
		"with neither present the caller gets the empty string and prints 'no Save File'"
	)


func test_the_live_paths_are_under_user() -> String:
	# The whole point of gather-2rb: a bare relative path resolves against the process
	# working directory, which in an exported build is the install directory and is often
	# unwritable. Both the destination and the temp file it is renamed from must be in
	# user://, or the rename crosses a filesystem boundary and stops being atomic.
	var dest: String = _T.assert_true(
		SaveLoad.SAVE_PATH.begins_with("user://"), "SAVE_PATH is under user://"
	)
	if dest != "":
		return dest

	return _T.assert_true(
		SaveLoad.TEMP_SAVE_PATH.begins_with("user://"),
		"the temp file is under user:// too, so the rename over SAVE_PATH is a same-volume move"
	)


# --- chunk kind tagging (gather-34n) -----------------------------------------


func test_an_untagged_payload_is_accepted_by_anything() -> String:
	# Every save written before the tag existed has no "kind", and those payloads must keep
	# matching exactly as they did — the tag can only ever NARROW a match that would
	# otherwise have been made blind. Getting this backwards would invalidate every existing
	# save at once, which is the failure this whole file exists to prevent.
	var node := CraftingStation.new()
	var accepted: bool = SaveLoad.chunk_kind_matches({"x": 0.0, "y": 0.0}, node)
	node.free()

	return _T.assert_true(accepted, "a payload with no kind still applies")


func test_a_payload_is_refused_by_a_different_kind_of_node() -> String:
	# The hazard the tag exists for. Chunk payloads are matched to nodes by POSITION alone,
	# and all four chunk classes carry the same dummy "filepath": "343", so a turret's
	# payload could be handed to a worker that ended up on the same coordinates. The
	# receiving load() is fully defaulted, so it would not raise — it would quietly restore
	# defaults for everything, which is this file's signature failure mode.
	var turret := BoneTurret.new()
	var station := CraftingStation.new()

	var payload := {"x": 0.0, "y": 0.0, SaveLoad.CHUNK_KIND: SaveLoad.chunk_kind_of(turret)}
	var to_turret: bool = SaveLoad.chunk_kind_matches(payload, turret)
	var to_station: bool = SaveLoad.chunk_kind_matches(payload, station)

	turret.free()
	station.free()

	var err: String = _T.assert_true(to_turret, "the turret's own payload still applies to it")
	if err != "":
		return err
	return _T.assert_false(to_station, "and is refused by a station at the same position")


func test_the_kind_is_the_script_class_name() -> String:
	# Keyed on class_name rather than on the engine class, because all four chunk classes
	# would otherwise collide on Node2D and the tag would distinguish nothing.
	var station := CraftingStation.new()
	var kind: String = SaveLoad.chunk_kind_of(station)
	station.free()

	return _T.assert_eq(kind, "CraftingStation", "the tag names the script's class")
