extends Control
class_name CharacterCreationOverlay

signal character_confirmed(character_name: String, class_id: StringName)
signal back_requested

enum CreationStep {
	NAME_STEP,
	CLASS_STEP
}

const UI_THEME := preload("res://Scripts/UI/ui_theme.gd")
const CLASS_SELECTION_MENU_SCENE: PackedScene = preload("res://Scenes/UI/ClassSelectionMenu.tscn")
const RANDOM_NAMES: Array[String] = [
	"Ákos",
	"Bálint",
	"Csongor",
	"Dávid",
	"Emese",
	"Farkas",
	"Gréta",
	"Hunor",
	"Iringó",
	"Kadosa",
	"Levente",
	"Orsolya",
	"Réka",
	"Szabolcs",
	"Tünde",
	"Vajk",
	"Zsombor"
]

var _name_panel: PanelContainer
var _name_subtitle_label: Label
var _name_slot_badge_label: Label
var name_input: LineEdit
var random_name_button: Button
var status_label: Label
var _name_back_button: Button
var _name_next_button: Button

var _class_panel: PanelContainer
var _class_subtitle_label: Label
var _hero_badge_label: Label
var _class_slot_badge_label: Label
var class_selection_menu: ClassSelectionMenu
var _class_summary_label: Label
var _class_back_button: Button
var confirm_button: Button

var current_slot_id: int = 1
var _in_game_mode: bool = false
var _current_step: CreationStep = CreationStep.NAME_STEP


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_build_ui()


func _build_ui() -> void:
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.015, 0.025, 0.045, 0.86)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dimmer)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_build_name_window(center)
	_build_class_window(center)


func _build_name_window(parent: Control) -> void:
	_name_panel = PanelContainer.new()
	_name_panel.name = "NameCreationPanel"
	_name_panel.custom_minimum_size = Vector2(640, 390)
	UI_THEME.style_panel(_name_panel, Color("d8b56c"), Color(0.032, 0.055, 0.088, 0.97))
	parent.add_child(_name_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	_name_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	vbox.add_child(header_row)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 3)
	header_row.add_child(title_col)

	var title_label := Label.new()
	title_label.text = "ÚJ KALANDOR — 1. LÉPÉS"
	title_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	title_label.add_theme_font_size_override("font_size", 23)
	title_col.add_child(title_label)

	_name_subtitle_label = Label.new()
	_name_subtitle_label.text = "Először add meg a hősöd nevét."
	_name_subtitle_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	_name_subtitle_label.add_theme_font_size_override("font_size", 13)
	title_col.add_child(_name_subtitle_label)

	_name_slot_badge_label = _create_badge_pill(header_row, "MENTÉSI HELY 01", UI_THEME.GOLD, UI_THEME.GOLD)

	var top_divider := HSeparator.new()
	top_divider.add_theme_color_override("color", Color(0.75, 0.57, 0.30, 0.7))
	vbox.add_child(top_divider)

	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI_THEME.style_panel(card, Color(0.32, 0.42, 0.54, 0.85), Color(0.05, 0.085, 0.13, 0.94))
	vbox.add_child(card)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 18)
	card_margin.add_theme_constant_override("margin_top", 16)
	card_margin.add_theme_constant_override("margin_right", 18)
	card_margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(card_margin)

	var card_vbox := VBoxContainer.new()
	card_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card_vbox.add_theme_constant_override("separation", 14)
	card_margin.add_child(card_vbox)

	var prompt_lbl := Label.new()
	prompt_lbl.text = "Karakter neve:"
	prompt_lbl.add_theme_color_override("font_color", UI_THEME.IVORY)
	prompt_lbl.add_theme_font_size_override("font_size", 15)
	card_vbox.add_child(prompt_lbl)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	card_vbox.add_child(input_row)

	name_input = LineEdit.new()
	name_input.name = "CharacterNameInput"
	name_input.placeholder_text = "Add meg a hősöd nevét..."
	name_input.max_length = 28
	name_input.custom_minimum_size = Vector2(0, 54)
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.add_theme_font_size_override("font_size", 16)
	name_input.add_theme_color_override("font_color", UI_THEME.IVORY)
	name_input.add_theme_color_override("font_placeholder_color", UI_THEME.MUTED)
	name_input.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.025, 0.04, 0.065, 0.98), Color(0.32, 0.42, 0.54, 0.9), 2, 6))
	var focus_box := UI_THEME.make_box(Color(0.0, 0.0, 0.0, 0.0), UI_THEME.GOLD, 2, 6)
	focus_box.draw_center = false
	name_input.add_theme_stylebox_override("focus", focus_box)
	name_input.text_changed.connect(_on_name_text_changed)
	name_input.text_submitted.connect(_on_name_submitted)
	input_row.add_child(name_input)

	random_name_button = Button.new()
	random_name_button.text = "Véletlen név"
	random_name_button.custom_minimum_size = Vector2(140, 54)
	UI_THEME.style_button(random_name_button, Color("8baac7"))
	random_name_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	random_name_button.pressed.connect(_on_random_name_pressed)
	input_row.add_child(random_name_button)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.custom_minimum_size = Vector2(0, 26)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	status_label.add_theme_font_size_override("font_size", 13)
	card_vbox.add_child(status_label)

	var footer_divider := HSeparator.new()
	footer_divider.add_theme_color_override("color", Color(0.28, 0.36, 0.45, 0.8))
	vbox.add_child(footer_divider)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)

	var step_hint := Label.new()
	step_hint.text = "1 / 2. lépés · Következik: Osztályválasztás"
	step_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_hint.add_theme_color_override("font_color", UI_THEME.MUTED)
	step_hint.add_theme_font_size_override("font_size", 12)
	footer.add_child(step_hint)

	_name_back_button = Button.new()
	_name_back_button.text = "Vissza a mentésekhez"
	_name_back_button.custom_minimum_size = Vector2(190, 46)
	UI_THEME.style_button(_name_back_button, Color("718096"))
	_name_back_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_back_button.pressed.connect(_on_back_to_saves_pressed)
	footer.add_child(_name_back_button)

	_name_next_button = Button.new()
	_name_next_button.text = "Tovább →"
	_name_next_button.custom_minimum_size = Vector2(155, 46)
	UI_THEME.style_button(_name_next_button, Color("e9bd61"), true)
	_name_next_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_next_button.pressed.connect(_on_next_to_class_pressed)
	footer.add_child(_name_next_button)


func _build_class_window(parent: Control) -> void:
	_class_panel = PanelContainer.new()
	_class_panel.name = "ClassSelectionPanel"
	_class_panel.custom_minimum_size = Vector2(1060, 650)
	_class_panel.clip_contents = true
	_class_panel.visible = false
	UI_THEME.style_panel(_class_panel, Color("d8b56c"), Color(0.032, 0.055, 0.088, 0.97))
	parent.add_child(_class_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_class_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	vbox.add_child(header_row)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 3)
	header_row.add_child(title_col)

	var title_label := Label.new()
	title_label.text = "OSZTÁLYVÁLASZTÁS — 2. LÉPÉS"
	title_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	title_label.add_theme_font_size_override("font_size", 24)
	title_col.add_child(title_label)

	_class_subtitle_label = Label.new()
	_class_subtitle_label.text = "Válaszd ki, milyen hősként indulsz útnak."
	_class_subtitle_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	_class_subtitle_label.add_theme_font_size_override("font_size", 13)
	title_col.add_child(_class_subtitle_label)

	var badges_row := HBoxContainer.new()
	badges_row.add_theme_constant_override("separation", 8)
	badges_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(badges_row)

	_hero_badge_label = _create_badge_pill(badges_row, "HŐS: -", Color("8baac7"), UI_THEME.IVORY)
	_class_slot_badge_label = _create_badge_pill(badges_row, "MENTÉSI HELY 01", UI_THEME.GOLD, UI_THEME.GOLD)

	var top_divider := HSeparator.new()
	top_divider.add_theme_color_override("color", Color(0.75, 0.57, 0.30, 0.7))
	vbox.add_child(top_divider)

	class_selection_menu = CLASS_SELECTION_MENU_SCENE.instantiate() as ClassSelectionMenu
	class_selection_menu.require_explicit_selection = true
	class_selection_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	class_selection_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	class_selection_menu.clip_contents = true
	class_selection_menu.class_selected.connect(_on_class_selected)
	vbox.add_child(class_selection_menu)

	var footer_divider := HSeparator.new()
	footer_divider.add_theme_color_override("color", Color(0.28, 0.36, 0.45, 0.8))
	vbox.add_child(footer_divider)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	vbox.add_child(footer)

	_class_summary_label = Label.new()
	_class_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_summary_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	_class_summary_label.add_theme_font_size_override("font_size", 13)
	footer.add_child(_class_summary_label)

	_class_back_button = Button.new()
	_class_back_button.text = "← Vissza a névhez"
	_class_back_button.custom_minimum_size = Vector2(180, 48)
	UI_THEME.style_button(_class_back_button, Color("718096"))
	_class_back_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_back_button.pressed.connect(_on_back_to_name_pressed)
	footer.add_child(_class_back_button)

	confirm_button = Button.new()
	confirm_button.text = "Kaland indítása"
	confirm_button.icon = load("res://Assets/UI/Icons/play_sword.png")
	confirm_button.custom_minimum_size = Vector2(215, 48)
	UI_THEME.style_button(confirm_button, Color("e9bd61"), true)
	confirm_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_button.pressed.connect(_on_confirm_pressed)
	footer.add_child(confirm_button)


func _create_badge_pill(parent: Control, initial_text: String, border_color: Color, text_color: Color) -> Label:
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_THEME.style_panel(badge, border_color, Color(0.08, 0.12, 0.17, 0.95))
	parent.add_child(badge)

	var badge_margin := MarginContainer.new()
	badge_margin.add_theme_constant_override("margin_left", 14)
	badge_margin.add_theme_constant_override("margin_top", 6)
	badge_margin.add_theme_constant_override("margin_right", 14)
	badge_margin.add_theme_constant_override("margin_bottom", 6)
	badge.add_child(badge_margin)

	var lbl := Label.new()
	lbl.text = initial_text
	lbl.add_theme_color_override("font_color", text_color)
	lbl.add_theme_font_size_override("font_size", 13)
	badge_margin.add_child(lbl)
	return lbl


func open_for_slot(slot_id: int) -> void:
	_in_game_mode = false
	current_slot_id = clampi(slot_id, 1, GameState.MANUAL_SAVE_SLOT_COUNT)
	var slot_text := "MENTÉSI HELY %02d" % current_slot_id
	_open_creation_flow(
		slot_text,
		"Először add meg a hősöd nevét.",
		"Válaszd ki, milyen hősként indulsz útnak.",
		"Vissza a mentésekhez",
		"Kaland indítása",
		"Nincs alapértelmezett karakter: adj meg egy tetszőleges nevet."
	)


func open_for_new_character() -> void:
	_in_game_mode = true
	_open_creation_flow(
		"ÚJ KARAKTER",
		"Add meg az új hősöd nevét.",
		"Válaszd ki az új karaktered osztályát.",
		"Mégse",
		"Karakter létrehozása",
		"Adj meg egy egyedi nevet az új hősödnek."
	)


func _open_creation_flow(
	badge_text: String,
	name_subtitle: String,
	class_subtitle: String,
	back_label: String,
	confirm_label: String,
	initial_hint: String
) -> void:
	if _name_slot_badge_label != null:
		_name_slot_badge_label.text = badge_text
	if _class_slot_badge_label != null:
		_class_slot_badge_label.text = badge_text
	if _name_subtitle_label != null:
		_name_subtitle_label.text = name_subtitle
	if _class_subtitle_label != null:
		_class_subtitle_label.text = class_subtitle
	if _name_back_button != null:
		_name_back_button.text = back_label
	if confirm_button != null:
		confirm_button.text = confirm_label
	if name_input != null:
		name_input.text = ""
	if class_selection_menu != null:
		class_selection_menu.reload_classes(false)
		class_selection_menu.clear_selection()
	_set_status(initial_hint, UI_THEME.MUTED)
	_show_step(CreationStep.NAME_STEP)
	visible = true


func close_overlay() -> void:
	visible = false


func _show_step(step: CreationStep) -> void:
	_current_step = step
	_name_panel.visible = step == CreationStep.NAME_STEP
	_class_panel.visible = step == CreationStep.CLASS_STEP
	if step == CreationStep.NAME_STEP:
		if name_input != null:
			name_input.grab_focus()
	else:
		var clean_name := name_input.text.strip_edges()
		if _hero_badge_label != null:
			_hero_badge_label.text = "HŐS: %s" % clean_name
		_refresh_class_summary()


func _on_random_name_pressed() -> void:
	if RANDOM_NAMES.is_empty():
		return
	var current_name := name_input.text.strip_edges()
	var candidates: Array = RANDOM_NAMES.filter(func(candidate: String) -> bool: return candidate != current_name)
	var pool: Array = candidates if not candidates.is_empty() else RANDOM_NAMES
	name_input.text = str(pool[randi() % pool.size()])
	name_input.caret_column = name_input.text.length()
	_set_status("Véletlen név generálva — bármikor átírhatod.", UI_THEME.MUTED)


func _on_name_text_changed(_new_text: String) -> void:
	if not name_input.text.strip_edges().is_empty():
		_set_status("Név megadva — kattints a Tovább gombra az osztályválasztáshoz.", Color("b9e4b5"))
	else:
		_set_status("Adj meg egy nevet a folytatáshoz.", UI_THEME.MUTED)


func _on_name_submitted(_text: String) -> void:
	_on_next_to_class_pressed()


func _on_next_to_class_pressed() -> void:
	var trimmed_name := name_input.text.strip_edges()
	if trimmed_name.is_empty():
		_set_status("Adj meg egy karakternevet a folytatáshoz!", Color("f1a79d"))
		name_input.grab_focus()
		return
	if _in_game_mode:
		for existing in GameState.characters:
			if existing.character_name.strip_edges().to_lower() == trimmed_name.to_lower():
				_set_status("Már létezik karakter ezzel a névvel ebben a mentésben!", Color("f1a79d"))
				name_input.grab_focus()
				return
	_show_step(CreationStep.CLASS_STEP)


func _on_back_to_name_pressed() -> void:
	_show_step(CreationStep.NAME_STEP)


func _on_back_to_saves_pressed() -> void:
	close_overlay()
	back_requested.emit()


func _on_class_selected(_class_id: StringName) -> void:
	_refresh_class_summary()


func _on_confirm_pressed() -> void:
	var trimmed_name := name_input.text.strip_edges()
	if trimmed_name.is_empty():
		_show_step(CreationStep.NAME_STEP)
		_set_status("Adj meg egy karakternevet a folytatáshoz!", Color("f1a79d"))
		return
	var selected_class := class_selection_menu.get_selected_class_id() if class_selection_menu != null else &""
	if selected_class == &"":
		_class_summary_label.text = "Válassz egy osztályt a bal oldali listából a folytatáshoz!"
		_class_summary_label.add_theme_color_override("font_color", Color("f1a79d"))
		return
	character_confirmed.emit(trimmed_name, selected_class)


func _set_status(text: String, color: Color) -> void:
	if status_label == null:
		return
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)
	status_label.update_minimum_size()


func _refresh_class_summary() -> void:
	if _class_summary_label == null:
		return
	var trimmed_name := name_input.text.strip_edges() if name_input != null else ""
	var selected_class := class_selection_menu.get_selected_class_id() if class_selection_menu != null else &""
	var class_data := GameState.get_character_class(selected_class) if selected_class != &"" else null

	if class_data == null:
		_class_summary_label.text = "Hős: %s — válassz egy osztályt a bal oldali listából!" % trimmed_name
		_class_summary_label.add_theme_color_override("font_color", UI_THEME.GOLD)
		confirm_button.disabled = true
	else:
		if _in_game_mode:
			_class_summary_label.text = "Létrehozásra kész: %s (%s)" % [trimmed_name, class_data.display_name]
		else:
			_class_summary_label.text = "Indulásra kész: %s (%s) -> Mentési hely %02d" % [trimmed_name, class_data.display_name, current_slot_id]
		_class_summary_label.add_theme_color_override("font_color", Color("b9e4b5"))
		confirm_button.disabled = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree() or not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _current_step == CreationStep.CLASS_STEP:
		_on_back_to_name_pressed()
	else:
		_on_back_to_saves_pressed()
	var vp := get_viewport()
	if vp != null and vp.is_inside_tree():
		vp.set_input_as_handled()
