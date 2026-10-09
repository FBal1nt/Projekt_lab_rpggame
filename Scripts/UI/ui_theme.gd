extends RefCounted

const INK := Color(0.025, 0.045, 0.075, 0.94)
const PANEL := Color(0.045, 0.075, 0.11, 0.96)
const GOLD := Color(0.88, 0.67, 0.32, 1.0)
const IVORY := Color(0.96, 0.91, 0.79, 1.0)
const MUTED := Color(0.67, 0.73, 0.78, 1.0)


static func make_box(
	background: Color,
	border: Color = GOLD,
	border_width: int = 2,
	corner_radius: int = 12
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	style.shadow_size = 6
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func style_button(
	button: Button,
	accent: Color = GOLD,
	primary: bool = false
) -> void:
	var normal_background := Color(0.035, 0.065, 0.10, 0.94)
	var hover_background := Color(0.085, 0.13, 0.17, 0.98)
	var pressed_background := Color(0.025, 0.045, 0.075, 1.0)
	if primary:
		normal_background = Color(0.24, 0.16, 0.065, 0.97)
		hover_background = Color(0.38, 0.25, 0.08, 0.99)
		pressed_background = Color(0.15, 0.105, 0.045, 1.0)

	button.add_theme_stylebox_override("normal", make_box(normal_background, accent, 2, 10))
	button.add_theme_stylebox_override("hover", make_box(hover_background, accent.lightened(0.20), 3, 10))
	button.add_theme_stylebox_override("pressed", make_box(pressed_background, accent.darkened(0.08), 2, 10))
	button.add_theme_stylebox_override("focus", make_box(Color(0.0, 0.0, 0.0, 0.0), accent.lightened(0.2), 2, 10))
	button.add_theme_stylebox_override("disabled", make_box(Color(0.06, 0.07, 0.08, 0.75), Color(0.35, 0.38, 0.40, 0.7), 1, 10))
	button.add_theme_color_override("font_color", IVORY)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.87, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.9, 0.83, 0.65, 1.0))
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.35))
	button.add_theme_font_size_override("font_size", 18)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 54.0)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 32)


static func style_panel(
	panel: Control,
	border: Color = GOLD,
	background: Color = PANEL
) -> void:
	panel.add_theme_stylebox_override("panel", make_box(background, border, 2, 12))
