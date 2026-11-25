extends SceneTree
## Nemici su livelli diversi e nel vuoto: chi sta sull'altopiano (2 m sopra) non deve ingaggiare chi sta
## sotto, la sentinella deve mirare in 3D (rampa) e chi cade nel vuoto deve essere sconfitto.
## Qui i nemici NON sono congelati: e' proprio il comportamento reale che si verifica.

var fails := 0
var main: Node
var p: CharacterBody3D
var audio: Node


func check(name: String, cond: bool, extra := "") -> void:
	if not cond:
		fails += 1
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + extra if extra != "" else ""))


func phys(n: int) -> void:
	for i in range(n):
		await physics_frame


func put(pos: Vector3) -> void:
	p.teleport_to(pos)
	p.hp = p.max_hp
	p.stamina = p.max_stamina
	p.state = p.State.MOVE
	p._invuln_time = 0.0
	p._state_time = 0.0
	p.facing = Vector3(1, 0, 0)


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await phys(5)
	audio = root.get_node("Audio")
	p = main.player
	# La sentinella dell'altopiano (indice 3) e i guardiani (1, 2) sono quelli veri del livello.
	var guard_a: CharacterBody3D = main.enemies[1]
	var guard_b: CharacterBody3D = main.enemies[2]
	var sentinel: CharacterBody3D = main.enemies[3]
	p.max_hp = 4
	p.hp = 4
	# Il guardiano del cortile (indice 0) e' vero ma sta a ~4 m dal punto di prova e ferirebbe legittimamente il robot:
	# qui interessano solo i nemici dell'altopiano.
	main.enemies[0].set_physics_process(false)

	print("=== CHI STA SOTTO NON VIENE INGAGGIATO ===")
	put(Vector3(4.0, 0.05, -5.0))
	var shots0 := int(audio.stats.get(&"shot", 0))
	var min_y := 99.0
	var states_seen := {}
	for i in range(300):
		await physics_frame
		for e: CharacterBody3D in [guard_a, guard_b, sentinel]:
			min_y = minf(min_y, e.global_position.y)
			states_seen[e.State.keys()[e.state]] = true
	check("la sentinella non spara a un giocatore 2 m piu' in basso", int(audio.stats.get(&"shot", 0)) == shots0)
	check("e non resta a mirare nel vuoto (nessun WINDUP)", not states_seen.has("WINDUP") and not states_seen.has("CHASE"), str(states_seen.keys()))
	check("nessun proiettile in volo", get_nodes_in_group("projectiles").size() == 0)
	check("i guardiani dell'altopiano non scendono a cercarti", min_y > 1.5, "y minima = %.2f" % min_y)
	check("il giocatore e' intatto", p.hp == p.max_hp)

	print("=== MIRA IN 3D SULLA RAMPA ===")
	# Sulla meta' alta della rampa (y ~ 1.25) il dislivello e' < 1.2: la sentinella ingaggia e deve mirare in basso.
	for e: CharacterBody3D in [guard_a, guard_b]:
		e.set_physics_process(false)   # solo la sentinella, per isolare la prova
	sentinel.reset()
	put(Vector3(0.0, 1.3, -6.5))
	p.set_physics_process(false)       # fermo, come un bersaglio
	var dir_y := 0.0
	var spawned := false
	var hit := false
	var hp0: int = p.hp
	for i in range(240):
		await physics_frame
		var shots := get_nodes_in_group("projectiles")
		if not spawned and shots.size() > 0:
			spawned = true
			dir_y = shots[0].direction.y
		if p.hp < hp0:
			hit = true
			break
	check("sulla rampa la sentinella ingaggia", spawned)
	check("il proiettile e' diretto verso il basso (mira 3D)", dir_y < -0.05, "direction.y = %.3f" % dir_y)
	check("e arriva davvero al petto del robot", hit, "hp %d -> %d" % [hp0, p.hp])
	p.set_physics_process(true)
	await phys(60)
	for pr in get_nodes_in_group("projectiles"):
		pr.queue_free()

	print("=== CHI CADE NEL VUOTO VIENE SCONFITTO ===")
	put(Vector3(-5.5, 0.05, 6.0))
	var faller: CharacterBody3D = main._spawn_enemy(Vector3(0.0, 2.05, -11.9))
	faller.velocity = Vector3(0.0, 0.0, -9.0)   # spinto verso nord, oltre il bordo dell'altopiano
	var fell_at := -1
	for i in range(240):
		await physics_frame
		if not faller.alive:
			fell_at = i
			break
	check("un nemico spinto oltre il bordo cade e viene sconfitto", fell_at > 0, "dopo %d frame" % fell_at)
	check("non resta in giro a cadere all'infinito", faller.global_position.y > -12.0, "y=%.1f" % faller.global_position.y)
	faller.reset()
	check("il reset lo riporta al suo posto, vivo", faller.alive and faller.global_position.distance_to(Vector3(0.0, 2.05, -11.9)) < 0.1)
	faller.queue_free()
	main.enemies.erase(faller)

	print("=== IL GIOCATORE NELLO STESSO LIVELLO VIENE ANCORA INGAGGIATO ===")
	# Regressione: abbassare la soglia non deve rompere i combattimenti normali.
	guard_a.set_physics_process(true)
	guard_a.reset()
	put(Vector3(3.5, 2.05, -7.5 - 0.0))   # in cima alla rampa, sull'altopiano
	p.global_position = Vector3(3.5, 2.05, -9.0 + 0.0)
	var engaged := false
	for i in range(200):
		await physics_frame
		if guard_a.state != guard_a.State.IDLE:
			engaged = true
			break
	check("sullo stesso livello il guardiano ingaggia come prima", engaged)

	print("=== RIEPILOGO ===")
	print("FALLITI: ", fails)
	quit(fails)
