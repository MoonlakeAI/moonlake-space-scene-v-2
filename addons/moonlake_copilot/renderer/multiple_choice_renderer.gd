@tool
extends RefCounted

const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const ImageGalleryRenderer = preload("res://addons/moonlake_copilot/renderer/image_gallery_renderer.gd")
const PythonBridge = preload("res://addons/moonlake_copilot/core/python_bridge.gd")

static func render(message: Dictionary) -> Control:
	var widget = MultipleChoiceWidget.new()
	widget.initialize(message)
	return widget


class MultipleChoiceWidget extends PanelContainer:
	var message_label: RichTextLabel
	var options_container: Control
	var python_bridge: Node
	var message_id: String
	var format: String
	var options: Array
	var is_answered: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(0, int(ThemeConstants.spacing(100)))
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(16)))
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(vbox)

		message_label = RichTextLabel.new()
		message_label.bbcode_enabled = true
		message_label.fit_content = true
		message_label.scroll_active = false
		message_label.selection_enabled = true
		message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		message_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		var transparent_style = Styles.transparent_label()
		message_label.add_theme_stylebox_override("normal", transparent_style)
		message_label.add_theme_stylebox_override("focus", transparent_style)

		ThemeConstants.apply_inter_font(message_label)
		message_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))

		vbox.add_child(message_label)

		_apply_style()

	func _apply_style() -> void:
		add_theme_stylebox_override("panel", Styles.todo_list_panel())

	func set_python_bridge(bridge: Node) -> void:
		python_bridge = bridge

	func initialize(message: Dictionary) -> void:
		var content = message.get("content", {})
		var message_text = content.get("message", "")
		format = content.get("format", "text")
		options = content.get("options", [])
		message_id = message.get("id", "")

		var selected_option_index = content.get("selected_option", -1)
		var has_selection = selected_option_index >= 0

		var skip_animation = message.get("skip_interactive_animation", false)

		message_label.text = message_text.replace("[", "[lb]").replace("]", "[rb]")

		if options_container:
			options_container.queue_free()

		var vbox = get_child(0)

		if format == "image":
			var gallery = ImageGalleryRenderer.new()
			gallery.load_images(
				options,
				"copilot",
				true,
				func(index: int) -> void:
					_on_option_selected(index, "Option %d" % (index + 1)),
				skip_animation
			)
			vbox.add_child(gallery)
			options_container = gallery

			if has_selection:
				gallery.set_selected_index(selected_option_index)
		else:
			options_container = VBoxContainer.new()
			options_container.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
			options_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vbox.add_child(options_container)

			for i in range(options.size()):
				var option_text = options[i]
				var option_widget = _create_text_option(i, option_text, skip_animation)
				options_container.add_child(option_widget)

		if has_selection:
			is_answered = true
			_highlight_selected_option(selected_option_index)

	func _create_text_option(index: int, option_text: String, skip_animation: bool = false) -> Button:
		var button = Button.new()
		button.text = "%d. %s" % [index + 1, option_text]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT

		ThemeConstants.apply_inter_font(button, ThemeConstants.Typography.FONT_SIZE_HEADER)

		# Button styles (normal, hover, pressed)
		var normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.2, 0.2, 0.2, 0.5)
		normal_style.corner_radius_top_left = int(ThemeConstants.spacing(6))
		normal_style.corner_radius_top_right = int(ThemeConstants.spacing(6))
		normal_style.corner_radius_bottom_left = int(ThemeConstants.spacing(6))
		normal_style.corner_radius_bottom_right = int(ThemeConstants.spacing(6))
		normal_style.content_margin_left = int(ThemeConstants.spacing(12))
		normal_style.content_margin_right = int(ThemeConstants.spacing(12))
		normal_style.content_margin_top = int(ThemeConstants.spacing(8))
		normal_style.content_margin_bottom = int(ThemeConstants.spacing(8))
		normal_style.anti_aliasing = true
		normal_style.anti_aliasing_size = 2.0

		var hover_style = StyleBoxFlat.new()
		hover_style.bg_color = Color(0.3, 0.3, 0.3, 0.7)
		hover_style.corner_radius_top_left = int(ThemeConstants.spacing(6))
		hover_style.corner_radius_top_right = int(ThemeConstants.spacing(6))
		hover_style.corner_radius_bottom_left = int(ThemeConstants.spacing(6))
		hover_style.corner_radius_bottom_right = int(ThemeConstants.spacing(6))
		hover_style.content_margin_left = int(ThemeConstants.spacing(12))
		hover_style.content_margin_right = int(ThemeConstants.spacing(12))
		hover_style.content_margin_top = int(ThemeConstants.spacing(8))
		hover_style.content_margin_bottom = int(ThemeConstants.spacing(8))
		hover_style.anti_aliasing = true
		hover_style.anti_aliasing_size = 2.0

		var pressed_style = StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.4, 0.4, 0.4, 0.8)
		pressed_style.corner_radius_top_left = int(ThemeConstants.spacing(6))
		pressed_style.corner_radius_top_right = int(ThemeConstants.spacing(6))
		pressed_style.corner_radius_bottom_left = int(ThemeConstants.spacing(6))
		pressed_style.corner_radius_bottom_right = int(ThemeConstants.spacing(6))
		pressed_style.content_margin_left = int(ThemeConstants.spacing(12))
		pressed_style.content_margin_right = int(ThemeConstants.spacing(12))
		pressed_style.content_margin_top = int(ThemeConstants.spacing(8))
		pressed_style.content_margin_bottom = int(ThemeConstants.spacing(8))
		pressed_style.anti_aliasing = true
		pressed_style.anti_aliasing_size = 2.0

		var disabled_style = StyleBoxFlat.new()
		disabled_style.bg_color = Color(0.15, 0.15, 0.15, 0.3)
		disabled_style.corner_radius_top_left = int(ThemeConstants.spacing(6))
		disabled_style.corner_radius_top_right = int(ThemeConstants.spacing(6))
		disabled_style.corner_radius_bottom_left = int(ThemeConstants.spacing(6))
		disabled_style.corner_radius_bottom_right = int(ThemeConstants.spacing(6))
		disabled_style.content_margin_left = int(ThemeConstants.spacing(12))
		disabled_style.content_margin_right = int(ThemeConstants.spacing(12))
		disabled_style.content_margin_top = int(ThemeConstants.spacing(8))
		disabled_style.content_margin_bottom = int(ThemeConstants.spacing(8))
		disabled_style.anti_aliasing = true
		disabled_style.anti_aliasing_size = 2.0

		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", pressed_style)
		button.add_theme_stylebox_override("disabled", disabled_style)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
		button.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.6))

		if skip_animation:
			button.disabled = true

		if not skip_animation:
			button.pressed.connect(func() -> void: _on_option_selected(index, option_text))

		return button

	func _highlight_selected_option(index: int) -> void:
		if format == "image" and options_container.has_method("set_selected_index"):
			options_container.set_selected_index(index)
			return

		var selected_style = StyleBoxFlat.new()
		selected_style.bg_color = Color(0.3, 0.5, 0.8, 0.8)
		selected_style.corner_radius_top_left = int(ThemeConstants.spacing(6))
		selected_style.corner_radius_top_right = int(ThemeConstants.spacing(6))
		selected_style.corner_radius_bottom_left = int(ThemeConstants.spacing(6))
		selected_style.corner_radius_bottom_right = int(ThemeConstants.spacing(6))
		selected_style.content_margin_left = int(ThemeConstants.spacing(12))
		selected_style.content_margin_right = int(ThemeConstants.spacing(12))
		selected_style.content_margin_top = int(ThemeConstants.spacing(8))
		selected_style.content_margin_bottom = int(ThemeConstants.spacing(8))
		selected_style.anti_aliasing = true
		selected_style.anti_aliasing_size = 2.0

		var current_index = 0
		for child in options_container.get_children():
			if child is Button:
				child.disabled = true
				if current_index == index:
					child.add_theme_stylebox_override("disabled", selected_style)
					child.add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0))
				current_index += 1

	func _on_option_selected(index: int, display_text: String) -> void:
		if is_answered:
			return

		is_answered = true

		if format == "image" and options_container.has_method("disable_interaction"):
			options_container.disable_interaction()

		_highlight_selected_option(index)

		if python_bridge:
			python_bridge.call_python("update_message_content", {
				"message_id": message_id,
				"content_updates": {
					"selected_option": index
				}
			})

		if python_bridge:
			var message_with_index = str(index + 1) + "|" + display_text
			var payload = PythonBridge.make_message_payload(message_id + "_response", message_with_index, display_text)
			python_bridge.call_python("send_user_message", payload)

	func update_message(message: Dictionary) -> void:
		initialize(message)
