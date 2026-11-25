extends SceneTree
## Audio: estensione nativa, banco di suoni, sicurezza dei thread e aggancio agli eventi di gioco.

var fails := 0
var audio: Node
var main: Node
var p: CharacterBody3D


func check(name: String, cond: bool, extra := "") -> void:
	if not cond:
		fails += 1
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + extra if extra != "" else ""))


func phys(n: int) -> void:
	for i in range(n):
		await physics_frame


func count(names: Array) -> int:
	var c := 0
	for n: String in names:
		c += int(audio.stats.get(StringName(n), 0))
	return c


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await phys(3)
	audio = root.get_node("Audio")
	p = main.player
	for e in main.enemies:
		e.set_physics_process(false)

	print("=== ESTENSIONE NATIVA ===")
	check("la classe CartoAudio e' registrata", ClassDB.class_exists("CartoAudio"))
	var n: RefCounted = ClassDB.instantiate("CartoAudio")
	check("versione dell'estensione", str(n.version()).begins_with("carto "), str(n.version()))
	check("frequenza di campionamento 44100", n.sample_rate() == 44100)
	var names: PackedStringArray = n.sfx_names()
	check("26 effetti disponibili", names.size() == 26, str(names.size()))
	var swing: AudioStreamWAV = n.render_sfx("swing", 1)
	check("render_sfx ritorna un AudioStreamWAV mono 16 bit", swing != null and not swing.stereo and swing.format == AudioStreamWAV.FORMAT_16_BITS and swing.mix_rate == 44100)
	check("i dati sono non vuoti e coerenti", swing.data.size() > 2000 and swing.data.size() % 2 == 0, str(swing.data.size()))
	check("un nome inesistente ritorna null", n.render_sfx("non_esiste", 1) == null)
	var t0 := Time.get_ticks_msec()
	var bank: Dictionary = n.render_sfx_bank(7)
	var bank_ms := Time.get_ticks_msec() - t0
	check("il banco contiene tutti i 26 suoni", bank.size() == 26, "in %d ms" % bank_ms)
	var all_ok := true
	for k: String in bank:
		var s: AudioStreamWAV = bank[k]
		if s == null or s.data.size() < 1000:
			all_ok = false
	check("ogni suono del banco e' valido", all_ok)
	var music: AudioStreamWAV = n.render_music(3, 6.0)
	check("la musica e' stereo e in loop", music.stereo and music.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	check("il loop copre tutta la musica", music.loop_end == 6 * 44100, str(music.loop_end))
	check("pcm_to_stream rifiuta dati vuoti", n.pcm_to_stream(PackedByteArray(), false, false) == null)

	print("=== THREAD ===")
	var bg: RefCounted = ClassDB.instantiate("CartoAudio")
	check("prima di start_render non c'e' niente da ritirare", not bg.is_render_done() and bg.take_render().is_empty())
	bg.start_render(5, 4.0)
	var spins := 0
	while not bg.is_render_done() and spins < 400:
		await process_frame   # il thread principale resta libero mentre Rust lavora
		spins += 1
	check("il rendering in background (thread di Rust) termina", bg.is_render_done(), "%d frame di attesa" % spins)
	var res: Dictionary = bg.take_render()
	check("risultato: 26 suoni + musica stereo di 4 s", res.get("sfx", {}).size() == 26 and res.get("music", PackedByteArray()).size() == 4 * 44100 * 4)
	check("il risultato si ritira una volta sola", bg.take_render().is_empty())
	var again: Dictionary = n.render_sfx_bank_pcm(5)
	check("il rendering in background e' identico a quello sincrono (deterministico)", again["swing"] == res["sfx"]["swing"] and again["lever"] == res["sfx"]["lever"])

	print("=== GESTORE AUDIO (autoload) ===")
	var waited := 0
	while not audio.available and waited < 300:
		await create_timer(0.1).timeout
		waited += 1
	check("i suoni vengono generati in background e diventano disponibili", audio.available, "%d ms di rendering" % audio.load_ms)
	check("la musica parte", audio._music.playing)

	print("=== EVENTI -> SUONI ===")
	var before: Dictionary = audio.stats.duplicate()
	p.teleport_to(Vector3(4, 0.05, 5))
	await phys(3)
	await _hold(["attack"], 2)
	await phys(30)
	check("attacco -> swing", count(["swing", "swing2"]) > int(before.get(&"swing", 0)) + int(before.get(&"swing2", 0)))
	p.stamina = p.max_stamina
	p.state = p.State.MOVE
	var r0 := count(["roll"])
	await _hold(["roll", "move_right"], 2)
	await phys(40)
	check("rotolo -> roll", count(["roll"]) == r0 + 1)

	p.teleport_to(Vector3(-2, 0.05, 6.5))
	p.state = p.State.MOVE
	await phys(3)
	var s0 := count(["step", "step2", "step3", "step4"])
	await _hold(["move_left"], 80)
	check("camminare -> passi (circa uno ogni 1.9 m)", count(["step", "step2", "step3", "step4"]) - s0 >= 2, str(count(["step", "step2", "step3", "step4"]) - s0))

	var h0 := count(["hit_player"])
	p._invuln_time = 0.0
	p.take_damage(1, Vector3.ZERO)
	check("danno subito -> hit_player", count(["hit_player"]) == h0 + 1)
	p._invuln_time = 0.0
	p.heal_full()

	var he0 := count(["hit_enemy"])
	var dummy: CharacterBody3D = main._spawn_enemy(Vector3(5.4, 0.05, 5))
	dummy.set_physics_process(false)
	p.teleport_to(Vector3(4, 0.05, 5))
	p.state = p.State.MOVE
	p.stamina = p.max_stamina
	p.facing = Vector3(1, 0, 0)
	await phys(3)
	await _hold(["attack"], 2)
	await phys(30)
	check("colpo a segno -> hit_enemy", count(["hit_enemy"]) > he0)
	var hurt0 := count(["enemy_hurt"])
	dummy.take_damage(1, Vector3.ZERO)
	check("nemico ferito -> enemy_hurt", count(["enemy_hurt"]) == hurt0 + 1)
	var die0 := count(["enemy_die"])
	dummy.take_damage(5, Vector3.ZERO)
	check("nemico sconfitto -> enemy_die", count(["enemy_die"]) == die0 + 1)

	var w0 := count(["enemy_windup"])
	var l0 := count(["enemy_lunge"])
	var hunter: CharacterBody3D = main._spawn_enemy(Vector3(4, 0.05, 2.0))
	p.teleport_to(Vector3(4, 0.05, 4.0))
	p.hp = 9999
	p.max_hp = 9999
	await phys(150)
	check("nemico carica -> enemy_windup", count(["enemy_windup"]) > w0)
	check("nemico scatta -> enemy_lunge", count(["enemy_lunge"]) > l0)
	hunter.set_physics_process(false)
	p.max_hp = 4
	p.hp = 4

	print("=== MONDO -> SUONI ===")
	var c0 := count(["chest_open"])
	main.chest1_it.interact()
	check("forziere lanterna -> chest_open + lantern_on + bridge_reveal", count(["chest_open"]) == c0 + 1 and count(["lantern_on"]) >= 1 and count(["bridge_reveal"]) >= 1)
	main.chest2_it.interact()
	check("forziere cuore -> item_get", count(["item_get"]) >= 1)
	main.shrine_it.interact()
	check("santuario -> shrine_rest + heal", count(["shrine_rest"]) >= 1 and count(["heal"]) >= 1)
	main.lever_it.interact()
	check("leva -> lever + gate_open", count(["lever"]) >= 1 and count(["gate_open"]) >= 1)
	var pg := count(["page_open", "page_close"])
	main.notebook.open()
	main.notebook.close()
	check("taccuino -> page_open + page_close", count(["page_open", "page_close"]) == pg + 2)
	var f0 := count(["fall"])
	p.fall_recover(main.checkpoint_pos)
	check("caduta -> fall", count(["fall"]) == f0 + 1)
	var d0 := count(["death"])
	p.hp = 1
	p._invuln_time = 0.0
	p.take_damage(1, Vector3.ZERO)
	check("morte -> death", count(["death"]) == d0 + 1)

	print("=== PANNING (il microfono guarda come la camera) ===")
	await process_frame
	await process_frame
	var lt: Transform3D = audio._listener.global_transform
	var cam: Camera3D = main.camera
	var screen_right: Vector3 = cam.global_basis.x
	var screen_up := -cam.global_basis.z
	screen_up.y = 0.0
	screen_up = screen_up.normalized()
	var right_local := lt.affine_inverse() * (lt.origin + screen_right)
	var up_local := lt.affine_inverse() * (lt.origin + screen_up)
	check("un suono a DESTRA sullo schermo e' a destra del microfono (x ~ +1)", right_local.x > 0.99 and absf(right_local.z) < 0.05, str(right_local.snappedf(0.01)))
	check("un suono IN ALTO sullo schermo e' davanti al microfono (x ~ 0, z ~ -1)", absf(up_local.x) < 0.05 and up_local.z < -0.99, str(up_local.snappedf(0.01)))
	check("il microfono sta sul robot, non sulla camera", lt.origin.distance_to(p.global_position) < 2.0, str(lt.origin.distance_to(p.global_position)))

	print("=== RIPRODUZIONE REALE ===")
	audio.play(&"hit_enemy", Vector3(0, 1, 0))
	var playing := 0
	for pl: AudioStreamPlayer3D in audio._pool:
		if pl.playing:
			playing += 1
	check("almeno un player 3D sta suonando", playing >= 1, str(playing))
	check("il bus SFX e il bus Music esistono", AudioServer.get_bus_index(&"SFX") != -1 and AudioServer.get_bus_index(&"Music") != -1)

	print("=== RIEPILOGO ===")
	print("FALLITI: ", fails)
	quit(fails)


func _hold(actions: Array, frames: int) -> void:
	for a: String in actions:
		Input.action_press(a)
	await phys(frames)
	for a: String in actions:
		Input.action_release(a)
