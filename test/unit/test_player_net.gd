extends RefCounted

## Covers the guards in player/states/player_net.gd (gather-uem).
##
## The state itself cannot be driven headless: enter() reads PlayerManager.player, the
## hotbar and an AnimationPlayer, on_hit() needs an Enemy and a live InventoryData, and
## nothing pumps a physics frame so body_entered never fires on its own. What these tests
## do reach is the part that actually broke — _arm_net()/_stow_net() take the Area2D as an
## argument for exactly this reason, so a bare Area2D stands in for p.net, and
## _is_current_state() is a pure read of the fsm.
##
## Every assertion below is on observable state (a connection count, a property value),
## never on "it did not error": a runtime error inside a `-> String` test still returns ""
## and counts as a pass (gather-1t9), so "no error was printed" is not something a test in
## this suite can claim.

var _T

var state: Node
var net: Area2D
var machine: StateMachine


func setup() -> void:
	# Never added to the tree: _ready() would not help and the state has none anyway.
	state = load("res://player/states/player_net.gd").new()
	net = _fresh_net()
	machine = StateMachine.new()


func teardown() -> void:
	for node in [state, net, machine]:
		if node != null and is_instance_valid(node):
			node.free()
	state = null
	net = null
	machine = null


## An Area2D in the state p.net is in when the swing starts: hidden and monitoring, since
## Area2D monitors by default and player.gd only ever hides the sprite.
func _fresh_net() -> Area2D:
	var area := Area2D.new()
	area.visible = false
	area.monitoring = true
	return area


func _connection_count() -> int:
	return net.body_entered.get_connections().size()


func test_arming_the_net_makes_it_live() -> String:
	state._arm_net(net)

	var err: String = _T.assert_true(net.visible, "the net sprite is shown")
	if err != "":
		return err
	err = _T.assert_true(net.monitoring, "the net monitors for bodies")
	if err != "":
		return err
	return _T.assert_eq(_connection_count(), 1, "on_hit is connected once")


func test_arming_twice_leaves_a_single_connection() -> String:
	# The player FSM has no exit() hook — change_to() only calls enter() — so re-entering
	# PlayerNet runs the connect line again. Unguarded that stacked a duplicate connection
	# and Godot logged "already connected" on every second swing (gather-uem, same shape as
	# gather-0du in enemy_follow.gd). A stacked connection is not merely noisy: on_hit
	# consumes a Net item, so two of them cost two nets for one skeleton.
	state._arm_net(net)
	state._arm_net(net)

	return _T.assert_eq(_connection_count(), 1, "the second swing did not stack a connection")


func test_stowing_writes_visible_now_and_monitoring_later() -> String:
	# The reported bug in one assertion. on_hit() runs inside body_entered, so the physics
	# server holds the area locked and a direct `monitoring = false` is refused outright
	# (area_2d.cpp:429). Deferring it is observable from here: `visible` is a CanvasItem
	# property and lands immediately, `monitoring` is still true on the next line because
	# the write is sitting in the message queue.
	state._arm_net(net)

	state._stow_net(net)

	var err: String = _T.assert_false(net.visible, "visible was written directly")
	if err != "":
		return err
	return _T.assert_true(net.monitoring, "monitoring was deferred, not written in place")


func test_the_deferred_monitoring_write_actually_lands() -> String:
	# The other half: deferring it must still turn the net off. Two frames, because the
	# message queue flushes at the end of the iteration we are resumed inside.
	state._arm_net(net)
	state._stow_net(net)

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return "no SceneTree main loop to flush the deferred write"
	await tree.process_frame
	await tree.process_frame

	return _T.assert_false(net.monitoring, "the net stopped monitoring once the queue flushed")


func test_stowing_drops_the_connection() -> String:
	# on_hit() stows the net it just caught something with. The deferred `monitoring` write
	# does not land until the end of the frame, so the connection is the only thing that
	# stops a second body being caught by a net the player no longer owns.
	state._arm_net(net)

	state._stow_net(net)

	return _T.assert_eq(_connection_count(), 0, "the catch handler is disconnected immediately")


func test_stowing_an_unarmed_net_is_a_no_op() -> String:
	# Both early returns in enter() happen before the net is ever armed, so a swing with
	# nothing selected still reaches _stow_net() through animation_finished with
	# body_entered never connected. Unguarded, that is a disconnect on a signal that was
	# never connected. (Godot answers that on stderr rather than by failing, so this test
	# can only assert the end state — read the runner's stderr for the error itself.)
	state._stow_net(net)

	var err: String = _T.assert_eq(_connection_count(), 0, "nothing is connected")
	if err != "":
		return err
	return _T.assert_false(net.visible, "the net is hidden anyway")


func test_stowing_twice_is_a_no_op() -> String:
	# on_hit() stows, and the animation that finishes a moment later stows again.
	state._arm_net(net)

	state._stow_net(net)
	state._stow_net(net)

	return _T.assert_eq(_connection_count(), 0, "the second stow left the net disconnected")


func test_a_foreign_current_state_is_rejected() -> String:
	# animation_finished is connected to the PLAYER's AnimationPlayer, so every animation that
	# finishes anywhere — Attack, Gather — used to arrive there: the connection outlived the
	# state because StateMachine had no exit() to drop it in. Without this check, finishing an
	# attack stowed the net and forced the player back to PlayerIdle for the rest of the
	# session (gather-3zg.2 fixed the identical defect in player_gather.gd; this file never
	# got it). exit() now drops the connection at the source (gather-rcm) and this guard is
	# the second line of defence, so it is still worth holding.
	#
	# A PlayerState rather than a bare Node: StateMachine.state is typed now, and assigning a
	# plain Node to it raises. That raise was invisible here — the suite stayed green because
	# a runtime error inside a `-> String` test still returns "" (gather-1t9) — and only the
	# runner's stderr showed it.
	var other := PlayerState.new()
	machine.state = other
	state.fsm = machine

	var result: bool = state._is_current_state()
	other.free()

	return _T.assert_false(result, "an animation finishing under another state is ignored")


func test_no_state_machine_is_rejected() -> String:
	# fsm is only assigned by StateMachine._enter_state(). An AnimationPlayer signal can
	# reach a state that was never entered, and that state has no machine to change.
	state.fsm = null

	return _T.assert_false(state._is_current_state(), "a state with no machine is ignored")


func test_the_current_state_is_accepted() -> String:
	# The guard must not swallow the swing it exists for.
	machine.state = state
	state.fsm = machine

	return _T.assert_true(state._is_current_state(), "the net's own animation is still handled")
