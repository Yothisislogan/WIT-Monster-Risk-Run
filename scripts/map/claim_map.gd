class_name ClaimMap
extends RefCounted
## THE CLAIM MAP — the branching run structure (GAME_DESIGN.md §5, §12, §15).
##
## A run used to be three rooms and a boss, about two minutes, against §5's
## 20–35 minute target. It is now a portfolio you route through: three acts of
## six rows each, where each row offers a choice of sites and the route you
## pick *is* your risk selection. For an insurance game that is the most
## on-theme structure available — you are deciding your own exposure, and the
## Risk Meter is the premium you pay for it.
##
## The graph is generated from a seed and saved with the run, so resuming
## never re-rolls the map (§17) and a route is reproducible.
##
## Shape, per act:
##   row 0                    always a Peril Zone. A run opens on combat.
##   rows 1 .. CHOICE_ROWS-2  the actual choices, drawn from WEIGHTS
##   row CHOICE_ROWS-1        always Salvage. A breath before the boss.
##   row CHOICE_ROWS          the boss. One node, every route converges.
##
## tools/check_map.py generates thousands of maps and asserts the structural
## invariants — connectivity, no dead ends, no crossed edges, the adjacency
## rules below, and that the pacing arithmetic still lands in §5's window.

const ACTS := 3
## Rows offering a choice, per act. The boss row follows and is always single.
const CHOICE_ROWS := 5
const WIDTH := 4
## Distinct routes carved per act. Their union is the graph, so this is what
## actually controls how branchy the map feels.
const PATHS := 4

enum Kind { PERIL, HIGH_RISK, OFFICE, CLAIM_EVENT, MINI_BOSS, SALVAGE, BOSS }

## Draw weights for the rows that are a genuine choice. Peril dominates on
## purpose: the detours are worth taking because the default is fighting.
##
## SALVAGE is deliberately absent. Rests are the guaranteed one before each
## boss and nothing else — when it was drawable here it reached 21% of all
## nodes, a rest could lead straight into the forced rest, and routing through
## them dropped a run under §5's floor. Scarcity is what makes a rest matter.
const WEIGHTS := {
	Kind.PERIL: 40,
	Kind.HIGH_RISK: 18,
	Kind.OFFICE: 14,
	Kind.CLAIM_EVENT: 14,
	Kind.MINI_BOSS: 8,
}

## Kinds that may not follow themselves along an edge. Two shops in a row is
## a dead choice — you have already spent — and two rests in a row removes
## the tension rests exist to release.
const NO_REPEAT := [Kind.OFFICE, Kind.SALVAGE, Kind.MINI_BOSS]

## At most one of these per act, so a route can never be a mini-boss gauntlet.
const ONCE_PER_ACT := [Kind.MINI_BOSS]

const KIND_NAMES := {
	Kind.PERIL: "PERIL ZONE",
	Kind.HIGH_RISK: "HIGH-RISK ZONE",
	Kind.OFFICE: "ADJUSTER'S OFFICE",
	Kind.CLAIM_EVENT: "CLAIM EVENT",
	Kind.MINI_BOSS: "SENIOR ADJUSTER",
	Kind.SALVAGE: "SALVAGE YARD",
	Kind.BOSS: "CATASTROPHE",
}

## Short label for the map screen's touch targets. A 96px circle on a phone
## fits about six characters and nothing else.
const KIND_SHORT := {
	Kind.PERIL: "FIGHT",
	Kind.HIGH_RISK: "HIGH",
	Kind.OFFICE: "SHOP",
	Kind.CLAIM_EVENT: "EVENT",
	Kind.MINI_BOSS: "SENIOR",
	Kind.SALVAGE: "REST",
	Kind.BOSS: "BOSS",
}

## Colour is the fast read, the label is the confirmation. Never colour alone
## (§7 colourblind-safe): every node carries its text too.
const KIND_COLORS := {
	Kind.PERIL: Color(0.72, 0.78, 0.92),
	Kind.HIGH_RISK: Color(1.0, 0.55, 0.4),
	Kind.OFFICE: Color(0.55, 0.9, 0.65),
	Kind.CLAIM_EVENT: Color(0.95, 0.85, 0.45),
	Kind.MINI_BOSS: Color(0.85, 0.6, 1.0),
	Kind.SALVAGE: Color(0.5, 0.85, 0.95),
	Kind.BOSS: Color(1.0, 0.35, 0.3),
}

## One-line description shown under a node on the map screen.
const KIND_BLURBS := {
	Kind.PERIL: "Routine exposure. Survey and move on.",
	Kind.HIGH_RISK: "Elevated exposure. Elevated settlement.",
	Kind.OFFICE: "Spend Premiums. Bring the receipt.",
	Kind.CLAIM_EVENT: "A situation requiring a decision.",
	Kind.MINI_BOSS: "A senior colleague would like a word.",
	Kind.SALVAGE: "Patch up. Nobody is watching.",
	Kind.BOSS: "The claim, in person.",
}

## Nodes as plain dictionaries, so the whole map serialises straight into the
## JSON save with no custom encoding (§24).
var nodes: Array = []
var seed_value: int = 0
## Node ids the player may move to right now. Empty once the run is over.
var available: Array = []
var current_id: int = -1
var visited: Array = []

var _rng := RandomNumberGenerator.new()
var _by_cell: Dictionary = {}   # "act:row:col" -> node id


static func generate(map_seed: int) -> ClaimMap:
	var map := ClaimMap.new()
	map._build(map_seed)
	return map


func _build(map_seed: int) -> void:
	seed_value = map_seed
	_rng.seed = map_seed
	nodes.clear()
	_by_cell.clear()
	for act in ACTS:
		_carve_act(act)
	_assign_kinds()
	_assign_rooms()
	_link_acts()
	visited.clear()
	current_id = -1
	available = _row_ids(0, 0)


# --- Generation -------------------------------------------------------------

func _cell_key(act: int, row: int, col: int) -> String:
	return "%d:%d:%d" % [act, row, col]


func _ensure_node(act: int, row: int, col: int) -> int:
	var key := _cell_key(act, row, col)
	if _by_cell.has(key):
		return int(_by_cell[key])
	var id := nodes.size()
	nodes.append({
		"id": id, "act": act, "row": row, "col": col,
		"kind": int(Kind.PERIL), "next": [], "room": "", "modifier": "",
	})
	_by_cell[key] = id
	return id


func _link(from_id: int, to_id: int) -> void:
	var list: Array = nodes[from_id]["next"]
	if not to_id in list:
		list.append(to_id)


## Two edges cross when they swap left-to-right order between rows. Crossed
## edges are unreadable on a phone, so a step that would cross is re-picked.
func _crosses(act: int, row: int, from_col: int, to_col: int) -> bool:
	for node in nodes:
		if int(node["act"]) != act or int(node["row"]) != row:
			continue
		var other_from := int(node["col"])
		if other_from == from_col:
			continue
		for next_id in node["next"]:
			var other_to := int(nodes[next_id]["col"])
			if from_col < other_from and to_col > other_to:
				return true
			if from_col > other_from and to_col < other_to:
				return true
	return false


func _carve_act(act: int) -> void:
	var boss_id := _ensure_node(act, CHOICE_ROWS, 0)
	nodes[boss_id]["kind"] = int(Kind.BOSS)
	for path in PATHS:
		var col := _rng.randi_range(0, WIDTH - 1)
		for row in CHOICE_ROWS:
			var from_id := _ensure_node(act, row, col)
			if row == CHOICE_ROWS - 1:
				_link(from_id, boss_id)
				break
			var next_col := _pick_next_column(act, row, col)
			_link(from_id, _ensure_node(act, row + 1, next_col))
			col = next_col


func _pick_next_column(act: int, row: int, col: int) -> int:
	var options: Array = []
	for step in [-1, 0, 1]:
		var candidate := clampi(col + step, 0, WIDTH - 1)
		if not candidate in options and not _crosses(act, row, col, candidate):
			options.append(candidate)
	if options.is_empty():
		return col
	return int(options[_rng.randi_range(0, options.size() - 1)])


func _row_ids(act: int, row: int) -> Array:
	var ids: Array = []
	for node in nodes:
		if int(node["act"]) == act and int(node["row"]) == row:
			ids.append(int(node["id"]))
	ids.sort_custom(func(a: int, b: int) -> bool:
		return int(nodes[a]["col"]) < int(nodes[b]["col"]))
	return ids


# --- Kinds ------------------------------------------------------------------

func _assign_kinds() -> void:
	for act in ACTS:
		var used: Dictionary = {}
		for row in CHOICE_ROWS:
			for id in _row_ids(act, row):
				nodes[id]["kind"] = int(_pick_kind(act, row, id, used))
				var kind := int(nodes[id]["kind"])
				if kind in ONCE_PER_ACT:
					used[kind] = true


func _pick_kind(_act: int, row: int, id: int, used: Dictionary) -> int:
	if row == 0:
		return int(Kind.PERIL)
	if row == CHOICE_ROWS - 1:
		return int(Kind.SALVAGE)
	# Anything reaching this node constrains what it may be.
	var banned: Dictionary = {}
	for other in nodes:
		if id in other["next"]:
			var kind := int(other["kind"])
			if kind in NO_REPEAT:
				banned[kind] = true
	for kind in used.keys():
		banned[kind] = true

	var total := 0
	var pool: Array = []
	for kind in WEIGHTS.keys():
		if banned.has(kind):
			continue
		total += int(WEIGHTS[kind])
		pool.append(kind)
	if pool.is_empty():
		return int(Kind.PERIL)
	var roll := _rng.randi_range(0, total - 1)
	for kind in pool:
		roll -= int(WEIGHTS[kind])
		if roll < 0:
			return int(kind)
	return int(Kind.PERIL)


## Every combat node gets a room scene now, not when it is entered, so the map
## screen can name the zone you are routing toward — the choice is only real
## if you can see what you are choosing.
func _assign_rooms() -> void:
	for act in ACTS:
		# Shuffle per act and deal without replacement, so a single act never
		# repeats a room until the pool is exhausted.
		var bag: Array = LevelData.COMBAT_ROOMS.duplicate()
		_shuffle(bag)
		var next := 0
		for row in CHOICE_ROWS + 1:
			for id in _row_ids(act, row):
				var kind := int(nodes[id]["kind"])
				if kind == int(Kind.BOSS):
					nodes[id]["room"] = LevelData.boss_room_for(act)
				elif is_combat(kind):
					if next >= bag.size():
						_shuffle(bag)
						next = 0
					nodes[id]["room"] = String(bag[next])
					next += 1


## Fisher-Yates against the map's own generator, because Array.shuffle() uses
## the global RNG and would make the map depend on everything else that has
## rolled a number this session — the seed has to be the whole story (§17).
func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap: Variant = list[i]
		list[i] = list[j]
		list[j] = swap


## Each act's boss opens the next act's first row.
func _link_acts() -> void:
	for act in range(ACTS - 1):
		var boss_id := int(_by_cell[_cell_key(act, CHOICE_ROWS, 0)])
		for id in _row_ids(act + 1, 0):
			_link(boss_id, id)


# --- Traversal --------------------------------------------------------------

func node(id: int) -> Dictionary:
	return nodes[id] if id >= 0 and id < nodes.size() else {}


func can_enter(id: int) -> bool:
	return id in available


## Commit to a node. Returns false if it was not a legal move, so a stale tap
## on the map screen can never desync the run.
func enter(id: int) -> bool:
	if not can_enter(id):
		return false
	current_id = id
	if not id in visited:
		visited.append(id)
	available = []
	return true


## Called once the node's content is finished, opening the next row.
func complete_current() -> void:
	if current_id < 0:
		available = []
		return
	available = (nodes[current_id]["next"] as Array).duplicate()


func is_run_complete() -> bool:
	return current_id >= 0 and available.is_empty() \
			and int(nodes[current_id]["kind"]) == int(Kind.BOSS) \
			and int(nodes[current_id]["act"]) == ACTS - 1


func current_act() -> int:
	return int(nodes[current_id]["act"]) if current_id >= 0 else 0


func kind_of(id: int) -> int:
	return int(nodes[id]["kind"]) if id >= 0 and id < nodes.size() else int(Kind.PERIL)


static func kind_name(kind: int) -> String:
	return String(KIND_NAMES.get(kind, "RISK SITE"))


static func kind_blurb(kind: int) -> String:
	return String(KIND_BLURBS.get(kind, ""))


static func kind_short(kind: int) -> String:
	return String(KIND_SHORT.get(kind, "SITE"))


static func kind_color(kind: int) -> Color:
	return KIND_COLORS.get(kind, Color(0.8, 0.8, 0.8))


static func is_combat(kind: int) -> bool:
	return kind in [Kind.PERIL, Kind.HIGH_RISK, Kind.MINI_BOSS, Kind.BOSS]


# --- Persistence ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"seed": seed_value,
		"nodes": nodes,
		"available": available,
		"current_id": current_id,
		"visited": visited,
	}


## Rebuilds from the seed rather than trusting the stored graph, then restores
## only the traversal state. A save written by an older build with a different
## generator still loads: it produces that build's map shape for this build's
## rules, and the position is clamped to something legal.
static func from_dict(data: Dictionary) -> ClaimMap:
	var map := ClaimMap.generate(int(data.get("seed", 0)))
	var current := int(data.get("current_id", -1))
	if current < 0 or current >= map.nodes.size():
		return map
	map.current_id = current
	map.visited = (data.get("visited", []) as Array).filter(
			func(id: Variant) -> bool: return int(id) >= 0 and int(id) < map.nodes.size())
	map.available = (data.get("available", []) as Array).filter(
			func(id: Variant) -> bool: return int(id) >= 0 and int(id) < map.nodes.size())
	return map
