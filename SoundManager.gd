extends Node
class_name SoundManager

# Define your sounds
enum SoundType {
	STONE,
	HIT,
	WALKING,
	DOOR_ACTION,
	WOOD_PLACE,
	MINING
	}

# Store your sounds as AudioStreamPlayer nodes or references to AudioStream resources
var sound_library = {
	SoundType.STONE: preload("res://Resources/Sounds/stone.wav"),
	SoundType.HIT: preload("res://Resources/Sounds/hit.wav"),
	SoundType.WALKING: preload("res://Resources/Sounds/walking.wav"),
	SoundType.DOOR_ACTION: preload("res://Resources/Sounds/door_open.wav"),
	SoundType.WOOD_PLACE: preload("res://Resources/Sounds/wood_place.wav"),
	SoundType.MINING: preload("res://Resources/Sounds/mining.wav")
}

func _ready():
	add_to_group("SoundManager")

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
			
func play_sound_queue(type: SoundType, player: AudioStreamPlayer, volume_db: float = 0.0, loop: bool = false):
	var sound_resource = sound_library[type]
	player.autoplay = false
	
	if player.playing == true:
		return
	if sound_resource:
		player.stream = sound_resource
		player.volume_db = volume_db
		#player.loop = loop
		player.play()


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
