extends SceneTree
## Misura i PRIMI secondi di gioco (quelli che il giocatore vede davvero all'avvio):
## il rendering audio in background, la compilazione degli shader, ecc.
## Uso: godot --path . --resolution 1280x720 --script tests/startup_bench.gd -- --carto-test [--carto-no-audio]

const MEASURE_SECONDS := 4.0

var frame_ms: Array[float] = []


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _run() -> void:
	var start := Time.get_ticks_usec()
	var last := start
	while (Time.get_ticks_usec() - start) < int(MEASURE_SECONDS * 1_000_000):
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for v in frame_ms:
		total += v
	var over50 := 0
	var over100 := 0
	for v in frame_ms:
		if v > 50.0:
			over50 += 1
		if v > 100.0:
			over100 += 1
	var p99: float = sorted[clampi(int(ceil(0.99 * sorted.size())) - 1, 0, sorted.size() - 1)]
	print("STARTUP frames=%d  avg_fps=%.1f  p99_ms=%.1f  worst_ms=%.1f  frames>50ms=%d  frames>100ms=%d" % [
		frame_ms.size(), 1000.0 * frame_ms.size() / total, p99, sorted.back(), over50, over100])
	var audio := root.get_node("Audio")
	if audio.available:
		print("STARTUP audio: rendering in background %d ms, accoglienza sul thread principale %.1f ms (di cui take_render %.1f ms)" % [audio.load_ms, audio.arrival_ms, audio.arrival_take_ms])
	else:
		print("STARTUP audio: non ancora pronto dopo %.0f s (o disattivato)" % MEASURE_SECONDS)
	quit()
