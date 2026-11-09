extends Camera2D

@export_group("Kamera Beállítások")
@export var move_speed: float = 600.0
@export var zoom_speed: float = 0.05
@export var min_zoom: Vector2 = Vector2(0.1, 0.1)
@export var max_zoom: Vector2 = Vector2(3.0, 3.0)

var is_dragging: bool = false
var drag_start_mouse_pos: Vector2 = Vector2.ZERO
var drag_start_cam_pos: Vector2 = Vector2.ZERO

func _ready():
	enabled = true
	make_current()

func _unhandled_input(event: InputEvent) -> void:
	# Egérgörgős nagyítás és kicsinyítés
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom = (zoom + Vector2(zoom_speed, zoom_speed)).clamp(min_zoom, max_zoom)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom = (zoom - Vector2(zoom_speed, zoom_speed)).clamp(min_zoom, max_zoom)
			# Jobb egérgomb vagy középső gomb nyomva tartása a húzáshoz
			elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
				is_dragging = true
				drag_start_mouse_pos = event.position
				drag_start_cam_pos = global_position
		else:
			if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
				is_dragging = false

	# Egérmozgatás nézethúzáshoz
	elif event is InputEventMouseMotion and is_dragging:
		var delta_mouse = (event.position - drag_start_mouse_pos) / zoom.x
		global_position = drag_start_cam_pos - delta_mouse

func _process(delta: float) -> void:
	# Billentyűzetes mozgatás (WASD / Nyilak)
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		global_position += input_dir * move_speed * delta / zoom.x
