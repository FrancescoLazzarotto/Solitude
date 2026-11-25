extends Node
## Audio del gioco (autoload "Audio"). Effetti e musica sono sintetizzati dal modulo Rust (CartoAudio)
## in un thread secondario all'avvio: nessun file audio, nessun blocco del caricamento.
## Se l'estensione nativa manca il gioco funziona lo stesso, in silenzio.

signal loaded

const POOL_SIZE := 16
const SEED := 2024
const MUSIC_SECONDS := 64.0
const MUSIC_DB := -11.0

## True quando i suoni sono pronti.
var available := false
## Quante volte e' stato richiesto ogni suono (utile ai test, anche se l'audio non e' pronto).
var stats: Dictionary = {}
var load_ms := 0

var _native: RefCounted
var _bank: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_idx := 0
var _listener: AudioListener3D
var _music: AudioStreamPlayer
var _diag_no_music := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	# Interruttori di diagnosi per i benchmark A/B (vedi tools/bench.ps1).
	if args.has("--carto-no-audio"):
		set_process(false)
		return
	_diag_no_music = args.has("--carto-audio-nomusic")
	_setup_buses()
	_listener = AudioListener3D.new()
	add_child(_listener)
	_listener.make_current()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 10.0
		p.max_distance = 60.0
		p.panning_strength = 0.7
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)

	if args.has("--carto-audio-norender"):
		set_process(false)   # player e listener esistono, ma nessun suono viene generato
		return
	if not ClassDB.class_exists("CartoAudio"):
		push_warning("Audio: estensione nativa non trovata (bin/carto.dll). Il gioco resta muto.")
		set_process(false)
		return
	_native = ClassDB.instantiate("CartoAudio")
	# Il rendering gira in un thread DENTRO Rust (da un Thread di Godot l'estensione non si puo' chiamare).
	_native.start_render(SEED, MUSIC_SECONDS)


func _process(_delta: float) -> void:
	if _native == null or not _native.is_render_done():
		return
	var result: Dictionary = _native.take_render()
	set_process(false)
	if result.is_empty():
		push_warning("Audio: rendering fallito, il gioco resta muto.")
		return
	var sfx: Dictionary = result["sfx"]
	for key: String in sfx:
		_bank[StringName(key)] = _native.pcm_to_stream(sfx[key], false, false)
	_music.stream = _native.pcm_to_stream(result["music"], true, true)
	load_ms = int(result["ms"])
	available = true
	_start_music()
	loaded.emit()


func _start_music() -> void:
	if _diag_no_music:
		return
	_music.volume_db = -60.0
	_music.play()
	create_tween().tween_property(_music, "volume_db", MUSIC_DB, 6.0)


## Riproduce un effetto. `pos` = posizione nel mondo (Vector3) oppure null per "qui, vicino al giocatore".
func play(sfx: StringName, pos: Variant = null, volume_db := 0.0, pitch := 1.0) -> void:
	stats[sfx] = int(stats.get(sfx, 0)) + 1
	if not available:
		return
	var stream: AudioStream = _bank.get(sfx)
	if stream == null:
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.global_position = pos if pos is Vector3 else _listener.global_position
	p.play()


## Il "microfono" segue il robot (la camera sta a 17 metri) e ha la STESSA rotazione orizzontale
## della camera: cosi' i suoni a destra sullo schermo panneggiano a destra, quelli in alto vanno davanti.
func set_listener(pos: Vector3, yaw: float) -> void:
	if _listener != null:
		_listener.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)


func _setup_buses() -> void:
	if AudioServer.get_bus_index(&"SFX") != -1:
		return
	for bus_name: StringName in [&"SFX", &"Music"]:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), 0.0)
	# Limitatore sul master: niente distorsione quando molti suoni si sommano.
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, limiter)


