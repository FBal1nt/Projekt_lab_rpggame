extends RefCounted

const INK := Color(0.020, 0.032, 0.056, 0.96)
const PANEL := Color(0.032, 0.050, 0.082, 0.98)
const SURFACE_DARK := Color(0.018, 0.028, 0.048, 0.97)
const SURFACE_CARD := Color(0.040, 0.062, 0.098, 0.96)
const SURFACE_ELEVATED := Color(0.058, 0.086, 0.132, 0.98)
const GOLD := Color(0.90, 0.69, 0.34, 1.0)
const IVORY := Color(0.96, 0.92, 0.82, 1.0)
const MUTED := Color(0.66, 0.73, 0.80, 1.0)
const EMERALD := Color(0.46, 0.88, 0.58, 1.0)
const CRIMSON := Color(0.92, 0.44, 0.38, 1.0)
const FORGE_EMBER := Color(0.88, 0.55, 0.26, 1.0)
const ARCANE_VIOLET := Color(0.64, 0.52, 0.94, 1.0)
const BORDER_SUBTLE := Color(0.28, 0.36, 0.48, 0.72)


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
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	style.shadow_size = 6
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func make_card_box(
	background: Color = SURFACE_CARD,
	border: Color = BORDER_SUBTLE,
	border_width: int = 1,
	corner_radius: int = 10,
	pad_h: float = 12.0,
	pad_v: float = 8.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 4
	style.content_margin_left = pad_h
	style.content_margin_right = pad_h
	style.content_margin_top = pad_v
	style.content_margin_bottom = pad_v
	return style


static func make_badge_box(
	background: Color = Color(0.08, 0.11, 0.16, 0.96),
	border: Color = GOLD,
	corner_radius: int = 7
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(corner_radius)
	style.shadow_size = 0
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


static func style_button(
	button: Button,
	accent: Color = GOLD,
	primary: bool = false,
	min_height: float = 54.0
) -> void:
	var normal_background := Color(0.036, 0.062, 0.098, 0.95)
	var hover_background := Color(0.082, 0.125, 0.180, 0.98)
	var pressed_background := Color(0.024, 0.042, 0.072, 1.0)
	if primary:
		normal_background = Color(
			clampf(accent.r * 0.30, 0.06, 0.42),
			clampf(accent.g * 0.24, 0.05, 0.32),
			clampf(accent.b * 0.22, 0.05, 0.34),
			0.97
		)
		hover_background = Color(
			clampf(accent.r * 0.44, 0.10, 0.54),
			clampf(accent.g * 0.36, 0.08, 0.42),
			clampf(accent.b * 0.34, 0.08, 0.46),
			0.99
		)
		pressed_background = Color(
			clampf(accent.r * 0.20, 0.04, 0.28),
			clampf(accent.g * 0.16, 0.04, 0.22),
			clampf(accent.b * 0.15, 0.04, 0.24),
			1.0
		)

	button.add_theme_stylebox_override("normal", make_box(normal_background, accent, 2, 10))
	button.add_theme_stylebox_override("hover", make_box(hover_background, accent.lightened(0.22), 2, 10))
	button.add_theme_stylebox_override("pressed", make_box(pressed_background, accent.darkened(0.08), 2, 10))
	button.add_theme_stylebox_override("focus", make_box(Color(0.0, 0.0, 0.0, 0.0), accent.lightened(0.20), 2, 10))
	button.add_theme_stylebox_override("disabled", make_box(Color(0.05, 0.06, 0.08, 0.72), Color(0.30, 0.34, 0.40, 0.65), 1, 10))
	button.add_theme_color_override("font_color", IVORY)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.97, 0.88, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.90, 0.83, 0.66, 1.0))
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.38))
	button.add_theme_font_size_override("font_size", 18)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, min_height)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 32)


static func style_compact_button(
	button: Button,
	accent: Color = GOLD,
	primary: bool = false,
	height: float = 38.0,
	font_size: int = 13
) -> void:
	style_button(button, accent, primary, height)
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBox = button.get_theme_stylebox(state_name)
		if sb is StyleBoxFlat:
			var flat := sb.duplicate() as StyleBoxFlat
			flat.content_margin_left = 12.0
			flat.content_margin_right = 12.0
			flat.content_margin_top = 5.0
			flat.content_margin_bottom = 5.0
			flat.shadow_size = 3
			button.add_theme_stylebox_override(state_name, flat)
	button.custom_minimum_size.y = height
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_constant_override("icon_max_width", 18)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.focus_mode = Control.FOCUS_NONE


static func style_panel(
	panel: Control,
	border: Color = GOLD,
	background: Color = PANEL
) -> void:
	panel.add_theme_stylebox_override("panel", make_box(background, border, 2, 12))


static func style_window_shell(window: Panel, accent: Color = GOLD) -> void:
	window.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shell := StyleBoxFlat.new()
	shell.bg_color = Color(0.022, 0.036, 0.062, 0.985)
	shell.border_color = accent
	shell.set_border_width_all(2)
	shell.set_corner_radius_all(14)
	shell.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	shell.shadow_size = 18
	window.add_theme_stylebox_override("panel", shell)
