extends Node
## Effetti visivi di impatto (autoload "Fx"): scintille e scuotimento della camera.
## Poche CPUParticles3D riusate a rotazione: nessuna allocazione durante il gioco.

const POOL_SIZE := 8
const TRAUMA_DECAY := 1.8          ## quanto in fretta passa lo scuotimento (1/s)
const SHAKE_AMPLITUDE := 0.32      ## metri di spostamento massimo della camera

## Contatori per i test.
var stats: Dictionary = {}
## 0..1: l'ampiezza dello scuotimento e' trauma^2.
var trauma := 0.0

var _pool: Array[CPUParticles3D] = []
var _idx := 0
var _time := 0.0


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	for i in range(POOL_SIZE):
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 0.55
		p.amount = 16
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 4.0
		p.gravity = Vector3(0, -9.0, 0)
		p.mesh = mesh
		p.material_override = mat
		p.color_ramp = ramp
		add_child(p)
		_pool.append(p)


## Scintille in `pos`. `amount` particelle del colore dato.
func burst(pos: Vector3, color: Color, amount := 14, speed := 1.0) -> void:
	stats["burst"] = int(stats.get("burst", 0)) + 1
	var p := _pool[_idx]
	_idx = (_idx + 1) % POOL_SIZE
	p.emitting = false
	p.amount = amount
	p.color = color
	p.initial_velocity_min = 1.5 * speed
	p.initial_velocity_max = 4.0 * speed
	p.global_position = pos
	p.restart()
	p.emitting = true


## Aggiunge "trauma" (0..1) allo scuotimento della camera.
func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func _process(delta: float) -> void:
	_time += delta
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)


## Spostamento da sommare alla posizione della camera.
func shake_offset() -> Vector3:
	if trauma <= 0.0:
		return Vector3.ZERO
	var a := trauma * trauma * SHAKE_AMPLITUDE
	return Vector3(sin(_time * 53.0), sin(_time * 71.0 + 1.3), sin(_time * 47.0 + 2.1)) * a
