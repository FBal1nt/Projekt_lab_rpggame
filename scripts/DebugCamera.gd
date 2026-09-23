extends Camera2D

var speed = 900 # A kamera mozgási sebessége

func _ready():
	# Kódmal kényszerítjük, hogy ez legyen az aktív kamera
	enabled = true
	print("Kamera elindult és aktív!")

func _process(delta):
	var input_dir = Vector2.ZERO
	
	# Nyilak és WASD is figyelése a biztonság kedvéért
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_D) == false and Input.is_key_pressed(KEY_A): 
		pass # Egyszerűsítve alább:
		
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_action_pressed("ui_right"): input_dir.x += 1
	if Input.is_key_pressed(KEY_LEFT) or Input.is_action_pressed("ui_left"): input_dir.x -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down"): input_dir.y += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_action_pressed("ui_up"): input_dir.y -= 1
	
	if input_dir != Vector2.ZERO:
		position += input_dir.normalized() * speed * delta

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom -= Vector2(0.1, 0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom += Vector2(0.1, 0.1)
