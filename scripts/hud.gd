extends CanvasLayer
## Interfaccia di gioco: cuori, stamina, suggerimenti, messaggi e dissolvenza.

const HEART_SIZE := 22.0
const STAMINA_PER_POINT := 2.2   ## pixel per punto di stamina massima

var _hearts: HBoxContainer
var _stamina_bg: ColorRect
var _stamina_fill: ColorRect
var _prompt: Label
var _toast: Label
var _fade: ColorRect
var _toast_tween: Tween
var _max_hearts := 0
var _flasks: HBoxContainer
var _max_flasks := 0


func _ready() -> void:
	layer = 5

	_hearts = HBoxContainer.new()
	_hearts.position = Vector2(16.0, 14.0)
	_hearts.add_theme_constant_override("separation", 6)
	add_child(_hearts)

	_stamina_bg = ColorRect.new()
	_stamina_bg.color = Color(0, 0, 0, 0.55)
	_stamina_bg.position = Vector2(16.0, 44.0)
	_stamina_bg.size = Vector2(220.0, 12.0)
	add_child(_stamina_bg)
	_stamina_fill = ColorRect.new()
	_stamina_fill.color = Color(0.35, 0.85, 0.45)
	_stamina_fill.position = Vector2(2.0, 2.0)
	_stamina_fill.size = Vector2(216.0, 8.0)
	_stamina_bg.add_child(_stamina_fill)

	_flasks = HBoxContainer.new()
	_flasks.position = Vector2(16.0, 64.0)
	_flasks.add_theme_constant_override("separation", 5)
	add_child(_flasks)

	var help := Label.new()
	help.text = "WASD muovi  ·  J / click attacca  ·  Spazio rotola  ·  Q cura  ·  E interagisci  ·  Tab taccuino"
	help.position = Vector2(16.0, 692.0)
	help.modulate = Color(1, 1, 1, 0.45)
	help.add_theme_font_size_override("font_size", 14)
	add_child(help)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -120.0
	_prompt.offset_bottom = -80.0
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 6)
	add_child(_prompt)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_left = 240.0
	_toast.offset_right = -240.0
	_toast.offset_top = 60.0
	_toast.offset_bottom = 160.0
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.modulate.a = 0.0
	add_child(_toast)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func set_hp(current: int, maximum: int) -> void:
	if maximum != _max_hearts:
		_max_hearts = maximum
		for c in _hearts.get_children():
			c.queue_free()
		for i in range(maximum):
			var r := ColorRect.new()
			r.custom_minimum_size = Vector2(HEART_SIZE, HEART_SIZE)
			_hearts.add_child(r)
	for i in range(_hearts.get_child_count()):
		var heart := _hearts.get_child(i) as ColorRect
		if heart != null:
			heart.color = Color(0.9, 0.25, 0.3) if i < current else Color(0.25, 0.1, 0.12, 0.8)


func set_flasks(current: int, maximum: int) -> void:
	if maximum != _max_flasks:
		_max_flasks = maximum
		for c in _flasks.get_children():
			c.queue_free()
		for i in range(maximum):
			var r := ColorRect.new()
			r.custom_minimum_size = Vector2(12, 16)
			_flasks.add_child(r)
	for i in range(_flasks.get_child_count()):
		var f := _flasks.get_child(i) as ColorRect
		if f != null:
			f.color = Color(0.35, 0.9, 0.75) if i < current else Color(0.1, 0.25, 0.22, 0.8)


func set_stamina(current: float, maximum: float) -> void:
	var width := maximum * STAMINA_PER_POINT
	_stamina_bg.size.x = width
	_stamina_fill.size.x = (width - 4.0) * clampf(current / maximum, 0.0, 1.0)
	_stamina_fill.color = Color(0.35, 0.85, 0.45) if current > 18.0 else Color(0.9, 0.7, 0.3)


func set_prompt(text: String) -> void:
	_prompt.text = text


func toast(text: String, duration := 4.0) -> void:
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


## Parte dal nero e si schiarisce: copre il primo caricamento (shader, rendering audio in background).
func fade_in_from_black(hold: float, duration: float) -> void:
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(_fade, "color:a", 0.0, duration)


func fade(to_alpha: float, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", to_alpha, time)
	await tw.finished
