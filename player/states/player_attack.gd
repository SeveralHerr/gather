extends PlayerState

## One sword swing, start to finish, and the cadence that separates it from the next one.
##
## The rule this file exists to hold is: **once a swing starts it plays to completion and
## the hitbox stays armed for its whole active window, whatever the player's finger does.**
## Before it, a swing was three separate facts that could disagree — the animation, the
## `$Attack` area's `monitoring` flag, and `AnimationPlayer.is_playing()` standing in for
## "am I still swinging" — and any of the three could be knocked over from outside:
##
##  * `Player._gather_input_release()` called `animation_player.stop()` on every `gather`
##    RELEASE. On a phone the one contextual button sends `gather` or `attack` from the same
##    physical button (`ui/mobile_controls.gd`), so the finger that started a swing ended it.
##  * `Player._physics_process()` disarmed `$Attack` as soon as the AnimationPlayer went
##    quiet, so the same stray `stop()` took the damage off the swing as well as the picture.
##
## Both now ask `owns_swing()` (see PlayerState) instead, and this state is the only thing
## that ever answers true.
##
## ## No `animation_finished` connection, deliberately
##
## Every other state here connects to the PLAYER's AnimationPlayer and has needed a guard,
## an exit() and a bead to survive it (gather-3zg.2, gather-hby, gather-uem — the list is in
## player_state.gd). That signal is the wrong clock for something that must be atomic: it is
## emitted by a node this state does not own, for whichever animation happens to be running,
## and it is silent when another system plays over the top. So the swing is timed instead,
## from the animation's own declared `length`, in `_process`.
##
## ## `_process` versus `process`
##
## This file defines BOTH and they are different methods with different jobs, which is the
## one genuinely confusing thing here:
##
##  * `process(delta)` is PlayerState's hook, routed by StateMachine only while this state is
##    current. Unused here.
##  * `_process(delta)` is Godot's own callback on this Node, and the state nodes are real
##    children of `Player/StateMachine`, so it runs EVERY frame whether or not the machine is
##    pointing at this state.
##
## The always-running one is what the cadence needs. `_cooldown_left` has to keep draining
## while the player is walking, mining or netting, or swapping to a pickaxe and back would
## reset the swing rhythm to zero — the cadence is a property of the arm, not of which state
## the machine happens to be parked in. It is a single float compare while idle.

## What the end of a cadence tick resolves to.
##
## WAIT   the cadence has not elapsed; nothing to do.
## SWING  a press was buffered during the swing and is now due.
## DROP   the buffered press outlived the state — the machine has moved on to mining or
##        netting — so it is discarded. Firing it would produce a sword swing out of a gather
##        half a second after the button was released, which reads as the game acting on its
##        own rather than as a late input.
## FREE   nothing is queued; hand the machine back to PlayerIdle.
enum Cadence { WAIT, SWING, DROP, FREE }

## Seconds between the end of one swing's animation and the earliest start of the next.
## Small on purpose — this is rhythm, not punishment. 0.14 on top of the 0.2s animation puts
## the ceiling at ~2.9 swings a second, which is fast enough to feel responsive and slow
## enough that mashing is visibly a *sequence* of swings rather than one continuous blur.
const SWING_RECOVERY := 0.14

## Used when the AnimationPlayer has no animation by that name — a corrupt library, or a
## rename in main.tscn that missed this file. Matches what the four swing animations are
## authored at. Timing a swing off a length of 0.0 would make the active window a single
## frame, which reads as a sword that does no damage.
const SWING_FALLBACK_LENGTH := 0.2

## How much of the player's walk speed survives the active frames of a swing.
##
## Not zero. A hard root is the more common choice in this genre and it is wrong for *this*
## game: the swing is 0.2s, enemies lunge from 18px, and a player pinned in place for a fifth
## of a second every time they attack cannot back out of a fight they have misjudged — which
## is the whole of the early-game combat loop. 0.45 reads as weight (the player visibly slows
## when they commit) while leaving them able to retreat.
const SWING_MOVE_SCALE := 0.45

## The two swings, per facing, alternated so a held attack reads as a combination rather than
## as one animation on repeat. Which four exist is decided by main.tscn's AnimationLibrary and
## nothing here invents one: `_animation_for()` falls back to the first entry when the second
## is missing, so deleting `Attack2` degrades to the old single-swing behaviour instead of
## playing nothing.
##
## `Attack_Left_2` is currently authored identically to `Attack_Left`, so the left-facing
## alternation is presently invisible. That is a *content* gap, not a logic one — the moment
## someone re-keys that animation the alternation appears with no code change — and wiring
## the left side to a single animation "because the second one looks the same" would mean
## exactly that edit silently doing nothing.
const SWING_ANIMATIONS_RIGHT := ["Attack", "Attack2"]
const SWING_ANIMATIONS_LEFT := ["Attack_Left", "Attack_Left_2"]

## Seconds left of the ACTIVE window — the frames during which the animation runs, the hitbox
## is armed, and nothing outside the machine may interfere. Reaches zero before
## `_cooldown_left` does; the gap between them is the recovery.
##
## The two floats below ARE the phase — active while `_active_left` runs, recovering while
## only `_cooldown_left` does, idle when neither. There is deliberately no field recording
## which of the three it is in: that would be a second copy of a fact these already carry, and
## two copies can disagree — which in this file means `owns_swing()` answering true for a
## window that has already closed, i.e. the atomicity rule protecting nothing.
var _active_left := 0.0

## Seconds until another swing may start. Deliberately NOT cleared by `exit()` — see there.
var _cooldown_left := 0.0

## One queued follow-up swing. Not a counter: a player mashing the button through a whole
## swing should get one more swing out of it, not five queued up to play out after they have
## stopped pressing.
var _buffered := false

## Which of the two animations the next swing uses. Persists across entries, so consecutive
## swings alternate however they are spaced.
var _swing_index := 0


func enter() -> void:
	p = PlayerManager.player
	if p == null:
		return

	#var equipped = p.equip_sword_inventory_data.inventory_slot_datas[0]
	var selected = p.hot_bar_inventory.selected_slot_data
	var equipped = selected.item if selected else null
	var has_sword_equipped = equipped and equipped is  GameItemSword

	# Without a sword there is no swing animation to wait on, so hand control back
	# immediately rather than parking the machine in a state that never exits.
	if not has_sword_equipped:
		fsm.change_to("PlayerIdle")
		return

	# A press arriving inside the cadence window is BUFFERED, never dropped and never a
	# restart. All three of those are reachable from here and only one of them is right:
	#
	#  * restarting is what a bare `play()` would do, and it is the worst of the three — the
	#    swing that was about to land resets to frame zero, so holding the button produces a
	#    hitbox that jitters at the start of the animation and an enemy that never gets hit;
	#  * dropping it means a player pressing in rhythm loses roughly every other press,
	#    because the press that mattered landed 30ms before the recovery ended;
	#  * buffering fires it the instant the cadence allows, which is what the player was
	#    asking for and is why they pressed early.
	#
	# `change_to()` skips `exit()` when the machine is already in this state (see
	# StateMachine), so a repeat press is a bare re-entry and lands here with the swing state
	# intact. It also arrives from `items/game_item_sword.gd:use()`, which is the same press
	# by another route.
	if _cooldown_left > 0.0:
		_buffered = true
		return

	_start_swing()


## Undoes exactly what a swing armed, and is safe on a state that never started one.
##
## `_cooldown_left` is deliberately NOT reset here, and that is the load-bearing line. exit()
## runs whenever anything else takes the machine — using a pickaxe, throwing a net — so if the
## cadence were torn down with the state, "swing, tap gather, swing" would be a way to attack
## as fast as the player can alternate two keys. The cadence belongs to the arm, so it drains
## on this node's own `_process` and outlives the state's tenancy.
##
## There is no `animation_finished` connection to drop any more; see the header.
func exit() -> void:
	_active_left = 0.0
	_buffered = false

	if p == null:
		return

	if p.attack != null:
		p.attack.visible = false
		p.attack.monitoring = false


## True only for the active frames. The recovery answers false on purpose: by then the blow
## has landed, so there is nothing left for the atomicity rule to protect and a player who
## wants to roll out of the follow-through should be allowed to.
func owns_swing() -> bool:
	return _active_left > 0.0


func movement_velocity(walk: Vector2) -> Vector2:
	if owns_swing():
		return walk * SWING_MOVE_SCALE
	return walk


## Whether the arm is free. Read by the `combat_state` devtools verb, which needs to tell "the
## button did nothing because a swing is running" apart from "the button did nothing because
## no sword is equipped". `enter()` makes the decision itself rather than calling this, so
## there is one place a press is resolved.
func can_swing() -> bool:
	return _cooldown_left <= 0.0


## Godot's own per-frame callback on this Node, NOT PlayerState's routed `process()`. See the
## header for why the cadence has to be timed by a clock that keeps running while some other
## state is current.
func _process(delta: float) -> void:
	if _cooldown_left <= 0.0:
		return

	if _active_left > 0.0:
		_active_left = maxf(0.0, _active_left - delta)
		if _active_left <= 0.0:
			_end_active_window()

	_cooldown_left = maxf(0.0, _cooldown_left - delta)

	var current := fsm != null and fsm.state == self and p != null and is_instance_valid(p)
	match cadence_after(_cooldown_left, _buffered, current):
		Cadence.WAIT:
			return
		Cadence.SWING:
			_start_swing()
		Cadence.DROP:
			_buffered = false
		Cadence.FREE:
			_buffered = false
			if fsm != null:
				fsm.change_to("PlayerIdle")


func _start_swing() -> void:
	_buffered = false

	var animation := _animation_for(p.animated_sprite_2d.flip_h, _swing_index)
	_swing_index += 1

	var length := SWING_FALLBACK_LENGTH
	if p.animation_player != null and p.animation_player.has_animation(animation):
		length = p.animation_player.get_animation(animation).length
	if length <= 0.0:
		length = SWING_FALLBACK_LENGTH

	_active_left = length
	_cooldown_left = length + SWING_RECOVERY

	# Before the hitbox goes live, never after: `body_entered` can fire on the very first
	# physics frame of the swing, and a clear that ran afterwards would wipe the record of a
	# hit that had already landed and let the same enemy be struck twice by one swing.
	p.begin_swing()

	p.attack.visible = true
	p.attack.monitoring = true

	if p.animation_player != null:
		p.animation_player.play(animation)


## Takes the hitbox down at the end of the active window.
##
## A direct `monitoring = false` is correct here: `_process` runs outside the physics query
## flush, so the server is not locked. That is the same distinction `player_net.gd` documents
## — it is only a `body_entered` handler that has to defer the write (gather-uem).
func _end_active_window() -> void:
	if p != null and p.attack != null:
		p.attack.visible = false
		p.attack.monitoring = false


## What a cadence tick resolves to. Pure, because the buffer rule is the part of this file
## most worth pinning and the part a headless test can otherwise not reach at all: `enter()`
## reads PlayerManager.player, the hotbar and an AnimationPlayer, and none of the three can be
## stood up outside a running game.
##
## `is_current` folds together "the machine is still pointing at this state" and "the player
## is still there", because a buffered swing needs both to be true and the caller has nothing
## useful to do with the difference.
static func cadence_after(cooldown_left: float, buffered: bool, is_current: bool) -> Cadence:
	if cooldown_left > 0.0:
		return Cadence.WAIT
	if not is_current:
		return Cadence.DROP
	return Cadence.SWING if buffered else Cadence.FREE


## Which animation swing number `index` uses, given the facing. Pure, so the alternation is
## testable without an AnimationPlayer — and `index` is unbounded because `_swing_index` only
## ever climbs, which is why this wraps rather than indexing raw.
static func _animation_for(facing_left: bool, index: int) -> String:
	var names: Array = SWING_ANIMATIONS_LEFT if facing_left else SWING_ANIMATIONS_RIGHT
	if names.is_empty():
		return ""
	return str(names[posmod(index, names.size())])
