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
