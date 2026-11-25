extends SceneTree
## Benchmark in finestra (vsync OFF) su un percorso scriptato: cortile -> rampa -> combattimento.
## Uso: godot --path <progetto> --resolution 1280x720 --script tests/bench.gd -- --carto-test
## Stampa FPS medi, 1% low, draw call, primitive e tempi di processo/fisica.

const WARMUP_FRAMES := 90

var main: Node
var p: CharacterBody3D
var frame_ms: Array[float] = []
var draw_calls: Array[float] = []
var prims: Array[float] = []
var t_process: Array[float] = []
var t_physics: Array[float] = []
var _last_us := 0
var _frame := 0
var _recording := false


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _tick() -> void:
	await process_frame
	var now := Time.get_ticks_usec()
	if _recording and _last_us > 0:
		frame_ms.append((now - _last_us) / 1000.0)
		if _frame % 5 == 0:
			draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			t_process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			t_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_last_us = now
	_frame += 1


func _hold(actions: Array, frames: int) -> void:
	for a: String in actions:
		Input.action_press(a)
	for i in range(frames):
		await _tick()
	for a: String in actions:
		Input.action_release(a)


func _run() -> void:
	# Riscaldamento (compilazione shader, cache). Il Main è pronto dopo il primo frame.
	await _tick()
	p = main.player
	p.max_hp = 9999
	p.hp = 9999
	for i in range(WARMUP_FRAMES):
		await _tick()
	_recording = true
	# 1) cortile: giro in tondo
	await _hold(["move_left"], 60)
	await _hold(["move_down"], 60)
	await _hold(["move_right"], 60)
	# 2) rampa e altopiano, nemici attivi
	p.teleport_to(Vector3(0, 0.05, -1))
	await _hold(["move_up", "move_right"], 115)
	# 3) combattimento: attacchi e rotoli ripetuti vicino ai guardiani
	for i in range(6):
		await _hold(["attack"], 2)
		await _hold(["move_left"], 25)
		await _hold(["roll", "move_right"], 3)
		await _hold(["move_right"], 25)
	# 4) torna al santuario
	p.teleport_to(Vector3(0, 0.05, 7.5))
	await _hold(["move_down"], 40)
	_recording = false
	_report()
	quit()


func _percentile(sorted: Array[float], q: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx := clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[idx]


func _avg(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


func _report() -> void:
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var avg_ms := _avg(frame_ms)
	var p99_ms := _percentile(sorted, 0.99)
	var maxv := 0.0
	for v in draw_calls:
		maxv = maxf(maxv, v)
	var gpu := RenderingServer.get_video_adapter_name()
	print("BENCH adapter=%s" % gpu)
	print("BENCH frames=%d  avg_fps=%.1f  avg_ms=%.2f  p99_ms=%.2f  low1pct_fps=%.1f  worst_ms=%.2f" % [
		frame_ms.size(), 1000.0 / avg_ms, avg_ms, p99_ms, 1000.0 / p99_ms, sorted.back()])
	print("BENCH draw_calls avg=%.0f max=%.0f  primitives avg=%.0f" % [_avg(draw_calls), maxv, _avg(prims)])
	print("BENCH process_ms avg=%.2f  physics_ms avg=%.2f" % [_avg(t_process), _avg(t_physics)])
	print("BENCH static_mem_MB=%.0f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
