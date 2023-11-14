extends Node
class_name SoundManager

# Define your sounds
enum SoundType {
	STONE
}

# Store your sounds as AudioStreamPlayer nodes or references to AudioStream resources
var sound_library = {
	SoundType.STONE: preload("res://Resources/Sounds/stone.wav")
}

# This function plays a sound of the given type
func play_sound(type: SoundType, volume_db: float = 0.0, loop: bool = false):
	var sound_resource = sound_library[type]
	if sound_resource:
		var player = AudioStreamPlayer.new()
		player.stream = sound_resource
		player.volume_db = volume_db
		#player.loop = loop
		add_child(player)
		player.play()
		if not loop:
			player.connect("finished", Callable(player, "queue_free"))

# This function stops all sounds of the given type
func stop_sound(type: SoundType):
	for child in get_children():
		if child is AudioStreamPlayer and child.stream == sound_library[type]:
			child.stop()
			child.queue_free()

# This function sets the volume of all sounds of the given type
func set_volume(type: SoundType, volume_db: float):
	for child in get_children():
		if child is AudioStreamPlayer and child.stream == sound_library[type]:
			child.volume_db = volume_db
