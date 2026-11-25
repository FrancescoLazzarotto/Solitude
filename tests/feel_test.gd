extends SceneTree
## Feeling: scintille d'impatto, scuotimento della camera, fiaschetta di cura.

var fails := 0
var main: Node
var p: CharacterBody3D
var fx: Node


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


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await phys(5)
	fx = root.get_node("Fx")
	p = main.player
	for e in main.enemies:
		e.set_physics_process(false)

	print("=== SCINTILLE E SCUOTIMENTO ===")
	check("senza trauma la camera non trema", fx.shake_offset() == Vector3.ZERO)
	var b0: int = int(fx.stats.get("burst", 0))
	var dummy: CharacterBody3D = main._spawn_enemy(Vector3(-6.0, 0.05, 4.0))
	dummy.set_physics_process(false)
	dummy.take_damage(1, Vector3.ZERO)
	check("un nemico colpito emette scintille", int(fx.stats.get("burst", 0)) == b0 + 1)
	check("e scuote la camera", fx.trauma > 0.15, "trauma=%.2f" % fx.trauma)
	var emitting := 0
	for pt: CPUParticles3D in fx._pool:
		if pt.emitting:
			emitting += 1
	check("almeno un emettitore di particelle e' attivo", emitting >= 1)
	var b1: int = int(fx.stats.get("burst", 0))
	dummy.take_damage(9, Vector3.ZERO)
	check("la sconfitta di un nemico fa due scatti (colpo + esplosione) e scuote forte", int(fx.stats.get("burst", 0)) == b1 + 2 and fx.trauma > 0.4, "trauma=%.2f" % fx.trauma)
	fx.trauma = 1.0
	var mag: float = fx.shake_offset().length()
	check("l'ampiezza massima e' limitata (<= 0.6 m)", mag <= 0.6 and mag > 0.0, "%.3f m" % mag)
	await create_timer(1.2).timeout
	check("lo scuotimento decade in meno di ~1 s", fx.trauma < 0.01, "trauma=%.3f" % fx.trauma)
	put(Vector3(4, 0.05, 5))
	var b2: int = int(fx.stats.get("burst", 0))
	p.take_damage(1, Vector3.ZERO)
	check("il robot colpito emette scintille e trema", int(fx.stats.get("burst", 0)) == b2 + 1 and fx.trauma > 0.4)
	fx.trauma = 0.0

	print("=== FIASCHETTA ===")
	check("l'azione 'heal' esiste (Q)", InputMap.has_action("heal"))
	put(Vector3(4, 0.05, 5))
	check("si parte con 3 fiaschette", p.flasks == 3 and p.max_flasks == 3)
	await hold(["heal"], 2)
	await phys(60)
	check("a vita piena la fiaschetta non si consuma", p.flasks == 3 and p.state == p.State.MOVE)

	p.hp = 2
	await hold(["heal"], 2)
	await phys(3)
	check("premendo Q si inizia a bere", p.state == p.State.DRINK)
	check("mentre si beve si e' vulnerabili", not p.is_invulnerable())
	await phys(25)
	check("la cura non arriva subito", p.hp == 2)
	await phys(30)
	check("dopo ~0.7 s la fiaschetta cura 2 cuori", p.hp == 4, "hp=%d" % p.hp)
	check("la fiaschetta e' consumata", p.flasks == 2)
	check("si torna a muoversi", p.state == p.State.MOVE)

	p.hp = 3
	p._invuln_time = 0.0
	await hold(["heal"], 2)
	await phys(10)
	check("bevo di nuovo", p.state == p.State.DRINK)
	p.take_damage(1, Vector3(3, 0, 5))
	check("un colpo interrompe la bevuta", p.state == p.State.HURT and p.hp == 2)
	await phys(60)
	check("nessun cuore viene recuperato (2, non 4)", p.hp == 2, "hp=%d" % p.hp)
	check("e la fiaschetta NON viene consumata", p.flasks == 2, "flasks=%d" % p.flasks)

	put(Vector3(4, 0.05, 5))
	p.hp = 2
	p.flasks = 0
	await hold(["heal"], 2)
	await phys(10)
	check("senza fiaschette non si beve", p.state == p.State.MOVE and p.hp == 2)

	put(Vector3(4, 0.05, 5))
	p.hp = 2
	p.flasks = 1
	await hold(["heal", "move_left"], 2)
	await hold(["move_left"], 20)
	check("mentre si beve si cammina piano", p.state == p.State.DRINK and p.velocity.length() < p.WALK_SPEED * 0.45, "v=%.2f" % p.velocity.length())
	await phys(50)

	p.flasks = 0
	p.hp = 1
	main.shrine_it.interact()
	check("il santuario ricarica le fiaschette", p.flasks == p.max_flasks and p.hp == p.max_hp)
	main._sync_hud()
	var hud: Node = main.hud
	check("l'HUD mostra una fiaschetta per ogni scorta", hud._flasks.get_child_count() == 3)
	var lit := 0
	for c in hud._flasks.get_children():
		if (c as ColorRect).color.a > 0.9:
			lit += 1
	check("e tutte e tre sono 'piene'", lit == 3, str(lit))

	print("=== RIEPILOGO ===")
	print("FALLITI: ", fails)
	quit(fails)
