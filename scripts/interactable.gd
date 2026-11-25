extends Node3D
## Punto interattivo (santuario, forziere, leva...). Il Main sceglie quello più vicino al robot.

var prompt := "Interagisci"
var radius := 2.0
var enabled := true
var on_interact := Callable()


func _ready() -> void:
	add_to_group("interactables")


func interact() -> void:
	if enabled and on_interact.is_valid():
		on_interact.call()
