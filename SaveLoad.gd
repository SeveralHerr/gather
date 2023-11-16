extends Control
class_name SaveLoad

var loads = []

func _on_save_pressed() -> void:
	_save()

	print("GAME SAVED")

func _on_load_pressed() -> void:
	_load()
	print("GAME LOADED")
	
func late_load():
	var chunk_nodes = get_tree().get_nodes_in_group("SaveChunks")
	for chunk in chunk_nodes:
		if !chunk.has_method("load"):
			print("Node '%s' is missing a save function, skipped" % chunk.name)
			continue
			
		for i in loads.size():
			var dict = loads[i]	
			print(dict["y"] , chunk.position.y)
			if dict["x"] == chunk.position.x and dict["y"] == chunk.position.y:
				chunk.call("load", dict)

	
	pass

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
	
	while save_file.get_position() < save_file.get_length():
		# Get the saved dictionary from the next line in the save file
		var json = JSON.new()
		json.parse(save_file.get_line())
		
		# Get the Data
		var node_data = json.get_data()
		if node_data.has("x") and node_data.has("y"):
			loads.append(node_data)
			
		
		elif has_node(node_data["filepath"]) :

			get_node(node_data["filepath"]).loadObject(node_data)
			
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
		if has_node(node_data["filepath"]) and node_data["filepath"] == "/root/Main":
			print("loading tilemap")
			get_node(node_data["filepath"]).loadObject(node_data)
			
	save_file.close() # Close File
