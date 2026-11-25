extends CharacterBody3D
## Il piccolo robot: movimento, rotolo, attacco con la spada, vita e stamina.

signal died
signal fell
signal stats_changed
signal hit_landed

enum State { MOVE, ATTACK, ROLL, HURT, DEAD, DRINK }

# ---------------------------------------------------------------------------
# VALORI DI "FEELING": cambiali per modificare la sensazione di gioco.
# ---------------------------------------------------------------------------
const WALK_SPEED := 5.0
const ACCEL := 42.0
const FRICTION := 55.0
const GRAVITY := 25.0

const ROLL_SPEED := 9.5
const ROLL_TIME := 0.42
const ROLL_IFRAMES := 0.30         ## secondi di invulnerabilità all'inizio del rotolo
const ROLL_COST := 25.0

const ATTACK_COST := 18.0
const ATTACK_TIME := 0.42
const ATTACK_HIT_TIME := 0.12      ## istante del colpo dentro l'animazione
const ATTACK_LUNGE_SPEED := 3.5
const ATTACK_RANGE := 2.2
const ATTACK_ARC_DOT := 0.3        ## 1.0 = solo davanti, 0 = semicerchio
const ATTACK_DAMAGE := 1
const ATTACK_CHAIN_TIME := 0.30    ## da qui si può concatenare un altro attacco
const ATTACK_CANCEL_TIME := 0.20   ## da qui si può annullare l'attacco con un rotolo
const AIM_ASSIST_RANGE := 3.2

const STAMINA_REGEN := 40.0
const STAMINA_REGEN_DELAY := 0.7
const INPUT_BUFFER := 0.15

const HURT_TIME := 0.25
const HURT_INVULN := 0.9
const KNOCKBACK := 7.0
const HIT_STOP := 0.06

const CAMERA_YAW := deg_to_rad(45.0)   ## deve coincidere con la camera del Main
const FALL_Y := -2.5
const SAFE_SAMPLE_INTERVAL := 0.1
const SAFE_HISTORY := 8
const SWORD_REST := Vector3(-50.0, 15.0, 0.0)
const FLASK_HEAL := 2               ## cuori curati da una fiaschetta
const DRINK_TIME := 0.7            ## tempo in cui si e' vulnerabili mentre si beve
const DRINK_MOVE_FACTOR := 0.3     ## si puo' camminare piano mentre si beve
const STEP_DISTANCE := 1.9         ## metri percorsi tra un passo e il successivo
const STEP_SOUNDS: Array[StringName] = [&"step", &"step2", &"step3", &"step4"]

var max_hp := 4
var hp := 4
var max_stamina := 100.0
var flasks := 3
var max_flasks := 3
var stamina := 100.0
var state: State = State.MOVE
var facing := Vector3(1.0, 0.0, 1.0).normalized()

var _state_time := 0.0
var _invuln_time := 0.0
var _stamina_delay := 0.0
var _buffer_action := &""
var _buffer_time := 0.0
var _roll_dir := Vector3.ZERO
var _hit_done := false
var _swing_flip := false
var _safe_history: Array[Vector3] = []
var _safe_timer := 0.0
var _step_dist := 0.0
var _step_index := 0

var _visual: Node3D
var _rig: Node3D
var _sword_pivot: Node3D
var _light: OmniLight3D
var _body_mat: StandardMaterial3D
var _swing_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	floor_snap_length = 0.4
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.1
	col.shape = shape
	col.position.y = 0.55
	add_child(col)

	_visual = Node3D.new()
	_visual.rotation.y = atan2(-facing.x, -facing.z)
	add_child(_visual)
	_rig = Node3D.new()
	_rig.position.y = 0.55
	_visual.add_child(_rig)

	_body_mat = _material(Color(0.78, 0.8, 0.84), 0.0)
	var dark_mat := _material(Color(0.18, 0.2, 0.25), 0.0)
	var glow_mat := _material(Color(0.3, 0.9, 1.0), 2.0)

	_add_mesh(_rig, _capsule(0.3, 0.7), _body_mat, Vector3(0.0, -0.15, 0.0))
	_add_mesh(_rig, _sphere(0.26), _body_mat, Vector3(0.0, 0.37, 0.0))
	var visor := BoxMesh.new()
	visor.size = Vector3(0.32, 0.1, 0.1)
	_add_mesh(_rig, visor, glow_mat, Vector3(0.0, 0.39, -0.2))
	var antenna := CylinderMesh.new()
	antenna.top_radius = 0.02
	antenna.bottom_radius = 0.02
	antenna.height = 0.25
	_add_mesh(_rig, antenna, dark_mat, Vector3(0.0, 0.73, 0.0))
	_add_mesh(_rig, _sphere(0.06), glow_mat, Vector3(0.0, 0.88, 0.0))

	# Spada: il perno è la "mano", la lama punta verso -Z.
	_sword_pivot = Node3D.new()
	_sword_pivot.position = Vector3(0.38, -0.05, -0.1)
	_sword_pivot.rotation_degrees = SWORD_REST
	_rig.add_child(_sword_pivot)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.07, 0.07, 0.85)
	_add_mesh(_sword_pivot, blade, _material(Color(0.8, 0.95, 1.0), 1.2), Vector3(0.0, 0.0, -0.5))
	var hilt := BoxMesh.new()
	hilt.size = Vector3(0.22, 0.08, 0.08)
	_add_mesh(_sword_pivot, hilt, dark_mat, Vector3(0.0, 0.0, -0.08))

	_light = OmniLight3D.new()
	_light.light_color = Color(0.5, 0.9, 1.0)
	_light.light_energy = 1.2
	_light.omni_range = 5.0
	_light.position.y = 1.2
	add_child(_light)


# --- Ciclo fisico ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	_state_time += delta
	_invuln_time = maxf(0.0, _invuln_time - delta)
	_buffer_time = maxf(0.0, _buffer_time - delta)
	_read_input_buffer()
	_regen_stamina(delta)

	match state:
		State.MOVE:
			_tick_move(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.ROLL:
			_tick_roll(delta)
		State.HURT:
			_tick_hurt(delta)
		State.DRINK:
			_tick_drink(delta)

	_apply_gravity(delta)
	move_and_slide()
	_track_safe_position(delta)
	if global_position.y < FALL_Y:
		fell.emit()
	_update_visual(delta)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= GRAVITY * delta


func _move_input() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Ruota secondo la camera, così "su" va verso l'alto dello schermo.
	return Vector3(v.x, 0.0, v.y).rotated(Vector3.UP, CAMERA_YAW)


func _read_input_buffer() -> void:
	if Input.is_action_just_pressed("attack"):
		_buffer_action = &"attack"
		_buffer_time = INPUT_BUFFER
	elif Input.is_action_just_pressed("heal"):
		_buffer_action = &"heal"
		_buffer_time = INPUT_BUFFER
	elif Input.is_action_just_pressed("roll"):
		_buffer_action = &"roll"
		_buffer_time = INPUT_BUFFER


func _regen_stamina(delta: float) -> void:
	if _stamina_delay > 0.0:
		_stamina_delay -= delta
		return
	if stamina < max_stamina:
		stamina = minf(max_stamina, stamina + STAMINA_REGEN * delta)
		stats_changed.emit()


# --- Stati -----------------------------------------------------------------

func _tick_move(delta: float) -> void:
	var dir := _move_input()
	var moving := dir.length_squared() > 0.01
	var target := dir * WALK_SPEED
	var rate := ACCEL if moving else FRICTION
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)
	if moving:
		facing = dir.normalized()
		_footsteps(delta)
	if _buffer_time > 0.0 and _buffer_action == &"heal":
		_start_drink()
	elif _buffer_time > 0.0 and stamina > 0.0:
		if _buffer_action == &"roll":
			_start_roll()
		elif _buffer_action == &"attack":
			_start_attack()


func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	_step_dist += Vector2(velocity.x, velocity.z).length() * delta
	if _step_dist >= STEP_DISTANCE:
		_step_dist = 0.0
		_step_index = (_step_index + 1) % STEP_SOUNDS.size()
		Audio.play(STEP_SOUNDS[_step_index], global_position, -4.0)


func _start_roll() -> void:
	_buffer_time = 0.0
	stamina = maxf(0.0, stamina - ROLL_COST)
	_stamina_delay = STAMINA_REGEN_DELAY
	var dir := _move_input()
	if dir.length_squared() < 0.01:
		dir = facing
	_roll_dir = dir.normalized()
	facing = _roll_dir
	state = State.ROLL
	_state_time = 0.0
	Audio.play(&"roll", global_position)
	stats_changed.emit()


func _tick_roll(_delta: float) -> void:
	var t := clampf(_state_time / ROLL_TIME, 0.0, 1.0)
	var speed := ROLL_SPEED * lerpf(1.0, 0.45, t)
	velocity.x = _roll_dir.x * speed
	velocity.z = _roll_dir.z * speed
	if _state_time >= ROLL_TIME:
		state = State.MOVE
		_state_time = 0.0


func _start_attack() -> void:
	_buffer_time = 0.0
	stamina = maxf(0.0, stamina - ATTACK_COST)
	_stamina_delay = STAMINA_REGEN_DELAY
	var dir := _move_input()
	if dir.length_squared() > 0.01:
		facing = dir.normalized()
	_assist_aim()
	state = State.ATTACK
	_state_time = 0.0
	_hit_done = false
	_swing_flip = not _swing_flip
	_play_swing()
	Audio.play(&"swing2" if _swing_flip else &"swing", global_position)
	stats_changed.emit()


func _tick_attack(delta: float) -> void:
	var lunge := ATTACK_LUNGE_SPEED if _state_time < 0.15 else 0.0
	velocity.x = move_toward(velocity.x, facing.x * lunge, ACCEL * 3.0 * delta)
	velocity.z = move_toward(velocity.z, facing.z * lunge, ACCEL * 3.0 * delta)

	if not _hit_done and _state_time >= ATTACK_HIT_TIME:
		_hit_done = true
		_do_hit()

	if _buffer_time > 0.0 and stamina > 0.0:
		if _buffer_action == &"roll" and _state_time > ATTACK_CANCEL_TIME:
			_start_roll()
			return
		if _buffer_action == &"attack" and _state_time > ATTACK_CHAIN_TIME:
			_start_attack()
			return
	if _state_time >= ATTACK_TIME:
		state = State.MOVE
		_state_time = 0.0


func _start_drink() -> void:
	_buffer_time = 0.0
	if flasks <= 0 or hp >= max_hp:
		return
	state = State.DRINK
	_state_time = 0.0
	Audio.play(&"drink", global_position)
	stats_changed.emit()


func _tick_drink(delta: float) -> void:
	# Si cammina piano e si e' vulnerabili: bere in mezzo a un combattimento e' una scommessa.
	var dir := _move_input()
	var target := dir * WALK_SPEED * DRINK_MOVE_FACTOR
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	if _state_time >= DRINK_TIME:
		flasks -= 1
		hp = mini(max_hp, hp + FLASK_HEAL)
		Audio.play(&"heal", global_position, -3.0)
		Fx.burst(global_position + Vector3(0, 0.9, 0), Color(0.5, 1.0, 0.6), 16, 0.7)
		state = State.MOVE
		_state_time = 0.0
		stats_changed.emit()


func _tick_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, FRICTION * 0.5 * delta)
	velocity.z = move_toward(velocity.z, 0.0, FRICTION * 0.5 * delta)
	if _state_time >= HURT_TIME:
		state = State.MOVE
		_state_time = 0.0


func _assist_aim() -> void:
	var best := AIM_ASSIST_RANGE
	for n: Node in get_tree().get_nodes_in_group("enemies"):
		if not n.get("alive"):
			continue
		var to: Vector3 = (n as Node3D).global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < best and dist > 0.01 and facing.dot(to / dist) > 0.2:
			best = dist
			facing = to / dist


func _do_hit() -> void:
	var hit_any := false
	for n: Node in get_tree().get_nodes_in_group("enemies"):
		if not n.get("alive"):
			continue
		var d: Vector3 = (n as Node3D).global_position - global_position
		var dy := d.y
		d.y = 0.0
		var dist := d.length()
		if dist > ATTACK_RANGE or absf(dy) > 1.6:
			continue
		if dist > 0.4 and facing.dot(d / dist) < ATTACK_ARC_DOT:
			continue
		n.call("take_damage", ATTACK_DAMAGE, global_position)
		Audio.play(&"hit_enemy", (n as Node3D).global_position)
		hit_any = true
	if hit_any:
		hit_landed.emit()
		_hit_stop(HIT_STOP)


func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.08
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


# --- Danni, vita, stamina --------------------------------------------------

func is_invulnerable() -> bool:
	return _invuln_time > 0.0 or (state == State.ROLL and _state_time < ROLL_IFRAMES)


func is_dead() -> bool:
	return state == State.DEAD


func take_damage(amount: int, from_pos: Vector3) -> bool:
	if state == State.DEAD or is_invulnerable():
		return false
	hp = maxi(0, hp - amount)
	var away := global_position - from_pos
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = -facing
	velocity = away.normalized() * KNOCKBACK
	_invuln_time = HURT_INVULN
	_flash()
	Audio.play(&"hit_player", global_position)
	Fx.burst(global_position + Vector3(0, 0.8, 0), Color(1.0, 0.3, 0.3), 16)
	Fx.add_trauma(0.5)
	stats_changed.emit()
	if hp <= 0:
		_die()
		return true
	state = State.HURT
	_state_time = 0.0
	return true


func _die() -> void:
	state = State.DEAD
	Audio.play(&"death", global_position)
	_rig.rotation.x = 0.0
	var tw := create_tween()
	tw.tween_property(_rig, "rotation_degrees:z", 90.0, 0.35)
	died.emit()


func revive(pos: Vector3) -> void:
	hp = max_hp
	stamina = max_stamina
	state = State.MOVE
	_state_time = 0.0
	_invuln_time = 1.0
	_rig.rotation = Vector3.ZERO
	teleport_to(pos)
	stats_changed.emit()


func teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	# Il punto di arrivo è sicuro per definizione: serve se cadi subito dopo.
	_safe_history.clear()
	_safe_history.append(pos)
	reset_physics_interpolation()


func heal_full() -> void:
	hp = max_hp
	flasks = max_flasks
	stamina = max_stamina
	stats_changed.emit()


func add_max_hp(amount: int) -> void:
	max_hp += amount
	hp = max_hp
	stats_changed.emit()


func add_max_stamina(amount: float) -> void:
	max_stamina += amount
	stamina = max_stamina
	stats_changed.emit()


func fall_recover(fallback: Vector3) -> void:
	## Caduto nel vuoto: perdi 1 di vita e torni sull'ultimo punto sicuro.
	hp = maxi(0, hp - 1)
	Audio.play(&"fall", global_position)
	stats_changed.emit()
	if hp <= 0:
		velocity = Vector3.ZERO
		_die()
		return
	teleport_to(get_safe_position(fallback))
	_invuln_time = 1.0


func set_lantern(on: bool) -> void:
	_light.light_color = Color(1.0, 0.85, 0.55) if on else Color(0.5, 0.9, 1.0)
	_light.light_energy = 2.4 if on else 1.2
	_light.omni_range = 9.0 if on else 5.0


# --- Punto sicuro per i salvataggi dalla caduta -----------------------------

func get_safe_position(fallback: Vector3) -> Vector3:
	if _safe_history.is_empty():
		return fallback
	return _safe_history[0]


func _track_safe_position(delta: float) -> void:
	_safe_timer -= delta
	if _safe_timer > 0.0 or not is_on_floor():
		return
	_safe_timer = SAFE_SAMPLE_INTERVAL
	if not _has_ground_around(global_position):
		return
	_safe_history.append(global_position)
	if _safe_history.size() > SAFE_HISTORY:
		_safe_history.pop_front()


func _has_ground_around(pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for off: Vector3 in [Vector3(0.7, 0, 0), Vector3(-0.7, 0, 0), Vector3(0, 0, 0.7), Vector3(0, 0, -0.7)]:
		var q := PhysicsRayQueryParameters3D.create(pos + off + Vector3.UP * 0.5, pos + off + Vector3.DOWN * 1.2)
		q.exclude = [get_rid()]
		if space.intersect_ray(q).is_empty():
			return false
	return true


# --- Aspetto ---------------------------------------------------------------

func _update_visual(delta: float) -> void:
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-facing.x, -facing.z), 1.0 - exp(-18.0 * delta))
	if state == State.ROLL:
		_rig.rotation.x = -TAU * clampf(_state_time / ROLL_TIME, 0.0, 1.0)
	else:
		_rig.rotation.x = 0.0
	_visual.visible = _invuln_time <= 0.0 or state == State.ROLL or int(_invuln_time * 16.0) % 2 == 0


func _play_swing() -> void:
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	var from := -85.0 if _swing_flip else 85.0
	_sword_pivot.rotation_degrees = Vector3(0.0, from, 0.0)
	_swing_tween = create_tween()
	_swing_tween.tween_property(_sword_pivot, "rotation_degrees", Vector3(0.0, -from, 0.0), 0.16) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(_sword_pivot, "rotation_degrees", SWORD_REST, 0.22)


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_body_mat.albedo_color = Color(1.0, 0.35, 0.3)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_body_mat, "albedo_color", Color(0.78, 0.8, 0.84), 0.3)


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return m


func _sphere(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return m


func _material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission_energy
	return m
