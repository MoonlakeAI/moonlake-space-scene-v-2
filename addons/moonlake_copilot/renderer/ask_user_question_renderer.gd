@tool
extends RefCounted

const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")

static func render(message: Dictionary) -> Control:
	var widget = AskUserQuestionWidget.new()
	widget.initialize(message)
	return widget


class AskUserQuestionWidget extends PanelContainer:
	var python_bridge: Node
	var message_id: String
	var tool_call_id: String
	var questions: Array = []
	var answers: Dictionary = {}
	var is_answered: bool = false
	var is_cancelled: bool = false
	var cancel_reason: String = ""

	var content_vbox: VBoxContainer
	var submit_button: Button

	var selected_options: Dictionary = {}
	var other_selected: Dictionary = {}
	var other_texts: Dictionary = {}
	var question_views: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(0, int(ThemeConstants.spacing(100)))
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var panel_style = Styles.todo_list_panel()
		if panel_style is StyleBoxFlat:
			panel_style.bg_color = Color(0.12, 0.12, 0.12, 0.92)
		add_theme_stylebox_override("panel", panel_style)

		content_vbox = VBoxContainer.new()
		content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(16)))
		add_child(content_vbox)

	func set_python_bridge(bridge: Node) -> void:
		python_bridge = bridge

	func initialize(message: Dictionary) -> void:
		var content = message.get("content", {})
		var content_block = content.get("content_block", {})
		var tool_input = content_block.get("input", {})

		message_id = message.get("id", "")
		tool_call_id = content.get("tool_call_id", message_id)

		questions = tool_input.get("questions", [])
		answers = content.get("answers", {})
		is_answered = content.get("answered", false) or (typeof(answers) == TYPE_DICTIONARY and not answers.is_empty())
		is_cancelled = content.get("cancelled", false)
		cancel_reason = content.get("cancel_reason", "")

		_build_ui()

	func _build_ui() -> void:
		for child in content_vbox.get_children():
			child.queue_free()

		question_views.clear()

		var header_hbox = HBoxContainer.new()
		header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
		content_vbox.add_child(header_hbox)

		var header_label = Label.new()
		header_label.text = _get_header_text()
		header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeConstants.apply_inter_font(header_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
		header_hbox.add_child(header_label)

		if is_cancelled:
			var cancel_label = Label.new()
			cancel_label.text = cancel_reason if not cancel_reason.is_empty() else "The question was cancelled."
			cancel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cancel_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			ThemeConstants.apply_inter_font(cancel_label)
			content_vbox.add_child(cancel_label)
			return

		if questions.is_empty():
			var empty_label = Label.new()
			empty_label.text = "No questions provided."
			empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ThemeConstants.apply_inter_font(empty_label)
			content_vbox.add_child(empty_label)
			return

		if is_answered:
			_build_answered_view()
			return

		_build_interactive_view()

	func _build_answered_view() -> void:
		for question in questions:
			var question_vbox = VBoxContainer.new()
			question_vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(6)))
			question_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content_vbox.add_child(question_vbox)

			var header_chip = _create_header_chip(str(question.get("header", "")))
			question_vbox.add_child(header_chip)

			var question_label = Label.new()
			question_label.text = str(question.get("question", ""))
			question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ThemeConstants.apply_inter_font(question_label)
			question_vbox.add_child(question_label)

			var answer_text = str(answers.get(question.get("header", ""), "No answer"))
			var answer_label = Label.new()
			answer_label.text = answer_text
			answer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			answer_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			ThemeConstants.apply_inter_font(answer_label)
			question_vbox.add_child(answer_label)

	func _build_interactive_view() -> void:
		for question_index in range(questions.size()):
			var question = questions[question_index]
			var question_vbox = VBoxContainer.new()
			question_vbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
			question_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content_vbox.add_child(question_vbox)

			var header_row = HBoxContainer.new()
			header_row.add_theme_constant_override("separation", int(ThemeConstants.spacing(8)))
			header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			question_vbox.add_child(header_row)

			var header_chip = _create_header_chip(str(question.get("header", "")))
			header_row.add_child(header_chip)

			if question.get("multiSelect", false):
				var multi_label = Label.new()
				multi_label.text = "(select multiple)"
				multi_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
				ThemeConstants.apply_inter_font(multi_label)
				header_row.add_child(multi_label)

			var question_label = Label.new()
			question_label.text = str(question.get("question", ""))
			question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ThemeConstants.apply_inter_font(question_label)
			question_vbox.add_child(question_label)

			var options_container = VBoxContainer.new()
			options_container.add_theme_constant_override("separation", int(ThemeConstants.spacing(6)))
			options_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			question_vbox.add_child(options_container)

			var option_buttons: Array = []
			var option_count = 0
			for option in question.get("options", []):
				var option_box = VBoxContainer.new()
				option_box.add_theme_constant_override("separation", int(ThemeConstants.spacing(2)))
				option_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				options_container.add_child(option_box)

				var option_button = _create_option_button(str(option.get("label", "")))
				var option_index = option_count
				option_button.pressed.connect(func() -> void:
					_on_option_pressed(question_index, option_index)
				)
				option_box.add_child(option_button)

				var description_label = Label.new()
				description_label.text = str(option.get("description", ""))
				description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				description_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
				description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ThemeConstants.apply_inter_font(description_label, ThemeConstants.Typography.FONT_SIZE_SMALL)
				option_box.add_child(description_label)

				option_buttons.append(option_button)
				option_count += 1

			var other_box = VBoxContainer.new()
			other_box.add_theme_constant_override("separation", int(ThemeConstants.spacing(4)))
			other_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			options_container.add_child(other_box)

			var other_button = _create_option_button("Other")
			other_button.pressed.connect(func() -> void:
				_on_other_pressed(question_index)
			)
			other_box.add_child(other_button)

			var other_input = LineEdit.new()
			other_input.placeholder_text = "Enter your custom answer..."
			other_input.visible = true
			other_input.modulate.a = 0.0
			other_input.editable = false
			other_input.text_changed.connect(func(text: String) -> void:
				_on_other_text_changed(question_index, text)
			)
			other_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ThemeConstants.apply_inter_font(other_input)
			other_box.add_child(other_input)

			question_views.append({
				"option_buttons": option_buttons,
				"other_button": other_button,
				"other_input": other_input,
				"multi_select": question.get("multiSelect", false),
				"options": question.get("options", [])
			})

			selected_options[question_index] = []
			other_selected[question_index] = false
			other_texts[question_index] = ""

			_refresh_question_view(question_index)

		submit_button = Button.new()
		submit_button.text = "Submit Answers"
		submit_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		submit_button.pressed.connect(_on_submit_pressed)
		ThemeConstants.apply_inter_font(submit_button, ThemeConstants.Typography.FONT_SIZE_HEADER)
		content_vbox.add_child(submit_button)

		_update_submit_state()

	func _on_option_pressed(question_index: int, option_index: int) -> void:
		var view = question_views[question_index]
		var multi_select = view.get("multi_select", false)
		var selections: Array = selected_options.get(question_index, [])

		if multi_select:
			if selections.has(option_index):
				selections.erase(option_index)
			else:
				selections.append(option_index)
		else:
			selections = [option_index]
			other_selected[question_index] = false
			other_texts[question_index] = ""

		selected_options[question_index] = selections
		_refresh_question_view(question_index)
		_update_submit_state()

	func _on_other_pressed(question_index: int) -> void:
		var view = question_views[question_index]
		var multi_select = view.get("multi_select", false)
		var is_selected = other_selected.get(question_index, false)

		if not multi_select and not is_selected:
			selected_options[question_index] = []

		other_selected[question_index] = not is_selected
		if is_selected:
			other_texts[question_index] = ""
		_refresh_question_view(question_index)
		_update_submit_state()

	func _on_other_text_changed(question_index: int, text: String) -> void:
		other_texts[question_index] = text
		_update_submit_state()

	func _on_submit_pressed() -> void:
		if not python_bridge:
			return

		answers = _build_answers()
		is_answered = true

		python_bridge.call_python("update_message_content", {
			"message_id": message_id,
			"content_updates": {
				"answers": answers,
				"answered": true
			}
		})

		python_bridge.call_python("tool_result", {
			"request_id": tool_call_id,
			"tool_name": "AskUserQuestion",
			"result": JSON.stringify(answers),
			"error": null
		})

		_build_ui()

	func _build_answers() -> Dictionary:
		var result: Dictionary = {}
		for question_index in range(questions.size()):
			var question = questions[question_index]
			var header = str(question.get("header", ""))
			var selections: Array = selected_options.get(question_index, [])
			var selection_labels: Array = []
			for option_index in selections:
				var options = question.get("options", [])
				if option_index >= 0 and option_index < options.size():
					selection_labels.append(str(options[option_index].get("label", "")))

			var other_text = str(other_texts.get(question_index, "")).strip_edges()
			if other_selected.get(question_index, false) and not other_text.is_empty():
				selection_labels.append("Other: %s" % other_text)

			if not selection_labels.is_empty():
				result[header] = ", ".join(selection_labels)

		return result

	func _refresh_question_view(question_index: int) -> void:
		var view = question_views[question_index]
		var option_buttons: Array = view.get("option_buttons", [])
		var selections: Array = selected_options.get(question_index, [])
		var multi_select = view.get("multi_select", false)

		for option_index in range(option_buttons.size()):
			var button = option_buttons[option_index]
			var is_selected = selections.has(option_index)
			_apply_option_style(button, is_selected)
			_set_option_label(button, is_selected, multi_select)

		var other_button: Button = view.get("other_button")
		var other_input: LineEdit = view.get("other_input")
		var is_other_selected = other_selected.get(question_index, false)
		_apply_option_style(other_button, is_other_selected)
		_set_option_label(other_button, is_other_selected, multi_select)
		other_input.visible = true
		if not is_other_selected:
			other_input.text = ""
			other_texts[question_index] = ""
			other_input.modulate.a = 0.0
			other_input.editable = false
		else:
			other_input.modulate.a = 1.0
			other_input.editable = true

	func _update_submit_state() -> void:
		if not submit_button:
			return

		var all_answered = true
		for question_index in range(questions.size()):
			if not _is_question_answered(question_index):
				all_answered = false
				break

		submit_button.disabled = not all_answered

	func _is_question_answered(question_index: int) -> bool:
		var selections: Array = selected_options.get(question_index, [])
		if not selections.is_empty():
			return true

		var other_text = str(other_texts.get(question_index, "")).strip_edges()
		return other_selected.get(question_index, false) and not other_text.is_empty()

	func _create_header_chip(text: String) -> Control:
		var chip = Label.new()
		chip.text = text
		chip.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		chip.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
		ThemeConstants.apply_inter_font(chip, ThemeConstants.Typography.FONT_SIZE_SMALL)

		var chip_style = StyleBoxFlat.new()
		chip_style.bg_color = Color(0.25, 0.25, 0.25, 0.7)
		var radius = int(ThemeConstants.spacing(4))
		chip_style.corner_radius_top_left = radius
		chip_style.corner_radius_top_right = radius
		chip_style.corner_radius_bottom_left = radius
		chip_style.corner_radius_bottom_right = radius
		chip_style.anti_aliasing = true
		chip_style.anti_aliasing_size = 2.0
		ThemeConstants.apply_dpi_padding_custom(chip_style, 12, 12, 6, 6)
		chip.add_theme_stylebox_override("normal", chip_style)

		return chip

	func _create_option_button(label_text: String) -> Button:
		var button = Button.new()
		button.text = label_text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ThemeConstants.apply_inter_font(button, ThemeConstants.Typography.FONT_SIZE_HEADER)

		var normal_style = StyleBoxFlat.new()
		var hover_style = StyleBoxFlat.new()
		var pressed_style = StyleBoxFlat.new()
		var disabled_style = StyleBoxFlat.new()

		normal_style.bg_color = Color(0.2, 0.2, 0.2, 0.5)
		hover_style.bg_color = Color(0.3, 0.3, 0.3, 0.7)
		pressed_style.bg_color = Color(0.4, 0.4, 0.4, 0.8)
		disabled_style.bg_color = Color(0.15, 0.15, 0.15, 0.3)

		var radius = int(ThemeConstants.spacing(6))
		for style in [normal_style, hover_style, pressed_style, disabled_style]:
			style.corner_radius_top_left = radius
			style.corner_radius_top_right = radius
			style.corner_radius_bottom_left = radius
			style.corner_radius_bottom_right = radius
			style.anti_aliasing = true
			style.anti_aliasing_size = 2.0
			ThemeConstants.apply_dpi_padding_custom(style, 12, 12, 8, 8)

		button.add_theme_stylebox_override("normal", normal_style)
		button.add_theme_stylebox_override("hover", hover_style)
		button.add_theme_stylebox_override("pressed", pressed_style)
		button.add_theme_stylebox_override("disabled", disabled_style)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

		button.set_meta("default_styles", {
			"normal": normal_style,
			"hover": hover_style,
			"pressed": pressed_style
		})
		button.set_meta("label_text", label_text)

		button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
		button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
		button.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.6))

		return button

	func _apply_option_style(button: Button, is_selected: bool) -> void:
		if not button:
			return

		if is_selected:
			var selected_style = StyleBoxFlat.new()
			selected_style.bg_color = Color(0.3, 0.5, 0.8, 0.8)
			var radius = int(ThemeConstants.spacing(6))
			selected_style.corner_radius_top_left = radius
			selected_style.corner_radius_top_right = radius
			selected_style.corner_radius_bottom_left = radius
			selected_style.corner_radius_bottom_right = radius
			selected_style.anti_aliasing = true
			selected_style.anti_aliasing_size = 2.0
			ThemeConstants.apply_dpi_padding_custom(selected_style, 12, 12, 8, 8)
			button.add_theme_stylebox_override("normal", selected_style)
			button.add_theme_stylebox_override("hover", selected_style)
			button.add_theme_stylebox_override("pressed", selected_style)
		else:
			var defaults = button.get_meta("default_styles", {})
			if typeof(defaults) == TYPE_DICTIONARY:
				if defaults.has("normal"):
					button.add_theme_stylebox_override("normal", defaults["normal"])
				if defaults.has("hover"):
					button.add_theme_stylebox_override("hover", defaults["hover"])
				if defaults.has("pressed"):
					button.add_theme_stylebox_override("pressed", defaults["pressed"])

	func _set_option_label(button: Button, is_selected: bool, multi_select: bool) -> void:
		if not button:
			return
		var base_label = str(button.get_meta("label_text", ""))
		var prefix = "● " if is_selected else "○ "
		button.text = prefix + base_label

	func _get_header_text() -> String:
		if is_cancelled:
			return "Question Cancelled"
		if is_answered:
			return "Questions Answered"
		return "Questions from Agent"
