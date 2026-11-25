extends CanvasLayer
## Il taccuino del robot: note di testo + schizzi a mano libera. Si salva da solo.

signal opened
signal closed

const Paths := preload("res://scripts/paths.gd")
const SketchCanvas := preload("res://scripts/sketch_canvas.gd")

var _notes: TextEdit
var _sketch: Control


func _ready() -> void:
	# Resta attivo anche con il gioco in pausa (mentre è aperto, il mondo si ferma).
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_ui()
	_load()
	visible = false


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	root.add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.14, 0.12)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Taccuino"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var clear_btn := Button.new()
	clear_btn.text = "Cancella disegno"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(func() -> void: _sketch.clear_drawing())
	header.add_child(clear_btn)
	var close_btn := Button.new()
	close_btn.text = "Chiudi (Tab)"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	vbox.add_child(split)

	_notes = TextEdit.new()
	_notes.placeholder_text = "Note…"
	_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_notes.custom_minimum_size = Vector2(280, 0)
	_notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes.size_flags_stretch_ratio = 0.8
	split.add_child(_notes)

	_sketch = SketchCanvas.new()
	_sketch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sketch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_sketch)


func _input(event: InputEvent) -> void:
	if event.is_action("toggle_notebook"):
		# Intercetta ogni evento di Tab (anche ripetizioni e rilascio), altrimenti
		# tenendolo premuto il TextEdit scrive tabulazioni nelle note.
		if event.is_action_pressed("toggle_notebook") and not event.is_echo():
			if visible:
				close()
			else:
				open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	Audio.play(&"page_open", null, -6.0)
	get_tree().paused = true
	_notes.grab_focus()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.play(&"page_close", null, -6.0)
	get_tree().paused = false
	_notes.release_focus()
	_save()
	closed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


func _save() -> void:
	var data := {"notes": _notes.text, "strokes": _sketch.to_data()}
	var f := FileAccess.open(Paths.user_file("notebook.json"), FileAccess.WRITE)
	if f == null:
		push_warning("Impossibile salvare il taccuino: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data))


func _load() -> void:
	var path := Paths.user_file("notebook.json")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_notes.text = str(parsed.get("notes", ""))
		var strokes: Variant = parsed.get("strokes", [])
		if strokes is Array:
			_sketch.from_data(strokes)
