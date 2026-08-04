extends CanvasLayer
## The Claim Map screen (GAME_DESIGN.md §5, §15, §23): where the run's real
## decision happens.
##
## Landscape phone, so the route runs left to right and the branches stack
## vertically — the direction of travel matches the direction the game scrolls.
## One act at a time: three acts on one screen would make every touch target
## too small to hit, and you cannot route past the boss in front of you anyway.
##
## Everything here is built in code. A hand-authored scene for a graph whose
## shape is decided at runtime would be a scene full of nodes that get deleted
## on the first frame.

const NODE_SIZE := Vector2(104.0, 104.0)
## The graph used to sit in a band across the middle of the frame, leaving a
## fifth of the screen empty under it and crowding the columns together. These
## spread it over the space that was already there.
const ROW_SPACING := 200.0
const COL_SPACING := 150.0
const ORIGIN := Vector2(120.0, 150.0)

## How a node reads when it is not the one you can take next. Dimming used to
## be done with modulate, which multiplies the WHOLE node — including the text
## and the dark outline the theme puts behind it — so an unreachable node at
## 30% alpha was a label you genuinely could not read on a dark background.
## The map is a screen for making a decision on; every option has to be legible
## whether or not it is currently takeable (§23).
const SPENT_MIX := 0.5     ## toward SLATE for a site already visited
const UNTAKEN_MIX := 0.34  ## toward SLATE for a route not currently open
const SLATE := Color(0.62, 0.67, 0.78, 1.0)

@onready var root: Control = %Root
@onready var graph: Control = %Graph
@onready var title: Label = %MapTitle
@onready var subtitle: Label = %MapSubtitle
@onready var legend: Label = %MapLegend

var _buttons: Dictionary = {}      # node id -> Button
var _positions: Dictionary = {}    # node id -> Vector2, centre, local to graph
var _act: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	graph.draw.connect(_draw_edges)
	Events.map_opened.connect(_on_map_opened)
	Events.run_ended.connect(func(_report: Dictionary) -> void: _close())


func _on_map_opened(available: Array) -> void:
	if GameManager.map == null or available.is_empty():
		return
	_act = int(GameManager.map.node(int(available[0])).get("act", 0))
	_rebuild(available)
	visible = true
	get_tree().paused = true
	Sfx.play("ui_move")
	# A controller has to land somewhere or the map is unusable without touch.
	for id in available:
		if _buttons.has(id):
			(_buttons[id] as Button).call_deferred("grab_focus")
			break


func _close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false


func _on_node_pressed(id: int) -> void:
	if not GameManager.map.can_enter(id):
		return
	Sfx.play("ui_confirm")
	_close()
	Events.node_chosen.emit(id)


# --- Building ---------------------------------------------------------------

func _rebuild(available: Array) -> void:
	for child in graph.get_children():
		graph.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_positions.clear()

	var map := GameManager.map
	title.text = "CLAIM MAP  ·  ACT %d OF %d" % [_act + 1, ClaimMap.ACTS]
	var progress := GameManager.route_progress()
	subtitle.text = "Site %d of %d surveyed.  Choose your exposure." % [progress.x, progress.y]
	legend.text = "Premiums: %d          Coverage: %d / %d          Risk: %s" % [
		GameManager.currency, GameManager.coverage, GameManager.max_coverage,
		ClaimReport.risk_label(GameManager.risk)]

	for node in map.nodes:
		if int(node["act"]) != _act:
			continue
		var id := int(node["id"])
		_positions[id] = ORIGIN + Vector2(
			float(node["row"]) * ROW_SPACING, float(node["col"]) * COL_SPACING)
		graph.add_child(_build_node_button(node, id in available, id in map.visited))
	graph.queue_redraw()


func _build_node_button(node: Dictionary, reachable: bool, visited: bool) -> Button:
	var id := int(node["id"])
	var kind := int(node["kind"])
	var button := Button.new()
	button.custom_minimum_size = NODE_SIZE
	button.size = NODE_SIZE
	button.position = _positions[id] - NODE_SIZE * 0.5
	button.text = ClaimMap.kind_short(kind)
	button.add_theme_font_size_override("font_size", 22)
	button.tooltip_text = "%s — %s" % [ClaimMap.kind_name(kind), ClaimMap.kind_blurb(kind)]
	button.disabled = not reachable
	# Reachable is bright, visited is spent, the rest is the road not taken —
	# but all three are readable. The state is carried by the font colour, not
	# by modulate, and every variant stays fully opaque.
	var tint := ClaimMap.kind_color(kind)
	var shade := tint
	if visited and not reachable:
		shade = tint.lerp(SLATE, SPENT_MIX)
	elif not reachable:
		shade = tint.lerp(SLATE, UNTAKEN_MIX)
	button.add_theme_color_override("font_color", shade)
	button.add_theme_color_override("font_disabled_color", shade)
	button.focus_mode = Control.FOCUS_ALL if reachable else Control.FOCUS_NONE
	button.pressed.connect(_on_node_pressed.bind(id))
	_buttons[id] = button
	return button


func _draw_edges() -> void:
	var map := GameManager.map
	if map == null:
		return
	for node in map.nodes:
		var id := int(node["id"])
		if not _positions.has(id):
			continue
		for next_id in node["next"]:
			if not _positions.has(next_id):
				continue      # an edge into the next act; it has its own screen
			var reachable: bool = int(next_id) in map.available
			var walked: bool = id in map.visited and int(next_id) in map.visited
			# These were 0.14 / 0.5 / 0.6 and the graph read as a blank screen
			# with a couple of lit nodes floating in it. The edges ARE the map.
			var color := Color(0.72, 0.76, 0.86, 0.42)
			if walked:
				color = Color(1.0, 0.85, 0.4, 0.75)
			elif reachable:
				color = Color(1, 1, 1, 0.9)
			graph.draw_line(_positions[id], _positions[next_id], color,
					4.0 if reachable or walked else 2.0, true)
