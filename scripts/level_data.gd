extends RefCounted
## Lettura dei dati del livello (levels/*.json). Lo stesso file e' validato da Rust (carto_core::level).
## NB: nei build esportati ricordarsi di includere i file *.json (filtro di esportazione).


static func load_level(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Livello non trovato: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("Livello non valido (JSON): %s" % path)
		return {}
	return parsed


static func v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func color(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))
