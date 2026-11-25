extends SceneTree
## Tipi di nemico: bruto (lento, forte, difficile da stordire) e sentinella (torretta con proiettile schivabile).

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


func projectiles() -> int:
	return get_nodes_in_group("projectiles").size()


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await phys(5)
	audio = root.get_node("Audio")
	p = main.player
	for e in main.enemies:
		e.set_physics_process(false)

	print("=== NEL LIVELLO ===")
	var kinds: Array = []
	for e in main.enemies:
		kinds.append(e.kind)
	check("il livello ha 3 guardiani, 1 sentinella e 1 bruto", kinds == ["guardian", "guardian", "guardian", "sentinel", "brute"], str(kinds))
	check("il guardiano e' invariato (3 PV)", main.enemies[0].max_hp == 3)

	print("=== BRUTO ===")
	var brute: CharacterBody3D = main._spawn_enemy(Vector3(4, 0.05, 0.0), "brute")
	check("il bruto ha 6 PV ed e' piu' grosso", brute.max_hp == 6 and brute._model.scale.x > 1.4)
	put(Vector3(4, 0.05, 5))
	# Misura quanto dura la carica e che danno fa.
	var windup_frames := 0
	var saw_windup := false
	var hp_before := 0
	var hit := false
	for i in range(420):
		await physics_frame
		if brute.state == brute.State.WINDUP:
			saw_windup = true
			windup_frames += 1
		if saw_windup and brute.state == brute.State.ATTACK and hp_before == 0:
			hp_before = p.hp
		if hp_before != 0 and p.hp < hp_before:
			hit = true
			break
	check("il bruto carica a lungo (>= 0.95 s: piu' tempo per schivare)", windup_frames >= 57, "%d frame" % windup_frames)
	check("un colpo del bruto toglie 2 cuori", hit and hp_before - p.hp == 2, "hp %d -> %d" % [hp_before, p.hp])
	brute.set_physics_process(false)
	brute.reset()
	for i in range(5):
		brute.take_damage(1, Vector3.ZERO)
	check("5 colpi non bastano a un bruto da 6 PV", brute.alive and brute.hp == 1)
	brute.take_damage(1, Vector3.ZERO)
	check("il sesto lo sconfigge", not brute.alive)
	var guard: CharacterBody3D = main._spawn_enemy(Vector3(-6, 0.05, 8), "guardian")
	guard.set_physics_process(false)
	check("il bruto si stordisce meno del guardiano", brute.KINDS["brute"]["stagger"] < guard.KINDS["guardian"]["stagger"] * 0.6)
	check("e subisce meno spinta", brute.KINDS["brute"]["knockback"] < guard.KINDS["guardian"]["knockback"])
	guard.queue_free()
	main.enemies.erase(guard)
	brute.queue_free()
	main.enemies.erase(brute)

	print("=== BRUTO: si schiva rotolando ===")
	var b2: CharacterBody3D = main._spawn_enemy(Vector3(4, 0.05, 1.5), "brute")
	put(Vector3(4, 0.05, 5))
	var armed := false
	for i in range(400):
		await physics_frame
		if b2.state == b2.State.WINDUP and b2._t >= 0.7:
			armed = true
			break
	check("il bruto arriva a caricare", armed)
	p.facing = Vector3(-1, 0, 0)
	await hold(["roll"], 2)
	await phys(80)
	check("rotolare durante la carica evita il colpo da 2 cuori", p.hp == p.max_hp, "hp=%d" % p.hp)
	b2.queue_free()
	main.enemies.erase(b2)

	print("=== SENTINELLA ===")
	var s: CharacterBody3D = main._spawn_enemy(Vector3(3, 0.05, 0), "sentinel")
	check("la sentinella ha 2 PV", s.max_hp == 2)
	var start_pos := s.global_position
	put(Vector3(3, 0.05, 6))
	var shot0 := int(audio.stats.get(&"shot", 0))
	var windup_seen := false
	var line_visible := false
	var fired_at := -1
	var f := 0
	while f < 300:
		await physics_frame
		f += 1
		if s.state == s.State.WINDUP:
			windup_seen = true
			line_visible = line_visible or s._warn.visible
		if projectiles() > 0:
			fired_at = f
			break
	check("la sentinella mira (carica) prima di sparare", windup_seen)
	check("mostra la linea di tiro durante la mira", line_visible)
	check("poi spara un proiettile", fired_at > 0, "dopo %d frame" % fired_at)
	check("lo sparo ha il suo suono", int(audio.stats.get(&"shot", 0)) == shot0 + 1)
	check("la sentinella non si muove", s.global_position.distance_to(start_pos) < 0.05, str(s.global_position.distance_to(start_pos)))

	# (La sentinella sta a x=3: il santuario, a x=0, non sta in mezzo alla linea di vista.)
	# Schivata: ci si sposta di lato mentre il proiettile viaggia.
	var hp_s: int = p.hp
	await hold(["move_left"], 22)
	await phys(60)
	check("spostandosi di lato il proiettile si schiva", p.hp == hp_s, "hp=%d (era %d)" % [p.hp, hp_s])
	await phys(180)
	check("il proiettile sparisce da solo (non resta in giro)", projectiles() == 0, str(projectiles()))

	# Colpo a segno restando fermi.
	put(Vector3(3, 0.05, 6))
	s.reset()
	hp_s = p.hp
	var got_hit := false
	for i in range(300):
		await physics_frame
		if p.hp < hp_s:
			got_hit = true
			break
	check("restando fermi il proiettile colpisce: 1 cuore", got_hit and hp_s - p.hp == 1, "hp %d -> %d" % [hp_s, p.hp])

	# Rotolo: le i-frames bastano.
	await phys(120)
	put(Vector3(3, 0.05, 6))
	s.reset()
	p.hp = p.max_hp
	var spawned := false
	for i in range(300):
		await physics_frame
		if projectiles() > 0:
			spawned = true
			break
	# Il proiettile viaggia a 8.5 m/s: dopo ~0.45 s e' a ~4 m, quasi addosso. Si rotola in quel momento.
	await phys(24)
	p.facing = Vector3(1, 0, 0)
	await hold(["roll", "move_right"], 2)
	await phys(40)
	check("rotolando al momento giusto le i-frames evitano il proiettile", spawned and p.hp == p.max_hp, "hp=%d" % p.hp)

	print("=== SENTINELLA: linea di vista ===")
	await phys(150)
	for pr in get_nodes_in_group("projectiles"):
		pr.queue_free()
	await phys(2)
	s.reset()
	put(Vector3(3, 0.05, 6))
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 3, 0.5)
	cs.shape = box
	wall.add_child(cs)
	main.add_child(wall)
	wall.global_position = Vector3(3, 1.5, 3)
	var shot1 := int(audio.stats.get(&"shot", 0))
	await phys(200)
	check("un muro in mezzo: la sentinella non spara", int(audio.stats.get(&"shot", 0)) == shot1 and projectiles() == 0 and s.state != s.State.WINDUP)
	wall.queue_free()
	await phys(2)

	s.take_damage(1, Vector3.ZERO)
	check("un colpo non basta (2 PV)", s.alive)
	s.take_damage(1, Vector3.ZERO)
	check("il secondo la distrugge", not s.alive)
	var shot2 := int(audio.stats.get(&"shot", 0))
	await phys(150)
	check("una sentinella distrutta non spara", int(audio.stats.get(&"shot", 0)) == shot2)
	s.reset()
	check("il santuario la ripristina (reset)", s.alive and s.hp == 2)

	print("=== RIEPILOGO ===")
	print("FALLITI: ", fails)
	quit(fails)
