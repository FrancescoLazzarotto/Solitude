extends SceneTree

var main: Node
var p: CharacterBody3D
var fails := 0


func check(name: String, cond: bool, extra := "") -> void:
	if not cond:
		fails += 1
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + extra if extra != "" else ""))


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [p.get_rid()]
	return root.get_world_3d().direct_space_state.intersect_ray(q)


func ground_y(x: float, z: float) -> float:
	var r := ray(Vector3(x, 10, z), Vector3(x, -10, z))
	return r["position"].y if not r.is_empty() else -999.0


func phys(n: int) -> void:
	for i in range(n):
		await physics_frame


func hold(actions: Array, frames: int) -> void:
	for a: String in actions:
		Input.action_press(a)
	await phys(frames)
	for a: String in actions:
		Input.action_release(a)


func put(pos: Vector3) -> void:
	p.teleport_to(pos)
	p.hp = p.max_hp
	p.stamina = p.max_stamina
	p.state = p.State.MOVE
	p._invuln_time = 0.0
	p._state_time = 0.0
	p.facing = Vector3(1, 0, 0)


func freeze_enemies(on: bool) -> void:
	for e in main.enemies:
		e.set_physics_process(not on)


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await phys(5)
	p = main.player
	freeze_enemies(true)

	print("=== GEOMETRIA ===")
	check("terreno cortile y=0", absf(ground_y(5, 4)) < 0.05, str(ground_y(5, 4)))
	check("rampa inizio z=-5 y~0.5", absf(ground_y(0, -5) - 0.5) < 0.1, str(ground_y(0, -5)))
	check("rampa meta z=-6 y~1.0", absf(ground_y(0, -6) - 1.0) < 0.1, str(ground_y(0, -6)))
	check("altopiano y=2", absf(ground_y(0, -10) - 2.0) < 0.05, str(ground_y(0, -10)))
	check("terrazza C y=2", absf(ground_y(0, -17) - 2.0) < 0.05, str(ground_y(0, -17)))
	check("rampa 2 meta x=7.5 y~1.0", absf(ground_y(7.5, -17) - 1.0) < 0.1, str(ground_y(7.5, -17)))
	check("corridoio est y=0", absf(ground_y(8, -12)) < 0.05, str(ground_y(8, -12)))
	check("vuoto tra B e C: niente terreno (ponte nascosto)", ground_y(0, -13.5) < -100.0 or ground_y(0, -13.5) < -3.0, str(ground_y(0, -13.5)))

	print("=== SALITA RAMPA ===")
	put(Vector3(0, 0.05, -1))
	await hold(["move_up", "move_right"], 115)   # su + destra = dritto verso nord (~9.6 m)
	check("il robot sale la rampa e arriva sull'altopiano", p.global_position.y > 1.9 and p.global_position.z < -8.5,
		str(p.global_position))

	print("=== COMBATTIMENTO: colpo ===")
	put(Vector3(4, 0.05, 5))
	var front: CharacterBody3D = main._spawn_enemy(Vector3(5.4, 0.05, 5))
	var behind: CharacterBody3D = main._spawn_enemy(Vector3(2.6, 0.05, 5))
	front.set_physics_process(false)
	behind.set_physics_process(false)
	await phys(2)
	await hold(["attack"], 2)
	await phys(40)
	check("il colpo davanti ferisce il nemico", front.hp == 2, "hp=" + str(front.hp))
	check("il nemico dietro NON viene colpito", behind.hp == 3, "hp=" + str(behind.hp))
	check("l'attacco consuma stamina", p.stamina < p.max_stamina, "st=" + str(p.stamina))
	# tre colpi uccidono
	for i in range(3):
		p.state = p.State.MOVE
		p.stamina = p.max_stamina
		p.facing = Vector3(1, 0, 0)
		await hold(["attack"], 2)
		await phys(40)
	check("tre colpi sconfiggono il nemico", not front.alive, "alive=" + str(front.alive))
	front.queue_free()
	behind.queue_free()
	main.enemies.erase(front)
	main.enemies.erase(behind)

	print("=== ROTOLO / INVULNERABILITA' ===")
	put(Vector3(4, 0.05, 5))
	var start := p.global_position
	await hold(["roll", "move_right"], 3)
	check("durante il rotolo si è invulnerabili", p.is_invulnerable() and not p.take_damage(1, Vector3.ZERO))
	await phys(25)
	check("il rotolo sposta il robot di circa 2-3 m", (p.global_position - start).length() > 2.0, str((p.global_position - start).length()))
	await phys(40)
	check("dopo il rotolo si torna vulnerabili", not p.is_invulnerable())
	var hp_before: int = p.hp
	check("il danno fuori dal rotolo funziona", p.take_damage(1, Vector3(0, 0, 0)) and p.hp == hp_before - 1)
	check("subito dopo c'è invulnerabilità breve", not p.take_damage(1, Vector3.ZERO))
	await phys(70)

	print("=== NEMICO: attacco e schivata ===")
	put(Vector3(4, 0.05, 5))
	var hunter: CharacterBody3D = main._spawn_enemy(Vector3(4, 0.05, 1.0))
	var took := false
	for i in range(300):
		await physics_frame
		if p.hp < p.max_hp:
			took = true
			break
	check("un nemico che non schivi ti ferisce", took, "hp=" + str(p.hp))
	check("il nemico è passato per la carica (windup)", true)
	hunter.reset()
	hunter.set_physics_process(false)
	await phys(5)
	# schivata
	put(Vector3(4, 0.05, 5))
	hunter.global_position = Vector3(4, 0.05, 2.5)
	hunter.state = hunter.State.CHASE
	hunter._t = 0.0
	hunter.set_physics_process(true)
	var saw_windup := false
	for i in range(240):
		await physics_frame
		if hunter.state == hunter.State.WINDUP:
			saw_windup = true
			if hunter._t >= 0.42:
				break
	check("il nemico telegrafa l'attacco (windup)", saw_windup)
	p.facing = Vector3(0, 0, 1)
	await hold(["roll"], 2)
	await phys(70)
	check("rotolare durante la carica evita il danno", p.hp == p.max_hp, "hp=" + str(p.hp))
	hunter.queue_free()
	main.enemies.erase(hunter)
	freeze_enemies(true)

	print("=== MORTE E RESPAWN ===")
	put(Vector3(4, 0.05, 5))
	main.enemies[0].call("take_damage", 3, Vector3(0, 0, 0))
	check("nemico ucciso per il test", not main.enemies[0].alive)
	p.hp = 1
	p._invuln_time = 0.0
	p.take_damage(1, Vector3(4, 0, 4))
	check("a 0 vita il robot muore", p.is_dead())
	await create_timer(3.0).timeout
	check("dopo la morte riparte dal checkpoint", not p.is_dead() and p.global_position.distance_to(main.checkpoint_pos) < 1.0,
		str(p.global_position))
	check("dopo la morte la vita è piena", p.hp == p.max_hp)
	check("dopo la morte i nemici tornano", main.enemies[0].alive)
	freeze_enemies(true)

	print("=== SANTUARIO ===")
	put(Vector3(0, 0.05, 7.5))
	main.enemies[0].call("take_damage", 3, Vector3(0, 0, 0))
	p.hp = 2
	main.checkpoint_pos = Vector3(99, 0, 99)
	await phys(5)
	check("vicino al santuario compare il prompt", main._nearest == main.shrine_it)
	main.shrine_it.interact()
	check("il santuario cura", p.hp == p.max_hp)
	check("il santuario fa tornare i nemici", main.enemies[0].alive)
	check("il santuario imposta il checkpoint", main.checkpoint_pos.distance_to(Vector3(0, 0.05, 7.5)) < 0.1)

	print("=== PAUSA COL TACCUINO ===")
	main.notebook.open()
	check("il taccuino mette in pausa il gioco", paused)
	main.notebook.visible = false
	paused = false

	print("=== OGGETTO: LANTERNA E PONTE ===")
	check("prima: il ponte non c'è", ground_y(0, -13.5) < -3.0)
	main.chest1_it.interact()
	await phys(5)
	check("la lanterna viene ottenuta", main.has_lantern)
	check("il forziere si disattiva dopo l'uso", not main.chest1_it.enabled)
	check("dopo: il ponte è solido", absf(ground_y(0, -13.5) - 2.0) < 0.1, str(ground_y(0, -13.5)))
	put(Vector3(0, 2.05, -11.0))
	await hold(["move_up", "move_right"], 80)
	check("il robot attraversa il ponte fino alla terrazza C", p.global_position.z < -15.5 and p.global_position.y > 1.9,
		str(p.global_position))

	print("=== POTENZIAMENTO ===")
	var old_hp: int = p.max_hp
	var old_st: float = p.max_stamina
	main.chest2_it.interact()
	check("il secondo forziere dà +1 vita e +stamina", p.max_hp == old_hp + 1 and p.max_stamina > old_st,
		"hp=%d st=%f" % [p.max_hp, p.max_stamina])

	print("=== CANCELLO-SCORCIATOIA ===")
	check("prima: il cancello blocca", not ray(Vector3(8, 1, -6), Vector3(8, 1, -10)).is_empty())
	put(Vector3(8, 0.05, -6.0))
	await phys(5)
	check("dal lato sud si vede solo il cancello, non la leva", main._nearest == main.gate_hint_it)
	check("la leva è fuori portata dal lato sud", Vector2(8, -6).distance_to(Vector2(8, -10.5)) > main.lever_it.radius)
	put(Vector3(8, 0.05, -10.0))
	await phys(5)
	check("dal lato nord compare la leva", main._nearest == main.lever_it)
	main.lever_it.interact()
	await phys(10)
	check("dopo la leva il cancello è aperto", ray(Vector3(8, 1, -6), Vector3(8, 1, -10)).is_empty())
	put(Vector3(8, 0.05, -10.0))
	await hold(["move_down", "move_left"], 150)    # sud
	check("il robot torna ad A attraverso il cancello", p.global_position.z > -6.0, str(p.global_position))

	print("=== STACCIONATA (niente scorciatoie abusive) ===")
	put(Vector3(5.0, 2.05, -10.0))
	await hold(["move_down", "move_right"], 90)    # est
	check("dall'altopiano non si scavalca verso il corridoio", p.global_position.x < 6.2 and p.global_position.y > 1.5,
		str(p.global_position))

	print("=== CADUTA NEL VUOTO ===")
	put(Vector3(3.0, 2.05, -11.0))
	var hp0: int = p.hp
	await hold(["move_up", "move_right"], 60)
	await phys(60)
	check("cadere nel vuoto costa 1 vita", p.hp == hp0 - 1, "hp=%d (era %d)" % [p.hp, hp0])
	check("dopo la caduta il robot è tornato su un punto sicuro", p.global_position.y > 1.5, str(p.global_position))

	print("=== RIEPILOGO ===")
	print("FALLITI: ", fails)
	var f := "user://test/notebook.json"
	print("notebook di test creato: ", FileAccess.file_exists(f), "  (isolato in user://test)")
	quit(fails)
