extends SceneTree
## Salvataggio dei progressi: andata e ritorno, progressi parziali, file corrotti, scrittura atomica.
## Va lanciato con `-- --carto-test --carto-savetest` (il runner lo fa da solo).

const SaveGame := preload("res://scripts/save_game.gd")

var fails := 0


func check(name: String, cond: bool, extra := "") -> void:
	if not cond:
		fails += 1
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + extra if extra != "" else ""))


func phys(n: int) -> void:
	for i in range(n):
		await physics_frame


func ground_y(x: float, z: float, exclude: RID) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 10, z), Vector3(x, -10, z))
	q.exclude = [exclude]
	var r := root.get_world_3d().direct_space_state.intersect_ray(q)
	return r["position"].y if not r.is_empty() else -999.0


func gate_blocks(exclude: RID) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(8, 1, -6), Vector3(8, 1, -10))
	q.exclude = [exclude]
	return not root.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func write_raw(text: String) -> void:
	var f := FileAccess.open(SaveGame.path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func new_game() -> Node:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await phys(4)
	for e in m.enemies:
		e.set_physics_process(false)
	return m


func close_game(m: Node) -> void:
	m.queue_free()
	await phys(3)


func _initialize() -> void:
	print("=== PREREQUISITI ===")
	check("il salvataggio e' attivo solo con --carto-savetest", SaveGame.enabled())
	check("in test il file sta in user://test (mai nel profilo vero)", SaveGame.path().begins_with("user://test/"), SaveGame.path())
	SaveGame.delete()
	check("si parte senza salvataggio", SaveGame.read().is_empty())

	print("=== PARTITA NUOVA ===")
	var a: Node = await new_game()
	check("senza salvataggio: niente lanterna, 4 cuori, cancello chiuso", not a.has_lantern and a.player.max_hp == 4 and not a.gate_open and gate_blocks(a.player.get_rid()))

	print("=== PROGRESSI -> FILE ===")
	a.chest1_it.interact()
	check("aprire il forziere della lanterna salva da solo", SaveGame.read().get("keys", []) == ["lantern"], str(SaveGame.read()))
	a.chest2_it.interact()
	a.lever_it.interact()
	a.player.add_max_stamina(0.0)
	a.shrine_it.interact()
	var saved := SaveGame.read()
	check("il file e' valido e versionato", int(saved.get("version", 0)) == SaveGame.VERSION)
	check("chiavi salvate: lanterna e leva", saved["keys"] == ["lantern", "lever"], str(saved["keys"]))
	check("forzieri aperti salvati", saved["chests_opened"] == ["lantern", "heart"], str(saved["chests_opened"]))
	check("potenziamenti salvati (5 cuori, 120 stamina)", int(saved["max_hp"]) == 5 and float(saved["max_stamina"]) == 120.0)
	check("il checkpoint e' un id, non delle coordinate", saved["checkpoint"] == "shrine", str(saved["checkpoint"]))
	check("le chiavi stanno in un unico insieme (a.keys)", a.keys == ["lantern", "lever"], str(a.keys))
	check("nessun file temporaneo rimasto (scrittura atomica)", not FileAccess.file_exists(SaveGame.path() + ".tmp"))
	for i in range(5):
		SaveGame.write(a.get_save_data())
	check("5 scritture ripetute: il file resta valido", SaveGame.read().get("keys", []) == ["lantern", "lever"] and not FileAccess.file_exists(SaveGame.path() + ".tmp"))
	await close_game(a)

	print("=== RIAVVIO: i progressi tornano ===")
	var b: Node = await new_game()
	var rid: RID = b.player.get_rid()
	check("la lanterna e' di nuovo posseduta", b.has_lantern)
	check("il ponte e' gia' solido, senza animazione", absf(ground_y(0, -13.5, rid) - 2.0) < 0.1, str(ground_y(0, -13.5, rid)))
	check("i forzieri sono aperti e non si riaprono", not b.chest1_it.enabled and not b.chest2_it.enabled)
	var lid1 := b.chest1_it.get_parent().get_node("LidPivot") as Node3D
	check("i coperchi sono visibilmente aperti", absf(lid1.rotation_degrees.x + 105.0) < 0.01)
	check("la leva e' tirata e il cancello e' aperto", b.gate_open and not b.lever_it.enabled and not gate_blocks(rid))
	check("i potenziamenti sono ancora li' (5 cuori, 120 stamina)", b.player.max_hp == 5 and b.player.max_stamina == 120.0)
	check("si riparte con vita e fiaschette piene", b.player.hp == 5 and b.player.flasks == b.player.max_flasks)
	check("il robot riparte dal santuario", b.player.global_position.distance_to(b.checkpoint_pos) < 0.5, str(b.player.global_position))
	check("l'HUD mostra 5 cuori", b.hud._hearts.get_child_count() == 5)
	b.chest2_it.interact()
	check("riaprire un forziere gia' aperto non da' altri bonus (disabilitato)", b.player.max_hp == 5 or not b.chest2_it.enabled)
	await close_game(b)

	print("=== PROGRESSI PARZIALI ===")
	SaveGame.delete()
	var c: Node = await new_game()
	c.chest1_it.interact()
	await close_game(c)
	var d: Node = await new_game()
	var rid_d: RID = d.player.get_rid()
	check("solo la lanterna: ponte solido, cuore ancora da prendere, cancello chiuso", d.has_lantern and absf(ground_y(0, -13.5, rid_d) - 2.0) < 0.1 and d.chest2_it.enabled and gate_blocks(rid_d) and d.lever_it.enabled)
	check("e 4 cuori", d.player.max_hp == 4)
	await close_game(d)

	print("=== SALVATAGGI DI UN ALTRO LIVELLO: id e chiavi sconosciuti ===")
	write_raw('{"version": 2, "checkpoint": "shrine", "keys": ["lantern"], "chests_opened": ["tesoro_nuovo"], "max_hp": 4}')
	var u1: Node = await new_game()
	check("un forziere sconosciuto non apre NESSUN altro forziere", u1.chest1_it.enabled and u1.chest2_it.enabled and u1.chests_opened.is_empty())
	check("le altre chiavi valide restano", u1.has_lantern)
	await close_game(u1)
	write_raw('{"version": 2, "checkpoint": "shrine", "keys": ["rampino"], "chests_opened": ["tesoro_nuovo", "heart"], "max_hp": 5}')
	var u2: Node = await new_game()
	check("una chiave sconosciuta viene ignorata", not u2.has_lantern and u2.keys.is_empty(), str(u2.keys))
	check("tra un id ignoto e uno noto, apre solo quello noto (il cuore)", u2.chest1_it.enabled and not u2.chest2_it.enabled, str(u2.chests_opened))
	await close_game(u2)
	write_raw('{"version": 2, "checkpoint": "stanza_che_non_esiste", "keys": [], "chests_opened": [], "max_hp": 4}')
	var u3: Node = await new_game()
	check("un checkpoint sconosciuto ripiega sul santuario", u3.player.global_position.distance_to(Vector3(0, 0.05, 7.5)) < 0.6, str(u3.player.global_position))
	await close_game(u3)

	print("=== VALORI OSTILI ===")
	write_raw('{"version": 2, "checkpoint": "shrine", "keys": [], "chests_opened": [], "max_hp": 999999, "max_stamina": -50, "max_flasks": 5000}')
	var h: Node = await new_game()
	check("i valori assurdi vengono limitati (niente 999999 cuori nell'HUD)", h.player.max_hp == 40 and h.player.max_stamina >= 10.0 and h.player.max_flasks == 20, "hp=%d st=%.0f fl=%d" % [h.player.max_hp, h.player.max_stamina, h.player.max_flasks])
	check("l'HUD resta ragionevole", h.hud._hearts.get_child_count() == 40)
	await close_game(h)
	write_raw('{"version": 2, "checkpoint": "shrine", "keys": [], "chests_opened": [], "max_hp": -3}')
	var h2: Node = await new_game()
	check("una vita massima negativa diventa 1", h2.player.max_hp == 1)
	await close_game(h2)

	print("=== MIGRAZIONE DAL FORMATO v1 (checkpoint a coordinate) ===")
	write_raw('{"version": 1, "checkpoint": [3.0, 0.05, -6.0], "keys": ["lantern"], "chests_opened": ["lantern"], "max_hp": 4, "max_stamina": 100.0, "max_flasks": 3}')
	var v1: Node = await new_game()
	check("un salvataggio v1 si carica: chiavi e forzieri tornano", v1.has_lantern and not v1.chest1_it.enabled)
	check("e le vecchie coordinate NON vengono usate: si riparte dal santuario", v1.player.global_position.distance_to(Vector3(0, 0.05, 7.5)) < 0.6, str(v1.player.global_position))
	await close_game(v1)
	v1 = await new_game()
	v1.shrine_it.interact()
	check("al primo salvataggio il file diventa v2", int(SaveGame.read().get("version", 0)) == 2 and SaveGame.read()["checkpoint"] == "shrine")
	await close_game(v1)

	print("=== FILE ROVINATI: nessun crash, si riparte da capo ===")
	for case: Array in [["testo non JSON {{{", "JSON rotto"], ["[1, 2, 3]", "JSON valido ma non un dizionario"], ['{"version": 999, "keys": ["lantern"]}', "versione sconosciuta"], ["", "file vuoto"]]:
		var f := FileAccess.open(SaveGame.path(), FileAccess.WRITE)
		f.store_string(case[0])
		f.close()
		var e: Node = await new_game()
		check("%s: si riparte pulito" % case[1], not e.has_lantern and e.player.max_hp == 4 and gate_blocks(e.player.get_rid()))
		await close_game(e)
	SaveGame.delete()
	check("delete() rimuove il file", not FileAccess.file_exists(SaveGame.path()))

	print("=== RIEPILOGO ===")
	print("FALLITI: ", fails)
	quit(fails)
