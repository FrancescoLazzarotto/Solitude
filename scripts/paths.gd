extends RefCounted
## Percorsi dei file utente. In modalità test (argomento `--carto-test`) tutto va in
## `user://test/`, così i test non toccano mai i salvataggi veri del giocatore.

static func is_test() -> bool:
	return OS.get_cmdline_user_args().has("--carto-test")


static func user_file(file_name: String) -> String:
	var base := "user://test/" if is_test() else "user://"
	if is_test():
		DirAccess.make_dir_recursive_absolute(base)
	return base + file_name
