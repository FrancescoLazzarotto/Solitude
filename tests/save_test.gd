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
	check("checkpoint salvato = santuario", Vector3(saved["checkpoint"][0], saved["checkpoint"][1], saved["checkpoint"][2]).distance_to(a.checkpoint_pos) < 0.001)
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
