extends Node2D
class_name RainVfx

## The rain itself: one GPUParticles2D that follows the camera, plus the ambience loop.
##
## Built in code rather than authored as a .tscn, like `skill_tree_ui.gd` and
## `hud_toolbar.gd` — the emitter's extents and particle count are both derived from the
## viewport, so a scene file would only be storing values that get overwritten on the first
## resize anyway.
##
## ## Why this is world-space and not a CanvasLayer
##
## A screen-space rain layer is the obvious build and it is the wrong one here: it would sit
## outside the root canvas and therefore outside the day/night CanvasModulate, so the drops
## would keep their full daylight brightness and glow against a dark world at midnight. As a
## child of `World` the rain is tinted by the same curve as everything else it is falling
## on. See the canvas table in CLAUDE.md.
##
## The cost of that choice is that this node gets no viewport rect for free — the same
## problem `ui/camera_hud.gd` has, solved the same way: extents come from
## `viewport_size / camera.zoom`, recomputed on `size_changed` rather than every frame, and
## nothing here ever hardcodes a window dimension.

## Above every world sprite. The rain falls in front of the player, the trees and the
## buildings; y-sorting it against them would put drops behind whatever happens to be lower
## on the screen, which reads as the rain being *inside* the scenery.
const RAIN_Z_INDEX := 60

## World units per second. Fast enough to read as rain rather than as snow, slow enough
## that a single drop is on screen long enough to be seen at all.
const FALL_SPEED := 210.0

## Sideways lean, as a fraction of the fall speed. Rain that falls dead vertical reads as a
## screen-door pattern laid over the game rather than as weather in it. Applied by slanting
## the emission DIRECTION — not by accelerating sideways, which in a ParticleProcessMaterial
## would push along the velocity vector and simply make the drops fall faster.
const DRIFT_RATIO := 0.16

## Drop dimensions in world units, before the per-particle scale jitter. A tile is 16
## units, so a drop is about a quarter of a tile long.
const DROP_WIDTH := 1
const DROP_HEIGHT := 4

const DROP_COLOR := Color(0.78, 0.88, 1.0, 0.55)

## One drop per this many square world units of visible area, and the bounds that density is
## clamped into. Density rather than a flat count because the window is resizable with
## stretch disabled (see CLAUDE.md): a fixed 300 drops is a downpour on a phone and a
## drizzle on a 4K monitor, since a larger window shows *more world* rather than the same
## world larger.
const AREA_PER_DROP := 90.0
const MIN_DROPS := 80
const MAX_DROPS := 600

## How much bigger than the visible area the emission box is, so drops are already falling
## when they enter the view instead of appearing at its edge.
const OVERSCAN := 1.25

## Seconds to fade the ambience in and out. Long enough that a storm arrives rather than
## switches on.
const AUDIO_FADE := 2.5

const RAIN_VOLUME_DB := -12.0

## Where a rain loop would live. Loaded at runtime rather than `preload`ed because the asset
## does not exist yet: a preload of a missing path is a *parse* error, which would take the
## whole scene down rather than just the sound. Everything else here works without it.
const RAIN_STREAM_PATH := "res://assets/audio/rain.wav"

var clock: WorldClock

var _particles: GPUParticles2D
var _audio: AudioStreamPlayer
var _audio_tween: Tween
var _camera: Camera2D

## The last extents computed, so _process can follow the camera without re-deriving the
## emission box every frame.
var _extents := Vector2.ZERO

## The zoom the extents were last computed against. Camera2D has no zoom_changed signal, so
## tracking it means comparing — the same guard, for the same reason, as camera_hud.gd.
var _last_zoom := Vector2.ZERO


func _ready() -> void:
	add_to_group("RainVfx")

	z_index = RAIN_Z_INDEX
	# The rain is a flat sheet in front of everything, not a thing at a world depth. Left
	# y-sorted it would be re-ordered against the scenery every frame.
	y_sort_enabled = false

	_build_particles()
	_build_audio()

	get_viewport().size_changed.connect(_resize_to_view)
	_resize_to_view()

	if clock != null:
		clock.weather_changed.connect(_on_weather_changed)
		_apply_weather(clock.weather)


func _build_particles() -> void:
	_particles = GPUParticles2D.new()
	_particles.name = "Drops"
	_particles.texture = _drop_texture()
	_particles.emitting = false
	_particles.local_coords = false
	# NEAREST, like the rest of the game's art: the drop is a 1x4 texture magnified 8x by
	# the camera, and a filtered one would arrive as a soft grey smear.
	_particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var material := ParticleProcessMaterial.new()
	material.particle_flag_disable_z = true
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.direction = Vector3(DRIFT_RATIO, 1.0, 0.0).normalized()
	# A little spread, so the sheet is not a set of perfectly parallel lines.
	material.spread = 3.0
	material.gravity = Vector3.ZERO
	material.initial_velocity_min = FALL_SPEED * 0.9
	material.initial_velocity_max = FALL_SPEED * 1.1
	material.scale_min = 0.7
	material.scale_max = 1.3
	material.color = DROP_COLOR
	_particles.process_material = material

	add_child(_particles)


## A vertical streak, generated rather than shipped as a PNG: it is four pixels of solid
## colour and an asset would be one more thing to keep a .uid sidecar for.
##
## The soft ends come from the gradient rather than from a filter, which is what lets the
## texture stay NEAREST-sampled and still not read as a hard rectangle.
func _drop_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = DROP_WIDTH
	texture.height = DROP_HEIGHT
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture


func _build_audio() -> void:
	if not ResourceLoader.exists(RAIN_STREAM_PATH):
		# No asset yet. The storm is silent and everything else about it still works —
		# deliberately not a push_warning, because this is a known-absent asset rather than
		# a misconfiguration, and a warning every time it rains would train the reader to
		# ignore the log.
		return

	var stream := load(RAIN_STREAM_PATH)
	if stream == null:
		return

	_audio = AudioStreamPlayer.new()
	_audio.name = "RainAmbience"
	_audio.stream = stream
	# Silent until faded in, so starting the player and starting the storm are separate.
	_audio.volume_db = -60.0
	add_child(_audio)


## Recomputes the emission box from the camera's visible world area.
##
## Same derivation as camera_hud.gd: zoom is a divisor, because Camera2D zoom scales the
## canvas rather than this node, so one world unit covers `zoom` screen pixels.
func _resize_to_view() -> void:
	if _particles == null:
		return

	var camera := _camera_node()
	var zoom := camera.zoom if camera != null else Vector2.ONE
	if is_zero_approx(zoom.x) or is_zero_approx(zoom.y):
		return

	var view := get_viewport_rect().size / zoom
	_extents = view * OVERSCAN * 0.5
	_last_zoom = zoom

	var material := _particles.process_material as ParticleProcessMaterial
	if material != null:
		material.emission_box_extents = Vector3(_extents.x, _extents.y, 1.0)

	var area := view.x * view.y
	_particles.amount = clampi(int(area / AREA_PER_DROP), MIN_DROPS, MAX_DROPS)

	# Long enough for a drop to cross the whole box, so none of them wink out mid-screen.
	_particles.lifetime = maxf(0.2, (_extents.y * 2.0) / FALL_SPEED)


func _camera_node() -> Camera2D:
	if is_instance_valid(_camera):
		return _camera
	var player := PlayerManager.player
	if player == null:
		return null
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	return _camera


func _process(_delta: float) -> void:
	if _particles == null or not _particles.emitting:
		return

	var camera := _camera_node()
	if camera == null:
		return

	# The sheet is pinned to the view, not to the world, so the player never rains their way
	# out of the far edge of the box. `local_coords = false` on the emitter is what keeps the
	# drops already in flight from being dragged along with it.
	global_position = camera.get_screen_center_position()

	# The camera's zoom is fixed at 8 today, but camera_hud.gd already learned that assuming
	# so is contract drift the first time anything writes it (gather-xgi).
	if not camera.zoom.is_equal_approx(_last_zoom):
		_last_zoom = camera.zoom
		_resize_to_view()


func _on_weather_changed(weather: WorldClock.Weather) -> void:
	_apply_weather(weather)


func _apply_weather(weather: WorldClock.Weather) -> void:
	var raining := weather == WorldClock.Weather.RAIN

	if _particles != null:
		if raining:
			# Re-sync before the first drop: the window may have been resized while it was
			# clear, and size_changed fires whether or not it is raining, so this is belt
			# and braces rather than the only path.
			_resize_to_view()
		_particles.emitting = raining

	_fade_audio(RAIN_VOLUME_DB if raining else -60.0, raining)


func _fade_audio(target_db: float, playing: bool) -> void:
	if _audio == null:
		return

	if _audio_tween != null and _audio_tween.is_valid():
		_audio_tween.kill()

	if playing and not _audio.playing:
		_audio.play()

	_audio_tween = create_tween()
	_audio_tween.tween_property(_audio, "volume_db", target_db, AUDIO_FADE)
	if not playing:
		# Stop only after the fade, or the last two seconds of the storm are silent.
		_audio_tween.tween_callback(_audio.stop)
