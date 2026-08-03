extends Node

class_name StateMachine

const DEBUG = true


var state: PlayerState

func _ready():
	# Set the initial state to the first child node. Cast rather than assigned raw: `state` is
	# typed now, and a non-PlayerState child here should surface as a null and a warning at
	# boot rather than as an "invalid call to enter()" on the first transition.
	state = get_child(0) as PlayerState
	if state == null:
		push_warning("StateMachine: first child of %s is not a PlayerState" % get_path())
		return
	call_deferred("_enter_state")


## Switches to the state named `new_state`, tearing the current one down first.
##
## The exit() call is the whole point of this function and was missing for a long time
## (gather-rcm). Without it a state's setup outlived the state: PlayerAttack and PlayerNet
## both connect to the PLAYER's AnimationPlayer, so once either had run once, every
## animation that finished anywhere in the game arrived at a state that was no longer
## current. Each state grew its own `fsm.state != self` guard to survive that, which works
## for a handler but cannot undo a side effect — the attack hitbox stayed armed, the net
## stayed live for a free second catch.
##
## Order matters: the outgoing state is torn down BEFORE `state` is reassigned and before
## the new state's enter() runs, so an exit() that inspects `fsm.state` still sees itself,
## and an enter() that arms something cannot have it immediately disarmed by the state it
## replaced.
func change_to(new_state):
	var next := get_node_or_null(NodePath(new_state)) as PlayerState
	if next == null:
		# Was get_node(), which raises. A raise inside a state transition aborts whatever
		# was mid-swing and leaves the machine pointing at the old state with its setup
		# half-undone, which is a much worse failure than not transitioning.
		push_warning("StateMachine: no state named '%s', staying in '%s'" % [new_state, state.name if state else "<none>"])
		return

	if state != null and state != next:
		state.exit()

	state = next
	_enter_state()


func _enter_state():
	if DEBUG:
		print("Entering state: ", state.name)
	# Give the new state a reference to it's state machine i.e. this one

	state.fsm = self
	state.enter()

# Route Game Loop function calls to
# current state handler method if it exists
func _process(delta):
	if state:
		state.process(delta)


## Routed for the same reason as _process. Nothing overrides it yet; it is here because an
## attack type that moves the player has to write `velocity` from a physics frame, and
## discovering that the machine drops physics frames is a poor way to find that out.
func _physics_process(delta):
	if state:
		state.physics_process(delta)
