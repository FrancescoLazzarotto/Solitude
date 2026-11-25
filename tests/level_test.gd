extends SceneTree
## Il validatore Rust (CartoLevel) contro la fisica vera: se il modello non rispecchia il mondo di gioco,
## le sue garanzie ("il cuore non si raggiunge senza lanterna") non valgono niente.

const LEVEL_PATH := "res://levels/slice.json"
## Origine della griglia del modello: floor(min / CELL) * CELL con CELL = 0.25 (min x = -10.5, min z = -20.5).
const GRID_X0 := -10.5
const GRID_Z0 := -20.5
const CELL := 0.25
const SAMPLES := 700

var fails := 0
var main: Node
var p: CharacterBody3D


func check(name: String, cond: bool, extra := "") -> void:
	if not cond:
		fails += 1
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + extra if extra != "" else ""))


func phys(n: int) -> void:
	for i in range(n):
		await physics_frame


func _initialize() -> void:
	var json := FileAccess.get_file_as_string(LEVEL_PATH)
	var v: RefCounted = ClassDB.instantiate("CartoLevel")

	print("=== VALIDATORE (attraverso Godot) ===")
	check("il livello e' valido", v.validate(json) == "", v.validate(json))
	check("un JSON rotto viene rifiutato con un messaggio", str(v.validate("{ non json")).begins_with("JSON del livello non valido"))
	var bad: Dictionary = v.analyze("{}")
	check("analyze di un livello rotto ritorna ok=false", bad["ok"] == false and str(bad["error"]) != "")
	var report: Dictionary = v.analyze(json)
	check("analyze: ok", report["ok"] == true)
	var stages: Array = report["stages"]
	check("tre fasi di progressione: niente, lanterna, lanterna+leva", stages.size() == 3, str(stages.size()))
	check("fase 0 senza chiavi", stages[0]["keys"].size() == 0)
	check("fase 1 = lanterna", Array(stages[1]["keys"]) == ["lantern"])
	check("il cuore e la leva si sbloccano solo con la lanterna", not "chest:heart" in stages[0]["items"] and "chest:heart" in stages[1]["items"] and not "lever" in stages[0]["items"] and "lever" in stages[1]["items"])
	check("a fine progressione tutto e' raggiungibile", "chest:heart" in stages[2]["items"] and "shrine" in stages[2]["items"] and "lever" in stages[2]["items"])

	print("=== MODELLO vs FISICA ===")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await phys(5)
	p = main.player
	for e in main.enemies:
		e.set_physics_process(false)
	var level: Dictionary = JSON.parse_string(json)
	var avoid: Array[Vector3] = [main._shrine_pos, LevelDataProbe.v3(level["props"]["stone"]["pos"]), main.chest1_it.global_position, main.chest2_it.global_position, main.lever_it.global_position]
	for e in main.enemies:
		avoid.append(e.global_position)
	avoid.append(p.global_position)

	await _compare("stato iniziale (nessuna chiave)", v, json, PackedStringArray(), avoid)

	main.chest1_it.interact()
	main.lever_it.interact()
	await phys(10)
	await _compare("dopo lanterna e leva (ponte presente, cancello aperto)", v, json, PackedStringArray(["lantern", "lever"]), avoid)

	print("=== RIEPILOGO ===")
	print("FALLITI: ", fails)
	quit(fails)


func _compare(label: String, v: RefCounted, json: String, keys: PackedStringArray, avoid: Array[Vector3]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var points := PackedVector2Array()
	while points.size() < SAMPLES:
		var ix := rng.randi_range(0, int(21.0 / CELL))
		var iz := rng.randi_range(0, int(31.0 / CELL))
		var pt := Vector2(GRID_X0 + (ix + 0.5) * CELL, GRID_Z0 + (iz + 0.5) * CELL)
		var near := false
		for a in avoid:
			if Vector2(a.x, a.z).distance_to(pt) < 1.8:
				near = true
				break
		if not near:
			points.append(pt)
	var model: PackedFloat32Array = v.heights(json, keys, points)
	var space := root.get_world_3d().direct_space_state
	var mismatches := 0
	var both_solid := 0
	var both_void := 0
	var shown := 0
	for i in range(points.size()):
		var pt := points[i]
		var q := PhysicsRayQueryParameters3D.create(Vector3(pt.x, 12.0, pt.y), Vector3(pt.x, -12.0, pt.y))
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		var phys_top := NAN if hit.is_empty() else float((hit["position"] as Vector3).y)
		var m := model[i]
		var ok := false
		if is_nan(m) and (is_nan(phys_top) or phys_top < -3.0):
			ok = true
			both_void += 1
		elif not is_nan(m) and not is_nan(phys_top) and absf(m - phys_top) < 0.03:
			ok = true
			both_solid += 1
		if not ok:
			mismatches += 1
			if shown < 6:
				print("   non coincide in (%.3f, %.3f): modello=%s fisica=%s" % [pt.x, pt.y, str(m), str(phys_top)])
				shown += 1
	check("%s: modello e fisica coincidono su %d punti" % [label, points.size()], mismatches == 0,
		"%d solidi, %d vuoti, %d differenze" % [both_solid, both_void, mismatches])
	check("%s: il campione contiene sia superfici sia vuoti" % label, both_solid > 100 and both_void > 5)


class LevelDataProbe:
	static func v3(a: Array) -> Vector3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
