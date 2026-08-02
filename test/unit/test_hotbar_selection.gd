extends RefCounted

## Guards the keys the hotbar claims for itself.
##
## `hot_bar_inventory.gd` reads raw keycodes in `_unhandled_key_input` rather than
## InputMap actions — deliberately, because slot selection is not an engine-level UI
## action and routing it through one would hand it to Control focus navigation first.
## The cost of that choice is that nothing prevents a key it claims from *also* being
## bound to a gameplay action, and nothing reports it when one is: the binding lives
## in `project.godot`, the keycode lives in a GDScript `if`, and the two never appear
## in the same place.
##
## That is not hypothetical. `E` was bound to `gather` and was simultaneously the
## hotbar's "next slot" key, and since nothing in the gather path marks the event
## handled it fell through — so every swing of the pickaxe silently advanced the
## hotbar by one slot. It survived lint, the whole unit suite and a `/verify` run.
## This test is the thing that would have caught it.

const HOTBAR_SCRIPT := "res://inventory/hot_bar_inventory.gd"

var _T


## The script's constants, read off the script rather than the node: the hotbar has
## no `class_name`, and standing an instance up would drag in the whole inventory.
func _constants() -> Dictionary:
	var script: GDScript = load(HOTBAR_SCRIPT)
	if script == null:
		return {}
	return script.get_script_constant_map()


## Every keycode the hotbar answers to: the two step keys plus the slot numbers.
func _claimed_keys() -> Array[int]:
	var constants := _constants()
	var claimed: Array[int] = [
		int(constants["STEP_PREV_KEY"]),
		int(constants["STEP_NEXT_KEY"]),
	]

	var slot_count := int(constants["SLOT_COUNT"])
	for i in slot_count:
		claimed.append(KEY_1 + i)
	return claimed


## Which InputMap actions bind `keycode`, by physical or literal keycode — the two
## are checked together because `project.godot` stores gather as `physical_keycode:
## 69` while the hotbar compares `event.keycode`, and on the layouts this game ships
## for those are the same key.
func _actions_bound_to(keycode: int) -> Array[String]:
	var found: Array[String] = []
	for action in InputMap.get_actions():
		# Godot's own ui_* actions are not the game's, and several of them legitimately
		# sit on keys a game also uses.
		if str(action).begins_with("ui_"):
			continue
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key == null:
				continue
			if key.keycode == keycode or key.physical_keycode == keycode:
				found.append(str(action))
				break
	return found


func test_no_hotbar_key_is_also_a_gameplay_action() -> String:
	for keycode in _claimed_keys():
		var clashes := _actions_bound_to(keycode)
		var err: String = _T.assert_eq(
			clashes.size(), 0,
			"key '%s' selects a hotbar slot and is also bound to %s" % [
				OS.get_keycode_string(keycode), str(clashes)])
		if err != "":
			return err

	return ""


func test_q_and_e_no_longer_step_the_selection() -> String:
	# Named explicitly rather than left implied by the test above, because E is only
	# a clash for as long as it is bound to gather. Someone rebinding gather later
	# must not thereby make E a legal hotbar key again — the reason it is gone is
	# that the player asked for the arrow keys, and the collision is why it was found.
	var claimed := _claimed_keys()

	var err: String = _T.assert_false(claimed.has(int(KEY_Q)), "Q does not step the hotbar")
	if err != "":
		return err
	return _T.assert_false(claimed.has(int(KEY_E)), "E does not step the hotbar")


func test_the_step_keys_are_the_arrow_keys() -> String:
	var constants := _constants()

	var err: String = _T.assert_eq(
		int(constants["STEP_PREV_KEY"]), int(KEY_LEFT), "Left steps back one slot")
	if err != "":
		return err
	return _T.assert_eq(
		int(constants["STEP_NEXT_KEY"]), int(KEY_RIGHT), "Right steps forward one slot")
