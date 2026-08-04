extends CharacterBody2D
class_name Bullet

var speed = 30
var spin_speed = 25.0

## What this bullet takes off an enemy.
##
## Was the literal `3` inside _physics_process. It is a field now because a charged turret
## fires harder-hitting rounds (BoneTurret.CHARGED_BONUS_DAMAGE) and the alternative - a
## turret reaching in to rewrite the collision handler's constant - is not expressible. The
## default is the 3 that was hardcoded, so an ordinary turret is unchanged.
var damage := 3
@onready var collision_shape_2d = $CollisionShape2D
@onready var sprite_2d = $Sprite2D
@onready var shadow = $Shadow

func _ready():
	$VisibleOnScreenNotifier2D.connect("screen_exited", Callable(self, "_on_exit"))
	$HitBox.connect("body_entered", Callable(self, "_on_hit"))


func start(_position, _direction):
	position = _position
	#rotation = _direction
	velocity = Vector2(speed, 0).rotated(_direction)


	
func _physics_process(delta):
	collision_shape_2d.rotation += spin_speed * delta
	sprite_2d.rotation += spin_speed * delta
	shadow.rotation += spin_speed * delta
	var collision = move_and_collide(velocity * delta)
	if collision and collision.get_collider() is Enemy:

		collision.get_collider().receive_hit(Vector2.ZERO, damage)
		queue_free()
		
func _on_exit():
	queue_free()
	
func _on_hit(_body: Node2D):

	pass
