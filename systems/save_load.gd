extends Control
class_name SaveLoad

var loads = []

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
	var save_file = FileAccess.open("saveFile", FileAccess.WRITE) # Open File
	
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

func _load() -> void:
	# Check if the SaveFile exists
	if !FileAccess.file_exists("saveFile"):
		print("Error, no Save File to load.")
		return
	
		
	var save_file = FileAccess.open("saveFile", FileAccess.READ) # Open File

	# `loads` holds the payloads for the load currently in progress and nothing else.
	# It used to accumulate for the lifetime of the session, so a second load applied
	# both the stale payload and the fresh one to every chunk at a matching position.
	loads.clear()

	while save_file.get_position() < save_file.get_length():
		# Get the saved dictionary from the next line in the save file
		var json = JSON.new()
		json.parse(save_file.get_line())

		# Get the Data
		var node_data = json.get_data()
		# A line that is not a dictionary, or a dictionary with no filepath, is a
		# saveObject() that aborted mid-way: a typed `-> Dictionary` still returns {}
		# when the body raises. Skipping it loses that one node's state, which is what
		# already happened — reading ["filepath"] off it only added a second error on
		# top and stopped the rest of the file being read.
		if node_data is not Dictionary or not node_data.has("filepath"):
			push_warning("SaveLoad: skipping an entry with no filepath (a saveObject likely failed)")
			continue

		if node_data.has("x") and node_data.has("y"):
			loads.append(node_data)

		else:
			var filepath: String = migrate_path(str(node_data["filepath"]))
			if has_node(filepath):
				get_node(filepath).loadObject(node_data)
			else:
				# Previously a silent fall-through, which is how a renamed node
				# loses its state without anyone noticing.
				push_warning("SaveLoad: no node at '%s', that entry was not restored" % filepath)

	save_file.close() # Close File

func _load_tilemap() -> void:
	# Check if the SaveFile exists
	if !FileAccess.file_exists("saveFile"):
		print("Error, no Save File to load.")
		return
		
	var save_file = FileAccess.open("saveFile", FileAccess.READ) # Open File
	
	while save_file.get_position() < save_file.get_length():
		# Get the saved dictionary from the next line in the save file
		var json = JSON.new()
		json.parse(save_file.get_line())
		
		# Get the Data
		var node_data = json.get_data()
		print(node_data)
		var filepath: String = migrate_path(str(node_data["filepath"]))
		if has_node(filepath) and filepath == "/root/Main":
			print("loading tilemap")
			get_node(filepath).loadObject(node_data)
			
	save_file.close() # Close File
