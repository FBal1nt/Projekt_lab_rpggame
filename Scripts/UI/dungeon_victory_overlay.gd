extends CanvasLayer
class_name DungeonVictoryOverlay

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const LOBBY_SCENE_PATH := "res://Scenes/Lobby/Lobby.tscn"

var _backdrop: ColorRect
var _hero_label: Label
var _run_label: Label
var _titles_heading: Label
var _titles_body: Label
var _lobby_button: Button
var _continue_button: Button
var _is_transitioning: bool = false
var _was_paused_before: bool = false


func _ready() -> void:
	add_to_group("dungeon_victory")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 115
	visible = false
	_build_ui()


func _input(event: InputEvent) -> void:
	if not visible or _is_transitioning or not is_inside_tree():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			var is_esc: bool = key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE
			if is_esc:
				var vp := get_viewport()
				if vp != null:
					vp.set_input_as_handled()
				close_victory()


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "VictoryBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.012, 0.02, 0.036, 0.84)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	UI_THEME.style_panel(panel, UI_THEME.GOLD, Color(0.03, 0.05, 0.085, 0.99))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	header.add_child(UiIcons.make_icon_rect(UiIcons.TROPHY, Vector2(30, 30)))

	var headline := Label.new()
	headline.text = "DUNGEON TELJESÍTVE!"
	headline.add_theme_color_override("font_color", UI_THEME.GOLD)
	headline.add_theme_font_size_override("font_size", 26)
	header.add_child(headline)

	header.add_child(UiIcons.make_icon_rect(UiIcons.TROPHY, Vector2(30, 30)))

	var sep := HSeparator.new()
	sep.modulate = Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.5)
	vbox.add_child(sep)

	_hero_label = Label.new()
	_hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hero_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	_hero_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_hero_label)

	_run_label = Label.new()
	_run_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_run_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	_run_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_run_label)

	var titles_card := PanelContainer.new()
	titles_card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.02, 0.036, 0.064, 0.96), Color(0.76, 0.60, 0.30, 0.72), 1, 10)
	)
	vbox.add_child(titles_card)

	var titles_margin := MarginContainer.new()
	titles_margin.add_theme_constant_override("margin_left", 16)
	titles_margin.add_theme_constant_override("margin_top", 12)
	titles_margin.add_theme_constant_override("margin_right", 16)
	titles_margin.add_theme_constant_override("margin_bottom", 12)
	titles_card.add_child(titles_margin)

	var titles_vbox := VBoxContainer.new()
	titles_vbox.add_theme_constant_override("separation", 6)
	titles_margin.add_child(titles_vbox)

	var titles_header := HBoxContainer.new()
	titles_header.add_theme_constant_override("separation", 8)
	titles_vbox.add_child(titles_header)
	titles_header.add_child(UiIcons.make_icon_rect(UiIcons.MEDAL, Vector2(18, 18)))

	_titles_heading = Label.new()
	_titles_heading.text = "MEGSZERZETT TITULUSOK"
	_titles_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	_titles_heading.add_theme_font_size_override("font_size", 14)
	titles_header.add_child(_titles_heading)

	_titles_body = Label.new()
	_titles_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_titles_body.add_theme_color_override("font_color", Color(0.88, 0.93, 0.98, 1.0))
	_titles_body.add_theme_font_size_override("font_size", 13)
	titles_vbox.add_child(_titles_body)

	var hint := Label.new()
	hint.text = "A megszerzett titulusok közül a Táborban a KARAKTER menüben aktiválhatsz egyet az extra bónuszokért (HP, sebzés, páncél stb.)!"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.68, 0.88, 0.72, 1.0))
	hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	_continue_button = Button.new()
	_continue_button.text = "TOVÁBB A FELFEDEZÉSRE"
	UI_THEME.style_button(_continue_button, Color("8baac7"), false)
	_continue_button.custom_minimum_size = Vector2(230, 44)
	_continue_button.add_theme_font_size_override("font_size", 13)
	_continue_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_button.pressed.connect(close_victory)
	btn_row.add_child(_continue_button)

	_lobby_button = Button.new()
	_lobby_button.text = "VISSZA A TÁBORBA"
	UI_THEME.style_button(_lobby_button, UI_THEME.GOLD, true)
	_lobby_button.custom_minimum_size = Vector2(230, 44)
	_lobby_button.add_theme_font_size_override("font_size", 14)
	_lobby_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiIcons.apply_button_icon(_lobby_button, UiIcons.HOME, 18)
	_lobby_button.pressed.connect(_on_lobby_pressed)
	btn_row.add_child(_lobby_button)


func show_victory(hero: HeroController, newly_unlocked: PackedStringArray, run_titles: PackedStringArray) -> void:
	if visible or not is_inside_tree():
		return
	_is_transitioning = false
	_set_buttons_disabled(false)

	if is_instance_valid(hero):
		var c_name: String = hero.active_class.class_name_id if hero.active_class else "Kalandor"
		_hero_label.text = "%s  •  %s (Szint %d)" % [hero.hero_name, c_name, hero.level]
	else:
		_hero_label.text = "A főellenség legyőzve!"

	var gs := get_node_or_null("/root/GameState")
	if gs != null and "run_state" in gs and gs.run_state is Dictionary and not gs.run_state.is_empty():
		var d_name := String(gs.run_state.get("dungeon_name", "Dungeon"))
		var diff_name := String(gs.run_state.get("difficulty_name", "Normál"))
		_run_label.text = "%s  •  Nehézség: %s" % [d_name, diff_name]
	else:
		_run_label.text = "A kazamata megtisztítva!"

	if not newly_unlocked.is_empty():
		_titles_heading.text = "ÚJ TITULUSOK FELOLDVA (%d)" % newly_unlocked.size()
		var lines: Array[String] = []
		for t in newly_unlocked:
			var t_str: String = String(t)
			var buff_str: String = String(gs.format_title_buff_summary(t_str)) if (gs != null and gs.has_method("format_title_buff_summary")) else ""
			lines.append("•  %s  (%s)" % [t_str, buff_str] if not buff_str.is_empty() else "•  %s" % t_str)
		_titles_body.text = "\n".join(lines)
	elif not run_titles.is_empty():
		_titles_heading.text = "ÖSSZEGYŰJTÖTT TITULUSOK (MÁR MEGVANNAK)"
		var lines: Array[String] = []
		for t in run_titles:
			var t_str: String = String(t)
			var buff_str: String = String(gs.format_title_buff_summary(t_str)) if (gs != null and gs.has_method("format_title_buff_summary")) else ""
			lines.append("•  %s  (%s)" % [t_str, buff_str] if not buff_str.is_empty() else "•  %s" % t_str)
		_titles_body.text = "\n".join(lines)
	else:
		_titles_heading.text = "MEGSZERZETT TITULUSOK"
		_titles_body.text = "Ebben a menetben nem szereztél új titulust."

	_was_paused_before = get_tree().paused
	get_tree().paused = true
	visible = true
	AudioManager.fade_out_music(0.25)
	AudioManager.sfx(&"victory_fanfare", 1.0, 1.0)
	if _lobby_button:
		_lobby_button.grab_focus()


func close_victory() -> void:
	if not visible or _is_transitioning:
		return
	visible = false
	if is_inside_tree():
		get_tree().paused = _was_paused_before
	AudioManager.resume_music_context()


func _set_buttons_disabled(disabled: bool) -> void:
	if _lobby_button:
		_lobby_button.disabled = disabled
	if _continue_button:
		_continue_button.disabled = disabled


func _on_lobby_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_set_buttons_disabled(true)

	visible = false
	get_tree().paused = false

	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("clear_run_state"):
		gs.clear_run_state()

	call_deferred("_go_to_lobby")


func _go_to_lobby() -> void:
	if not is_inside_tree():
		_is_transitioning = false
		_set_buttons_disabled(false)
		return
	var st := get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("request_scene_change"):
		if st.call("request_scene_change", LOBBY_SCENE_PATH):
			return
	var err := get_tree().change_scene_to_file(LOBBY_SCENE_PATH)
	if err != OK:
		push_error("[DungeonVictoryOverlay] Nem sikerült visszatérni a táborba: %s" % error_string(err))
		_is_transitioning = false
		_set_buttons_disabled(false)
