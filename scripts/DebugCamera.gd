extends Camera2D

@export var min_zoom: Vector2 = Vector2(0.5, 0.5)
@export var max_zoom: Vector2 = Vector2(2.5, 2.5)
@export var zoom_step: Vector2 = Vector2(0.1, 0.1)

func _ready() -> void:
	enabled = true
	# Bekapcsoljuk a Godot beépített simított követését:
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	# Biztosítjuk, hogy pontosan a játékos közepén álljon:
	position = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = (zoom - zoom_step).clamp(min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = (zoom + zoom_step).clamp(min_zoom, max_zoom)
