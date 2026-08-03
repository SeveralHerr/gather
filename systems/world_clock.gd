extends Node
class_name WorldClock

## The world's time of day and its weather. This node draws nothing and lights nothing —
## it owns the numbers, and the lighting, the rain and the systems that react to either
## read them or listen to its signals.
##
## Same split as LevelUpManager, and for the same reason: a model that renders is a model
## that cannot be tested, cannot be driven from devtools without a viewport, and quietly
## acquires a second copy of its state in whatever it draws into.
##
## ## Why there is no Timer in this file
##
## Every duration here — the day, the storm — is a float advanced by `delta`. That is not a
## style preference. `Timer.start(t)` *assigns* `wait_time = t`, so restoring a partially
## elapsed timer on load silently reschedules every later cycle to the remaining time (see
## the save-fidelity section of CLAUDE.md, and gather-9x0 where a furnace did exactly this).
## A float has no such second field to clobber: `time_of_day` and `weather_time_left` are
## progress, they are what gets saved, and restoring them is assignment and nothing else.

## The phases of a day, in the order they occur. DAWN is the start of a day rather than
## the end of a night, which is what makes `day` increment at a boundary the player can
## see rather than in the middle of the dark.
enum Phase { DAWN, DAY, DUSK, NIGHT }

enum Weather { CLEAR, RAIN }

## Emitted when the phase changes, and only then — not every frame within a phase.
signal phase_changed(phase: Phase)

## Emitted when time_of_day wraps past 1.0 and `day` increments.
signal day_started(day: int)

## Emitted on the DAY -> DUSK... no: on entry to NIGHT. Separate from phase_changed so the
## things that only care about darkness (the spawner) do not have to filter four phases.
signal night_started(day: int)

signal weather_changed(weather: Weather)

# --- tuning ------------------------------------------------------------------

## Real seconds in one full cycle.
##
## Ten minutes, calibrated against the two loops it has to interleave with rather than
## against any other game's day: enemies trickle in every ~21s (EnemySpawner.SPAWN_INTERVAL)
## and resources regrow every 24s (the ResourceTimer in main.tscn). A cycle has to be long
## enough that a phase contains many of both — a three-minute night is ~8 spawns and ~7
## regrowths, which is a stretch of play with its own shape. Much shorter and night is a
## flicker the player waits out; much longer and a new player may never see one.
const DAY_LENGTH_SECONDS := 600.0

## Phase boundaries as fractions of a day, starting at dawn. Day is half the cycle and
## night is a little under a third; the two twilights are short because they are
## transitions, not places to be.
##
##   DAWN  0.00 - 0.10   1 min
##   DAY   0.10 - 0.60   5 min
##   DUSK  0.60 - 0.70   1 min
##   NIGHT 0.70 - 1.00   3 min
const DAWN_END := 0.10
const DAY_END := 0.60
const DUSK_END := 0.70

## The tint at full noon. Not pure white on purpose: it is the value every other tint is
## interpolated toward, so leaving a little headroom here means a future "bright summer
## day" has somewhere to go without every channel clipping.
const DAY_TINT := Color(1.0, 1.0, 1.0)

## The tint at the deepest point of night.
##
## The 0.42 floor is a READABILITY floor, not an aesthetic one. Everything the player has
## to read on a dark screen — the HP bar, an item sprite on the ground, the outline of a
## resource node — is multiplied by this, and below about 0.35 the 16px art stops being
## identifiable rather than merely being dark. Anyone tempted to make night "properly
## dark" should turn the blue up, not this down.
const NIGHT_TINT := Color(0.42, 0.46, 0.68)

## The tint at the midpoint of each twilight. Warm, and applied to both dawn and dusk from
## the one constant — the sun sets the same colour it rises.
const TWILIGHT_TINT := Color(0.86, 0.66, 0.55)

## Multiplied over whatever the time of day produces while it is raining.
##
## A multiplier rather than a colour of its own, so it composes with every hour the same
## way: an overcast noon and an overcast midnight are each the hour they already were,
## darker and a little cooler. A storm with its own absolute tint would flatten the two
## into the same grey and read as a different biome rather than as different weather.
##
## Note that "cooler" here is a ratio, not a difference — blue is attenuated less than red,
## so the world leans cool at every hour even though the absolute gap between the channels
## shrinks along with everything else. test_world_clock.gd pins that distinction.
const RAIN_TINT := Color(0.72, 0.76, 0.80)

## Chance of a storm on any given day, rolled once at dawn.
const RAIN_CHANCE := 0.25

## How much of a day a storm lasts, as a fraction. The upper end is deliberately shorter
## than the daylight it usually starts in: a storm that outlives the day it began in would
## make the rain bonus and the night penalty overlap every time, and those two are supposed
## to be felt separately before they are felt together.
const RAIN_MIN_FRACTION := 0.15
const RAIN_MAX_FRACTION := 0.35

# --- state -------------------------------------------------------------------

## Fraction through the current day, 0.0 (dawn) to 1.0 (exclusive).
##
## Starts at DAWN_END rather than 0.0 so a new game opens in full daylight. Starting at
## literal dawn means a new player's first thirty seconds are spent watching an orange
## screen resolve into a normal one, which reads as a loading artefact.
var time_of_day := DAWN_END

var day := 1

var weather: Weather = Weather.CLEAR

## Real seconds left in the current storm. Zero whenever `weather` is CLEAR. This is the
## `time_left`-shaped field: it is progress through this storm, not the configured length
## of storms, and it is what has to be saved. See the class comment.
var weather_time_left := 0.0

## The phase the last _process saw, so phase_changed fires on transitions rather than
## every frame. Deliberately initialised to the phase DAWN_END sits in, matching
## time_of_day above — otherwise the first frame of a new game emits a spurious change.
var _last_phase: Phase = Phase.DAY

## Set false by tests and by devtools when they want to drive the clock by hand.
var running := true


func _ready() -> void:
	add_to_group("SaveLoad")
	add_to_group("WorldClock")
	randomize()


func _process(delta: float) -> void:
	if not running or delta <= 0.0:
		return
	tick(delta)


## Advances the world by `delta` real seconds and emits whatever that crossed.
##
## Separate from _process so a test or a devtools verb can step the clock without a frame,
## and so `set_time_of_day` can reuse the same emission logic instead of growing a second
## copy of it that drifts.
func tick(delta: float) -> void:
	var advanced := advance(time_of_day, delta, DAY_LENGTH_SECONDS)
	time_of_day = advanced["time_of_day"]
	var days_elapsed: int = advanced["days_elapsed"]

	_advance_weather(delta)

	for _i in days_elapsed:
		day += 1
		_roll_weather()
		day_started.emit(day)

	_emit_phase_if_changed()


## Fires phase_changed (and night_started) if the phase has moved since the last call.
func _emit_phase_if_changed() -> void:
	var phase := phase_for(time_of_day)
	if phase == _last_phase:
		return

	_last_phase = phase
	phase_changed.emit(phase)
	if phase == Phase.NIGHT:
		night_started.emit(day)


func _advance_weather(delta: float) -> void:
	if weather == Weather.CLEAR:
		return

	weather_time_left -= delta
	if weather_time_left <= 0.0:
		set_weather(Weather.CLEAR, 0.0)


## Rolls for a storm. Called once per day at dawn, never mid-day: weather that can start at
## any moment is weather the player cannot read, and the whole point of a storm is that its
## arrival is a thing you notice and its bonus is a thing you go and use.
func _roll_weather() -> void:
	if weather != Weather.CLEAR:
		return
	if randf() >= RAIN_CHANCE:
		return

	var fraction := randf_range(RAIN_MIN_FRACTION, RAIN_MAX_FRACTION)
	set_weather(Weather.RAIN, fraction * DAY_LENGTH_SECONDS)


# --- pure helpers (unit-tested; keep them free of node access) ----------------


## `t` advanced by `delta` seconds, wrapped into 0..1, plus how many day boundaries that
## crossed. Returns both because the caller needs them together and a wrapped float alone
## cannot tell you whether it wrapped once or three times — which a long step-time, or a
## load that fast-forwards, genuinely can.
static func advance(t: float, delta: float, day_length: float) -> Dictionary:
	if day_length <= 0.0:
		# A zero-length day is a division by zero and an infinite day count. Refuse rather
		# than freeze: the clock simply does not move.
		push_warning("WorldClock: day_length must be positive, got %s" % day_length)
		return {"time_of_day": t, "days_elapsed": 0}

	var raw := t + delta / day_length
	return {
		"time_of_day": fposmod(raw, 1.0),
		"days_elapsed": int(floor(raw)) - int(floor(t)),
	}


## Which phase a fraction-through-the-day falls in. Boundaries belong to the phase they
## open: exactly DAWN_END is DAY, not DAWN.
static func phase_for(t: float) -> Phase:
	var wrapped := fposmod(t, 1.0)
	if wrapped < DAWN_END:
		return Phase.DAWN
	if wrapped < DAY_END:
		return Phase.DAY
	if wrapped < DUSK_END:
		return Phase.DUSK
	return Phase.NIGHT


## The canvas tint for a given time and weather.
##
## Continuous everywhere, including across every phase boundary and across the wrap at 1.0
## — a tint that jumps is a visible flicker, and the boundary it jumps at is the one place
## a reader is least likely to look. Each phase interpolates between the two endpoint
## colours that bracket it, so continuity is structural rather than something the constants
## have to be chosen to preserve.
static func tint_for(t: float, weather_state: Weather = Weather.CLEAR) -> Color:
	var wrapped := fposmod(t, 1.0)
	var tint: Color

	if wrapped < DAWN_END:
		# Night's colour at 0.0 climbing to full day at DAWN_END. The night side of this is
		# the same colour the NIGHT arm below holds, which is what makes the wrap seamless.
		tint = _through(NIGHT_TINT, TWILIGHT_TINT, DAY_TINT, _ramp(wrapped, 0.0, DAWN_END))
	elif wrapped < DAY_END:
		tint = DAY_TINT
	elif wrapped < DUSK_END:
		tint = _through(DAY_TINT, TWILIGHT_TINT, NIGHT_TINT, _ramp(wrapped, DAY_END, DUSK_END))
	else:
		tint = NIGHT_TINT

	if weather_state == Weather.RAIN:
		tint = tint * RAIN_TINT

	return tint


## `f` (0..1) along the path from -> via -> to, spending half the range on each leg.
##
## Twilight is not a straight line between night and day: the sun is warm at the horizon
## and neither endpoint is. A plain `NIGHT_TINT.lerp(DAY_TINT, f)` passes through the
## desaturated blue-grey halfway between them, which looks like a screen fading up rather
## than like a sunrise. The endpoints are exact at f=0 and f=1, so the phases either side
## still meet this one without a seam.
static func _through(from: Color, via: Color, to: Color, f: float) -> Color:
	if f < 0.5:
		return from.lerp(via, f * 2.0)
	return via.lerp(to, (f - 0.5) * 2.0)


## Where `t` falls between `start` and `end`, eased.
##
## Smoothstep rather than linear so a transition leaves the phase behind it and arrives at
## the one ahead gradually instead of starting and stopping abruptly at both ends. It is
## also what makes the tint's *rate of change* continuous at the boundaries, not just its
## value — a linear ramp meeting a constant is a visible crease even though the colours match.
static func _ramp(t: float, start: float, end: float) -> float:
	if end <= start:
		return 1.0
	var f := clampf((t - start) / (end - start), 0.0, 1.0)
	return f * f * (3.0 - 2.0 * f)


## Whether it is dark enough that the things which care about darkness should care.
## NIGHT only — dusk is when the player decides whether to head home, and folding it in
## here would mean the decision and its consequence arrive together.
static func is_dark(phase: Phase) -> bool:
	return phase == Phase.NIGHT


## Human-readable phase name, for devtools and for anything that shows the player a clock.
static func phase_name(phase: Phase) -> String:
	match phase:
		Phase.DAWN:
			return "dawn"
		Phase.DAY:
			return "day"
		Phase.DUSK:
			return "dusk"
		Phase.NIGHT:
			return "night"
	return "unknown"


static func weather_name(weather_state: Weather) -> String:
	return "rain" if weather_state == Weather.RAIN else "clear"


## The inverse of `weather_name`, for devtools and for a save written by a build with more
## weather types than this one. Unknown names read as CLEAR rather than raising.
static func weather_from_name(name: String) -> Weather:
	return Weather.RAIN if name.to_lower() == "rain" else Weather.CLEAR


# --- runtime reads -----------------------------------------------------------


func phase() -> Phase:
	return phase_for(time_of_day)


func tint() -> Color:
	return tint_for(time_of_day, weather)


func is_raining() -> bool:
	return weather == Weather.RAIN


func is_night() -> bool:
	return is_dark(phase())


## Sets the time and emits whatever that crossed, WITHOUT counting elapsed days — jumping
## the clock is not the same as living through the difference, and a devtools jump from
## dusk to dawn should not roll the weather twice on its way.
##
## Everything that reacts to the clock reacts to its signals, so this leaves the world in
## the same state the world would have reached by waiting. That is the requirement on a
## setter verb in CLAUDE.md, and the reason this is a method here rather than a raw
## property write in devtools_ext.
func set_time_of_day(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	_emit_phase_if_changed()


## Starts or stops weather. `seconds` is ignored for CLEAR.
func set_weather(new_weather: Weather, seconds: float) -> void:
	var changed := new_weather != weather
	weather = new_weather
	weather_time_left = maxf(0.0, seconds) if new_weather != Weather.CLEAR else 0.0

	if changed:
		weather_changed.emit(weather)


# --- save --------------------------------------------------------------------


func saveObject() -> Dictionary:
	return {
		"filepath": get_path(),
		"time_of_day": time_of_day,
		"day": day,
		"weather": weather_name(weather),
		# Progress, not configuration. Saving the storm's total length instead would restore
		# a storm that had thirty seconds left as a fresh three-minute one.
		"weather_time_left": weather_time_left,
	}


## Every read is `get` with a default, and nothing here indexes: a raise inside a `-> void`
## aborts the method and looks exactly like success, so a save written by an older build —
## which has no entry for this node at all — has to be a no-op rather than a crash.
func loadObject(loadedDict: Dictionary) -> void:
	time_of_day = fposmod(float(loadedDict.get("time_of_day", DAWN_END)), 1.0)
	day = int(loadedDict.get("day", 1))

	var stored_weather: Variant = loadedDict.get("weather", "clear")
	set_weather(
		weather_from_name(str(stored_weather)),
		float(loadedDict.get("weather_time_left", 0.0))
	)

	# The phase is derived, never stored — one fact in one place. Seeding _last_phase from
	# the restored time rather than letting the next tick discover it is what stops a load
	# into the middle of the night emitting night_started a second time.
	_last_phase = phase_for(time_of_day)
	phase_changed.emit(_last_phase)
