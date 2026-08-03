extends Timer

## Drives continuous resource regrowth. There is no wave / phase concept: this
## fires forever, and ResourceManager2.add_random_resource() is what declines the
## spawn once the density-scaled cap is reached.
##
## The cadence itself is `wait_time` on the ResourceTimer node in main.tscn (24s), not a
## constant here — the only tuning number in this file's domain that lives in the scene.
## It was 8s, which refilled a cleared area about as fast as it could be cleared and made
## the density cap, rather than the timer, the only thing the player ever felt.
##
## Rain speeds that up (gather-bqn). The multiplier is applied to `_base_interval`, captured
## once from the scene, and NEVER to the live `wait_time`: multiplying the current value
## compounds every time the weather changes, and after three storms the world regrows
## instantly while nothing in the diff looks wrong. Same reasoning as PlayerStats recomputing
## from the taken set rather than applying deltas.

@export var tileMapHandler: TileMapHandler
@export var resourceManager: ResourceManager2

## What one regrowth costs while it is raining, as a fraction of the clear-weather cadence.
##
## This is the reason to go out in a storm rather than sit it out, so it has to be worth
## interrupting what you were doing for — 0.9 would be invisible. It is the positive half of
## the cycle; night is the negative half.
const RAIN_INTERVAL_MULT := 0.55

## The scene-authored cadence, captured before anything multiplies it. This is what the
## timer returns to when the storm ends, and it is deliberately read off the node rather
## than duplicated as a constant here — see the note above about where that number lives.
var _base_interval := 0.0


func _ready() -> void:
	# Belt and braces against the scene ever being saved with these flipped: a
	# one_shot or stopped timer means resources stop regrowing partway into a run,
	# which looks like a balance problem rather than a dead timer.
	one_shot = false

	_base_interval = wait_time

	var clock := _clock()
	if clock != null:
		clock.weather_changed.connect(_on_weather_changed)
		_apply_weather(clock.weather)
	else:
		# Never silent. This node is under `World` and the clock under `Systems`, which
		# main.tscn declares last, so this lookup happening too early is a live hazard rather
		# than a theoretical one — it is exactly what went wrong before WorldClock moved its
		# group registration into `_enter_tree`. The failure mode is rain that visibly falls
		# while the regrowth cadence never changes, which looks like a balance decision.
		push_warning("ResourceSpawnTimer: no WorldClock in the tree, so rain will not speed up regrowth")

	if is_stopped():
		start()


## The clock, by group rather than by path: this node is under `World` and the clock is
## under `Systems`, so there is no stable relative path between them, and a group lookup
## states what it wants. Iterated and type-checked rather than indexed, per CLAUDE.md.
func _clock() -> WorldClock:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("WorldClock"):
		if node is WorldClock:
			return node
	return null


func _on_weather_changed(weather: WorldClock.Weather) -> void:
	_apply_weather(weather)


## Retunes the cadence for the current weather.
##
## `wait_time` is assigned directly rather than through `start()`, which would restart the
## countdown: a storm arriving one second before a regrowth would push that regrowth a full
## interval into the future, so the first visible effect of "things grow faster now" would
## be a longer wait. Godot applies a new `wait_time` from the next cycle, which is what is
## wanted here — and note this is the same property `Timer.start(t)` clobbers, which is why
## `_base_interval` exists at all.
func _apply_weather(weather: WorldClock.Weather) -> void:
	if _base_interval <= 0.0:
		return

	var multiplier := RAIN_INTERVAL_MULT if weather == WorldClock.Weather.RAIN else 1.0
	wait_time = _base_interval * multiplier


func _on_timeout():
	if resourceManager == null:
		return
	resourceManager.add_random_resource()
