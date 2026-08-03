extends Node2D
class_name CraftingStation

## A placed sawmill or furnace. The station is a *producer*, not a menu: crafting pays
## the cost up front and sets a work order, and the station then ticks one item per
## second into the world at its own feet. That is why crafting is station-bound and
## why building a second one is real throughput rather than decoration.

signal toggle_crafting_station(crafting_station)

## Emitted on every tick so the panel can redraw without polling from _process.
## `remaining` is the count left after this item.
signal produced(product: Types.Item, remaining: int)

## Emitted when the work order changes for any other reason (queued, cancelled).
signal order_changed

@export var recipe_list = []
@export var selected_recipe: CraftingRecipe
@export var count: int
@export var type: Types.Item
@export var timer: Timer

var starting_count: int = 0

func player_interact() -> void:
	toggle_crafting_station.emit(self)

func _ready():
	add_to_group("CraftingStations")
	add_to_group("SaveChunks")

	timer = Timer.new()
	timer.wait_time = 1
	add_child(timer)
	timer.connect("timeout", Callable(self, "_on_timeout"))

	# Bound by reference on purpose: Recipes mutates these arrays in place when a
	# skill unlocks something, so a station placed before the unlock still sees it.
	recipe_list = Recipes.get_recipes(type)
	# A furnace can legitimately exist with nothing unlocked at it yet, so this cannot
	# assume recipe_list[0] is there.
	selected_recipe = recipe_list[0] if not recipe_list.is_empty() else null

	for node in get_tree().get_nodes_in_group("InventoryManager"):
		# The scene root is in every group, so a type check is the only reliable way
		# to find the real manager - indexing [1] happens to work today only because
		# every station is instanced at runtime, after the manager's _ready.
		if node is NewInventoryManager:
			toggle_crafting_station.connect(node._toggle_crafting_station)
			break


func _process(_delta):
	if count <= 0:
		timer.stop()
	elif count > 0:
		if timer.is_stopped():
			timer.start()


## Pays for `amount` of `recipe` out of `inventory_data` and puts it on the order.
## All-or-nothing: an unaffordable order removes nothing and returns false.
func enqueue(recipe: CraftingRecipe, amount: int, inventory_data: InventoryData) -> bool:
	if recipe == null or amount <= 0 or inventory_data == null:
		return false
	if not inventory_data.spend_cost(recipe.cost_list, amount):
		return false

	# Selection, order size and progress denominator move together. Setting one
	# without the others is what left a loaded station showing a progress bar over a
	# max_value of zero.
	selected_recipe = recipe
	count += amount
	starting_count = count
	order_changed.emit()
	return true


## Abandons the rest of the order and refunds it. The refund is dropped at the
## station rather than pushed into the bag so a full inventory cannot eat it.
func cancel() -> int:
	var refunded := count
	if refunded > 0 and selected_recipe:
		for item_type in selected_recipe.cost_list:
			var per_unit := int(selected_recipe.cost_list[item_type]) * refunded
			for i in per_unit:
				PickUpManager.create_pickup(GameItems.get_item(item_type), position + Vector2(0, 6))

	count = 0
	starting_count = 0
	timer.stop()
	order_changed.emit()
	return refunded


func _on_timeout():
	# A running timer with no recipe is a state the save format can express and the loader
	# could not survive: save() writes selected_recipe -1 whenever the recipe is null, and
	# load() restores the running timer either way — so the first tick read `.product` off
	# null and threw "Invalid access to property or key 'product' on a base object of type
	# 'Nil'". Stop rather than produce: there is nothing to make.
	if selected_recipe == null:
		timer.stop()
		count = 0
		starting_count = 0
		order_changed.emit()
		return

	count -= 1
	PickUpManager.create_pickup(GameItems.get_item(selected_recipe.product), position + Vector2(0, 6))

	# Every produced item scores, so a station ticking away pays out visibly. Found by
	# group rather than exported so a station placed at runtime needs no wiring.
	var level_up_manager := LevelUpManager.find(self)
	if level_up_manager:
		level_up_manager.add_xp(LevelUpManager.XP_CRAFT, global_position + Vector2(0, -8))

	produced.emit(selected_recipe.product, count)


func save():
	var dict = {
		"x": position.x,
		"y": position.y,
		"selected_recipe": selected_recipe.product if selected_recipe else -1,
		"count": count,
		# The progress bar divides by this. Leaving it out of the save is what made a
		# loaded, half-finished station show an empty bar over a live work order.
		"starting_count": starting_count,
		"wait_time": timer.wait_time,
		# The interval above is how long ONE item takes; this is how much of the current
		# one is left. Without it, load() restarted the timer from wait_time and a furnace
		# 95% through an ore silently went back to the start of it (gather-9x0). count and
		# starting_count are restored either way, so the progress bar looked correct while
		# the work order had actually slipped back by up to a full cycle — the player sees
		# only "it didn't resume where I left off".
		"time_left": timer.time_left,
		"timer_status": timer.is_stopped(),
		"type": type,
		"filepath": "343"
	}

	return dict

## Every value here comes from JSON.parse of a file on disk, so nothing about its shape is
## guaranteed: an older build's save, or one edited by hand, can put any type in any slot.
## Each read is therefore defaulted rather than indexed. An unguarded dict["k"] raises, and
## `func load(dict)` is untyped, so the raise aborts the method and returns null — leaving a
## station half-restored with no error anyone can see (gather-wfu).
func load(dict):
	if typeof(dict) != TYPE_DICTIONARY:
		return

	type = int(dict.get("type", type))

	# One lookup keyed on the station, rather than an if/elif naming each one. A station type
	# this chain did not name used to restore with selected_recipe still null and its work
	# order silently dropped on the next line (gather-uaq).
	var recipe_id: int = int(dict.get("selected_recipe", -1))
	selected_recipe = Recipes.get_recipe(type, recipe_id)

	count = int(dict.get("count", 0))
	# Saves written before starting_count was persisted have no key for it; falling
	# back to count means the bar reads full rather than dividing by zero.
	starting_count = int(dict.get("starting_count", count))

	# How long ONE item takes. Held in a local because start() below overwrites it.
	var interval: float = maxf(0.01, float(dict.get("wait_time", timer.wait_time)))
	timer.wait_time = interval

	# Same invariant, enforced on the way in: no recipe means no work order, so a payload
	# that pairs a running timer with selected_recipe -1 comes back stopped instead of
	# ticking toward a production it cannot perform.
	if selected_recipe == null:
		timer.stop()
		count = 0
		starting_count = 0
		return

	# `== true` on a JSON value raises "Invalid operands" against a String rather than
	# evaluating false — the trap bone_worker.gd:782 documents at length. Compare the type.
	var stopped: bool = bool(dict.get("timer_status", true))
	if stopped:
		timer.stop()
	else:
		# Saves predating time_left have no key for it, and start() with a non-positive
		# argument is an error, so fall back to a whole fresh cycle: the old behaviour,
		# now only for the old saves that actually need it.
		var remaining: float = float(dict.get("time_left", 0.0))
		if remaining > 0.0:
			# Timer.start(t) ASSIGNS wait_time = t — it is not "run for t this once". So
			# the interval has to be put back immediately afterwards, or the station
			# resumes correctly and then runs every *later* item at whatever was left of
			# this one. A furnace saved with 0.3s to go would smelt the remaining 53 ore
			# in 0.3s each. Assigning wait_time on a running Timer does not restart it, so
			# the restored time_left survives this line.
			timer.start(remaining)
			timer.wait_time = interval
		else:
			timer.start()
