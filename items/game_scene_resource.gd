extends Node
class_name GameSceneResource

## A resource that is a real node in the world rather than a cell on the tilemap — the
## `is_scene_tile` half of the two representations every resource-handling path has to cope
## with (see ResourceManager2). Being a node is exactly what lets it react to being hit at
## all: a layer-1 tilemap cell has no transform, no modulate and no material, so it can only
## be given feedback that lives *beside* it.
##
## `extends Node` on a StaticBody2D root is pre-existing and left alone; the sprite is
## reached through the @onready below rather than through `self`, so nothing here needs the
## narrower type.

@export var resource_type: Types.Item
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_particles = $HitParticles

## Both are 1 -> 0 progress values driving the two reactions below. Driven procedurally from
## `_process` rather than by a Tween, for two reasons: a swing lands several times per gather
## and per-swing Tween creation is the kind of churn this project gates on, and a procedural
## driver is the only version that can guarantee the sprite is put back to *exactly* its rest
## transform — a killed tween leaves it wherever it stopped.
##
## `_process` is off unless one of them is running, so an island full of stone nodes costs
## nothing.
var _hit := 0.0
var _break := 0.0

## Captured rather than assumed: the scene authors the sprite at scale 1, but an inherited
## variant could not, and a reaction that snaps back to a hardcoded Vector2.ONE would resize
## the node permanently.
var _rest_scale := Vector2.ONE
var _rest_position := Vector2.ZERO


func _ready() -> void:
	if animated_sprite_2d != null:
		_rest_scale = animated_sprite_2d.scale
		_rest_position = animated_sprite_2d.position
	set_process(false)


## One swing of the pickaxe landed. Restarts the squash from full rather than accumulating,
## so holding the gather key gives a run of identical distinct hits instead of a build-up
## that reads as a vibration.
func hit_react() -> void:
	if animated_sprite_2d == null:
		return
	_hit = 1.0
	set_process(true)


## The node is breaking. Runs over Juice.NODE_BREAK_TIME, which is also what
## ResourceManager2.SCENE_BREAK_TIME is defined as — i.e. how long the caller waits before the
## resource is actually removed — so the pop finishes exactly as the node goes away.
func break_react() -> void:
	if animated_sprite_2d == null:
		return
	_hit = 0.0
	_break = 1.0
	# The scene ships a two-frame "Destroy" animation that nothing was playing; a break used
	# to be the idle frame vanishing between one frame and the next.
	if animated_sprite_2d.sprite_frames != null and animated_sprite_2d.sprite_frames.has_animation("Destroy"):
		animated_sprite_2d.play("Destroy")
	set_process(true)


func _process(delta: float) -> void:
	if _break > 0.0:
		_advance_break(delta)
		return
	if _hit > 0.0:
		_advance_hit(delta)
		return
	_rest()


func _advance_hit(delta: float) -> void:
	_hit = maxf(_hit - delta / Juice.NODE_HIT_TIME, 0.0)
	if _hit <= 0.0:
		_rest()
		return

	# Squared, so the squash snaps out hard and eases back — a linear decay reads as the node
	# slowly inflating, which is the wrong half of the motion to emphasise.
	var e := _hit * _hit
	animated_sprite_2d.scale = _rest_scale * Vector2(
		1.0 + Juice.NODE_HIT_SQUASH.x * e,
		1.0 - Juice.NODE_HIT_SQUASH.y * e
	)
	# A single recoil rather than an oscillation: the node is being struck, not rung.
	animated_sprite_2d.position = _rest_position + Vector2(Juice.NODE_HIT_RECOIL * e, 0.0)


func _advance_break(delta: float) -> void:
	# ResourceManager2 frees the node at the end of SCENE_BREAK_TIME, so this never has to
	# reach 0 — but it is floored anyway, because the node also survives a gather that is
	# interrupted after the break started.
	_break = maxf(_break - delta / Juice.NODE_BREAK_TIME, 0.0)
	if _break <= 0.0:
		_rest()
		return

	var grown := 1.0 - _break
	animated_sprite_2d.scale = _rest_scale * (1.0 + Juice.NODE_BREAK_GROW * grown)
	animated_sprite_2d.modulate.a = _break


func _rest() -> void:
	_hit = 0.0
	_break = 0.0
	if animated_sprite_2d != null:
		animated_sprite_2d.scale = _rest_scale
		animated_sprite_2d.position = _rest_position
		animated_sprite_2d.modulate.a = 1.0
	set_process(false)
