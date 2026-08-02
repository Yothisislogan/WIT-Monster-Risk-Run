extends Control
## Gesture surface for the right half of the screen (GAME_DESIGN.md §6, §22).
##
## This replaces seven on-screen buttons. Buttons cost the thing a phone has
## least of — screen — and on a landscape platformer they sit exactly where
## the action is. Gestures cost nothing to draw and put the whole play area
## back on screen.
##
## The mapping, chosen so that the shape of the gesture matches the shape of
## the move:
##
##   tap             jump          the most frequent verb gets the simplest
##                                 gesture; tap again in the air to double jump
##   swipe left/right  dash        a directional move from a directional swipe
##   swipe up        boss ability  "unleash"
##   swipe down      ground pound (airborne) / Monster Munch (grounded)
##   hold            charge shot, released on lift
##   two-finger tap  pause
##
## Swipe down fires the `pound` and `munch` actions together and lets the
## player decide: pound refuses unless airborne, munch refuses unless a
## weakened peril is in range. Neither does anything in the other's situation,
## so one gesture covers both without this layer knowing anything about the
## player's state.
##
## The basic weapon is not on a gesture at all — auto-fire is the default on
## touch, so holding is free to mean "charge". See Settings.DEFAULTS.
##
## Timings are exported because they are exactly the sort of thing that has to
## be tuned on a real phone, and tools/check_gestures.py holds them inside a
## band where taps, swipes and holds stay mutually exclusive.

## A press shorter than this, that has barely moved, is a tap.
@export var tap_max_time: float = 0.28
## How far a finger may drift and still count as a tap rather than a swipe.
@export var tap_slop: float = 26.0
## A swipe must cover this much, this quickly, or it is a hold or a drift.
@export var swipe_min_distance: float = 78.0
@export var swipe_max_time: float = 0.42
## A stationary finger starts charging after this long. Must sit above
## tap_max_time or every tap would fire a shot on the way past.
@export var hold_start_time: float = 0.30
## Two fingers landing within this window is a two-finger tap, not two taps.
@export var multi_touch_window: float = 0.25
## How long a fired action stays pressed. It cannot be zero: Input.action_press
## followed by action_release in the same frame is invisible to
## is_action_just_pressed, which is how every consumer of these reads them, so
## the gesture would do nothing at all. It must also stay below the player's
## jump_cut_min_hold, or releasing would cut every tapped jump to a hop —
## tools/check_gestures.py asserts both.
@export var action_hold_time: float = 0.06

var _touches: Dictionary = {}      # index -> {"start", "position", "time", "held"}
var _pressed_until: Dictionary = {}   # StringName -> time to release at
var _charging_index: int = -1
var _time: float = 0.0
## Set when a second finger arrives in time; suppresses both fingers' taps so
## a pause never also jumps.
var _multi_touch_consumed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # raw touch handling below


func _process(delta: float) -> void:
	_time += delta
	_release_expired()
	_update_holds()


## Actions fired by a gesture are held for a few frames rather than pulsed, so
## that a _physics_process reading is_action_just_pressed actually observes one.
func _release_expired() -> void:
	for action in _pressed_until.keys():
		if _time >= float(_pressed_until[action]):
			Input.action_release(action)
			_pressed_until.erase(action)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_abort_all()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index, event.position)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index]["position"] = event.position


func _on_press(index: int, position: Vector2) -> void:
	if not get_global_rect().has_point(position):
		return
	# A second finger inside the window is a two-finger tap. Resolve it now and
	# mark both fingers spent, so lifting them does not also jump twice.
	if not _touches.is_empty() and _youngest_age() <= multi_touch_window:
		_multi_touch_consumed = true
		_release_charge()
		_fire("pause")
		return
	_touches[index] = {
		"start": position, "position": position, "time": _time, "held": false}


func _on_release(index: int, position: Vector2) -> void:
	if not _touches.has(index):
		return
	var touch: Dictionary = _touches[index]
	_touches.erase(index)
	var was_charging := _charging_index == index
	if was_charging:
		_release_charge()
	if _multi_touch_consumed:
		if _touches.is_empty():
			_multi_touch_consumed = false
		return
	if was_charging:
		return                       # the hold already was the input

	var travel: Vector2 = position - Vector2(touch["start"])
	var duration: float = _time - float(touch["time"])
	var action := classify(travel, duration, tap_max_time, tap_slop,
			swipe_min_distance, swipe_max_time)
	match action:
		"dash_left":
			_fire_directional("dash", -1)
		"dash_right":
			_fire_directional("dash", 1)
		"special":
			_fire("special")
		"down":
			# Let the player's own preconditions pick. Pound refuses on the
			# ground; munch refuses with nothing weakened nearby.
			_fire("pound")
			_fire("munch")
		"tap":
			_fire("jump")


## Pure classification, no engine state — mirrored exactly by
## tools/check_gestures.py, which is why it takes its thresholds as arguments.
static func classify(travel: Vector2, duration: float, tap_time: float,
		slop: float, swipe_distance: float, swipe_time: float) -> String:
	var length := travel.length()
	if length >= swipe_distance and duration <= swipe_time:
		if absf(travel.x) >= absf(travel.y):
			return "dash_right" if travel.x > 0.0 else "dash_left"
		return "down" if travel.y > 0.0 else "special"
	if duration <= tap_time and length <= slop:
		return "tap"
	return "none"


## A finger that has sat still long enough starts charging the weapon.
func _update_holds() -> void:
	if _charging_index != -1 or _multi_touch_consumed:
		return
	for index in _touches.keys():
		var touch: Dictionary = _touches[index]
		if bool(touch["held"]):
			continue
		if _time - float(touch["time"]) < hold_start_time:
			continue
		# A swipe has already travelled well past the slop by now, so this
		# cannot catch one mid-flight.
		if (Vector2(touch["position"]) - Vector2(touch["start"])).length() > tap_slop:
			continue
		touch["held"] = true
		_charging_index = index
		Input.action_press("attack")
		return


func _release_charge() -> void:
	if _charging_index == -1:
		return
	_charging_index = -1
	Input.action_release("attack")


func _fire(action: StringName) -> void:
	# Re-press from scratch if it is somehow still down, so a second tap inside
	# the hold window still reads as a fresh press (tap, tap = double jump).
	if _pressed_until.has(action):
		Input.action_release(action)
	Input.action_press(action)
	_pressed_until[action] = _time + action_hold_time


## Dash takes its direction from the swipe, so it no longer depends on which
## way you happened to be facing. The axis is held for the same window; if the
## movement thumb is already pushing the other way the two cancel and the dash
## falls back to facing, which is the reasonable reading of that input.
func _fire_directional(action: StringName, direction: int) -> void:
	_fire(&"move_right" if direction > 0 else &"move_left")
	_fire(action)


func _youngest_age() -> float:
	var youngest := INF
	for touch in _touches.values():
		youngest = minf(youngest, _time - float(touch["time"]))
	return youngest


func _abort_all() -> void:
	_release_charge()
	for action in _pressed_until.keys():
		Input.action_release(action)
	_pressed_until.clear()
	_touches.clear()
	_multi_touch_consumed = false
