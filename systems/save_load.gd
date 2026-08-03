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
##
## 2 (gather-8uy): the *header* grew. It now carries saved_at, level and land_radius so a
## Load Game screen can draw a slot row without loading the save into the tree. No entry
## changed shape, which is why the bump ships without a migration: every v1 and pre-version
## file still loads exactly as it did, and slot_info() reports zeros for metadata that is not
## there. The version moved anyway, because "this file has a metadata header" is a fact a
## reader must be able to establish from the version alone rather than by probing for keys.
const FORMAT_VERSION := 2

## The version reported for a file with no header, i.e. every save written before gather-8rs.
const PRE_VERSION := 0

## header_version()'s answer for a line that is an ordinary entry. Distinct from PRE_VERSION:
## "this line is not a header" and "this file predates headers" are different facts.
const NOT_A_HEADER := -1

## The key the header line is recognised by. No saveObject() produces it, which is what lets
## the reader tell a header from an entry without depending on line order.
const HEADER_KEY := "save_format_version"

## The metadata keys a v2 header carries alongside HEADER_KEY (gather-8uy).
##
## They exist so a Load Game screen can render "Level 7 · radius 12 · saved yesterday" from
## the FIRST LINE of a file. The alternative is parsing every entry of every slot each time
## the screen opens, and there is nowhere to put the result once parsed: loadObject() is the
## only thing that understands an entry, and it applies it to the live tree — which is the
## game the player has not left yet.
##
## These are metadata, not state. Nothing loads from them, nothing branches on them, and a
## header that lacks them is still a perfectly loadable save. See slot_info().
const HEADER_SAVED_AT := "saved_at"
const HEADER_LEVEL := "level"
const HEADER_LAND_RADIUS := "land_radius"

## Where the numbered save slots live (gather-8uy). Created on demand: an installed build has
## never written a save, so this directory does not exist until the first one.
const SAVES_DIR := "user://saves"

## How many slots the game offers. Slot numbers are 1-based and there is no slot 0 — the
## number is shown to the player, and nobody has ever wanted to read "Slot 0".
const SLOT_COUNT := 3

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

## The slot `[` and `]` act on: the last one saved to or loaded from. Starts at 1 so a fresh
## install quicksaves somewhere sensible without the player having to pick a slot first.
##
## Deliberately not persisted anywhere. It is a property of this session, and a file that
## remembered it would be a fourth thing on disk that can disagree with the other three.
var current_slot := 1

## Test seam. Every slot file is addressed through _slot_path(), which reads this, so a unit
## test can point the whole slot API at a throwaway directory instead of at user://saves —
## where the developer's real game lives. Same reasoning as pick_load_path() taking its two
## candidate paths as arguments rather than reading the constants directly.
var saves_dir: String = SAVES_DIR

## The other half of that seam: the pre-slot save the one-time migration reads from. Empty
## means "work it out from SAVE_PATH / LEGACY_SAVE_PATH", which is what the game wants; a
## test sets it so migrating cannot reach the developer's own saveFile.
var single_save_path: String = ""

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
##
## `metadata` is merged in rather than gathered here, because this is static: the version is
## a property of the build, the metadata is a property of the running game (see
## collect_metadata()). A caller that only wants a well-formed header — a test, or anything
## checking the version — passes nothing and gets one whose metadata reads as zeros, which is
## exactly how a v1 header reads too.
static func make_header(metadata: Dictionary = {}) -> Dictionary:
	var header := {HEADER_KEY: FORMAT_VERSION}
	header.merge(metadata)
	return header


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


## Whether `slot` is a slot this build has. Slots are 1-based; see SLOT_COUNT.
static func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


## The file a slot lives in under `dir`, or "" for a slot number that does not exist.
##
## The empty string rather than a plausible-looking "slot_0.save": a caller that got a path
## for a slot the game does not have would go on to create it, and the file would then be
## invisible to list_slots() forever after.
static func slot_path_in(dir: String, slot: int) -> String:
	if not is_valid_slot(slot):
		return ""
	return "%s/slot_%d.save" % [dir, slot]


static func slot_path(slot: int) -> String:
	return slot_path_in(SAVES_DIR, slot)


## The same, honouring this instance's saves_dir so a test can redirect it.
func _slot_path(slot: int) -> String:
	return slot_path_in(saves_dir, slot)


## The temp file a write to `path` stages through, in the same directory as its destination.
## Both halves matter: the rename that follows is only atomic within one filesystem, and
## user:// is not necessarily on the same volume as anywhere else. For SAVE_PATH this is
## exactly TEMP_SAVE_PATH, which is what keeps the pre-slot write path unchanged.
static func temp_path_for(path: String) -> String:
	return path + ".tmp"


## A slot with nothing in it — and the shape of every answer slot_info() gives.
##
## Every key is always present, so a caller branches on a VALUE and never on has(). A UI that
## had to check presence would grow a separate code path per key, and the keys that go
## missing are exactly the ones an ancient or corrupt file lacks: the cases that matter most
## and get exercised least.
static func empty_slot_info(slot: int) -> Dictionary:
	return {
		"slot": slot,
		"exists": false,
		"readable": false,
		"version": PRE_VERSION,
		"saved_at": 0,
		"level": 0,
		"land_radius": 0,
	}


## Reads one metadata field out of a parsed header.
##
## JSON has a single number type, so every int written into the header comes back a float;
## and a header written by an older build has none of these keys at all. Both have to read as
## 0 rather than as an error — the whole point of the metadata is to describe a file this
## build did not necessarily write.
static func header_int(header: Dictionary, key: String) -> int:
	var raw: Variant = header.get(key, 0)
	if raw is float or raw is int:
		return int(raw)
	return 0


## One save's metadata, read from its first line and nothing else.
##
## Deliberately does not call read_save(): listing three slots must not mean parsing three
## whole worlds, and nothing here may touch the tree, because the Load screen is drawn while
## the current game is still running underneath it.
##
## `readable` answers "can this file be described", not "is this file loadable". A first line
## that is not a JSON object at all is corrupt or truncated, and the UI greys the slot out
## rather than offering to load it. A first line that is a valid *entry* is not corrupt — it
## is a save written before headers existed, which loads perfectly well and must stay
## offerable; slot 1 holds exactly such a file for anyone whose game predates gather-8rs. So
## readable is false only for the genuinely unparseable case, and `version` carries the
## PRE_VERSION / v1 / v2 distinction on its own.
static func info_for_path(slot: int, path: String) -> Dictionary:
	var info := empty_slot_info(slot)
	if path == "" or not FileAccess.file_exists(path):
		return info

	info["exists"] = true

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveLoad: '%s' exists but could not be opened (error %d)" % [path, FileAccess.get_open_error()])
		return info

	var first_line := ""
	if file.get_position() < file.get_length():
		first_line = file.get_line()
	file.close()

	var parsed: Variant = JSON.parse_string(first_line)
	if parsed is not Dictionary:
		# An empty file, a half-written first line, or something that was never a save.
		return info

	var header: Dictionary = parsed
	var version := header_version(header)
	if version == NOT_A_HEADER:
		# A headerless save: readable, loadable, and pre-version by definition.
		info["readable"] = true
		return info

	info["readable"] = true
	info["version"] = version
	info["saved_at"] = header_int(header, HEADER_SAVED_AT)
	info["level"] = header_int(header, HEADER_LEVEL)
	info["land_radius"] = header_int(header, HEADER_LAND_RADIUS)
	return info


## Every slot under `dir`, slot 1 first, empty slots included. Split from list_slots() for
## the same reason as pick_load_path(): so a test can drive it over throwaway files.
static func list_slots_in(dir: String) -> Array:
	var out: Array = []
	for slot in range(1, SLOT_COUNT + 1):
		out.append(info_for_path(slot, slot_path_in(dir, slot)))
	return out


## One slot's metadata. Never loads the save into the tree.
func slot_info(slot: int) -> Dictionary:
	return info_for_path(slot, _slot_path(slot))


## Exactly SLOT_COUNT entries, slot 1 first, each of the shape empty_slot_info() describes.
func list_slots() -> Array:
	return list_slots_in(saves_dir)


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


## Pure file IO, deliberately: this runs before anything else in the tree is guaranteed to
## exist, and both halves only touch user://. Creating the directory here rather than lazily
## means the very first quicksave of a fresh install finds somewhere to write, and the
## migration runs once at the only moment nobody can be mid-save.
func _ready() -> void:
	_ensure_saves_dir()
	migrate_single_save()


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

## Quicksave. Signature unchanged on purpose: ui/debug_panel_ui.gd, the devtools verbs and
## every existing test call this and _load() by name.
func _save() -> void:
	save_to_slot(current_slot)


## Quickload, against the same slot.
func _load() -> void:
	load_from_slot(current_slot)


## Makes SAVES_DIR exist. An installed build has never saved, so the directory is absent on
## first run and every FileAccess.open() below it fails — silently, from the player's point of
## view, which is precisely the failure mode gather-2rb already paid for once.
func _ensure_saves_dir() -> bool:
	if DirAccess.dir_exists_absolute(saves_dir):
		return true

	var err := DirAccess.make_dir_recursive_absolute(saves_dir)
	# Checked rather than trusted: two instances racing to create it is a benign error, an
	# unwritable user:// is not, and only the second reading leaves nothing on disk.
	if err != OK and not DirAccess.dir_exists_absolute(saves_dir):
		push_warning("SaveLoad: could not create '%s' (error %d); nothing was saved" % [saves_dir, err])
		return false
	return true


## Writes the whole world into `slot`. Returns whether the save actually landed on disk, so a
## menu can tell the player it failed instead of drawing an empty row a moment later.
func save_to_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		push_warning("SaveLoad: slot %d is outside 1..%d, nothing was saved" % [slot, SLOT_COUNT])
		return false

	if not _ensure_saves_dir():
		return false

	if not write_save_to(_slot_path(slot)):
		return false

	# Only on success: a failed save must not move where `[` and `]` point, or the next
	# quickload silently reads a different game than the one the player was playing.
	current_slot = slot
	return true


## Loads `slot` into the live tree. Returns false when there was nothing to load.
func load_from_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		push_warning("SaveLoad: slot %d is outside 1..%d, nothing was loaded" % [slot, SLOT_COUNT])
		return false

	# Every entry is resolved with has_node() against an absolute path, which needs this node
	# to be in a tree. Out of the tree the loop below would warn once per entry and restore
	# nothing, which reads like a corrupt save rather than a misuse.
	if not is_inside_tree():
		push_warning("SaveLoad: not in the tree, there is nothing to load a save into")
		return false

	var slot_file := _slot_path(slot)
	var path := resolve_slot_load_path(slot)
	if path == "":
		print("Error, no Save File to load.")
		return false

	load_save_from(path)
	current_slot = slot

	# Both migrations run only after the file has been read, so a crash during load cannot
	# consume the one copy that exists. Chained: the pre-gather-2rb file is copied into
	# user:// first, then user://saveFile is copied into slot 1.
	if path == LEGACY_SAVE_PATH:
		_migrate_legacy_save()
	if path != slot_file:
		migrate_single_save()

	return true


## Empties a slot. Returns whether the slot is empty when the call returns, so deleting one
## that was already empty is a success rather than an error a menu has to explain.
func delete_slot(slot: int) -> bool:
	if not is_valid_slot(slot):
		push_warning("SaveLoad: slot %d is outside 1..%d, nothing was deleted" % [slot, SLOT_COUNT])
		return false

	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			push_warning("SaveLoad: could not delete '%s' (error %d); the slot still holds a save" % [path, err])
			return false

	# An interrupted write leaves a .tmp beside the slot. It is dead weight either way, but
	# leaving it behind a delete means the next write finds a file it expects to have created.
	var temp := temp_path_for(path)
	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)

	return true


## Which file a load of `slot` should read.
##
## Slot 1 is where the pre-slot save lands, so it doubles as the fallback for it: if the
## migration in _ready() could not run — a read-only user://, a first launch that crashed
## before it, a build rolled back and forward again — a player whose game predates slots still
## loads it instead of being told there is no save. Every other slot is only ever its own file.
func resolve_slot_load_path(slot: int) -> String:
	var fallback := resolve_load_path() if slot == 1 else ""
	return pick_load_path(_slot_path(slot), fallback)


## The metadata stamped into the header of the save being written.
##
## Every lookup is guarded and falls back to 0. This runs from the writer, which a unit test
## drives with no LevelUpManager, no LandManager and — for an instance that was never added to
## the tree — no tree at all. A save that raised while describing itself would take the
## player's whole world with it for the sake of a number on a menu row.
func collect_metadata() -> Dictionary:
	return {
		HEADER_SAVED_AT: int(Time.get_unix_time_from_system()),
		HEADER_LEVEL: _saved_level(),
		HEADER_LAND_RADIUS: _saved_land_radius(),
	}


func _saved_level() -> int:
	# find() already answers null for a node with no tree, which is the unit-test case.
	var manager := LevelUpManager.find(self)
	return manager.level if manager != null else 0


## LandManager has no find() of its own, and main.gd creates it at runtime rather than
## authoring it into main.tscn, so there is no fixed path to it either — the group is the only
## handle. The type check is not optional: a group lookup returns whatever is in the group.
func _saved_land_radius() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	for node in tree.get_nodes_in_group("LandManager"):
		if node is LandManager:
			return node.radius
	return 0


## Writes the whole world to `path`, staging through a temp file beside it. Returns whether
## the file is on disk under its real name when this returns.
func write_save_to(path: String) -> bool:
	if path == "":
		push_warning("SaveLoad: asked to write a save to an empty path; nothing was saved")
		return false

	# Write to the temp path, never to the destination. Until the rename at the bottom of this
	# function runs, the previous good save is still whole on disk.
	var temp := temp_path_for(path)
	var save_file := FileAccess.open(temp, FileAccess.WRITE) # Open File
	if save_file == null:
		push_warning("SaveLoad: could not open '%s' for writing (error %d); nothing was saved and the previous save is untouched" % [temp, FileAccess.get_open_error()])
		return false

	# The header goes first so a human reading the file sees the version before the payload,
	# and so slot_info() can read the metadata without scanning. The reader does not depend on
	# that position — see header_version().
	save_file.store_line(JSON.stringify(make_header(collect_metadata())))

	# A SaveLoad outside the tree has no groups to walk. That is the unit-test case, and it
	# produces a header-only save rather than a crash — which is also the honest answer: an
	# empty world is what a tree with nothing in it contains.
	var tree := get_tree()
	if tree != null:
		# Go through every object in the SaveLoad group
		var save_nodes = tree.get_nodes_in_group("SaveLoad")
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

		var chunk_nodes = tree.get_nodes_in_group("SaveChunks")
		for chunk in chunk_nodes:
			if !chunk.has_method("save"):
				print("Node '%s' is missing a save function, skipped" % chunk.name)
				continue
			var chunk_data = chunk.call("save")
			save_file.store_line(JSON.stringify(chunk_data))

	save_file.close() # Close File

	# The whole file is on disk and closed before anything touches the destination, so the swap
	# either happens or does not. An interrupted save leaves a stray .tmp and the previous
	# save intact, which is the outcome this is for.
	var err := DirAccess.rename_absolute(temp, path)
	if err != OK:
		push_warning("SaveLoad: could not move '%s' over '%s' (error %d); the previous save is intact and the new one is still at the temp path" % [temp, path, err])
		return false
	return true


## Reads `path` and hands every entry to the node it belongs to. The chunk payloads are parked
## in `loads` for late_load(), which main.gd:_finish_load runs a frame later.
func load_save_from(path: String) -> void:
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


## Moves the one pre-slot save into slot 1 (gather-8uy). Runs from _ready(), so a player who
## had a game in progress before slots existed finds it in slot 1 the first time they open the
## Load screen rather than being shown three empty rows.
##
## Returns whether a copy was actually made, which is false on every launch after the first.
func migrate_single_save() -> bool:
	var source := single_save_path if single_save_path != "" else resolve_load_path()
	return copy_save_into_slot(source, _slot_path(1))


## Copies `source` into `dest` if and only if `dest` is empty.
##
## That single check is both rules at once: "exactly once", because after the first run the
## destination exists; and "only if slot 1 is empty", because once the copy is there the
## player may have played on top of it and the pre-slot file is the stale one.
##
## The bytes are copied verbatim rather than re-serialised, for the reason _migrate_legacy_save
## gives above: stamping FORMAT_VERSION onto a payload this build has not actually rewritten is
## a claim about its shape that is not true. A v1 or headerless file therefore lands in slot 1
## still declaring what it really is, and slot_info() reports it honestly.
##
## `source` is deliberately left where it is. Deleting it would make the migration
## irreversible on a build rollback, and the cost of keeping it is one file that is never read
## again. The consequence is worth stating plainly: a player who deletes slot 1 and relaunches
## gets the pre-slot save back, because an empty slot 1 is exactly the condition this
## migrates into. Nothing is lost either way, which is the property being protected.
static func copy_save_into_slot(source: String, dest: String) -> bool:
	if source == "" or dest == "":
		return false
	if not FileAccess.file_exists(source):
		return false
	if FileAccess.file_exists(dest):
		return false

	var bytes := FileAccess.get_file_as_bytes(source)
	if bytes.is_empty():
		return false

	# The destination directory may not exist yet — this is static, so it cannot lean on
	# _ensure_saves_dir(), and it is reached on first launch before anything has been saved.
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())

	var temp := temp_path_for(dest)
	var out := FileAccess.open(temp, FileAccess.WRITE)
	if out == null:
		push_warning("SaveLoad: could not open '%s' to migrate '%s' (error %d)" % [temp, source, FileAccess.get_open_error()])
		return false
	out.store_buffer(bytes)
	out.close()

	var err := DirAccess.rename_absolute(temp, dest)
	if err != OK:
		push_warning("SaveLoad: could not move '%s' into '%s' (error %d); the save stays where it is and will be migrated again next launch" % [temp, dest, err])
		return false

	print("SaveLoad: migrated the save at '%s' into '%s'" % [source, dest])
	return true

## Dead code: nothing calls this, main.gd included. It is kept in step with _load() — same
## path resolution, same header skip, same entry guard — so that it cannot become the one
## reader that chokes on a header line, but it should probably be deleted outright in a
## change of its own rather than maintained forever.
func _load_tilemap() -> void:
	# Check if the SaveFile exists
	var path := resolve_slot_load_path(current_slot)
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
