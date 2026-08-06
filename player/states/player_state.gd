extends Node
class_name PlayerState

## Base for every state under Player/StateMachine.
##
## It exists so that adding a state — a new attack type, a new tool swing — is a script that
## overrides two methods, rather than a script that has to remember four separate defensive
## idioms. Before it, every state re-declared `fsm` and `p` itself and hand-rolled its own
## teardown, because StateMachine had no exit() hook at all: it only ever called enter()
## (gather-rcm). Three shipped bugs came out of that single missing call — the gather state
## being yanked out from under a sword swing (gather-3zg.2), the attack hitbox being disarmed
## from a state that was not current (gather-hby), and the net stowing itself on somebody
## else's animation (gather-uem) — and all three have the same shape: a connection made in
## enter() that outlived the state, firing for whoever came next.
##
## So the contract is:
##
##  * `enter()` sets the state up. Anything it connects or arms, `exit()` undoes.
##  * `exit()` runs on the way out, whatever the reason, and BEFORE the next state's enter().
##    It must be safe to call on a state that never finished entering — every early return in
##    an enter() below leaves exactly that — so guard on the thing itself, not on a flag.
##  * `process` / `physics_process` are routed by the machine only while the state is current.
##
## The enemy machine (enemies/states/enemy_state.gd) has had this shape all along, which is
## why none of the three bugs above has an enemy-side twin.

## The machine running this state. Injected by StateMachine before enter().
var fsm: StateMachine

## The player this state acts on. Assigned in enter() by every state that needs it, and left
## null until then — so exit() must never assume it is set.
var p: Player


## Called when the machine switches to this state.
func enter() -> void:
	pass


## Called when the machine switches away, before the next state enters.
##
## Also called on a state whose enter() bailed out early, so it is written to tolerate a
## half-built state rather than to assume enter() ran to completion.
func exit() -> void:
	pass


func process(_delta: float) -> void:
	pass


func physics_process(_delta: float) -> void:
	pass


## True while this state has a sword swing in its ACTIVE frames — the animation running and
## the hitbox armed.
##
## This is the predicate that makes a swing atomic, and it is answered by the state rather
## than by the player because the state is the only thing that knows where in the swing it
## is. `player.gd` asks it in three places, and all three used to get the question wrong by
## asking the AnimationPlayer instead:
##
##  * `_gather_input_release()` called `animation_player.stop()` unconditionally. On a phone
##    the primary button sends `gather` OR `attack` from the same physical button
##    (ui/mobile_controls.gd, `_action_for`), so lifting the finger that started a swing
##    stopped the swing's own animation two frames in.
##  * `_physics_process()` disarmed `$Attack` the moment `AnimationPlayer.is_playing()` went
##    false, which is a consequence of the above rather than an independent fact — so one
##    stray `stop()` both cut the animation short and silently took the damage off it.
##  * `_destroy_input_press()` plays the Gather animation straight over whatever is running.
##
## A state that is merely *recovering* from a swing answers false: the blow has landed, the
## hitbox is down, and there is nothing left to protect.
func owns_swing() -> bool:
	return false


## True while this state has taken control of the player and refuses new actions until it
## hands them back — the dodge roll, which is a commitment the moment it starts.
##
## Separate from `owns_swing()` because the two gate different things: a swing may not be
## interrupted but does not stop the player rolling out of its recovery, and a roll may not
## be interrupted at all. Collapsing them into one flag would mean either a roll that can be
## cancelled by mashing attack, or a swing recovery the player is locked inside.
func is_committed() -> bool:
	return false


## The velocity the player should actually move at this frame, given the `walk` vector the
## input and the skill tree worked out.
##
## The hook exists because two states need to overrule ordinary walking in opposite
## directions and neither can be expressed as a speed multiplier alone: PlayerAttack slows
## the player without changing where they are going, and PlayerRoll ignores the input
## entirely and drives a fixed burst. Returning the argument unchanged is what every other
## state wants, so a new state costs nothing here.
func movement_velocity(walk: Vector2) -> Vector2:
	return walk
