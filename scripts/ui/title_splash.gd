extends Node2D
## The title screen's animated backdrop, built entirely from polygons at
## runtime (GAME_DESIGN.md §20 — bright environments, clear visual hierarchy).
##
## `assets/art/` is empty and always has been: every visual in this game is
## procedural geometry, because a hand-written .tscn cannot import a sprite
## that nobody can open an editor to draw. So the title screen is a storm over
## Blaze Borough assembled out of Polygon2D, Line2D and CPUParticles2D — a
## gradient sky, a Risk moon, three scrolling skyline layers with lit windows,
## slanting rain, drifting Premiums, and lightning that flashes the whole
## scene and hands the strike down to the Monster to react to.
##
## Everything is laid out against the 1280x720 design viewport, but the
## project stretches with aspect "expand" (project.godot), so on a 20:9 phone
## the player genuinely sees outside that box. Backdrop geometry is therefore
## built across OVERSCAN on every side rather than to the nominal edges;
## tools/check_title.py asserts the margin covers the widest phone we target.
##
## Node count is a real constraint here — this runs in a browser on a phone.
## The windows of a whole city are three Polygon2D nodes per building, not one
## per window, using Polygon2D.polygons to put many faces in a single node.

signal lightning_struck(strength: float)

## How far past the 1280x720 design box the sky and skyline are drawn. A 20:9
## landscape phone showing 720px of height reveals 1600px of width, i.e. 160px
## past each side, so this has room to spare.
const OVERSCAN := 240.0
const DESIGN := Vector2(1280.0, 720.0)

## Sky ramp, top to bottom: night indigo, storm violet, then the amber smear
## of a city that is on fire somewhere off-screen.
const SKY_COLORS := [
	Color(0.05, 0.06, 0.13, 1.0),
	Color(0.16, 0.11, 0.28, 1.0),
	Color(0.42, 0.20, 0.30, 1.0),
	Color(0.86, 0.42, 0.24, 1.0),
]
## Where each ramp colour sits, as a fraction of the design height.
const SKY_STOPS := [0.0, 0.42, 0.78, 1.0]

const MOON_CENTRE := Vector2(1000.0, 214.0)
const MOON_RADIUS := 138.0
const MOON_COLOR := Color(0.99, 0.78, 0.42, 1.0)

## Far to near. `speed` is px/sec of drift; the near layer moves fastest, which
## is what sells the depth. `lit` is the share of window slots that are lit.
const SKYLINE_LAYERS := [
	{"y": 470.0, "height": 250.0, "width": 128.0, "gap": 54.0,
	 "speed": 5.0, "shade": 0.30, "lit": 0.0},
	{"y": 556.0, "height": 224.0, "width": 104.0, "gap": 42.0,
	 "speed": 12.0, "shade": 0.50, "lit": 0.30},
	{"y": 660.0, "height": 208.0, "width": 86.0, "gap": 30.0,
	 "speed": 26.0, "shade": 0.74, "lit": 0.44},
]
const SKYLINE_BASE := Color(0.13, 0.10, 0.24, 1.0)
const SKYLINE_LIT := Color(0.30, 0.24, 0.46, 1.0)
const WINDOW_PANE := 13.0
const WINDOW_PITCH := 30.0
const WINDOW_COLOR := Color(1.0, 0.83, 0.44, 1.0)
## Windows that blink are their own node, so this is a node budget as much as
## an art direction: one blinker per building.
const BLINKERS_PER_BUILDING := 1
const BLINK_PERIOD := Vector2(1.6, 5.5)

const STAR_COUNT := 54

## Lightning cadence. One flash rarely reads as weather; two or three inside a
## second does, followed by a long calm.
const STRIKE_GAP := Vector2(4.5, 9.0)
const BURST_EXTRA_MAX := 2
const BURST_GAP := Vector2(0.12, 0.3)
const FLASH_CEILING := 0.42
## Reduce flashing (§22) keeps the storm but drops the full-screen bloom to a
## hint. The bolt itself stays: it is a shape, not a strobe.
const FLASH_CEILING_REDUCED := 0.06

var _time: float = 0.0
var _strike_timer: float = 2.0
var _burst_left: int = 0
var _flash: Polygon2D = null
var _flash_level: float = 0.0
var _bolt: Line2D = null
var _bolt_level: float = 0.0
var _stars: Array[Polygon2D] = []
var _star_phases: PackedFloat32Array = PackedFloat32Array()
var _skylines: Array[Node2D] = []
var _blinkers: Array[Polygon2D] = []
var _blink_phases: PackedFloat32Array = PackedFloat32Array()
var _blink_rates: PackedFloat32Array = PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Seeded, so the skyline is the same city every time the player comes back
	# to the menu rather than a different one on every scene load.
	_rng.seed = 0x1715C0DE
	_build_sky()
	_build_moon()
	_build_stars()
	_build_skylines()
	_build_rain()
	_build_premiums()
	_build_lightning()
	_strike_timer = _rng.randf_range(1.2, 2.6)


func _process(delta: float) -> void:
	_time += delta
	_drift_skylines(delta)
	_twinkle()
	_blink_windows()
	_run_lightning(delta)


# --- construction ------------------------------------------------------------

func _quad(left: float, top: float, right: float, bottom: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(left, top), Vector2(right, top),
		Vector2(right, bottom), Vector2(left, bottom)])


func _circle(centre: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


## The sky is one Polygon2D per ramp segment using vertex_colors, so the
## gradient is interpolated by the renderer instead of being faked with a stack
## of flat bands. Three quads is the whole sky.
func _build_sky() -> void:
	for i in SKY_COLORS.size() - 1:
		var top := float(SKY_STOPS[i]) * DESIGN.y
		var bottom := float(SKY_STOPS[i + 1]) * DESIGN.y
		if i == 0:
			top = -OVERSCAN
		if i == SKY_COLORS.size() - 2:
			bottom = DESIGN.y + OVERSCAN
		var band := Polygon2D.new()
		band.polygon = _quad(-OVERSCAN, top, DESIGN.x + OVERSCAN, bottom)
		band.vertex_colors = PackedColorArray([
			SKY_COLORS[i], SKY_COLORS[i],
			SKY_COLORS[i + 1], SKY_COLORS[i + 1]])
		add_child(band)


## The Risk moon: a disc, a soft halo and two thin rings. It sits behind the
## Monster's shoulder and is the one warm thing in the upper half of the frame.
func _build_moon() -> void:
	for step in 4:
		var halo := Polygon2D.new()
		halo.polygon = _circle(MOON_CENTRE, MOON_RADIUS * (2.05 - 0.28 * step), 40)
		halo.color = Color(MOON_COLOR.r, MOON_COLOR.g, MOON_COLOR.b, 0.045)
		add_child(halo)

	var disc := Polygon2D.new()
	disc.polygon = _circle(MOON_CENTRE, MOON_RADIUS, 48)
	disc.color = MOON_COLOR
	add_child(disc)

	# A few craters, so it reads as a moon and not a headlight.
	for crater in [
			{"at": Vector2(-44.0, -30.0), "r": 26.0},
			{"at": Vector2(38.0, 24.0), "r": 34.0},
			{"at": Vector2(10.0, -62.0), "r": 17.0}]:
		var pit := Polygon2D.new()
		pit.polygon = _circle(MOON_CENTRE + Vector2(crater["at"]), float(crater["r"]), 20)
		pit.color = MOON_COLOR.darkened(0.14)
		add_child(pit)

	for ring_scale in [1.34, 1.52]:
		var ring := Line2D.new()
		var points := _circle(MOON_CENTRE, MOON_RADIUS * ring_scale, 56)
		points.append(points[0])
		ring.points = points
		ring.width = 3.0
		ring.default_color = Color(MOON_COLOR.r, MOON_COLOR.g, MOON_COLOR.b, 0.3)
		ring.antialiased = true
		add_child(ring)


func _build_stars() -> void:
	for i in STAR_COUNT:
		var star := Polygon2D.new()
		var size := _rng.randf_range(1.4, 3.2)
		var at := Vector2(
			_rng.randf_range(-OVERSCAN, DESIGN.x + OVERSCAN),
			_rng.randf_range(-OVERSCAN * 0.5, DESIGN.y * 0.52))
		star.polygon = _quad(at.x - size, at.y - size, at.x + size, at.y + size)
		star.color = Color(0.86, 0.90, 1.0, 1.0)
		add_child(star)
		_stars.append(star)
		_star_phases.append(_rng.randf_range(0.0, TAU))


## Each layer is two identical tiles side by side, scrolled left by up to one
## tile width and then snapped back. The snap is invisible only because the
## tiles match exactly, which is why the RNG is re-seeded per tile rather than
## run straight through: heights AND window layout have to repeat.
func _build_skylines() -> void:
	for spec in SKYLINE_LAYERS:
		var layer := Node2D.new()
		add_child(layer)
		_skylines.append(layer)

		var step := float(spec["width"]) + float(spec["gap"])
		var tile := int(ceil((DESIGN.x + 2.0 * OVERSCAN) / step)) + 1
		var tile_seed := _rng.randi()
		for repeat in 2:
			_rng.seed = tile_seed
			for i in tile:
				_build_building(layer, spec, -OVERSCAN + float(repeat * tile + i) * step)
		layer.set_meta("speed", float(spec["speed"]))
		layer.set_meta("wrap", float(tile) * step)


func _build_building(layer: Node2D, spec: Dictionary, x: float) -> void:
	var width := float(spec["width"])
	var height := float(spec["height"]) * _rng.randf_range(0.5, 1.0)
	var top := float(spec["y"]) - height

	var block := Polygon2D.new()
	block.polygon = _quad(x, top, x + width, DESIGN.y + OVERSCAN)
	block.color = SKYLINE_BASE.lerp(SKYLINE_LIT, float(spec["shade"]))
	layer.add_child(block)

	var lit_share := float(spec["lit"])
	if lit_share <= 0.0:
		return

	# Every lit window slot in this building collapses into one Polygon2D with
	# many faces, except the handful chosen to blink.
	var slots: Array[Vector2] = []
	var columns := int((width - 16.0) / WINDOW_PITCH)
	var rows := int((height - 24.0) / WINDOW_PITCH)
	for column in columns:
		for row in rows:
			if _rng.randf() > lit_share:
				continue
			slots.append(Vector2(x + 12.0 + column * WINDOW_PITCH,
				top + 16.0 + row * WINDOW_PITCH))
	if slots.is_empty():
		return

	for i in mini(BLINKERS_PER_BUILDING, slots.size()):
		var at: Vector2 = slots.pop_back()
		var blinker := Polygon2D.new()
		blinker.polygon = _quad(at.x, at.y, at.x + WINDOW_PANE, at.y + WINDOW_PANE)
		blinker.color = WINDOW_COLOR
		layer.add_child(blinker)
		_blinkers.append(blinker)
		_blink_phases.append(_rng.randf_range(0.0, TAU))
		_blink_rates.append(TAU / _rng.randf_range(BLINK_PERIOD.x, BLINK_PERIOD.y))

	if slots.is_empty():
		return
	var panes := Polygon2D.new()
	var points := PackedVector2Array()
	# Untyped, because Polygon2D.polygons is a plain Array and this is what
	# goes straight into it.
	var faces := []
	for at in slots:
		var base := points.size()
		points.append_array(_quad(at.x, at.y, at.x + WINDOW_PANE, at.y + WINDOW_PANE))
		faces.append(PackedInt32Array([base, base + 1, base + 2, base + 3]))
	panes.polygon = points
	panes.polygons = faces
	panes.color = Color(WINDOW_COLOR.r, WINDOW_COLOR.g, WINDOW_COLOR.b, 0.8)
	layer.add_child(panes)


func _build_rain() -> void:
	var rain := CPUParticles2D.new()
	rain.amount = 180
	rain.lifetime = 1.5
	rain.preprocess = 1.5
	rain.local_coords = false
	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain.emission_rect_extents = Vector2(DESIGN.x * 0.5 + OVERSCAN, 12.0)
	rain.position = Vector2(DESIGN.x * 0.5, -OVERSCAN * 0.5)
	rain.direction = Vector2(-0.28, 1.0)
	rain.spread = 3.0
	rain.gravity = Vector2(-90.0, 900.0)
	rain.initial_velocity_min = 460.0
	rain.initial_velocity_max = 640.0
	rain.scale_amount_min = 1.0
	rain.scale_amount_max = 2.2
	rain.color = Color(0.68, 0.80, 1.0, 0.34)
	add_child(rain)


## Premiums drifting up out of the city — the same gold as the pickup, so the
## title screen is already teaching what the currency looks like (§9).
func _build_premiums() -> void:
	var coins := CPUParticles2D.new()
	coins.amount = 26
	coins.lifetime = 6.5
	coins.preprocess = 6.5
	coins.local_coords = false
	coins.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	coins.emission_rect_extents = Vector2(DESIGN.x * 0.5, 20.0)
	coins.position = Vector2(DESIGN.x * 0.5, DESIGN.y + 40.0)
	coins.direction = Vector2(0.0, -1.0)
	coins.spread = 16.0
	coins.gravity = Vector2(14.0, -12.0)
	coins.initial_velocity_min = 40.0
	coins.initial_velocity_max = 96.0
	coins.scale_amount_min = 3.0
	coins.scale_amount_max = 6.0
	coins.angle_min = -180.0
	coins.angle_max = 180.0
	coins.color = Color(1.0, 0.82, 0.30, 0.62)
	add_child(coins)


func _build_lightning() -> void:
	_bolt = Line2D.new()
	_bolt.width = 5.0
	_bolt.default_color = Color(0.86, 0.93, 1.0, 0.0)
	_bolt.antialiased = true
	add_child(_bolt)

	_flash = Polygon2D.new()
	_flash.polygon = _quad(-OVERSCAN, -OVERSCAN,
		DESIGN.x + OVERSCAN, DESIGN.y + OVERSCAN)
	_flash.color = Color(0.78, 0.87, 1.0, 0.0)
	add_child(_flash)


# --- animation ---------------------------------------------------------------

## Drift left forever. fposmod keeps position.x inside (-wrap, 0], and because
## the layer is two matching tiles the wrap point looks like no event at all.
func _drift_skylines(delta: float) -> void:
	for layer in _skylines:
		var speed: float = layer.get_meta("speed")
		var wrap: float = layer.get_meta("wrap")
		layer.position.x = fposmod(layer.position.x - speed * delta, wrap) - wrap


func _twinkle() -> void:
	for i in _stars.size():
		_stars[i].color.a = 0.35 + 0.45 * (0.5 + 0.5 * sin(_time * 1.7 + _star_phases[i]))


## Each blinking window runs its own slow square wave. No timers, no array
## churn — the phase and rate were picked once at build time.
func _blink_windows() -> void:
	for i in _blinkers.size():
		var wave := sin(_time * _blink_rates[i] + _blink_phases[i])
		_blinkers[i].color.a = 0.9 if wave > -0.35 else 0.06


func _run_lightning(delta: float) -> void:
	_flash_level = maxf(_flash_level - delta * 4.2, 0.0)
	_bolt_level = maxf(_bolt_level - delta * 6.5, 0.0)
	var ceiling := FLASH_CEILING_REDUCED if Juice.reduced_flashing else FLASH_CEILING
	_flash.color.a = minf(_flash_level, 1.0) * ceiling
	_bolt.default_color.a = _bolt_level

	_strike_timer -= delta
	if _strike_timer > 0.0:
		return
	_strike()
	if _burst_left > 0:
		_burst_left -= 1
		_strike_timer = _rng.randf_range(BURST_GAP.x, BURST_GAP.y)
	else:
		_burst_left = _rng.randi_range(0, BURST_EXTRA_MAX)
		_strike_timer = _rng.randf_range(STRIKE_GAP.x, STRIKE_GAP.y)


func _strike() -> void:
	var strength := _rng.randf_range(0.55, 1.0)
	_flash_level = strength
	_bolt_level = strength
	_bolt.points = _bolt_path()
	if strength > 0.85:
		Sfx.play("pound_impact", 0.12, 0.35)
	lightning_struck.emit(strength)


## A jagged descent from above the frame to somewhere behind the skyline.
## Regenerated per strike, so no two bolts repeat.
func _bolt_path() -> PackedVector2Array:
	var points := PackedVector2Array()
	var at := Vector2(_rng.randf_range(140.0, DESIGN.x - 140.0), -OVERSCAN * 0.4)
	var target_y := _rng.randf_range(360.0, 500.0)
	points.append(at)
	while at.y < target_y:
		at += Vector2(_rng.randf_range(-46.0, 46.0), _rng.randf_range(34.0, 74.0))
		points.append(at)
	return points
