extends RefCounted
## Salvataggio dei progressi (user://save.json). Scrittura atomica: prima su un file temporaneo,
## poi rinominato, cosi' un crash a meta' scrittura non corrompe mai il salvataggio buono.
## Nei test (--carto-test) e' DISATTIVATO a meno di passare --carto-savetest, per non far
## filtrare lo stato di un test nel successivo.

const Paths := preload("res://scripts/paths.gd")
const VERSION := 2


static func enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--carto-new-game"):
		return false
	return not Paths.is_test() or args.has("--carto-savetest")


static func path() -> String:
	return Paths.user_file("save.json")


static func write(data: Dictionary) -> bool:
	var payload := data.duplicate(true)
	payload["version"] = VERSION
	var final_path := path()
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_warning("Salvataggio non riuscito: %s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(final_path))
	if err != OK:
		push_warning("Salvataggio: rinomina fallita (%s)" % error_string(err))
		return false
	return true


## Dizionario vuoto se non c'e' un salvataggio valido (assente, illeggibile o di un'altra versione).
static func read() -> Dictionary:
	var p := path()
	if not FileAccess.file_exists(p):
		return {}
	# JSON.new().parse() ritorna un codice d'errore; JSON.parse_string() stamperebbe un ERROR nel log.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p)) != OK or not (json.data is Dictionary):
		push_warning("Salvataggio illeggibile: si riparte da capo.")
		return {}
	var d: Dictionary = json.data
	match int(d.get("version", -1)):
		VERSION:
			return d
		1:
			return _migrate_v1(d)
		_:
			push_warning("Salvataggio di un'altra versione: si riparte da capo.")
			return {}


## v1 salvava il checkpoint come coordinate; c'era un solo checkpoint (il santuario), quindi l'id e' "shrine".
static func _migrate_v1(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out["checkpoint"] = "shrine"
	out["version"] = VERSION
	return out


static func delete() -> void:
	var p := path()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
