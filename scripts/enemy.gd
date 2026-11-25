extends CharacterBody3D
## Guardiano: un piccolo automa ostile. Ti nota, ti insegue, carica il colpo (telegrafato) e scatta.

signal defeated

enum State { IDLE, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD }

const MAX_HP := 3
const AGGRO_RANGE := 7.0
const DEAGGRO_RANGE := 11.0
const CHASE_SPEED := 3.0
const ATTACK_TRIGGER_DIST := 2.6
const WINDUP_TIME := 0.65          ## il tempo che hai per schivare
const LUNGE_SPEED := 11.0
const LUNGE_TIME := 0.22
const RECOVER_TIME := 0.9          ## dopo l'attacco è vulnerabile
const STAGGER_TIME := 0.35
const KNOCKBACK := 6.0
const HIT_RANGE := 1.5
const DAMAGE := 1
const GRAVITY := 25.0

var target: Node3D
var hp := MAX_HP
var alive := true
var state: State = State.IDLE
var spawn_position := Vector3.ZERO

var _t := 0.0
var _lock_dir := Vector3.FORWARD
var _hit_done := false
var _visual: Node3D
var _col: CollisionShape3D
var _body_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D
var _warn: MeshInstance3D
var _flash_tween: Tween

const BODY_COLOR := Color(0.32, 0.3, 0.36)


func _ready() -> void:
	add_to_group("enemies")
	spawn_position = global_position
	floor_snap_length = 0.4

	_col = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.0
	_col.shape = shape
	_col.position.y = 0.5
	add_child(_col)

	_visual = Node3D.new()
	add_child(_visual)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = BODY_COLOR
	_body_mat.roughness = 0.7
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(1.0, 0.25, 0.2)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.25, 0.2)
	_eye_mat.emission_energy_multiplier = 2.0

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

	# Anello di avvertimento a terra durante la carica dell'attacco.
	_warn = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.5
	disc.bottom_radius = 1.5
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


func _physics_process(delta: float) -> void:
	if not alive:
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
		dist = to.length() if absf(dy) < 2.2 else INF
	var dir := to.normalized() if dist < INF and dist > 0.001 else Vector3.ZERO

	match state:
		State.IDLE:
			_damp(delta, 30.0)
			if dist < AGGRO_RANGE:
				_enter(State.CHASE)
		State.CHASE:
			if dist > DEAGGRO_RANGE:
				_enter(State.IDLE)
			else:
				_face(dir, delta)
				velocity.x = dir.x * CHASE_SPEED
				velocity.z = dir.z * CHASE_SPEED
				if dist < ATTACK_TRIGGER_DIST:
					_enter(State.WINDUP)
		State.WINDUP:
			_damp(delta, 40.0)
			if _t < WINDUP_TIME * 0.7 and dir != Vector3.ZERO:
				_face(dir, delta)
				_lock_dir = dir
			var k := clampf(_t / WINDUP_TIME, 0.0, 1.0)
			_eye_mat.emission_energy_multiplier = lerpf(2.0, 9.0, k)
			_visual.scale = Vector3(1.0, lerpf(1.0, 0.8, k), 1.0)
			if _t >= WINDUP_TIME:
				_enter(State.ATTACK)
		State.ATTACK:
			velocity.x = _lock_dir.x * LUNGE_SPEED
			velocity.z = _lock_dir.z * LUNGE_SPEED
			if not _hit_done and dist < HIT_RANGE:
				_hit_done = true
				target.call("take_damage", DAMAGE, global_position)
			if _t >= LUNGE_TIME:
				_enter(State.RECOVER)
		State.RECOVER:
			_damp(delta, 35.0)
			if _t >= RECOVER_TIME:
				_enter(State.CHASE)
		State.STAGGER:
			_damp(delta, 14.0)
			if _t >= STAGGER_TIME:
				_enter(State.CHASE)

	move_and_slide()


func _enter(new_state: State) -> void:
	state = new_state
	_t = 0.0
	_hit_done = false
	_warn.visible = new_state == State.WINDUP
	if new_state == State.WINDUP:
		Audio.play(&"enemy_windup", global_position, -2.0)
	elif new_state == State.ATTACK:
		Audio.play(&"enemy_lunge", global_position)
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


func take_damage(amount: int, from_pos: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	_flash()
	var away := global_position - from_pos
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3.BACK
	velocity = away.normalized() * KNOCKBACK
	if hp <= 0:
		_die()
		return
	Audio.play(&"enemy_hurt", global_position)
	_enter(State.STAGGER)


func _die() -> void:
	alive = false
	state = State.DEAD
	Audio.play(&"enemy_die", global_position)
	_warn.visible = false
	_col.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tw.tween_callback(func() -> void: _visual.visible = false)
	defeated.emit()


func reset() -> void:
	## Chiamato dal santuario: il nemico torna com'era all'inizio.
	hp = MAX_HP
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
	_flash_tween.tween_property(_body_mat, "albedo_color", BODY_COLOR, 0.25)


func _add_mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_visual.add_child(mi)
	return mi
