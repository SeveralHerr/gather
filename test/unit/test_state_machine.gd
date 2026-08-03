extends RefCounted

## Covers player/states/state_machine.gd's transition contract (gather-rcm).
##
## The machine had no exit() hook for most of the project's life: change_to() only ever
## called enter(). Three shipped bugs came out of that one omission — gather-3zg.2,
## gather-hby and gather-uem — all of them a connection made in enter() that outlived the
## state and then fired for whoever came next. The states each grew a `fsm.state != self`
## guard to survive it, which protects a handler but cannot undo a side effect.
##
## These tests drive the real StateMachine with recording PlayerStates rather than the real
## player states, because every one of those reads PlayerManager.player, a hotbar and an
## AnimationPlayer in enter(). What is being asserted is the machine's contract, and the
## machine is what the next attack type will rely on.
##
## The machine is never added to the tree: _ready() would seize `state` from get_child(0),
## and these tests want to set the starting state explicitly. get_node() resolves against a
## node's own children whether or not it is in a tree, so change_to() still works.

var _T

var machine: StateMachine
var calls: Array


class RecordingState extends PlayerState:
	## Shared with the test, so the ORDER of calls across two different states is observable
	## — which is the half of the contract that matters. exit() running after the next state
	## has already entered would arm something and then immediately tear it down.
	var calls: Array = []

	func enter() -> void:
		calls.append("%s.enter" % name)

	func exit() -> void:
		calls.append("%s.exit" % name)


func setup() -> void:
	machine = StateMachine.new()
	calls = []
	_add_state("Alpha")
	_add_state("Beta")


func teardown() -> void:
	if machine != null and is_instance_valid(machine):
		machine.free()
	machine = null
	calls = []


func _add_state(state_name: String) -> RecordingState:
	var state := RecordingState.new()
	state.name = state_name
	state.calls = calls
	machine.add_child(state)
	return state


func _state(state_name: String) -> PlayerState:
	return machine.get_node(state_name) as PlayerState


func test_changing_state_exits_the_old_one_before_entering_the_new() -> String:
	machine.state = _state("Alpha")
	machine.state.fsm = machine

	machine.change_to("Beta")

	# Both halves in one assertion on purpose. "exit was called" and "exit was called first"
	# are different claims, and only the second one is worth anything: a teardown that runs
	# after the incoming enter() disarms what the new state has just armed.
	return _T.assert_eq(str(calls), str(["Alpha.exit", "Beta.enter"]), "exit ran before enter")


func test_the_new_state_becomes_current() -> String:
	machine.state = _state("Alpha")
	machine.state.fsm = machine

	machine.change_to("Beta")

	var err: String = _T.assert_eq(machine.state.name, "Beta", "Beta is current")
	if err != "":
		return err
	# Injected on every entry, because a state reached from a signal may never have been
	# entered before and has no machine to change otherwise.
	return _T.assert_true(machine.state.fsm == machine, "the new state was given the machine")


func test_re_entering_the_current_state_does_not_exit_it() -> String:
	# PlayerGather depends on this directly. A repeat gather press re-enters the state, and
	# its enter() bails out early on resource_manager.is_holding_e to avoid restarting the
	# hold timer — but an exit() in between would have hidden the swing sprite and dropped
	# the animation connection first, so the held gather would run invisibly (gather-3zg.2).
	machine.state = _state("Alpha")
	machine.state.fsm = machine

	machine.change_to("Alpha")

	return _T.assert_eq(str(calls), str(["Alpha.enter"]), "no exit ran on a re-entry")


func test_an_unknown_state_name_leaves_the_machine_alone() -> String:
	# Was get_node(), which raises. A raise mid-transition aborts whatever was swinging and
	# leaves the machine pointing at a state whose teardown is half-done — strictly worse
	# than refusing to move.
	machine.state = _state("Alpha")
	machine.state.fsm = machine

	machine.change_to("NoSuchState")

	var err: String = _T.assert_eq(machine.state.name, "Alpha", "the machine stayed put")
	if err != "":
		return err
	return _T.assert_eq(str(calls), str([]), "neither hook ran")


func test_the_base_state_hooks_are_safe_to_call() -> String:
	# Every hook has a default body, so a state that overrides only enter() is complete.
	# StateMachine routes process and physics_process unconditionally now — no has_method
	# probe — so a missing default would be a crash on the first frame rather than a no-op.
	var bare := PlayerState.new()
	bare.enter()
	bare.exit()
	bare.process(0.016)
	bare.physics_process(0.016)
	var still_here: bool = is_instance_valid(bare)
	bare.free()

	return _T.assert_true(still_here, "the default hooks did not raise")
