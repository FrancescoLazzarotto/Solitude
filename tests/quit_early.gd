extends SceneTree
## Avvia il gioco e lo chiude dopo N millisecondi (--quit-after-ms=N). Serve a verificare che chiudere
## mentre i thread in background lavorano ancora non faccia crashare il processo.
## Lanciato da tools/test.ps1 (shutdown stress); non e' un *_test.gd per scelta.


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var ms := 300
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quit-after-ms="):
			ms = int(a.get_slice("=", 1))
	await create_timer(ms / 1000.0).timeout
	quit(0)
