extends Control
class_name SaveLoad

var loads = []

## The version of the on-disk format this build writes, stamped into the header line of
## every save (gather-8rs).
##
## LEGACY_PATHS below migrates node *paths*; nothing migrated the *shape* of a payload, so
## every change to a saveObject() so far has had to be absorbed by defensive has() checks in
## the matching loadObject (enemy_spawner.gd, level_up_manager.gd, bone_worker.gd all carry
## one). Those checks guess. A version lets the next such change be a migration that knows.
##
## Bump this only when the payload shape actually changes, and add the migration in the same
## commit — a version nobody branches on is worse than none, because it looks like a promise.
const FORMAT_VERSION := 1

## The version reported for a file with no header, i.e. every save written before gather-8rs.
const PRE_VERSION := 0

## header_version()'s answer for a line that is an ordinary entry. Distinct from PRE_VERSION:
## "this line is not a header" and "this file predates headers" are different facts.
const NOT_A_HEADER := -1

## The key the header line is recognised by. No saveObject() produces it, which is what lets
## the reader tell a header from an entry without depending on line order.
const HEADER_KEY := "save_format_version"

## Where saves live now (gather-2rb). A bare "saveFile" resolves against the process working
## directory: the project root under the editor, but the install directory in an exported
## build — frequently unwritable on Windows, in which case saving silently did nothing and
## the player lost everything on quit. user:// is per-user and always writable.
const SAVE_PATH := "user://saveFile"

## The pre-gather-2rb location, still read once if it is the only save present, so nobody
## with a game in progress loses it to this change.
const LEGACY_SAVE_PATH := "saveFile"

## Saves are written here first and renamed over SAVE_PATH (gather-pjp). Writing straight
## into the destination meant a crash, an alt-F4 or a power cut part-way through left a
## truncated file, and _load() reads line by line: the player gets a partial world restored
## with no error they can act on. The rename is the only step that can lose the old save, and
## it is atomic. `*.tmp` is gitignored, though under user:// that hardly matters.
const TEMP_SAVE_PATH := "user://saveFile.tmp"

## The format version of the file the last _load() read: FORMAT_VERSION for a save this build
## wrote, PRE_VERSION for anything older. This is the field a future migration branches on.
var loaded_format_version: int = PRE_VERSION

## Node paths that moved when main.tscn's tree was reorganised, old -> new.
##
## Every saveObject() keys its entry on get_path(), an absolute runtime path, and
## _load() resolves it with has_node(). A path that no longer exists does not raise
## — the `elif` simply falls through and that node's entire state is dropped in
## silence. So renaming a node in main.tscn invalidates part of every save written
## before the rename, with no symptom beyond a player who comes back at the origin
## with an empty inventory.
##
## Keep entries here forever: they cost one dictionary lookup and they are the only
## thing standing between a tree cleanup and a wiped save.
const LEGACY_PATHS := {
	"/root/Main/Node2D/Player": "/root/Main/World/Player",
	"/root/Main/Node2D/EnemySpawner": "/root/Main/World/EnemySpawner",
	"/root/Main/Node2D/Player/Camera2D/UI/LevelUpUI": "/root/Main/Systems/LevelUpManager",
	# The intermediate home the node held for one step of the same restructure, before
	# it was recognised as a model rather than a HUD widget. Cheap to keep, and the
	# alternative is a save written between the two steps silently losing its levels.
	"/root/Main/World/Player/Camera2D/HUD/LevelUpManager": "/root/Main/Systems/LevelUpManager",
	"/root/Main/ResourceManager": "/root/Main/Systems/ResourceManager",
}


## The path an entry should be loaded into, following LEGACY_PATHS if the saved one
## predates a rename.
static func migrate_path(filepath: String) -> String:
	return LEGACY_PATHS.get(filepath, filepath)


## The header line written at the top of every save.
static func make_header() -> Dictionary:
	return {HEADER_KEY: FORMAT_VERSION}


## The format version a parsed line declares, or NOT_A_HEADER if it is an ordinary entry.
##
## Every line in the file is a JSON object and the reader has always treated all of them as
## entries, so a header can only be added by making it recognisable from its contents. That
## check has to run before the filepath guard below, or the header itself gets reported as a
## saveObject() that failed.
static func header_version(entry: Variant) -> int:
	if entry is not Dictionary or not entry.has(HEADER_KEY):
		return NOT_A_HEADER

	var raw: Variant = entry[HEADER_KEY]
	# JSON has a single number type, so an int stored here parses back as a float.
	if raw is float or raw is int:
		return int(raw)

	# The key is present, so this line is a header and must not be handed to a node — but
	# its version is unreadable. PRE_VERSION is the conservative answer: it is the value
	# that tells a future migration to inspect the payload rather than trust the header.
	push_warning("SaveLoad: header line carries a non-numeric version (%s), reading the file as pre-version" % [raw])
	return PRE_VERSION


## Whether a parsed line is something _load() can hand to a node.
##
## A line that is not a dictionary, or a dictionary with no filepath, is a saveObject() that
## aborted mid-way: a typed `-> Dictionary` still returns {} when the body raises. Chunk
## payloads are checked by this too — they carry a dummy "filepath" (see bone_worker.save())
## purely to satisfy it, so loosening the guard for them would change what they must emit.
static func is_node_entry(entry: Variant) -> bool:
	return entry is Dictionary and entry.has("filepath")


## Which of the two save locations a load should read, or "" if there is no save at all.
##
## Split out from resolve_load_path() so a test can exercise the precedence over throwaway
## files instead of over the developer's own saveFile.
static func pick_load_path(primary: String, legacy: String) -> String:
	if FileAccess.file_exists(primary):
		return primary
	if FileAccess.file_exists(legacy):
		return legacy
	return ""


## The save this build should load: user:// wins, and the pre-gather-2rb location is only
## consulted when nothing has been written to user:// yet.
static func resolve_load_path() -> String:
	return pick_load_path(SAVE_PATH, LEGACY_SAVE_PATH)


## Parses a save file into the two kinds of payload it holds, touching no nodes.
##
## Everything that knows about the on-disk format lives here — the header, the entry guard,
## the split between node entries and position-keyed chunks — so a test can drive the real
## reader over a real file. A test that re-implemented this loop would only prove that the
## test agrees with itself.
##
## Returns {"version": int, "entries": Array, "chunks": Array}. A file that cannot be opened
## reads as an empty pre-version save rather than raising: the callers below already have a
## no-save path, and half-loading is the failure mode this whole file exists to avoid.
static func read_save(path: String) -> Dictionary:
	var entries: Array = []
	var chunks: Array = []
	var file_version := PRE_VERSION

	var save_file := FileAccess.open(path, FileAccess.READ)
	if save_file == null:
		push_warning("SaveLoad: could not open '%s' for reading (error %d)" % [path, FileAccess.get_open_error()])
		return {"version": file_version, "entries": entries, "chunks": chunks}

	var seen_header := false
	while save_file.get_position() < save_file.get_length():
		# Get the saved dictionary from the next line in the save file
		var json := JSON.new()
		json.parse(save_file.get_line())

		# Get the Data
		var node_data: Variant = json.get_data()

		var version := header_version(node_data)
		if version != NOT_A_HEADER:
			# Only the first header counts. A second one would mean two saves concatenated,
			# which the entry loop below already handles as "last writer wins" per node.
			if not seen_header:
				file_version = version
				seen_header = true
			continue

		# Skipping a malformed entry loses that one node's state, which is what already
		# happened — reading ["filepath"] off it only added a second error on top and
		# stopped the rest of the file being read.
		if not is_node_entry(node_data):
			push_warning("SaveLoad: skipping an entry with no filepath (a saveObject likely failed)")
			continue

		if node_data.has("x") and node_data.has("y"):
			chunks.append(node_data)
		else:
			entries.append(node_data)

	save_file.close()
	return {"version": file_version, "entries": entries, "chunks": chunks}


func _on_save_pressed() -> void:
	_save()

	print("GAME SAVED")

func _on_load_pressed() -> void:
	_load()
	print("GAME LOADED")

func _process(_delta):
	if Input.is_action_just_pressed("save"):
		_save()
	if Input.is_action_just_pressed("load"):
		_load()

## Hands the position-keyed payloads collected by _load() to the scene tiles they belong
## to. Must run at least one frame after the tilemap is replayed — a scene tile is
## instantiated by the engine the frame *after* its cell is written, so calling this any
## earlier walks an empty SaveChunks group and every chest and crafting station in the
## world comes back empty (gather-74z). main.gd:_finish_load owns that await.
func late_load():
	var chunk_nodes = get_tree().get_nodes_in_group("SaveChunks")
	for chunk in chunk_nodes:
		if !chunk.has_method("load"):
			print("Node '%s' is missing a save function, skipped" % chunk.name)
			continue

		for i in loads.size():
			var dict = loads[i]
			if dict["x"] == chunk.position.x and dict["y"] == chunk.position.y:
				chunk.call("load", dict)

func _save() -> void:
	# Write to the temp path, never to SAVE_PATH. Until the rename at the bottom of this
	# function runs, the previous good save is still whole on disk.
	var save_file := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE) # Open File
	if save_file == null:
		push_warning("SaveLoad: could not open '%s' for writing (error %d); nothing was saved and the previous save is untouched" % [TEMP_SAVE_PATH, FileAccess.get_open_error()])
		return

	# The header goes first so a human reading the file sees the version before the payload.
	# The reader does not depend on that position — see header_version().
	save_file.store_line(JSON.stringify(make_header()))

	# Go through every object in the SaveLoad group
	var save_nodes = get_tree().get_nodes_in_group("SaveLoad")
	for node in save_nodes:
		# Check if the node has a save function.
		if !node.has_method("saveObject"):
			print("Node '%s' is missing a save function, skipped" % node.name)
			continue

		# Call the node's save function.
		var node_data = node.call("saveObject")

		# Store the save dictionary as a new line in the save file.
		print(JSON.stringify(node_data))
		save_file.store_line(JSON.stringify(node_data))

	var chunk_nodes = get_tree().get_nodes_in_group("SaveChunks")
	for chunk in chunk_nodes:
		if !chunk.has_method("save"):
			print("Node '%s' is missing a save function, skipped" % chunk.name)
			continue
		var chunk_data = chunk.call("save")
		save_file.store_line(JSON.stringify(chunk_data))

	save_file.close() # Close File

	# The whole file is on disk and closed before anything touches SAVE_PATH, so the swap
	# either happens or does not. An interrupted save leaves a stray .tmp and the previous
	# save intact, which is the outcome this is for.
	var err := DirAccess.rename_absolute(TEMP_SAVE_PATH, SAVE_PATH)
	if err != OK:
		push_warning("SaveLoad: could not move '%s' over '%s' (error %d); the previous save is intact and the new one is still at the temp path" % [TEMP_SAVE_PATH, SAVE_PATH, err])

func _load() -> void:
	# Check if the SaveFile exists
	var path := resolve_load_path()
	if path == "":
		print("Error, no Save File to load.")
		return

	var save := read_save(path)
	loaded_format_version = int(save["version"])

	# `loads` holds the payloads for the load currently in progress and nothing else.
	# It used to accumulate for the lifetime of the session, so a second load applied
	# both the stale payload and the fresh one to every chunk at a matching position.
	loads.clear()
	var chunks: Array = save["chunks"]
	loads.append_array(chunks)

	var entries: Array = save["entries"]
	for node_data in entries:
		var filepath: String = migrate_path(str(node_data["filepath"]))
		if has_node(filepath):
			get_node(filepath).loadObject(node_data)
		else:
			# Previously a silent fall-through, which is how a renamed node
			# loses its state without anyone noticing.
			push_warning("SaveLoad: no node at '%s', that entry was not restored" % filepath)

	if path == LEGACY_SAVE_PATH:
		_migrate_legacy_save()

## Copies a save found at the pre-gather-2rb location into user://, so the fallback in
## pick_load_path() is never consulted again for this player.
##
## Runs only after that file has been read, so a crash during load cannot consume the one
## copy that exists. The bytes are copied verbatim rather than re-serialised: a headerless
## file still loads, and stamping FORMAT_VERSION onto a payload this build has not actually
## rewritten would be a claim about its shape that is not true.
##
## The old file is deliberately left where it is. Once the user:// copy exists it is never
## read again, and deleting a file outside user:// — in a directory the game may not own —
## is a larger promise than this migration needs to make.
func _migrate_legacy_save() -> void:
	var bytes := FileAccess.get_file_as_bytes(LEGACY_SAVE_PATH)
	if bytes.is_empty():
		return

	var out := FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	if out == null:
		push_warning("SaveLoad: could not open '%s' to migrate the legacy save (error %d)" % [TEMP_SAVE_PATH, FileAccess.get_open_error()])
		return
	out.store_buffer(bytes)
	out.close()

	var err := DirAccess.rename_absolute(TEMP_SAVE_PATH, SAVE_PATH)
	if err != OK:
		push_warning("SaveLoad: could not move the legacy save to '%s' (error %d); it stays where it is and will be read again next time" % [SAVE_PATH, err])
		return

	print("SaveLoad: migrated the legacy save at '%s' to '%s'" % [LEGACY_SAVE_PATH, SAVE_PATH])

## Dead code: nothing calls this, main.gd included. It is kept in step with _load() — same
## path resolution, same header skip, same entry guard — so that it cannot become the one
## reader that chokes on a header line, but it should probably be deleted outright in a
## change of its own rather than maintained forever.
func _load_tilemap() -> void:
	# Check if the SaveFile exists
	var path := resolve_load_path()
	if path == "":
		print("Error, no Save File to load.")
		return

	var save := read_save(path)

	var entries: Array = save["entries"]
	for node_data in entries:
		print(node_data)
		var filepath: String = migrate_path(str(node_data["filepath"]))
		if has_node(filepath) and filepath == "/root/Main":
			print("loading tilemap")
			get_node(filepath).loadObject(node_data)
