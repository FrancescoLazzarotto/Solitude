extends Node3D
## Il Cartografo – prima fetta giocabile.
## Percorso: santuario -> rampa -> altopiano con guardiani -> lanterna -> ponte nascosto
## -> forziere dall'altra parte -> leva -> cancello-scorciatoia che riporta al santuario.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const InteractableScript := preload("res://scripts/interactable.gd")
const HudScript := preload("res://scripts/hud.gd")
const Paths := preload("res://scripts/paths.gd")
const NotebookScript := preload("res://scripts/notebook.gd")
const LevelData := preload("res://scripts/level_data.gd")

const LEVEL_PATH := "res://levels/slice.json"

# --- Camera (prospettiva con angolo fisso, alla Tunic) ---
const CAMERA_PITCH_DEG := 50.0
const CAMERA_YAW_DEG := 45.0       ## deve coincidere con CAMERA_YAW di player.gd
const CAMERA_DISTANCE := 17.0
const CAMERA_FOV := 38.0
const CAMERA_FOLLOW := 7.0

var player: CharacterBody3D
var camera: Camera3D
var hud: CanvasLayer
var notebook: CanvasLayer

var enemies: Array[CharacterBody3D] = []
var checkpoint_pos := Vector3.ZERO
var has_lantern := false
var gate_open := false

var shrine_it: Node3D
var stone_it: Node3D
var chest1_it: Node3D
var chest2_it: Node3D
var lever_it: Node3D
var gate_hint_it: Node3D

var _level: Dictionary = {}
var _props: Dictionary = {}
var _shrine_pos := Vector3.ZERO
var _bridge_center := Vector3.ZERO
var _cam_offset := Vector3.ZERO
var _cam_focus := Vector3.ZERO
var _nearest: Node3D
var _dying := false
var _grid_tex: ImageTexture
var _shrine_light: OmniLight3D
var _gate_body: StaticBody3D
var _gate_col: CollisionShape3D
var _bridge_col: CollisionShape3D
var _bridge_mesh: MeshInstance3D
var _bridge_mat: StandardMaterial3D


func _ready() -> void:
	_level = LevelData.load_level(LEVEL_PATH)
	if _level.is_empty():
		return
	_props = _level["props"]
	_shrine_pos = LevelData.v3(_props["shrine"]["pos"])
	checkpoint_pos = LevelData.v3(_props["shrine"]["spawn"])
	_setup_input()
	_grid_tex = _make_grid_texture()
	_build_environment()
	_build_level()
	_build_props()
	_build_player()
	_build_enemies()
	_build_camera()
	_build_ui()


# ===========================================================================
# INPUT
# ===========================================================================

func _setup_input() -> void:
	_add_action(&"move_up", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add_action(&"move_down", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add_action(&"move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_action(&"move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_add_action(&"interact", [KEY_E], [JOY_BUTTON_A], [])
	_add_action(&"attack", [KEY_J], [JOY_BUTTON_X], [], [MOUSE_BUTTON_LEFT])
	_add_action(&"roll", [KEY_SPACE, KEY_SHIFT], [JOY_BUTTON_B], [])
	_add_action(&"heal", [KEY_Q], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_add_action(&"toggle_notebook", [KEY_TAB], [JOY_BUTTON_Y], [])


func _add_action(action: StringName, keys: Array, buttons: Array, axes: Array, mouse: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.3)
	for k: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k as Key
		InputMap.action_add_event(action, ev)
	for b: int in buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b as JoyButton
		InputMap.action_add_event(action, ev)
	for a: Array in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = a[0] as JoyAxis
		ev.axis_value = a[1]
		InputMap.action_add_event(action, ev)
	for m: int in mouse:
		var ev := InputEventMouseButton.new()
		ev.button_index = m as MouseButton
		InputMap.action_add_event(action, ev)


# ===========================================================================
# AMBIENTE E LIVELLO
# ===========================================================================

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.52, 0.65)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.11)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


func _build_level() -> void:
	var mats := {}
	for key: String in _level["materials"]:
		mats[key] = _world_mat(LevelData.color(_level["materials"][key]))
	for sd: Dictionary in _level["solids"]:
		_box(LevelData.v3(sd["min"]), LevelData.v3(sd["max"]), mats[sd["mat"]], bool(sd.get("collide", true)))
	# Rampe (cuneo solido: niente spazi sotto)
	for wd: Dictionary in _level["wedges"]:
		_add_wedge(LevelData.v3(wd["start"]), LevelData.v3(wd["end"]), float(wd["width"]), mats[wd["mat"]])


func _build_props() -> void:
	_build_shrine()
	_build_stone()
	_build_chests()
	_build_gate_and_lever()
	_build_hidden_bridge()


func _build_shrine() -> void:
	var root := Node3D.new()
	root.position = _shrine_pos
	add_child(root)
	var body := StaticBody3D.new()
	body.add_child(_box_collision(Vector3(0.9, 1.6, 0.9), Vector3(0, 0.8, 0)))
	root.add_child(body)
	var base := BoxMesh.new()
	base.size = Vector3(1.4, 0.3, 1.4)
	_mesh(root, base, _mat(Color(0.4, 0.42, 0.48)), Vector3(0, 0.15, 0))
	var pillar := BoxMesh.new()
	pillar.size = Vector3(0.7, 1.5, 0.7)
	_mesh(root, pillar, _mat(Color(0.5, 0.52, 0.58)), Vector3(0, 0.95, 0))
	var orb := SphereMesh.new()
	orb.radius = 0.22
	orb.height = 0.44
	_mesh(root, orb, _mat(Color(0.4, 1.0, 0.9), 3.0), Vector3(0, 1.95, 0))
	_shrine_light = OmniLight3D.new()
	_shrine_light.light_color = Color(0.4, 1.0, 0.9)
	_shrine_light.light_energy = 1.6
	_shrine_light.omni_range = 6.0
	_shrine_light.position = Vector3(0, 2.0, 0)
	root.add_child(_shrine_light)
	shrine_it = _make_interactable(root, Vector3.ZERO, "Riposa al santuario", float(_props["shrine"]["radius"]), use_shrine)


func _build_stone() -> void:
	var root := Node3D.new()
	root.position = LevelData.v3(_props["stone"]["pos"])
	root.rotation_degrees.y = float(_props["stone"]["yaw"])
	add_child(root)
	var body := StaticBody3D.new()
	body.add_child(_box_collision(Vector3(1.4, 2.4, 0.6), Vector3(0, 1.2, 0)))
	root.add_child(body)
	var slab := BoxMesh.new()
	slab.size = Vector3(1.4, 2.4, 0.6)
	_mesh(root, slab, _mat(Color(0.42, 0.44, 0.48)), Vector3(0, 1.2, 0))
	var glow := _mat(Color(0.3, 0.9, 1.0), 1.8)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.14
	ring.outer_radius = 0.26
	var r := _mesh(root, ring, glow, Vector3(0, 1.95, 0.32))
	r.rotation_degrees.x = 90.0
	var tri := PrismMesh.new()
	tri.size = Vector3(0.6, 0.5, 0.06)
	_mesh(root, tri, glow, Vector3(0, 1.2, 0.32))
	var dia := BoxMesh.new()
	dia.size = Vector3(0.36, 0.36, 0.06)
	var d := _mesh(root, dia, glow, Vector3(0, 0.5, 0.32))
	d.rotation_degrees.z = 45.0
	stone_it = _make_interactable(root, Vector3(0, 0, 1.2), "Esamina", float(_props["stone"]["radius"]), func() -> void:
		hud.toast("Tre simboli luminosi: un anello, un triangolo e un rombo.\nMeglio annotarli nel taccuino (Tab).", 6.0))


func _build_chests() -> void:
	# Posizione, orientamento e raggio vengono dai dati; colore e azione sono "colla" di gioco.
	var glue := {
		"lantern": [Color(1.0, 0.8, 0.4), open_lantern_chest],
		"heart": [Color(1.0, 0.4, 0.5), open_heart_chest],
	}
	for c: Dictionary in _props["chests"]:
		var id: String = c["id"]
		var g: Array = glue[id]
		var it := _make_chest(LevelData.v3(c["pos"]), float(c["yaw"]), float(c["radius"]), g[0], "Apri il forziere", g[1])
		if id == "lantern":
			chest1_it = it
		else:
			chest2_it = it


func _make_chest(pos: Vector3, yaw: float, radius: float, glow_color: Color, prompt: String, cb: Callable) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	var body := StaticBody3D.new()
	body.add_child(_box_collision(Vector3(0.9, 0.5, 0.6), Vector3(0, 0.25, 0)))
	root.add_child(body)
	var wood := _mat(Color(0.5, 0.33, 0.2))
	var trim := _mat(Color(0.85, 0.72, 0.4), 0.4)
	var base := BoxMesh.new()
	base.size = Vector3(0.9, 0.5, 0.6)
	_mesh(root, base, wood, Vector3(0, 0.25, 0))
	var lid_pivot := Node3D.new()
	lid_pivot.name = "LidPivot"
	lid_pivot.position = Vector3(0, 0.5, -0.3)
	root.add_child(lid_pivot)
	var lid := BoxMesh.new()
	lid.size = Vector3(0.94, 0.22, 0.64)
	_mesh(lid_pivot, lid, wood, Vector3(0, 0.11, 0.3))
	var band := BoxMesh.new()
	band.size = Vector3(0.14, 0.26, 0.68)
	_mesh(lid_pivot, band, trim, Vector3(0, 0.11, 0.3))
	var light := OmniLight3D.new()
	light.name = "ChestLight"
	light.light_color = glow_color
	light.light_energy = 1.3
	light.omni_range = 5.0
	light.position = Vector3(0, 1.0, 0.3)
	root.add_child(light)
	return _make_interactable(root, Vector3(0, 0, 0.5), prompt, radius, cb)


func _open_chest_visual(it: Node3D) -> void:
	var root := it.get_parent() as Node3D
	var pivot := root.get_node("LidPivot") as Node3D
	var tw := create_tween()
	tw.tween_property(pivot, "rotation_degrees:x", -105.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Sfera luminosa che sale
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	orb.mesh = sm
	orb.material_override = _mat(Color(1.0, 0.95, 0.7), 4.0)
	orb.position = Vector3(0, 0.6, 0.3)
	root.add_child(orb)
	var tw2 := create_tween()
	tw2.tween_property(orb, "position:y", 1.8, 0.9).set_ease(Tween.EASE_OUT)
	tw2.tween_property(orb, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	tw2.tween_callback(orb.queue_free)
	it.set("enabled", false)
	Fx.burst(root.global_position + Vector3(0, 0.7, 0), Color(1.0, 0.9, 0.5), 22, 0.9)
	(root.get_node("ChestLight") as OmniLight3D).light_energy = 0.4


func _build_gate_and_lever() -> void:
	var iron := _mat(Color(0.3, 0.22, 0.22))
	var gate: Dictionary = _props["gate"]
	_gate_body = _box(LevelData.v3(gate["min"]), LevelData.v3(gate["max"]), iron)
	_gate_col = _gate_body.get_child(0) as CollisionShape3D
	var lock := BoxMesh.new()
	lock.size = Vector3(0.7, 0.7, 0.2)
	_mesh(_gate_body, lock, _mat(Color(1.0, 0.25, 0.2), 2.5), Vector3(0, 0.6, 0.2))
	gate_hint_it = _make_interactable(self, LevelData.v3(gate["hint"]), "Esamina il cancello", 2.4, func() -> void:
		hud.toast("Il cancello è sbarrato. Non si apre da questo lato.", 4.0))

	var lever_root := Node3D.new()
	lever_root.position = LevelData.v3(_props["lever"]["pos"])
	add_child(lever_root)
	var lbase := BoxMesh.new()
	lbase.size = Vector3(0.7, 0.4, 0.7)
	_mesh(lever_root, lbase, _mat(Color(0.4, 0.42, 0.48)), Vector3(0, 0.2, 0))
	var pivot := Node3D.new()
	pivot.name = "LeverPivot"
	pivot.position = Vector3(0, 0.4, 0)
	pivot.rotation_degrees.x = 30.0
	lever_root.add_child(pivot)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.05
	stick.bottom_radius = 0.05
	stick.height = 0.9
	_mesh(pivot, stick, _mat(Color(0.7, 0.7, 0.75)), Vector3(0, 0.45, 0))
	var knob := SphereMesh.new()
	knob.radius = 0.12
	knob.height = 0.24
	_mesh(pivot, knob, _mat(Color(1.0, 0.25, 0.2), 2.0), Vector3(0, 0.95, 0))
	lever_it = _make_interactable(lever_root, Vector3(0, 0, 0.8), "Tira la leva", float(_props["lever"]["radius"]), pull_lever)


func _build_hidden_bridge() -> void:
	var bmin := LevelData.v3(_props["bridge"]["min"])
	var bmax := LevelData.v3(_props["bridge"]["max"])
	_bridge_center = (bmin + bmax) * 0.5
	var body := StaticBody3D.new()
	body.position = _bridge_center
	_bridge_col = _box_collision(bmax - bmin, Vector3.ZERO)
	_bridge_col.disabled = true
	body.add_child(_bridge_col)
	add_child(body)
	_bridge_mat = StandardMaterial3D.new()
	_bridge_mat.albedo_color = Color(0.4, 0.95, 1.0, 0.0)
	_bridge_mat.emission_enabled = true
	_bridge_mat.emission = Color(0.4, 0.95, 1.0)
	_bridge_mat.emission_energy_multiplier = 1.5
	_bridge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var bm := BoxMesh.new()
	bm.size = bmax - bmin
	_bridge_mesh = _mesh(body, bm, _bridge_mat, Vector3.ZERO)
	_bridge_mesh.visible = false


# ===========================================================================
# GIOCATORE, NEMICI, CAMERA, UI
# ===========================================================================

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.position = LevelData.v3(_props["player_start"])
	add_child(player)
	player.connect("died", _on_player_died)
	player.connect("fell", _on_player_fell)
	player.connect("stats_changed", _sync_hud)


func _build_enemies() -> void:
	for e: Dictionary in _props["enemies"]:
		_spawn_enemy(LevelData.v3(e["pos"]), str(e.get("kind", "guardian")))


func _spawn_enemy(pos: Vector3, kind := "guardian") -> CharacterBody3D:
	var e := CharacterBody3D.new()
	e.set_script(EnemyScript)
	e.kind = kind
	e.position = pos
	e.target = player
	add_child(e)
	enemies.append(e)
	return e


func _build_camera() -> void:
	var pitch := deg_to_rad(CAMERA_PITCH_DEG)
	var yaw := deg_to_rad(CAMERA_YAW_DEG)
	var horiz := CAMERA_DISTANCE * cos(pitch)
	_cam_offset = Vector3(sin(yaw) * horiz, CAMERA_DISTANCE * sin(pitch), cos(yaw) * horiz)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAMERA_FOV
	camera.near = 0.3
	camera.far = 120.0
	camera.rotation_degrees = Vector3(-CAMERA_PITCH_DEG, CAMERA_YAW_DEG, 0.0)
	# La camera si muove in _process: niente interpolazione fisica su di lei.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	_snap_camera()


func _snap_camera() -> void:
	_cam_focus = player.global_position + Vector3(0, 0.8, 0)
	camera.global_position = _cam_focus + _cam_offset


func _build_ui() -> void:
	hud = CanvasLayer.new()
	hud.set_script(HudScript)
	add_child(hud)
	notebook = CanvasLayer.new()
	notebook.set_script(NotebookScript)
	add_child(notebook)
	_sync_hud()
	if not Paths.is_test():
		hud.fade_in_from_black(0.35, 1.0)


func _sync_hud() -> void:
	hud.set_hp(player.hp, player.max_hp)
	hud.set_stamina(player.stamina, player.max_stamina)
	hud.set_flasks(player.flasks, player.max_flasks)


# ===========================================================================
# CICLO DI GIOCO
# ===========================================================================

func _process(delta: float) -> void:
	var target_pos := player.get_global_transform_interpolated().origin + Vector3(0, 0.8, 0)
	_cam_focus = _cam_focus.lerp(target_pos, 1.0 - exp(-CAMERA_FOLLOW * delta))
	camera.global_position = _cam_focus + _cam_offset + Fx.shake_offset()
	Audio.set_listener(player.global_position + Vector3(0, 1.0, 0), deg_to_rad(CAMERA_YAW_DEG))
	_update_interaction()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _nearest != null and not _dying:
		_nearest.call("interact")


func _update_interaction() -> void:
	var previous := _nearest
	_nearest = null
	if not _dying and not bool(player.call("is_dead")):
		var best := INF
		for n: Node in get_tree().get_nodes_in_group("interactables"):
			if not bool(n.get("enabled")):
				continue
			var d: Vector3 = (n as Node3D).global_position - player.global_position
			if absf(d.y) > 2.5:
				continue
			d.y = 0.0
			var dist := d.length()
			if dist <= float(n.get("radius")) and dist < best:
				best = dist
				_nearest = n as Node3D
	hud.set_prompt("[E] " + str(_nearest.get("prompt")) if _nearest != null else "")
	if _nearest != null and _nearest != previous:
		Audio.play(&"blip", null, -14.0)


func _on_player_died() -> void:
	if _dying:
		return
	_dying = true
	await get_tree().create_timer(0.6).timeout
	await hud.fade(1.0, 0.6)
	respawn_at_checkpoint()
	await hud.fade(0.0, 0.7)
	_dying = false


func respawn_at_checkpoint() -> void:
	reset_enemies()
	player.revive(checkpoint_pos)
	_snap_camera()


func _on_player_fell() -> void:
	player.fall_recover(checkpoint_pos)
	_snap_camera()
	if not bool(player.call("is_dead")):
		hud.toast("Sei caduto nel vuoto…", 2.0)


func reset_enemies() -> void:
	for e in enemies:
		e.call("reset")


# ===========================================================================
# EVENTI DI GIOCO (chiamati dagli interattivi)
# ===========================================================================

func use_shrine() -> void:
	checkpoint_pos = LevelData.v3(_props["shrine"]["spawn"])
	reset_enemies()
	player.heal_full()
	hud.toast("Santuario: salute ripristinata.\nI nemici sono tornati. Se cadi, ripartirai da qui.", 4.5)
	Audio.play(&"shrine_rest", _shrine_pos)
	Fx.burst(_shrine_pos + Vector3(0, 1.9, 0), Color(0.4, 1.0, 0.9), 22, 0.8)
	Audio.play(&"heal", player.global_position, -4.0)
	var tw := create_tween()
	tw.tween_property(_shrine_light, "light_energy", 5.0, 0.2)
	tw.tween_property(_shrine_light, "light_energy", 1.6, 0.8)


func open_lantern_chest() -> void:
	_open_chest_visual(chest1_it)
	has_lantern = true
	player.set_lantern(true)
	hud.toast("Hai trovato la LANTERNA.\nOra vedi i sentieri che l'oscurità nascondeva.", 5.0)
	Audio.play(&"chest_open", chest1_it.global_position)
	Audio.play(&"lantern_on", player.global_position, -3.0)
	_reveal_bridge()


func _reveal_bridge() -> void:
	_bridge_col.set_deferred("disabled", false)
	_bridge_mesh.visible = true
	var tw := create_tween()
	tw.tween_property(_bridge_mat, "albedo_color:a", 0.8, 1.5)
	Audio.play(&"bridge_reveal", Vector3(_bridge_center.x, 2.0, _bridge_center.z))


func open_heart_chest() -> void:
	_open_chest_visual(chest2_it)
	player.add_max_hp(1)
	player.add_max_stamina(20.0)
	hud.toast("Cuore di rame: salute massima +1, stamina massima +20.", 5.0)
	Audio.play(&"chest_open", chest2_it.global_position)
	Audio.play(&"item_get", player.global_position, -3.0)


func pull_lever() -> void:
	if gate_open:
		return
	gate_open = true
	lever_it.set("enabled", false)
	gate_hint_it.set("enabled", false)
	var pivot := lever_it.get_parent().get_node("LeverPivot") as Node3D
	create_tween().tween_property(pivot, "rotation_degrees:x", -30.0, 0.3)
	_gate_col.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(_gate_body, "position:y", -2.8, 1.4).set_trans(Tween.TRANS_QUAD)
	hud.toast("Un cancello si apre, lontano.\nUna scorciatoia verso il santuario.", 4.5)
	Audio.play(&"lever", lever_it.global_position)
	Audio.play(&"gate_open", _gate_body.global_position, 0.0)


# ===========================================================================
# UTILITÀ DI COSTRUZIONE
# ===========================================================================

func _make_interactable(parent: Node3D, local_pos: Vector3, prompt: String, radius: float, cb: Callable) -> Node3D:
	var it := Node3D.new()
	it.set_script(InteractableScript)
	it.position = local_pos
	it.prompt = prompt
	it.radius = radius
	it.on_interact = cb
	parent.add_child(it)
	return it


func _mat(color: Color, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m


func _world_mat(tint: Color) -> StandardMaterial3D:
	## Materiale con griglia di piastrelle in coordinate-mondo (funziona anche su rampe e muri).
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = _grid_tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.roughness = 0.85
	return m


func _make_grid_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var edge := x < 2 or y < 2
			var c := 0.78 if edge else 1.0
			var n := 0.96 + 0.04 * sin(float(x) * 0.7) * sin(float(y) * 0.9)
			img.set_pixel(x, y, Color(c * n, c * n, c * n, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(a: Vector3, b: Vector3, mat: Material, collide := true) -> StaticBody3D:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var size := hi - lo
	var body := StaticBody3D.new()
	body.position = (lo + hi) * 0.5
	if collide:
		body.add_child(_box_collision(size, Vector3.ZERO))
	var bm := BoxMesh.new()
	bm.size = size
	_mesh(body, bm, mat, Vector3.ZERO)
	add_child(body)
	return body


func _box_collision(size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	return cs


func _add_wedge(start: Vector3, end: Vector3, width: float, mat: Material) -> StaticBody3D:
	## Cuneo (rampa solida): parte da `start` (a terra) e sale fino a `end` (in alto).
	var h := end - start
	h.y = 0.0
	var side := h.normalized().cross(Vector3.UP) * (width * 0.5)
	var base_end := Vector3(end.x, start.y, end.z)
	var p: Array[Vector3] = [start - side, start + side, end - side, end + side, base_end - side, base_end + side]
	var center := Vector3.ZERO
	for v in p:
		center += v
	center /= p.size()
	var tris := [[0, 1, 3], [0, 3, 2], [2, 3, 5], [2, 5, 4], [0, 4, 5], [0, 5, 1], [0, 2, 4], [1, 5, 3]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t: Array in tris:
		var a: Vector3 = p[t[0]]
		var b: Vector3 = p[t[1]]
		var c: Vector3 = p[t[2]]
		var cross := (b - a).cross(c - a)
		var outward := (a + b + c) / 3.0 - center
		# In Godot la faccia frontale è in senso orario: il prodotto vettoriale punta verso l'interno.
		if cross.dot(outward) > 0.0:
			var tmp := b
			b = c
			c = tmp
			cross = -cross
		var n := -cross.normalized()
		for v: Vector3 in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(v)
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(p)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body
