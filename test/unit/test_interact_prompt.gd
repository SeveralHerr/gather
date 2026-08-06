extends RefCounted

## Covers the three resolutions behind the world-space interact prompt
## (`ui/interact_prompt.gd`): which key it names, what it calls the thing it is pointing at,
## and which nodes it is willing to point at in the first place.
##
## None of the animation is asserted here — a pop and a bob are exactly the kind of thing a
## headless run cannot judge, and pretending otherwise would produce a green suite that means
## nothing. What IS worth pinning is everything the prompt could get *wrong* rather than ugly:
##
##  * A hardcoded "F". The binding lives in `project.godot` and the prompt reads it at runtime,
##    so `test_key_label_follows_a_rebind` rebinds a scratch action and checks the answer
##    moves. A prompt that names the wrong key teaches the player something false, which is
##    strictly worse than no prompt.
##  * A hardcoded "USE". The touch cap is read out of `MobileControls.BUTTON_SPECS`, the table
##    that draws the button a phone player actually presses. The web build is played on a
##    phone, and nothing else in the project would notice those two drifting apart.
##  * A `match` on the target's class. The caption and the press are both gated on duck-typed
##    predicates, so an interactable added later is picked up without editing this feature.
##
## The label lookups take the registry as an argument rather than naming the `GameItems`
## autoload, which is what makes them testable at all: the autoload node exists under the
## headless runner but its `_ready()` never runs, so its `item_list` is empty and every lookup
## through it answers null. The registry here is built by hand from `items/items.gd`'s own
## `_ready()`, the way `test_crafting.gd` and `test_ore_chain.gd` do it.

var _T

## A scratch action, created and erased per test, so a rebind assertion cannot leave the real
## InputMap altered for whatever test runs next.
const SCRATCH_ACTION := "test_interact_prompt_scratch"

var items: Items


func setup() -> void:
	items = Items.new()
	items._ready()


func teardown() -> void:
	if InputMap.has_action(SCRATCH_ACTION):
		InputMap.erase_action(SCRATCH_ACTION)
	if items != null:
		items.free()
		items = null


func _bind(action: String, physical: Key) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	var event := InputEventKey.new()
	# physical_keycode with keycode left at 0 — the shape every binding in project.godot
	# actually has, and therefore the branch the prompt has to survive.
	event.physical_keycode = physical
	InputMap.action_add_event(action, event)


# --- which key the cap names --------------------------------------------------

func test_the_action_binding_resolves_to_f() -> String:
	# project.godot binds `action` to physical keycode 70. This asserts the prompt reads that
	# binding rather than the string "F" — the same call the game makes, against the real map.
	return _T.assert_eq(
		InteractPrompt.key_label_for_action(InteractPrompt.ACTION),
		"F",
		"the interact prompt names the key `action` is actually bound to"
	)


func test_key_label_follows_a_rebind() -> String:
	_bind(SCRATCH_ACTION, KEY_G)
	var first: String = _T.assert_eq(
		InteractPrompt.key_label_for_action(SCRATCH_ACTION), "G", "a G binding reads as G")
	if first != "":
		return first

	_bind(SCRATCH_ACTION, KEY_Q)
	return _T.assert_eq(
		InteractPrompt.key_label_for_action(SCRATCH_ACTION),
		"Q",
		"rebinding the action moves the prompt with it — nothing here is hardcoded"
	)


func test_an_unbound_action_names_no_key() -> String:
	return _T.assert_eq(
		InteractPrompt.key_label_for_action("no_such_action_exists"),
		"",
		"an action that is not in the map answers empty rather than inventing a key"
	)


func test_an_action_with_no_keyboard_event_names_no_key() -> String:
	# A binding can exist and carry only a joypad or mouse event. The cap has no key to draw
	# then, and `prompt_key` is what turns that into the touch face rather than a blank plate.
	if InputMap.has_action(SCRATCH_ACTION):
		InputMap.erase_action(SCRATCH_ACTION)
	InputMap.add_action(SCRATCH_ACTION)
	InputMap.action_add_event(SCRATCH_ACTION, InputEventJoypadButton.new())

	return _T.assert_eq(
		InteractPrompt.key_label_for_action(SCRATCH_ACTION),
		"",
		"an action bound to no keyboard event answers empty"
	)


# --- the touch cap ------------------------------------------------------------

func test_the_touch_cap_is_the_face_of_the_button_that_sends_the_action() -> String:
	# The parity guard. `ui/mobile_controls.gd` is the ONLY way into a chest or a station on a
	# phone, so the cap must say whatever is painted on that button. Read out of the same table
	# the overlay draws from, in both directions: the button has to exist, and the cap has to
	# match it.
	var face := ""
	for spec in MobileControls.BUTTON_SPECS:
		if str(spec.get("action", "")) == InteractPrompt.ACTION:
			face = str(spec.get("label", ""))
			break

	var err: String = _T.assert_true(
		face != "",
		"the touch overlay still has a button that sends `action` — without one the prompt " +
		"points at a button a phone player does not have"
	)
	if err != "":
		return err

	return _T.assert_eq(
		InteractPrompt.touch_key_label(), face, "the touch cap says what that button says")


func test_a_touchscreen_gets_the_button_face_and_a_keyboard_gets_the_key() -> String:
	var touch: String = _T.assert_eq(
		InteractPrompt.prompt_key(true),
		InteractPrompt.touch_key_label(),
		"a touch device is shown the button, not a keyboard key it does not have"
	)
	if touch != "":
		return touch

	return _T.assert_eq(
		InteractPrompt.prompt_key(false), "F", "a keyboard device is shown the bound key")


# --- what the prompt is willing to point at -----------------------------------

func test_anything_with_player_interact_is_interactable() -> String:
	var station := CraftingStation.new()
	var chest := TestChest.new()
	var err: String = _T.assert_true(
		InteractPrompt.is_interactable(station) and InteractPrompt.is_interactable(chest),
		"both of the interactables that exist today answer the duck-typed predicate"
	)
	station.free()
	chest.free()
	return err


func test_a_body_without_player_interact_is_not_interactable() -> String:
	# The half that was broken: `player.gd` highlighted whatever was nearest in the Interact
	# area and then type-checked at the press, so a body on the Interactable layer that is not
	# a chest or a station got a highlight and a prompt and did nothing when pressed.
	var plain := Node2D.new()
	var err: String = _T.assert_false(
		InteractPrompt.is_interactable(plain), "a plain body is not something to prompt for")
	plain.free()
	return err


func test_null_is_not_interactable() -> String:
	return _T.assert_false(
		InteractPrompt.is_interactable(null), "nothing in range is not something to prompt for")


func test_a_freed_body_is_not_interactable() -> String:
	# A chest broken while the player is standing on it never fires body_exited, so `player.gd`
	# genuinely holds freed objects in `chests` (gather-3zg.6). The predicate has to survive
	# being handed one.
	var chest := TestChest.new()
	chest.free()
	return _T.assert_false(
		InteractPrompt.is_interactable(chest), "a freed interactable is not interactable")


# --- what the caption calls it ------------------------------------------------

func test_the_caption_comes_from_the_target() -> String:
	# A stand-in that names itself, standing for every interactable added after this test was
	# written: the prompt must read the target's own answer, not a table it keeps.
	var stub := _NamedStub.new()
	var err: String = _T.assert_eq(
		InteractPrompt.label_for(stub), "Anvil", "the caption is whatever the target calls itself")
	stub.free()
	return err


func test_a_target_that_names_nothing_falls_back() -> String:
	var plain := Node2D.new()
	var err: String = _T.assert_eq(
		InteractPrompt.label_for(plain),
		InteractPrompt.FALLBACK_LABEL,
		"a target with no name of its own still gets a readable caption"
	)
	plain.free()
	return err


func test_an_empty_name_falls_back() -> String:
	var stub := _EmptyStub.new()
	var err: String = _T.assert_eq(
		InteractPrompt.label_for(stub),
		InteractPrompt.FALLBACK_LABEL,
		"an empty answer is treated as no answer rather than drawn as a blank caption"
	)
	stub.free()
	return err


func test_the_station_caption_is_the_registered_item_name() -> String:
	# Through the registry, so renaming a station in items.gd renames the prompt and nothing in
	# `crafting/crafting_station.gd` has to be edited. Furnace rather than the workbench: the
	# workbench's registered name is being changed in a concurrent piece of work, and a test
	# that pins a name being deliberately changed is a test that fails for being right.
	return _T.assert_eq(
		InteractPrompt.item_name(items, Types.Item.Furnace, "Station"),
		"Furnace",
		"a station's caption is the name the item registry holds for it"
	)


func test_the_chest_caption_is_the_registered_item_name() -> String:
	return _T.assert_eq(
		InteractPrompt.item_name(items, Types.Item.Chest, "Chest"),
		"Chest",
		"a chest's caption is the name the item registry holds for it"
	)


func test_an_unregistered_type_falls_back_instead_of_raising() -> String:
	# `item_list` is deliberately not total over Types.Item — the world resources live in
	# resources.gd — and `get_item` answers null for those (gather-5rj). Tree is a real example
	# rather than an invented one.
	return _T.assert_eq(
		InteractPrompt.item_name(items, Types.Item.Tree, "Station"),
		"Station",
		"a type the registry does not hold falls back rather than raising"
	)


func test_no_registry_at_all_falls_back() -> String:
	# The case a headless run is actually in: the GameItems autoload exists but its _ready()
	# never ran, so it answers null for everything. A missing registry must degrade to the
	# fallback, never to an empty caption.
	return _T.assert_eq(
		InteractPrompt.item_name(null, Types.Item.Chest, "Chest"),
		"Chest",
		"no registry means the fallback, not a blank caption"
	)


func test_both_interactables_always_name_themselves() -> String:
	# Whatever the registry answers, neither may ever hand the prompt an empty string — that
	# would draw a caption-shaped hole under the key cap.
	var station := CraftingStation.new()
	var chest := TestChest.new()
	var err: String = _T.assert_true(
		station.interact_prompt_label() != "" and chest.interact_prompt_label() != "",
		"a station and a chest both always have something to call themselves"
	)
	station.free()
	chest.free()
	return err


# --- the node itself ----------------------------------------------------------

func test_the_prompt_is_idle_until_it_is_pointed_at_something() -> String:
	# The GatherProgress discipline: invisible and NOT processing while there is nothing to
	# point at. This one is worth asserting because the prompt's idle bob means `_process`
	# genuinely does run for as long as it is up, so "off when hidden" is the only thing
	# keeping it off the frame budget in the 99% of play spent away from a bench.
	var prompt: InteractPrompt = await _T.instantiate_ui(InteractPrompt.new(), Vector2i(320, 180))
	var err: String = _T.assert_false(prompt.visible, "a prompt with no target is not drawn")
	if err == "":
		err = _T.assert_false(prompt.is_processing(), "and does not process")
	if err == "":
		err = _T.assert_false(prompt.is_showing(), "and does not claim to be showing")
	_T.free_ui(prompt)
	return err


## A live target for the hosted tests. Deliberately the stub rather than a real TestChest: a
## chest's `_ready()` reaches for the NewInventoryManager in the tree and connects a signal to
## it, so hosting one headless raises inside `_ready` — which the runner would score as a pass
## while filling stderr (gather-1t9). The stub is exactly what the prompt actually needs of a
## target: a Node2D that answers the two duck-typed methods.
func _hosted_target(prompt: InteractPrompt, at: Vector2) -> Node2D:
	var stub := _NamedStub.new()
	stub.position = at
	prompt.add_sibling(stub)
	return stub


func test_pointing_at_a_target_raises_the_prompt_over_it() -> String:
	var prompt: InteractPrompt = await _T.instantiate_ui(InteractPrompt.new(), Vector2i(320, 180))
	var target := _hosted_target(prompt, Vector2(64.0, 48.0))

	prompt.point_at(target)

	var err: String = _T.assert_true(prompt.is_showing(), "a prompt with a target is showing")
	if err == "":
		# Snapped, not slid in: the anchor is placed at the target on arrival so the bubble
		# never flies across the world from wherever the last one died.
		err = _T.assert_eq(
			prompt.global_position,
			target.global_position + Vector2(0.0, InteractPrompt.Y_OFFSET),
			"and sits directly over it"
		)
	if err == "":
		# Against the resolver rather than against "F": which of the two faces is correct
		# depends on whether the host reports a touchscreen, and the static tests above are
		# what pin each face. What this asserts is that the node asks at all.
		err = _T.assert_eq(
			prompt.key_text,
			InteractPrompt.prompt_key(DisplayServer.is_touchscreen_available()),
			"with the cap the resolver answers for this device"
		)
	if err == "":
		err = _T.assert_eq(prompt.caption_text, "Anvil", "and the target's own name under it")

	target.free()
	_T.free_ui(prompt)
	return err


func test_pointing_at_nothing_dismisses_the_prompt() -> String:
	var prompt: InteractPrompt = await _T.instantiate_ui(InteractPrompt.new(), Vector2i(320, 180))
	var target := _hosted_target(prompt, Vector2.ZERO)

	prompt.point_at(target)
	prompt.point_at(null)

	# Still on screen — it is fading out — but no longer claiming a target, which is what
	# `player.gd` and the press both read.
	var err: String = _T.assert_false(
		prompt.is_showing(), "a dismissed prompt stops showing the moment it is dismissed")

	target.free()
	_T.free_ui(prompt)
	return err


func test_pointing_at_a_non_interactable_dismisses_rather_than_prompting() -> String:
	# The prompt and the press are gated on the same predicate, so they cannot disagree about
	# what is openable. A body with no player_interact() gets no bubble at all.
	var prompt: InteractPrompt = await _T.instantiate_ui(InteractPrompt.new(), Vector2i(320, 180))
	var plain := Node2D.new()
	prompt.add_sibling(plain)

	prompt.point_at(plain)

	var err: String = _T.assert_false(
		prompt.is_showing(), "a body that cannot be interacted with gets no prompt")

	plain.free()
	_T.free_ui(prompt)
	return err


## A stand-in interactable that names itself, so the caption path is exercised against
## something that is neither of the two classes that exist today — which is the whole point of
## the duck-typed lookup.
class _NamedStub extends Node2D:
	func player_interact() -> void:
		pass

	func interact_prompt_label() -> String:
		return "Anvil"


## The same, answering nothing. A target that names itself the empty string must fall back
## rather than draw a blank caption.
class _EmptyStub extends Node2D:
	func player_interact() -> void:
		pass

	func interact_prompt_label() -> String:
		return ""
