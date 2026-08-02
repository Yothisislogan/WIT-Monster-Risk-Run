extends Node2D
## The WIT Monster, five times life size, idling on the title screen.
##
## This is the same character as scripts/player/monster_visual.gd and it is
## built the same way — Polygon2D, no sprites — but it answers to nothing. The
## in-game one reads velocity and grounding off a CharacterBody2D; this one has
## no body to read, so its personality has to come from the idle alone:
## breathing, a slow sway, a tail that lags behind the sway, pupils that drift
## and settle, blinks at uneven intervals, and a reaction when the storm
## outside flashes (§32.10 — "the Monster's personality is visible through
## animation alone").
##
## Geometry is authored in local space with the feet on the ground plane and
## the origin between them. LOCAL_BOUNDS states the box the art stays inside;
## tools/check_title.py re-derives that box from the polygons below and fails
## if any of them grows past it, because the whole title layout — where the
## wordmark ends, where the menu column starts — is arranged around it.

## Where the Monster stands, in 1280x720 design coordinates.
const HOME := Vector2(998.0, 548.0)
const ART_SCALE := 1.15

## Local-space bounds of every polygon below, before animation.
const LOCAL_BOUNDS := Rect2(-152.0, -352.0, 304.0, 388.0)

const IDLE_BOB := 8.0        ## px of vertical float, before ART_SCALE
const BREATH := 0.03         ## fraction of scale the chest adds on the inhale
const SWAY_DEGREES := 1.8
const TAIL_SWAY_FACTOR := 4.0
## The chest squashes vertically by less than it swells horizontally.
const BREATH_SQUASH_RATIO := 0.6
## The startle is the largest thing that happens to this silhouette, and it is
## the reason these are constants rather than literals down in _process:
## tools/check_title.py sweeps the whole animation envelope from them to prove
## the Monster never swings into the wordmark or the menu column.
const STARTLE_LIFT := 14.0
const STARTLE_SWELL := 0.04
const STARTLE_SQUASH := 0.05
const STARTLE_MOUTH_WIDEN := 0.12
const MOUTH_OPEN_MAX := 1.5

const SKIN := Color(0.12, 0.48, 0.88, 1.0)
const SKIN_DARK := Color(0.09, 0.35, 0.68, 1.0)
const BELLY_COLOR := Color(0.35, 0.68, 0.98, 1.0)
const EYE_WHITE := Color(1.0, 1.0, 1.0, 1.0)
const EYE_LIT := Color(1.0, 0.95, 0.7, 1.0)
const PUPIL_COLOR := Color(0.05, 0.12, 0.24, 1.0)
const MOUTH_COLOR := Color(0.07, 0.05, 0.14, 1.0)
const TOOTH := Color(1.0, 0.98, 0.92, 1.0)
const CLAW := Color(0.92, 0.95, 1.0, 1.0)
## The rim light is the Risk moon behind the right shoulder catching the edge.
const RIM := Color(1.0, 0.80, 0.46, 0.85)

const BODY: Array[Vector2] = [
	Vector2(-96, 4), Vector2(-116, -60), Vector2(-122, -140),
	Vector2(-108, -214), Vector2(-74, -268), Vector2(-26, -296),
	Vector2(26, -296), Vector2(74, -268), Vector2(108, -214),
	Vector2(122, -140), Vector2(116, -60), Vector2(96, 4),
]
const BELLY: Array[Vector2] = [
	Vector2(-62, -26), Vector2(-72, -96), Vector2(-56, -150),
	Vector2(0, -166), Vector2(56, -150), Vector2(72, -96),
	Vector2(62, -26), Vector2(40, 2), Vector2(-40, 2),
]
const FOOT: Array[Vector2] = [
	Vector2(-46, -6), Vector2(46, -6), Vector2(54, 18),
	Vector2(40, 32), Vector2(-44, 32), Vector2(-58, 18),
]
const CLAW_TOOTH: Array[Vector2] = [
	Vector2(-6, 20), Vector2(6, 20), Vector2(0, 32),
]
const ARM: Array[Vector2] = [
	Vector2(0, 0), Vector2(30, 6), Vector2(44, 62),
	Vector2(38, 108), Vector2(10, 116), Vector2(-8, 96), Vector2(-10, 40),
]
const HORN: Array[Vector2] = [
	Vector2(-22, 0), Vector2(-6, -76), Vector2(18, -4),
]
const TAIL: Array[Vector2] = [
	Vector2(0, 0), Vector2(-22, 18), Vector2(-52, 26),
	Vector2(-76, 12), Vector2(-70, -6), Vector2(-46, 4), Vector2(-18, -12),
]
## Authored around its own origin, because _update_mouth scales it open.
const MOUTH: Array[Vector2] = [
	Vector2(-56, -29), Vector2(56, -29), Vector2(44, 15),
	Vector2(0, 29), Vector2(-44, 15),
]
const TOOTH_SHAPE: Array[Vector2] = [
	Vector2(-9, 0), Vector2(9, 0), Vector2(0, 20),
]
const BROW: Array[Vector2] = [
	Vector2(-30, 0), Vector2(28, -14), Vector2(30, 2), Vector2(-28, 14),
]

## Placement of the mirrored parts. Left copies use scale.x = -1.
const FOOT_OFFSET := Vector2(52.0, 4.0)
const CLAW_SPACING := 26.0
const ARM_OFFSET := Vector2(96.0, -180.0)
const HORN_OFFSET := Vector2(52.0, -276.0)
const EYE_OFFSET := Vector2(44.0, -212.0)
const BROW_OFFSET := Vector2(46.0, -244.0)
const TAIL_OFFSET := Vector2(-74.0, -70.0)
const MOUTH_OFFSET := Vector2(0.0, -99.0)
const TOOTH_OFFSET := Vector2(-36.0, -128.0)
const TOOTH_SPACING := 24.0
const EYE_RADIUS := 27.0
const EYE_SQUASH := 0.86
const PUPIL_RADIUS := 12.0
const PUPIL_TRAVEL := 8.0
const LID_MARGIN := 2.0
const LID_HEIGHT_FACTOR := 2.0
const CLAW_TOES := 3
const TOOTH_COUNT := 4
## How far the lit silhouette copy peeks out from behind the body.
const RIM_OFFSET := Vector2(7.0, -4.0)

const BLINK_GAP := Vector2(2.2, 5.4)
const BLINK_TIME := 0.13

var _age: float = 0.0
var _blink_timer: float = 2.0
var _blink: float = 0.0
var _startle: float = 0.0
var _pupil_target := Vector2.ZERO
var _pupil_at := Vector2.ZERO
var _pupil_timer: float = 0.0

var _root: Node2D = null
var _tail: Node2D = null
var _eyes: Array[Polygon2D] = []
var _pupils: Array[Polygon2D] = []
var _lids: Array[Polygon2D] = []
var _mouth: Polygon2D = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x105A11FE
	position = HOME
	scale = Vector2(ART_SCALE, ART_SCALE)
	_build()
	_blink_timer = _rng.randf_range(BLINK_GAP.x, BLINK_GAP.y)


func _process(delta: float) -> void:
	_age += delta
	_startle = maxf(_startle - delta * 2.4, 0.0)

	# Breathing drives the bob and the chest a beat apart, so the Monster looks
	# like it is inhaling rather than like a sprite being scaled by a tween.
	var breath := sin(_age * 1.25)
	_root.position.y = -IDLE_BOB * (0.5 + 0.5 * breath) - _startle * STARTLE_LIFT
	_root.scale = Vector2(
		1.0 + BREATH * breath + _startle * STARTLE_SWELL,
		1.0 - BREATH * breath * BREATH_SQUASH_RATIO + _startle * STARTLE_SQUASH)
	_root.rotation = deg_to_rad(SWAY_DEGREES) * sin(_age * 0.62)

	# The tail lags the sway by a beat and swings further, which is most of
	# what makes the pose read as alive rather than as one rocking sprite.
	_tail.rotation = deg_to_rad(SWAY_DEGREES * TAIL_SWAY_FACTOR) * sin(_age * 0.62 - 0.9)

	_update_eyes(delta)
	_update_mouth()


## Wired by title_screen.gd to the backdrop's lightning. The Monster startles,
## its eyes catch the flash, and it grins wider — it likes the storm.
func on_lightning(strength: float) -> void:
	_startle = maxf(_startle, strength)
	_blink = 0.0
	_blink_timer = maxf(_blink_timer, 0.5)
	for eye in _eyes:
		eye.color = EYE_WHITE.lerp(EYE_LIT, strength)


# --- construction ------------------------------------------------------------

func _build() -> void:
	# One inner node carries every animated transform, so `position` and
	# `scale` on this node stay exactly HOME and ART_SCALE — which is what the
	# layout checker measures against.
	_root = Node2D.new()
	add_child(_root)

	_tail = Node2D.new()
	_tail.position = TAIL_OFFSET
	_root.add_child(_tail)
	_tail.add_child(_polygon(TAIL, SKIN_DARK))

	for side in [-1.0, 1.0]:
		var foot := _polygon(FOOT, SKIN_DARK)
		foot.position = Vector2(FOOT_OFFSET.x * side, FOOT_OFFSET.y)
		foot.scale = Vector2(side, 1.0)
		_root.add_child(foot)
		for toe in CLAW_TOES:
			var claw := _polygon(CLAW_TOOTH, CLAW)
			claw.position = Vector2(
				FOOT_OFFSET.x * side + (toe - 1) * CLAW_SPACING, FOOT_OFFSET.y)
			_root.add_child(claw)

	# Rim first, then the body over it: an offset copy of the silhouette
	# showing as a lit sliver down the moon side. Drawing order does the
	# masking, so there is no second shape to keep in sync with the first.
	var rim := _polygon(BODY, RIM)
	rim.position = RIM_OFFSET
	_root.add_child(rim)
	_root.add_child(_polygon(BODY, SKIN))
	_root.add_child(_polygon(BELLY, BELLY_COLOR))

	for side in [-1.0, 1.0]:
		var horn := _polygon(HORN, SKIN_DARK)
		horn.position = Vector2(HORN_OFFSET.x * side, HORN_OFFSET.y)
		horn.scale = Vector2(side, 1.0)
		_root.add_child(horn)

		var arm := _polygon(ARM, SKIN)
		arm.position = Vector2(ARM_OFFSET.x * side, ARM_OFFSET.y)
		arm.scale = Vector2(side, 1.0)
		_root.add_child(arm)

	_mouth = _polygon(MOUTH, MOUTH_COLOR)
	_mouth.position = MOUTH_OFFSET
	_root.add_child(_mouth)
	for i in TOOTH_COUNT:
		var tooth := _polygon(TOOTH_SHAPE, TOOTH)
		tooth.position = TOOTH_OFFSET + Vector2(i * TOOTH_SPACING, 0.0)
		_root.add_child(tooth)

	for side in [-1.0, 1.0]:
		var eye := _polygon(_ellipse(EYE_RADIUS, EYE_RADIUS * EYE_SQUASH, 22), EYE_WHITE)
		eye.position = Vector2(EYE_OFFSET.x * side, EYE_OFFSET.y)
		_root.add_child(eye)
		_eyes.append(eye)

		var pupil := _polygon(_ellipse(PUPIL_RADIUS, PUPIL_RADIUS, 16), PUPIL_COLOR)
		pupil.position = eye.position
		_root.add_child(pupil)
		_pupils.append(pupil)

		# The lid is a full-height shutter scaled from 0 to 1 on the blink,
		# the same trick the in-game Monster uses.
		var lid := _polygon([
			Vector2(-EYE_RADIUS - LID_MARGIN, 0.0),
			Vector2(EYE_RADIUS + LID_MARGIN, 0.0),
			Vector2(EYE_RADIUS + LID_MARGIN, EYE_RADIUS * LID_HEIGHT_FACTOR),
			Vector2(-EYE_RADIUS - LID_MARGIN, EYE_RADIUS * LID_HEIGHT_FACTOR)],
			SKIN_DARK)
		lid.position = eye.position - Vector2(0.0, EYE_RADIUS)
		lid.scale = Vector2(1.0, 0.0)
		_root.add_child(lid)
		_lids.append(lid)

		var brow := _polygon(BROW, SKIN_DARK)
		brow.position = Vector2(BROW_OFFSET.x * side, BROW_OFFSET.y)
		brow.scale = Vector2(side, 1.0)
		_root.add_child(brow)


## Takes a plain Array of Vector2 rather than a PackedVector2Array, because
## the shapes above are consts and `PackedVector2Array([...])` is a
## constructor call — not a constant expression, and not something a const can
## hold. The conversion happens here, once, at the point of use.
func _polygon(points: Array, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array(points)
	poly.color = color
	return poly


func _ellipse(rx: float, ry: float, segments: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle) * rx, sin(angle) * ry))
	return points


# --- animation ---------------------------------------------------------------

func _update_eyes(delta: float) -> void:
	_pupil_timer -= delta
	if _pupil_timer <= 0.0:
		_pupil_timer = _rng.randf_range(0.9, 2.6)
		_pupil_target = Vector2(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.7, 0.7)) * PUPIL_TRAVEL
	# Saccade fast, then hold still: eyes do not ease into place.
	_pupil_at = _pupil_at.lerp(_pupil_target, 1.0 - exp(-14.0 * delta))
	for i in _pupils.size():
		_pupils[i].position = _eyes[i].position + _pupil_at

	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = _rng.randf_range(BLINK_GAP.x, BLINK_GAP.y)
		_blink = BLINK_TIME * 2.0
	# Run the lid every frame rather than only while _blink is positive: the
	# frame that takes _blink to zero would otherwise leave the shutter parked
	# wherever it happened to be, and the Monster would spend the next four
	# seconds at half-mast.
	_blink = maxf(_blink - delta, 0.0)
	var closed := clampf(1.0 - absf(_blink / BLINK_TIME - 1.0), 0.0, 1.0)
	for lid in _lids:
		lid.scale.y = closed
	for eye in _eyes:
		eye.color = eye.color.lerp(EYE_WHITE, 1.0 - exp(-4.0 * delta))


## The grin opens on the inhale and on a startle, so the Monster is never
## holding one expression.
func _update_mouth() -> void:
	var open := 0.72 + 0.14 * sin(_age * 1.25) + _startle * 0.5
	_mouth.scale = Vector2(
		1.0 + _startle * STARTLE_MOUTH_WIDEN,
		clampf(open, 0.5, MOUTH_OPEN_MAX))
