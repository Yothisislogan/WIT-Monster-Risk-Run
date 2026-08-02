extends ParallaxBackground
## Procedural parallax backdrop. Three silhouette layers built from polygons
## and tinted per Risk Zone, so every room reads as a different place without
## shipping a single image (GAME_DESIGN.md §20 bright environments,
## clear visual hierarchy).

const LAYER_SPECS := [
	{"scale": 0.15, "y": 250.0, "height": 300.0, "width": 150.0, "gap": 60.0, "shade": 0.35},
	{"scale": 0.35, "y": 330.0, "height": 250.0, "width": 110.0, "gap": 45.0, "shade": 0.55},
	{"scale": 0.6, "y": 420.0, "height": 200.0, "width": 80.0, "gap": 34.0, "shade": 0.8},
]

var _layers: Array[ParallaxLayer] = []


func _ready() -> void:
	Events.room_started.connect(_on_room_started)
	for spec in LAYER_SPECS:
		_layers.append(_build_layer(spec))
	_apply_palette(LevelData.FALLBACK)


func _build_layer(spec: Dictionary) -> ParallaxLayer:
	var layer := ParallaxLayer.new()
	var scale_factor := float(spec["scale"])
	layer.motion_scale = Vector2(scale_factor, scale_factor * 0.4)
	var width := float(spec["width"])
	var gap := float(spec["gap"])
	var step := width + gap
	layer.motion_mirroring = Vector2(step * 12.0, 0.0)
	add_child(layer)

	# A skyline of boxes with varied heights — cheap, and reads instantly.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(scale_factor * 10000.0)
	for i in 12:
		var block := Polygon2D.new()
		var height := float(spec["height"]) * rng.randf_range(0.55, 1.0)
		var x := i * step
		var top := float(spec["y"]) - height
		block.polygon = PackedVector2Array([
			Vector2(x, top), Vector2(x + width, top),
			Vector2(x + width, 720.0), Vector2(x, 720.0)])
		layer.add_child(block)
	return layer


func _on_room_started(path: String) -> void:
	_apply_palette(LevelData.entry(path))


func _apply_palette(entry: Dictionary) -> void:
	var base: Color = entry.get("backdrop", Color(0.16, 0.22, 0.4))
	for i in _layers.size():
		var shade := float(LAYER_SPECS[i]["shade"])
		var tint := base.darkened(1.0 - shade)
		for block in _layers[i].get_children():
			if block is Polygon2D:
				block.color = tint
