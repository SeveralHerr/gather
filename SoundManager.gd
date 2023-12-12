extends Node
class_name SoundManager

var gathering_player: AudioStreamPlayer

# Define your sounds
enum SoundType {
	STONE,
	HIT,
	WALKING,
	DOOR_ACTION,
	WOOD_PLACE,
	MINING,
	POP,
	BONE,
	SQUISH,
	WOOD_GATHER
	}

# Store your sounds as AudioStreamPlayer nodes or references to AudioStream resources
var sound_library = {
	SoundType.STONE: preload("res://Resources/Sounds/stone.wav"),
	SoundType.HIT: preload("res://Resources/Sounds/hit.wav"),
	SoundType.WALKING: preload("res://Resources/Sounds/walking.wav"),
	SoundType.DOOR_ACTION: preload("res://Resources/Sounds/door_open.wav"),
	SoundType.WOOD_PLACE: preload("res://Resources/Sounds/wood_place.wav"),
	SoundType.MINING: preload("res://Resources/Sounds/mining.wav"),
	SoundType.POP: preload("res://Resources/Sounds/pop.wav"),
	SoundType.BONE: preload("res://Resources/Sounds/bone_hit.wav"),
	SoundType.SQUISH: preload("res://Resources/Sounds/squish.wav"),
	SoundType.WOOD_GATHER: preload("res://Resources/Sounds/wood_place.wav")
}

func _ready():
	add_to_group("SoundManager")
	gathering_player = AudioStreamPlayer.new()
	add_child(gathering_player)

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
			
func play_sound_queue(type: SoundType, player: AudioStreamPlayer, volume_db: float = 0.0, _loop: bool = false):
	var sound_resource = sound_library[type]
	player.autoplay = false
	
	if player.playing == true:
		return
	if sound_resource:
		player.stream = sound_resource
		player.volume_db = volume_db
		#player.loop = loop
		player.play()
		
func play_gathering_sound(type: SoundType, volume_db: float = 0.0, _loop: bool = false):
	var sound_resource = sound_library[type]
	gathering_player.autoplay = false
	
	if gathering_player.playing == true:
		return
	if sound_resource:
		gathering_player.stream = sound_resource
		#gathering_player.stream.loop_mode = 1
		gathering_player.volume_db = volume_db

		gathering_player.play()
		
func stop_gathering_sound():
	gathering_player.stop()


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
