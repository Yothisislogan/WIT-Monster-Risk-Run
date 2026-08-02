extends Control
## The wordmark. Three rows of type, each drawn three times — a hard drop
## shadow, a magenta ghost offset the other way, and the letters themselves —
## which is how you get depth out of a font with no art behind it.
##
## The rows fly in on a stagger and then never quite settle: each floats on its
## own slow sine, and all three catch the backdrop's lightning. Nothing here is
## interactive; the Control is mouse-transparent and the menu below it owns
## every touch.
##
## Layout is absolute inside the Stage (the 1280x720 box the whole title screen
## is composed in), and it is the only copy of these numbers —
## tools/check_title.py reads the box from here to prove the wordmark clears
## the menu column and the Monster, and measures the strings to prove they fit
## the width at these sizes.

const ORIGIN := Vector2(64.0, 46.0)
const WIDTH := 690.0

## text, font size, row top (relative to ORIGIN), row height, colour.
const ROWS := [
	{"text": "WIT MONSTER", "size": 86, "y": 0.0, "height": 118.0,
	 "color": Color(0.42, 0.80, 1.0, 1.0)},
	{"text": "RISK RUN", "size": 54, "y": 116.0, "height": 76.0,
	 "color": Color(1.0, 0.78, 0.30, 1.0)},
	{"text": "FULLY UNINSURED.  HIGHLY FLAMMABLE.", "size": 24, "y": 200.0,
	 "height": 38.0, "color": Color(0.78, 0.84, 0.96, 1.0)},
]
const BOX_HEIGHT := 238.0

const SHADOW_OFFSET := Vector2(6.0, 8.0)
const SHADOW_COLOR := Color(0.02, 0.02, 0.05, 0.6)
const GHOST_OFFSET := Vector2(-5.0, -3.0)
const GHOST_COLOR := Color(1.0, 0.25, 0.55, 0.5)

## Per-row idle float: amplitude in px, then radians/sec, then phase.
const FLOAT := [
	{"amount": 5.0, "rate": 1.1, "phase": 0.0},
	{"amount": 3.5, "rate": 1.45, "phase": 1.7},
	{"amount": 2.0, "rate": 0.9, "phase": 3.1},
]

var _time: float = 0.0
var _rows: Array[Control] = []
var _flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_play_entrance()


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta * 3.0, 0.0)
	for i in _rows.size():
		var spec: Dictionary = FLOAT[i]
		var row := _rows[i]
		row.position.y = float(ROWS[i]["y"]) + float(spec["amount"]) * sin(
			_time * float(spec["rate"]) + float(spec["phase"]))
		# The lightning catches the type as well as the city.
		var lit := 1.0 + _flash * 0.9
		row.modulate = Color(lit, lit, lit, row.modulate.a)


func _build() -> void:
	position = ORIGIN
	for i in ROWS.size():
		var spec: Dictionary = ROWS[i]
		var row := Control.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.position = Vector2(0.0, float(spec["y"]))
		row.size = Vector2(WIDTH, float(spec["height"]))
		add_child(row)
		_rows.append(row)

		# The inner node is what the entrance tween moves, so the idle float on
		# the outer node never fights it for the same property.
		var slide := Control.new()
		slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slide.size = row.size
		row.add_child(slide)

		slide.add_child(_layer(spec, SHADOW_OFFSET, SHADOW_COLOR))
		slide.add_child(_layer(spec, GHOST_OFFSET, GHOST_COLOR))
		slide.add_child(_layer(spec, Vector2.ZERO, spec["color"]))


func _layer(spec: Dictionary, offset: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.text = String(spec["text"])
	label.position = offset
	label.size = Vector2(WIDTH, float(spec["height"]))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(spec["size"]))
	label.add_theme_color_override("font_color", color)
	return label


## Wordmark drops, subtitle slides in from the left, tagline fades up. Staggered
## so it reads as one move rather than three things arriving at once.
func _play_entrance() -> void:
	var tween := create_tween()
	tween.set_parallel(true)

	var wordmark := _rows[0].get_child(0) as Control
	tween.tween_property(wordmark, "position", Vector2.ZERO, 0.62) \
		.from(Vector2(0.0, -260.0)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var submark := _rows[1].get_child(0) as Control
	tween.tween_property(submark, "position", Vector2.ZERO, 0.55) \
		.from(Vector2(-620.0, 0.0)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.16)

	for i in _rows.size():
		tween.tween_property(_rows[i], "modulate:a", 1.0, 0.45) \
			.from(0.0).set_delay(0.1 * i + (0.35 if i == 2 else 0.0))


## Wired by title_screen.gd to the backdrop's lightning.
func on_lightning(strength: float) -> void:
	_flash = maxf(_flash, strength)
