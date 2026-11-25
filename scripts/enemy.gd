extends CharacterBody3D
## Nemici. Tre tipi, stessa macchina a stati:
##  - guardian: piccolo automa. Ti nota, ti insegue, carica il colpo (telegrafato) e scatta.
##  - brute:    grosso e lento. Carica a lungo, colpisce forte e in ampio raggio; difficile da stordire.
##  - sentinel: torretta immobile. Ti mira (linea di tiro), poi spara un proiettile che si schiva.

signal defeated

enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD }

const ProjectileScript := preload("res://scripts/projectile.gd")

## Parametri per tipo. Il guardiano ha esattamente i valori originali.
const KINDS := {
	"guardian": {
		"hp": 3, "aggro": 7.0, "deaggro": 11.0, "speed": 3.0, "trigger": 2.6, "windup": 0.65,
		"lunge_speed": 11.0, "lunge_time": 0.22, "recover": 0.9, "stagger": 0.35, "knockback": 6.0,
		"hit_range": 1.5, "damage": 1, "scale": 1.0, "color": Color(0.32, 0.3, 0.36), "pitch": 1.0,
	},
	"brute": {
		"hp": 6, "aggro": 8.0, "deaggro": 12.0, "speed": 2.1, "trigger": 3.3, "windup": 1.0,
		"lunge_speed": 8.0, "lunge_time": 0.3, "recover": 1.4, "stagger": 0.18, "knockback": 3.0,
		"hit_range": 2.4, "damage": 2, "scale": 1.55, "color": Color(0.38, 0.16, 0.16), "pitch": 0.65,
	},
	"sentinel": {
		"hp": 2, "aggro": 12.0, "deaggro": 14.0, "speed": 0.0, "trigger": 0.0, "windup": 0.85,
		"lunge_speed": 0.0, "lunge_time": 0.0, "recover": 1.7, "stagger": 0.3, "knockback": 1.5,
		"hit_range": 0.0, "damage": 1, "scale": 1.0, "color": Color(0.25, 0.3, 0.4), "pitch": 1.4,
	},
}
const GRAVITY := 25.0
## Dislivello massimo per considerare il giocatore "sullo stesso livello". Deve stare ben sotto i 2 m
## dei gradini del livello (altopiano e terrazza): chi sta sotto non va ingaggiato, ma sulla meta' alta
## di una rampa si'.
const LEVEL_DY := 1.2
## Sotto questa quota un nemico e' caduto nel vuoto.
const FALL_Y := -2.5
const SENTINEL_RANGE := 11.0
const PROJECTILE_SPEED := 8.5

## Va impostato PRIMA di aggiungere il nodo alla scena.
var kind := "guardian"
var target: Node3D
var hp := 3
var max_hp := 3
var alive := true
var state: State = State.IDLE
var spawn_position := Vector3.ZERO

var _cfg: Dictionary
var _t := 0.0
var _lock_dir := Vector3.FORWARD
var _lock_aim := Vector3.FORWARD   ## direzione di tiro in 3D (verso il petto del bersaglio)
var _hit_done := false
var _visual: Node3D
var _model: Node3D
var _col: CollisionShape3D
var _body_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _warn: MeshInstance3D
var _flash_tween: Tween
var _body_color := Color(0.32, 0.3, 0.36)


func _ready() -> void:
	_cfg = KINDS.get(kind, KINDS["guardian"])
	max_hp = int(_cfg["hp"])
	hp = max_hp
	_body_color = _cfg["color"]
	add_to_group("enemies")
	spawn_position = global_position
	floor_snap_length = 0.4
	var sc: float = _cfg["scale"]

	_col = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45 * sc
	shape.height = 1.0 * sc if kind != "sentinel" else 1.2
	_col.shape = shape
	_col.position.y = shape.height * 0.5
	add_child(_col)

	_visual = Node3D.new()
	add_child(_visual)
	_model = Node3D.new()
	_model.scale = Vector3.ONE * sc
	_visual.add_child(_model)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = _body_color
	_body_mat.roughness = 0.7
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(1.0, 0.25, 0.2)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.25, 0.2)
	_eye_mat.emission_energy_multiplier = 2.0

	if kind == "sentinel":
		_build_sentinel_model()
	else:
		_build_walker_model()

	# Segnale a terra durante la carica: un anello (guardiano, bruto) o una linea di tiro (sentinella).
	_warn = MeshInstance3D.new()
	if kind == "sentinel":
		var line := BoxMesh.new()
		line.size = Vector3(0.14, 0.02, SENTINEL_RANGE)
		_warn.mesh = line
	else:
		var disc := CylinderMesh.new()
		var r: float = float(_cfg["hit_range"]) + 0.0
		disc.top_radius = maxf(1.5, r)
		disc.bottom_radius = disc.top_radius
		disc.height = 0.02
		_warn.mesh = disc
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(1.0, 0.2, 0.15, 0.35)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_warn.material_override = wm
	_warn.position.y = 0.04
	_warn.visible = false
	add_child(_warn)


func _build_walker_model() -> void:
	var body := BoxMesh.new()
	body.size = Vector3(0.9, 0.55, 1.1)
	_add_mesh(body, _body_mat, Vector3(0.0, 0.5, 0.0))
	var back := BoxMesh.new()
	back.size = Vector3(0.6, 0.3, 0.6)
	_add_mesh(back, _body_mat, Vector3(0.0, 0.9, 0.15))
	var eye := BoxMesh.new()
	eye.size = Vector3(0.5, 0.12, 0.08)
	_add_mesh(eye, _eye_mat, Vector3(0.0, 0.58, -0.56))
	for sx: float in [-0.5, 0.5]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.22
		wheel.bottom_radius = 0.22
		wheel.height = 0.16
		var mi := _add_mesh(wheel, _body_mat, Vector3(sx, 0.22, 0.0))
		mi.rotation_degrees.z = 90.0
	if kind == "brute":
		# Punte sulla schiena: si legge a colpo d'occhio che e' quello pericoloso.
		for sx: float in [-0.22, 0.0, 0.22]:
			var spike := PrismMesh.new()
			spike.size = Vector3(0.14, 0.34, 0.14)
			_add_mesh(spike, _body_mat, Vector3(sx, 1.18, 0.15))


func _build_sentinel_model() -> void:
	var base := CylinderMesh.new()
	base.top_radius = 0.38
	base.bottom_radius = 0.48
	base.height = 0.5
	_add_mesh(base, _body_mat, Vector3(0.0, 0.25, 0.0))
	var dome := SphereMesh.new()
	dome.radius = 0.4
	dome.height = 0.8
	_add_mesh(dome, _body_mat, Vector3(0.0, 0.85, 0.0))
	var eye := BoxMesh.new()
	eye.size = Vector3(0.3, 0.16, 0.12)
	_add_mesh(eye, _eye_mat, Vector3(0.0, 0.9, -0.36))
	for sx: float in [-0.3, 0.3]:
		var fin := PrismMesh.new()
		fin.size = Vector3(0.08, 0.4, 0.3)
		_add_mesh(fin, _body_mat, Vector3(sx, 0.75, 0.15))


func _physics_process(delta: float) -> void:
	if not alive:
		return
	if global_position.y < FALL_Y:
		_die()   # spinto o caduto nel vuoto: il santuario lo ripristina come tutti gli altri
		return
	_t += delta
	if is_on_floor():
		velocity.y = maxf(velocity.y, -1.0)
	else:
		velocity.y -= GRAVITY * delta

	var to := Vector3.ZERO
	var dist := INF
	if target != null and not bool(target.call("is_dead")):
		to = target.global_position - global_position
		var dy := to.y
		to.y = 0.0
		dist = to.length() if absf(dy) < LEVEL_DY else INF
	var dir := to.normalized() if dist < INF and dist > 0.001 else Vector3.ZERO
	var sentinel := kind == "sentinel"

	match state:
		State.IDLE:
			_damp(delta, 30.0)
			if dist < float(_cfg["aggro"]):
				_enter(State.CHASE)
		State.CHASE:
			if dist > float(_cfg["deaggro"]):
				_enter(State.IDLE)
			elif sentinel:
				# Immobile: osserva e, con linea di vista libera, inizia a mirare.
				_damp(delta, 40.0)
				_face(dir, delta)
				if dist <= SENTINEL_RANGE and _has_line_of_sight():
					_enter(State.WINDUP)
			else:
				_face(dir, delta)
				velocity.x = dir.x * float(_cfg["speed"])
				velocity.z = dir.z * float(_cfg["speed"])
				if dist < float(_cfg["trigger"]):
					_enter(State.WINDUP)
		State.WINDUP:
			var windup: float = _cfg["windup"]
			_damp(delta, 40.0)
			if _t < windup * 0.7 and dir != Vector3.ZERO:
				_face(dir, delta)
				_lock_dir = dir
				if sentinel:
					# Mira in 3D: dal "muso" al petto del bersaglio, cosi' funziona anche su rampe e dislivelli.
					_lock_aim = (target.global_position + Vector3(0, 0.8, 0) - (global_position + Vector3(0, 0.9, 0))).normalized()
			var k := clampf(_t / windup, 0.0, 1.0)
			_eye_mat.emission_energy_multiplier = lerpf(2.0, 9.0, k)
			_visual.scale = Vector3(1.0, lerpf(1.0, 0.8, k), 1.0) if not sentinel else Vector3.ONE
			if sentinel:
				_update_aim_line()
			if _t >= windup:
				if sentinel:
					_fire()
					_enter(State.RECOVER)
				else:
					_enter(State.ATTACK)
		State.ATTACK:
			velocity.x = _lock_dir.x * float(_cfg["lunge_speed"])
			velocity.z = _lock_dir.z * float(_cfg["lunge_speed"])
			if not _hit_done and dist < float(_cfg["hit_range"]):
				_hit_done = true
				target.call("take_damage", int(_cfg["damage"]), global_position)
			if _t >= float(_cfg["lunge_time"]):
				_enter(State.RECOVER)
		State.RECOVER:
			_damp(delta, 35.0)
			if _t >= float(_cfg["recover"]):
				_enter(State.CHASE)
		State.STAGGER:
			_damp(delta, 14.0)
			if _t >= float(_cfg["stagger"]):
				_enter(State.CHASE)

	move_and_slide()


func _enter(new_state: State) -> void:
	state = new_state
	_t = 0.0
	_hit_done = false
	_warn.visible = new_state == State.WINDUP
	if new_state == State.WINDUP:
		Audio.play(&"enemy_windup", global_position, -2.0, float(_cfg["pitch"]))
	elif new_state == State.ATTACK:
		Audio.play(&"enemy_lunge", global_position, 0.0, 0.8 if kind == "brute" else 1.0)
	if new_state != State.WINDUP:
		_eye_mat.emission_energy_multiplier = 2.0
		_visual.scale = Vector3.ONE


func _damp(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


func _face(dir: Vector3, delta: float) -> void:
	if dir == Vector3.ZERO:
		return
	_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-12.0 * delta))


## C'e' una linea di vista libera tra l'"occhio" della sentinella e il robot?
func _has_line_of_sight() -> bool:
	if target == null:
		return false
	var from := global_position + Vector3(0, 0.9, 0)
	var to := target.global_position + Vector3(0, 0.8, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid(), target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _update_aim_line() -> void:
	# La linea parte dalla sentinella e segue la direzione di tiro; si "blocca" quando il tiro e' fissato.
	_warn.rotation.y = atan2(-_lock_dir.x, -_lock_dir.z)
	_warn.position = _lock_dir * (SENTINEL_RANGE * 0.5) + Vector3(0, 0.04, 0)


func _fire() -> void:
	var shot := Node3D.new()
	shot.set_script(ProjectileScript)
	shot.direction = _lock_aim
	shot.damage = int(_cfg["damage"])
	shot.target = target
	shot.shooter_rid = get_rid()
	get_parent().add_child(shot)
	shot.global_position = global_position + Vector3(0, 0.9, 0) + _lock_aim * 0.6
	Audio.play(&"shot", global_position)
	Fx.burst(shot.global_position, Color(1.0, 0.6, 0.3), 8, 0.6)


func take_damage(amount: int, from_pos: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	_flash()
	var away := global_position - from_pos
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3.BACK
	velocity = away.normalized() * float(_cfg["knockback"])
	Fx.burst(global_position + Vector3(0, 0.7, 0), Color(1.0, 0.75, 0.4), 12)
	Fx.add_trauma(0.22)
	if hp <= 0:
		_die()
		return
	Audio.play(&"enemy_hurt", global_position, 0.0, 0.8 if kind == "brute" else 1.0)
	_enter(State.STAGGER)


func _die() -> void:
	alive = false
	state = State.DEAD
	Audio.play(&"enemy_die", global_position, 0.0, 0.8 if kind == "brute" else 1.0)
	Fx.burst(global_position + Vector3(0, 0.6, 0), Color(1.0, 0.35, 0.25), 26, 1.3)
	Fx.add_trauma(0.35)
	_warn.visible = false
	_col.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tw.tween_callback(func() -> void: _visual.visible = false)
	defeated.emit()


func reset() -> void:
	## Chiamato dal santuario: il nemico torna com'era all'inizio.
	hp = max_hp
	alive = true
	state = State.IDLE
	_t = 0.0
	velocity = Vector3.ZERO
	global_position = spawn_position
	_visual.rotation = Vector3.ZERO
	_visual.scale = Vector3.ONE
	_visual.visible = true
	_warn.visible = false
	_eye_mat.emission_energy_multiplier = 2.0
	_col.set_deferred("disabled", false)
	reset_physics_interpolation()


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_body_mat.albedo_color = Color(1.0, 0.9, 0.9)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_body_mat, "albedo_color", _body_color, 0.25)


func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_model.add_child(mi)
	return mi
