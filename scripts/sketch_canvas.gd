extends Control
## Area di disegno a mano libera del taccuino.

const PAPER_COLOR := Color(0.10, 0.12, 0.15)
const LINE_COLOR := Color(0.75, 0.92, 1.0)
const LINE_WIDTH := 3.0

## Lista di tratti; ogni tratto è un Array di Vector2.
var strokes: Array = []
var _current: Array = []
var _drawing := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(300, 300)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drawing = true
			_current = [event.position]
			strokes.append(_current)
		else:
			_drawing = false
		queue_redraw()
	elif event is InputEventMouseMotion and _drawing:
		_current.append(event.position)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER_COLOR)
	for stroke: Array in strokes:
		if stroke.size() == 1:
			draw_circle(stroke[0], LINE_WIDTH * 0.5, LINE_COLOR)
		elif stroke.size() > 1:
			draw_polyline(PackedVector2Array(stroke), LINE_COLOR, LINE_WIDTH, true)


func clear_drawing() -> void:
	strokes.clear()
	_current = []
	_drawing = false
	queue_redraw()


func to_data() -> Array:
	var out: Array = []
	for stroke: Array in strokes:
		var pts: Array = []
		for p: Vector2 in stroke:
			pts.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
		out.append(pts)
	return out


func from_data(data: Array) -> void:
	strokes.clear()
	for pts: Variant in data:
		if pts is Array:
			var stroke: Array = []
			for p: Variant in pts:
				if p is Array and p.size() == 2:
					stroke.append(Vector2(float(p[0]), float(p[1])))
			if not stroke.is_empty():
				strokes.append(stroke)
	_current = []
	queue_redraw()
