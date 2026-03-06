class_name StyleBuilder
extends RefCounted

var _style: StyleBoxFlat

func _init() -> void:
	_style = StyleBoxFlat.new()

func background(color: Color) -> StyleBuilder:
	_style.bg_color = color
	return self

func transparent() -> StyleBuilder:
	_style.bg_color = Color(0, 0, 0, 0)
	return self

func corners(radius: float) -> StyleBuilder:
	_style.corner_radius_top_left = int(radius)
	_style.corner_radius_top_right = int(radius)
	_style.corner_radius_bottom_left = int(radius)
	_style.corner_radius_bottom_right = int(radius)
	return self

func corners_custom(tl: float, tr: float, bl: float, br: float) -> StyleBuilder:
	_style.corner_radius_top_left = int(tl)
	_style.corner_radius_top_right = int(tr)
	_style.corner_radius_bottom_left = int(bl)
	_style.corner_radius_bottom_right = int(br)
	return self

func border(width: float, color: Color) -> StyleBuilder:
	_style.border_width_left = int(width)
	_style.border_width_right = int(width)
	_style.border_width_top = int(width)
	_style.border_width_bottom = int(width)
	_style.border_color = color
	return self

func border_custom(left: float, right: float, top: float, bottom: float, color: Color) -> StyleBuilder:
	_style.border_width_left = int(left)
	_style.border_width_right = int(right)
	_style.border_width_top = int(top)
	_style.border_width_bottom = int(bottom)
	_style.border_color = color
	return self

func padding(horizontal: float, vertical: float) -> StyleBuilder:
	_style.content_margin_left = horizontal
	_style.content_margin_right = horizontal
	_style.content_margin_top = vertical
	_style.content_margin_bottom = vertical
	return self

func padding_all(amount: float) -> StyleBuilder:
	_style.content_margin_left = amount
	_style.content_margin_right = amount
	_style.content_margin_top = amount
	_style.content_margin_bottom = amount
	return self

func padding_custom(left: float, right: float, top: float, bottom: float) -> StyleBuilder:
	_style.content_margin_left = left
	_style.content_margin_right = right
	_style.content_margin_top = top
	_style.content_margin_bottom = bottom
	return self

func anti_aliasing(enabled: bool, size: float = 1.0) -> StyleBuilder:
	_style.anti_aliasing = enabled
	_style.anti_aliasing_size = size
	return self

func shadow(color: Color, size: int = 4, offset_x: float = 0.0, offset_y: float = 4.0) -> StyleBuilder:
	_style.shadow_color = color
	_style.shadow_size = size
	_style.shadow_offset = Vector2(offset_x, offset_y)
	return self

func build() -> StyleBoxFlat:
	return _style
