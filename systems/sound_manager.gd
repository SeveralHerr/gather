extends Node
class_name SoundManager

## Max fractional pitch offset applied to one-shot sounds, e.g. 0.1 == +/-10%.
## Deliberately NOT applied to the looping gathering player: a sustained sound
## whose pitch jumps between restarts sounds broken, not lively.
const PITCH_VARIATION := 0.1

## Thunder loudness, in decibels rather than a 0-1 linear scale, because
## perceived loudness is logarithmic: a linear ramp spends most of its range in
## a band the ear barely separates and then collapses to nothing at the end, so
## a "half distance" bolt lands nowhere near half as loud. -18 dB is roughly a
## quarter of the apparent volume of the overhead strike, which is about right
## for a flash on the horizon without making it inaudible.
const THUNDER_NEAR_DB := 0.0
const THUNDER_FAR_DB := -18.0

## Air absorbs high frequencies over distance, so a far bolt is all rumble and
## no crack. There is no filter on an AudioStreamPlayer, so the high end is
## suggested by dropping the pitch instead. Kept shallow on purpose - past about
## 0.85 it stops sounding like distance and starts sounding like the tape is
## slowing down.
const THUNDER_NEAR_PITCH := 1.0
const THUNDER_FAR_PITCH := 0.85

## Small deliberate jitter so a storm's repeated bolts are not identical takes.
## Much smaller than PITCH_VARIATION: the distance pitch above is the message
## here, and +/-10% on top of it would swamp it.
const THUNDER_PITCH_JITTER := 0.03

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
	WOOD_GATHER,
	THUNDER
	}

# Store your sounds as AudioStreamPlayer nodes or references to AudioStream resources
var sound_library = {
	SoundType.STONE: preload("res://assets/audio/stone.wav"),
	SoundType.HIT: preload("res://assets/audio/hit.wav"),
	SoundType.WALKING: preload("res://assets/audio/walking.wav"),
	SoundType.DOOR_ACTION: preload("res://assets/audio/door_open.wav"),
	SoundType.WOOD_PLACE: preload("res://assets/audio/wood_place.wav"),
	SoundType.MINING: preload("res://assets/audio/mining.wav"),
	SoundType.POP: preload("res://assets/audio/pop.wav"),
	SoundType.BONE: preload("res://assets/audio/bone_hit.wav"),
	SoundType.SQUISH: preload("res://assets/audio/squish.wav"),
	SoundType.WOOD_GATHER: preload("res://assets/audio/wood_place.wav"),
	SoundType.THUNDER: preload("res://assets/audio/thunder.wav")
}

func _ready():
	add_to_group("SoundManager")
	gathering_player = AudioStreamPlayer.new()
	add_child(gathering_player)

# Returns a pitch_scale randomly offset by up to +/-PITCH_VARIATION.
func _random_pitch() -> float:
	return randf_range(1.0 - PITCH_VARIATION, 1.0 + PITCH_VARIATION)

# This function plays a sound of the given type
func play_sound(type: SoundType, volume_db: float = 0.0, loop: bool = false):
	var sound_resource = sound_library[type]
	if sound_resource:
		var player = AudioStreamPlayer.new()
		player.stream = sound_resource
		player.volume_db = volume_db
		player.pitch_scale = _random_pitch()
		#player.loop = loop
		add_child(player)
		player.play()
		if not loop:
			player.connect("finished", Callable(player, "queue_free"))
			
## A one-shot at an EXACT pitch, with none of the random variation `play_sound` applies.
##
## The variation exists so a sound retriggered dozens of times (a footstep, a pickaxe) does
## not read as a machine, and it is the right default. It is wrong when the pitch is the
## message: the xp splash blips a rising three-note scale as the running total crosses each
## colour band, and +/-10% on each note is enough to invert two of the intervals - the tune
## comes out different every gather, which sounds like a bug rather than a flourish.
func play_sound_pitched(type: SoundType, pitch: float, volume_db: float = 0.0) -> void:
	var sound_resource = sound_library.get(type)
	if sound_resource == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = sound_resource
	player.volume_db = volume_db
	player.pitch_scale = maxf(0.01, pitch)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## Thunder for a lightning flash `distance` tiles away, 0.0 overhead to 1.0 on the horizon.
##
## The sound is deliberately late. Light arrives instantly and sound does not, and that gap
## is the entire reason a distant strike reads as distant - flash and bang together always
## look like they happened on top of the player no matter how quiet the bang is. WorldClock
## owns the delay curve because it also owns the storm that decides when to fire.
##
## Goes through the exact-pitch path rather than `play_sound`, since the pitch here carries
## the distance and `_random_pitch`'s +/-10% is wide enough to make a far bolt read as a
## near one.
func play_thunder(distance: float) -> void:
	var d := clampf(distance, 0.0, 1.0)
	var sound_resource = sound_library.get(SoundType.THUNDER)
	if sound_resource == null:
		return

	var delay := WorldClock.thunder_delay(d)
	var tree := get_tree()
	if delay > 0.0 and tree != null:
		await tree.create_timer(delay).timeout
		# Up to 4.5 seconds pass here, which is long enough for the player to die, the
		# scene to be reloaded or the game to quit. Resuming a coroutine into a node that
		# has left the tree - or been freed - raises, and a raise inside a `-> void` is
		# silent, so this guard is the difference between one skipped bolt and an error
		# nobody sees.
		if not is_instance_valid(self) or not is_inside_tree():
			return

	var pitch := lerpf(THUNDER_NEAR_PITCH, THUNDER_FAR_PITCH, d)
	pitch += randf_range(-THUNDER_PITCH_JITTER, THUNDER_PITCH_JITTER)

	var player := AudioStreamPlayer.new()
	player.stream = sound_resource
	player.volume_db = lerpf(THUNDER_NEAR_DB, THUNDER_FAR_DB, d)
	player.pitch_scale = maxf(0.01, pitch)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func play_sound_queue(type: SoundType, player: AudioStreamPlayer, volume_db: float = 0.0, _loop: bool = false):
	var sound_resource = sound_library[type]
	player.autoplay = false
	
	if player.playing == true:
		return
	if sound_resource:
		player.stream = sound_resource
		player.volume_db = volume_db
		# One-shot retrigger (footsteps etc.), not a sustained loop, so vary it.
		player.pitch_scale = _random_pitch()
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
