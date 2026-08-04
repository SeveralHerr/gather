extends Node2D
class_name FallingChest

## The boss's reward chest, arriving the way a reward chest should: from off the top of the
## screen, at speed, landing hard enough to shake the camera.
##
## Placed at the world position of the cell the chest will occupy, so everything below is in
## local coordinates with (0, 0) as the ground and `_height` measured up from it.
##
## It animates, crashes, bounces, and then emits `landed` and frees itself - it never writes
## a tile. The caller owns the actual chest; this owns the moment. Keeping the two apart is
## what lets a save taken mid-fall settle the reward with no animation at all, instead of the
## player losing a chest that was legitimately theirs (IslandManager._settle_pending_rewards).
##
## Procedural rather than tweened, like the rest of the game's feedback: the sequence has to
## survive being freed at any frame - a load, a land regeneration - and a killed tween leaves
## the sprite wherever it stopped, while a killed _process leaves nothing behind at all.

## Emitted once the chest has finished bouncing and the world may put the real one down.
signal landed

## How far above the ground it starts. The camera runs at zoom 8 on a 1080-tall window, so
## the visible world is ~135px tall - starting at 150 means it genuinely drops in from off
## screen rather than popping into existence in mid-air.
const DROP_HEIGHT := 150.0

## Downward acceleration, px/s^2. Tuned against DROP_HEIGHT for a fall of roughly 0.6s: long
## enough to see it coming and read the shadow, short enough that it reads as dropped rather
## than lowered.
const GRAVITY := 900.0

## How much speed the chest keeps through a bounce, and how many it gets. Two is the whole
## joke - one is a thud, three is a beach ball.
const BOUNCE_DAMPING := 0.38
const BOUNCE_LIMIT := 2

## Below this landing speed a bounce is not worth playing and the chest just settles.
const BOUNCE_MIN_SPEED := 60.0

## Rotations per second while airborne. It tumbles in and then straightens: a chest left
## resting at a jaunty angle reads as a bug rather than a joke, because every other chest in
## the game is axis-aligned.
const SPIN_SPEED := TAU * 1.15

## How long the chest spends unwinding its squash and its spin before `landed` fires, and how
## fast each unwinds. The rotation rate is the higher of the two because it has further to
## travel and a visible snap at the end is worse than an early arrival.
const SETTLE_TIME := 0.2
const SQUASH_RECOVER := 7.0
const SPIN_RECOVER := 16.0

## Impact squash. Applied to the sprite alone, so the shadow underneath stays put.
const IMPACT_SQUASH := Vector2(1.55, 0.5)

## The shadow: an ellipse under the chest that grows as it falls, which is what sells height
## on a flat 2D map. Drawn rather than textured - it is a 6px blob that changes size every
## frame, which is not worth an art asset.
const SHADOW_MIN_RADIUS := 1.6
const SHADOW_MAX_RADIUS := 6.4
const SHADOW_SQUASH := 0.45
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.32)
const SHADOW_SEGMENTS := 16

## Dust thrown up on impact. Rather more than a pickaxe swing produces, because this is the
## only thing in the game that arrives from the sky.
const DUST_AMOUNT := 14
const DUST_LIFETIME := 0.5

const HIT_PARTICLES := preload("res://world/vfx/hit_particles.tscn")

var _sprite: Sprite2D
var _dust: GPUParticles2D

## Height above the ground in pixels, and speed in px/s with DOWN positive - so a bounce is
## simply a negative speed and needs no second code path.
var _height := DROP_HEIGHT
var _speed := 0.0

var _bounces := 0
var _resting := false
var _settling := 0.0
var _done := false


## `texture` is GameItem.get_atlas() for the chest, so the thing that falls is the thing the
## player is about to open rather than a stand-in that has to be kept in sync with it.
static func drop(texture: Texture2D) -> FallingChest:
	var chest := FallingChest.new()
	chest.name = "FallingChest"
	chest._sprite = Sprite2D.new()
	chest._sprite.texture = texture
	# Nearest, like every other sprite in the game. An AtlasTexture cut from the tileset
	# picks up the parent's default otherwise, and a blurry chest against crisp terrain is
	# very visible at zoom 8.
	chest._sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Above the terrain and above the drops: for the second it is airborne it is genuinely
	# in front of everything.
	chest._sprite.z_index = 2
	return chest


func _ready() -> void:
	add_child(_sprite)

	_dust = HIT_PARTICLES.instantiate()
	_dust.name = "ImpactDust"
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.amount = DUST_AMOUNT
	_dust.lifetime = DUST_LIFETIME
	_dust.emitting = false
	_dust.z_index = Juice.PARTICLE_Z_INDEX
	add_child(_dust)

	_sprite.position = Vector2(0.0, -_height)


func _process(delta: float) -> void:
	if _done:
		_linger(delta)
		return

	if _resting:
		_recover(delta)
	else:
		_integrate(delta)

	_sprite.position = Vector2(0.0, -_height)
	queue_redraw()


## One integrator for the fall and for every bounce. `_speed` carries the sign, so an upward
## bounce is the same three lines as the drop.
func _integrate(delta: float) -> void:
	_speed += GRAVITY * delta
	_height -= _speed * delta

	if _height > 0.0:
		_sprite.rotation += SPIN_SPEED * delta
		return

	# Overshot the ground this frame. Pin it there rather than letting the sprite sink -
	# at these speeds that is a visible half-tile of chest below the floor.
	_height = 0.0
	_impact()


## The crash. Everything that makes it read as heavy happens here, and the bounces after it
## are quieter and shake nothing - that is what keeps the first hit the moment.
func _impact() -> void:
	_sprite.scale = IMPACT_SQUASH
	# restart() rather than `emitting = true`: a one-shot emitter that is already running
	# ignores the assignment, so the second bounce would throw no dust.
	_dust.restart()

	# Juice documents MASSIVE as reserved for the boss, and this is the boss's punctuation
	# mark. Only on the first hit; a bounce that shook the screen as hard as the landing
	# would flatten the whole sequence into one long rumble.
	if _bounces == 0:
		Juice.shake(self, Juice.Shake.MASSIVE)
	_crash_sound()

	if _bounces < BOUNCE_LIMIT and _speed > BOUNCE_MIN_SPEED:
		_bounces += 1
		_speed = -_speed * BOUNCE_DAMPING
		return

	_speed = 0.0
	_resting = true


## Two samples at once, an octave apart. The library has no crash and neither sound alone is
## one: STONE pitched right down is the weight, WOOD_PLACE over it is the lid and the hinges.
func _crash_sound() -> void:
	# Quieter on each bounce, so the sequence decays instead of firing three identical bangs.
	var attenuation := -7.0 * float(_bounces)
	GameSoundManager.play_sound_pitched(SoundManager.SoundType.STONE, 0.55, 4.0 + attenuation)
	GameSoundManager.play_sound_pitched(SoundManager.SoundType.WOOD_PLACE, 0.8, attenuation)


## On the ground: unwind the squash and the spin, then hand over.
func _recover(delta: float) -> void:
	_sprite.scale = _sprite.scale.move_toward(Vector2.ONE, SQUASH_RECOVER * delta)
	# lerp_angle, so a chest that stopped at 5.9 radians unwinds the short way rather than
	# spinning most of a turn backwards to reach zero.
	_sprite.rotation = lerp_angle(_sprite.rotation, 0.0, minf(1.0, SPIN_RECOVER * delta))

	_settling += delta
	if _settling < SETTLE_TIME:
		return

	_done = true
	# Hidden rather than freed on the spot: the caller answers `landed` by writing the real
	# chest tile, and the dust is still in the air. Freeing here would cut the burst off
	# mid-flight, which is the one part of the impact that outlives the impact.
	_sprite.visible = false
	landed.emit()


## The tail: nothing left to animate, just the dust finishing. Counted down in _process
## rather than handed to a SceneTreeTimer, for the same reason none of this is tweened - a
## timer holding a connection back to this node outlives the node itself if the world is torn
## down first, and it is the one thing here that can leak.
func _linger(delta: float) -> void:
	_settling += delta
	if _settling >= SETTLE_TIME + DUST_LIFETIME:
		queue_free()


func _draw() -> void:
	if _done:
		return

	var closeness := 1.0 - clampf(_height / DROP_HEIGHT, 0.0, 1.0)
	var radius: float = lerpf(SHADOW_MIN_RADIUS, SHADOW_MAX_RADIUS, closeness)

	var points := PackedVector2Array()
	for i in SHADOW_SEGMENTS:
		var angle := TAU * float(i) / float(SHADOW_SEGMENTS)
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * SHADOW_SQUASH))
	draw_colored_polygon(points, SHADOW_COLOR)
