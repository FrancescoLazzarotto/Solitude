extends Node3D
## Proiettile della sentinella: va dritto, si schiva (rotolo o spostandosi), si ferma contro i muri.

const SPEED := 8.5
const LIFETIME := 2.6
const HIT_RADIUS := 0.55

var direction := Vector3.FORWARD
var damage := 1
var target: Node3D
var shooter_rid: RID

var _life := 0.0


func _ready() -> void:
	add_to_group("projectiles")
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 10
	mesh.rings = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.2)
	mat.emission_energy_multiplier = 3.5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life >= LIFETIME:
		queue_free()
		return
	var from := global_position
	var to := from + direction * SPEED * delta
	# Muri e ostacoli: un raggio dal vecchio al nuovo punto (niente "tunneling" a velocita' alta).
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [shooter_rid]
	if target != null:
		q.exclude.append(target.get_rid())
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		Fx.burst(to, Color(1.0, 0.6, 0.3), 8, 0.6)
		queue_free()
		return
	global_position = to
	if target != null and not bool(target.call("is_dead")):
		var chest: Vector3 = target.global_position + Vector3(0, 0.8, 0)
		if chest.distance_to(global_position) < HIT_RADIUS:
			if bool(target.call("take_damage", damage, global_position - direction * 0.5)):
				Fx.burst(global_position, Color(1.0, 0.6, 0.3), 10, 0.7)
			queue_free()
