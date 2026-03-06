@tool
extends RefCounted

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")
const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")
const ImageGalleryRenderer = preload("res://addons/moonlake_copilot/renderer/image_gallery_renderer.gd")

const CHARS_PER_SEC = AnimationConstants.FAST_CHARS_PER_SEC
const TIMER_INTERVAL = AnimationConstants.TIMER_INTERVAL
const CHARS_PER_FRAME = AnimationConstants.FAST_CHARS_PER_FRAME
const MAX_BUFFER_SIZE = AnimationConstants.MAX_BUFFER_SIZE

static func render(message: Dictionary, config = null) -> Control:
	var sender = message.get("sender", "copilot")
	var widget = TextMessageWidget.new()
	widget.initialize(message)

	if sender == "user":
		var wrapper = HBoxContainer.new()
		wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrapper.set_meta("message_sender", "user")

		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.size_flags_stretch_ratio = 0.15
		wrapper.add_child(spacer)

		# Only show revert button if version control feature is enabled
		if config and config.enable_snapshot_reverts:
			var button_container = VBoxContainer.new()
			button_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			button_container.custom_minimum_size.x = ThemeConstants.spacing(36)

			var revert_button = Button.new()
			revert_button.icon = EditorInterface.get_editor_theme().get_icon("Reload", "EditorIcons")
			revert_button.tooltip_text = "Revert files to before this message"
			revert_button.custom_minimum_size = Vector2(ThemeConstants.spacing(32), ThemeConstants.spacing(32))

			var style_normal = StyleBoxFlat.new()
			style_normal.bg_color = Color(0.25, 0.25, 0.25, 0.6)
			style_normal.corner_radius_top_left = int(ThemeConstants.spacing(6))
			style_normal.corner_radius_top_right = int(ThemeConstants.spacing(6))
			style_normal.corner_radius_bottom_left = int(ThemeConstants.spacing(6))
			style_normal.corner_radius_bottom_right = int(ThemeConstants.spacing(6))
			style_normal.anti_aliasing = true
			style_normal.anti_aliasing_size = 2.0
			revert_button.add_theme_stylebox_override("normal", style_normal)

			var style_hover = StyleBoxFlat.new()
			style_hover.bg_color = Color(0.35, 0.35, 0.35, 0.8)
			style_hover.corner_radius_top_left = int(ThemeConstants.spacing(6))
			style_hover.corner_radius_top_right = int(ThemeConstants.spacing(6))
			style_hover.corner_radius_bottom_left = int(ThemeConstants.spacing(6))
			style_hover.corner_radius_bottom_right = int(ThemeConstants.spacing(6))
			style_hover.anti_aliasing = true
			style_hover.anti_aliasing_size = 2.0
			revert_button.add_theme_stylebox_override("hover", style_hover)

			var metadata = message.get("metadata", {})
			var local_id = metadata.get("local_id", "")
			if local_id != "":
				revert_button.set_meta("snapshot_id", local_id)
			else:
				revert_button.visible = false

			button_container.add_child(revert_button)
			wrapper.add_child(button_container)

		widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		widget.size_flags_stretch_ratio = 0.75
		wrapper.add_child(widget)

		return wrapper

	# COPILOT MESSAGE: Brown outer container + black text area + Moonlake icon (full width)
	elif sender == "copilot":
		var container = PanelContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # Shrink to fit content
		container.set_meta("message_sender", "copilot")  # Mark for identification

		# Use copilot message panel style from theme
		var style = Styles.copilot_message_panel()
		container.add_theme_stylebox_override("panel", style)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(12)))
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		container.add_child(hbox)

		# Moonlake icon
		var icon_container = VBoxContainer.new()
		var icon_width = int(ThemeConstants.spacing(48))
		icon_container.custom_minimum_size.x = icon_width
		icon_container.size_flags_vertical = Control.SIZE_FILL
		icon_container.alignment = BoxContainer.ALIGNMENT_BEGIN

		var icon_texture = TextureRect.new()
		icon_texture.texture = load("res://addons/moonlake_copilot/assets/moonlakeWhite.svg")
		var icon_size = int(ThemeConstants.spacing(35))
		icon_texture.custom_minimum_size = Vector2(icon_size, icon_size)
		icon_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		icon_container.add_child(icon_texture)
		hbox.add_child(icon_container)

		# Message widget
		widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(widget)

		return container

	# SYSTEM/OTHER: Return widget as-is
	else:
		return widget


class TextMessageWidget extends VBoxContainer:
	signal content_streaming

	var mode_badge: HBoxContainer = null
	var code_edit: CodeEdit
	var full_text: String = ""
	var revealed_chars: float = 0.0
	var timer: Timer
	var pending_delta_buffer: String = ""
	var retry_button: Button = null
	var message_id: String = ""
	var python_bridge
	var is_user_message: bool = false
	var user_id: String = ""
	var content: Dictionary = {}
	var is_user_scrolled_up: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_FILL
		add_theme_constant_override("separation", 0)

		code_edit = CodeEdit.new()
		code_edit.editable = false
		code_edit.gutters_draw_line_numbers = false
		code_edit.indent_automatic = false
		code_edit.auto_brace_completion_highlight_matching = false
		code_edit.selecting_enabled = true
		code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		code_edit.scroll_fit_content_height = true
		code_edit.scroll_past_end_of_file = false
		code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL

		code_edit.syntax_highlighter = SyntaxFactory.create_highlighter(SyntaxFactory.ContentType.MARKDOWN)

		ThemeConstants.apply_inter_font(code_edit)

		code_edit.gutters_draw_breakpoints_gutter = false
		code_edit.gutters_draw_bookmarks = false
		code_edit.gutters_draw_executing_lines = false

		add_child(code_edit)

		TripleClickSelector.enable_triple_click_selection(code_edit)

		# Detect user scroll in code edit
		code_edit.gui_input.connect(_on_code_edit_input)

		timer = Timer.new()
		timer.wait_time = TIMER_INTERVAL
		timer.timeout.connect(_on_timer_timeout)
		add_child(timer)

	func _hide_scrollbars() -> void:
		code_edit.scroll_fit_content_height = true
		await get_tree().process_frame
		_ensure_scrollbars_hidden()

	func _ensure_scrollbars_hidden() -> void:
		for child in code_edit.get_children():
			if child is HScrollBar:
				child.visible = false
			elif child is VScrollBar:
				child.visible = false

	func initialize(message: Dictionary) -> void:
		message_id = message.get("id", "")
		user_id = message.get("created_by", "")

		var sender = message.get("sender", "copilot")
		is_user_message = (sender == "user")
		_apply_sender_style(sender)
		_apply_alignment(sender)

		content = message.get("content", {})
		var message_text = content.get("message", "")
		full_text = message_text

		var mode = content.get("mode", "")
		if mode == null:
			mode = ""

		if is_user_message and mode != "":
			_create_mode_badge(mode)

		var images = content.get("images", [])
		var extracted_urls = _extract_image_urls_from_text(message_text)
		for url in extracted_urls:
			images.append(url)

		if images.size() > 0:
			var gallery = ImageGalleryRenderer.new()
			self.add_child(gallery)
			gallery.load_images(images, sender)

		var file_ids = content.get("file_ids", [])
		if file_ids.size() > 0:
			_add_file_attachments(file_ids)

		var skip_typewriter = message.get("skip_typewriter", false)

		if sender == "copilot" and full_text.length() > 0 and not skip_typewriter:
			revealed_chars = 0.0
			code_edit.text = ""
			call_deferred("_hide_scrollbars")
			call_deferred("_start_typewriter")
		else:
			code_edit.text = full_text
			revealed_chars = full_text.length()
			call_deferred("_clamp_height")

	func _start_typewriter() -> void:
		if not timer.is_stopped():
			return
		timer.start()

	func _apply_sender_style(sender: String) -> void:
		var style: StyleBox
		var editor_scale = EditorInterface.get_editor_scale()
		match sender:
			"user":
				var user_style = Styles.user_message_panel()
				ThemeConstants.apply_dpi_padding_custom(user_style, int(12 * editor_scale), int(12 * editor_scale), int(10 * editor_scale), int(10 * editor_scale))
				style = user_style
				code_edit.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				code_edit.add_theme_color_override("font_readonly_color", Color(1.0, 1.0, 1.0, 1.0))
			"copilot", "system":
				# Use copilot message content style (no border for inner text area)
				style = Styles.copilot_message_content()
				code_edit.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				code_edit.add_theme_color_override("font_readonly_color", Color(1.0, 1.0, 1.0, 1.0))
			_:
				style = StyleBoxEmpty.new()

		code_edit.add_theme_stylebox_override("normal", style)
		code_edit.add_theme_stylebox_override("focus", style)
		code_edit.add_theme_stylebox_override("read_only", style)

	func _apply_alignment(sender: String) -> void:
		match sender:
			"user":
				is_user_message = true
			"copilot", "system":
				size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_:
				size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _create_mode_badge(mode: String) -> void:
		var mode_config = {
			"prototype-games": {
				"label": "Prototype Games",
				"icon": ""
			},
			"generate-3d-world": {
				"label": "Generate 3D World",
				"icon": ""
			}
		}

		if not mode_config.has(mode):
			return

		var config = mode_config[mode]

		mode_badge = HBoxContainer.new()
		var badge_separation = int(ThemeConstants.spacing(6))
		mode_badge.add_theme_constant_override("separation", badge_separation)
		mode_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

		add_child(mode_badge)
		move_child(mode_badge, 0)

		var icon_label = Label.new()
		icon_label.text = config["icon"]
		var editor_scale = EditorInterface.get_editor_scale()
		var icon_font_size = int(ThemeConstants.Typography.FONT_SIZE_HEADER * editor_scale)
		icon_label.add_theme_font_size_override("font_size", icon_font_size)
		icon_label.add_theme_color_override("font_color", Color(0.24, 0.72, 1.0))
		mode_badge.add_child(icon_label)

		var text_label = Label.new()
		text_label.text = config["label"]
		text_label.add_theme_color_override("font_color", Color(0.24, 0.72, 1.0))
		ThemeConstants.apply_inter_font(text_label, ThemeConstants.Typography.FONT_SIZE_HEADER)
		mode_badge.add_child(text_label)

	func _ready() -> void:
		if is_user_message:
			await get_tree().process_frame
			await get_tree().process_frame
			code_edit.queue_redraw()
			update_minimum_size()

	func _clamp_height() -> void:
		var tree = get_tree()
		if tree: #2 frame wait
			await tree.process_frame
			await tree.process_frame

		if not is_user_message:
			for child in code_edit.get_children():
				if child is VScrollBar:
					child.visible = true

	func _on_code_edit_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			is_user_scrolled_up = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var vscroll = code_edit.get_v_scroll_bar()
			if vscroll and code_edit.get_v_scroll() >= vscroll.max_value - 10:
				is_user_scrolled_up = false

	func _scroll_to_bottom() -> void:
		if not is_user_scrolled_up:
			call_deferred("_do_scroll_to_bottom")

	func _do_scroll_to_bottom() -> void:
		var tree = get_tree()
		if not tree or is_user_scrolled_up:
			return
		await tree.process_frame
		if is_user_scrolled_up:
			return
		var vscroll = code_edit.get_v_scroll_bar()
		if vscroll and vscroll.max_value > 0:
			code_edit.set_v_scroll(vscroll.max_value)
			var last_line = code_edit.get_line_count() - 1
			if last_line >= 0:
				code_edit.set_caret_line(last_line)

	func _on_timer_timeout() -> void:
		if revealed_chars >= full_text.length():
			code_edit.text = full_text
			timer.stop()
			call_deferred("_clamp_height")
			return

		revealed_chars += CHARS_PER_FRAME
		var chars_to_show = int(revealed_chars)
		code_edit.text = full_text.substr(0, chars_to_show)

		_ensure_scrollbars_hidden()
		content_streaming.emit()

	func append_delta(delta: String) -> void:
		full_text += delta

		if timer.is_stopped() and full_text.length() > 0:
			timer.start()

		if pending_delta_buffer.length() > MAX_BUFFER_SIZE:
			_flush_pending_deltas()

	func _flush_pending_deltas() -> void:
		if pending_delta_buffer.length() == 0:
			return

		code_edit.text = full_text
		revealed_chars = full_text.length()
		pending_delta_buffer = ""

	func finish_animation() -> void:
		code_edit.text = full_text
		revealed_chars = full_text.length()
		pending_delta_buffer = ""

		if timer and not timer.is_stopped():
			timer.stop()

		call_deferred("_clamp_height")

	func update_message(message: Dictionary) -> void:
		var success = message.get("success", true)
		var error_text = message.get("error", "")

		if not success and error_text:
			_show_error_state(error_text)
			return

		content = message.get("content", {})
		var message_text = content.get("message", "")
		var new_full_text = message_text

		if new_full_text != full_text:
			full_text = new_full_text
			revealed_chars = 0.0
			code_edit.text =""
			timer.start()

		var file_ids = content.get("file_ids", [])
		if file_ids.size() > 0:
			var has_attachments = false
			for child in self.get_children():
				if child is MarginContainer:
					has_attachments = true
					break

			if not has_attachments:
				_add_file_attachments(file_ids)

	func _show_error_state(error_message: String) -> void:
		timer.stop()

		var error_style = Styles.error_panel()
		code_edit.add_theme_stylebox_override("normal", error_style)
		code_edit.add_theme_stylebox_override("focus", error_style)
		code_edit.add_theme_color_override("font_color", ThemeConstants.COLORS.TEXT_ERROR)

		code_edit.text = "Error: " + error_message
		revealed_chars = code_edit.text.length()

		if retry_button == null:
			retry_button = Button.new()
			retry_button.text = "Retry"
			var button_width = int(ThemeConstants.spacing(80))
			var button_height = int(ThemeConstants.spacing(30))
			retry_button.custom_minimum_size = Vector2(button_width, button_height)
			retry_button.pressed.connect(_on_retry_pressed)

			retry_button.add_theme_stylebox_override("normal", Styles.error_button())
			retry_button.add_theme_stylebox_override("hover", Styles.error_button_hover())

			self.add_child(retry_button)

	func _on_retry_pressed() -> void:
		if retry_button:
			retry_button.visible = false

		var params = {
			"local_message_id": message_id,
			"workdir": ProjectSettings.globalize_path("res://")
		}
		python_bridge.call_python("retry_message", params)

	func _extract_image_urls_from_text(text: String) -> Array:
		var urls = []
		if text.is_empty():
			return urls

		const IMAGE_SERVICES = ["picsum.photos", "imgur.com", "i.imgur.com"]

		var words = text.split(" ")
		for word in words:
			var lower_word = word.to_lower()
			if lower_word.begins_with("http://") or lower_word.begins_with("https://"):
				var clean_url = word
				while clean_url.length() > 0:
					var last_char = clean_url[clean_url.length() - 1]
					if last_char in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_=&%/":
						break
					clean_url = clean_url.substr(0, clean_url.length() - 1)

				var url_path = clean_url.to_lower()
				var query_index = url_path.find("?")
				if query_index != -1:
					url_path = url_path.substr(0, query_index)

				var has_extension = url_path.ends_with(".png") or url_path.ends_with(".jpg") or \
				                    url_path.ends_with(".jpeg") or url_path.ends_with(".webp")

				var is_image_service = false
				for service in IMAGE_SERVICES:
					if service in url_path:
						is_image_service = true
						break

				if has_extension or is_image_service:
					urls.append(clean_url)

		return urls

	func _add_file_attachments(file_ids: Array) -> void:
		var attachments_container = HBoxContainer.new()
		var chip_separation = int(ThemeConstants.spacing(8))
		var top_margin = int(ThemeConstants.spacing(12))
		attachments_container.add_theme_constant_override("separation", chip_separation)
		attachments_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		attachments_container.alignment = BoxContainer.ALIGNMENT_END
		var margin_wrapper = MarginContainer.new()
		margin_wrapper.add_theme_constant_override("margin_top", top_margin)
		margin_wrapper.add_theme_constant_override("margin_right", chip_separation)
		margin_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin_wrapper.add_child(attachments_container)
		self.add_child(margin_wrapper)

		var files = content.get("files", [])
		if files.is_empty():
			_render_attachments_fallback(file_ids, attachments_container)
			return

		for i in range(files.size()):
			var file_info = files[i]
			var file_url = file_info.get("file_url", "")
			var file_id = file_info.get("id", "")

			var url_lower = file_url.to_lower()
			var chip_text: String
			var chip_icon: Texture2D
			var is_image = url_lower.ends_with(".png") or url_lower.ends_with(".jpg") or url_lower.ends_with(".jpeg") or url_lower.ends_with(".gif") or url_lower.ends_with(".webp")
			if is_image:
				chip_text = "Image %d" % (i + 1)
				chip_icon = EditorInterface.get_editor_theme().get_icon("ImageTexture", "EditorIcons")
			else:
				chip_text = "Text %d" % (i + 1)
				chip_icon = EditorInterface.get_editor_theme().get_icon("TextFile", "EditorIcons")

			var chip = Button.new()
			chip.icon = chip_icon
			chip.text = chip_text
			chip.tooltip_text = "Click to open"
			chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			chip.flat = false

			chip.add_theme_stylebox_override("normal", Styles.attachment_chip())
			chip.add_theme_stylebox_override("hover", Styles.attachment_chip_hover())
			chip.add_theme_stylebox_override("pressed", Styles.attachment_chip())
			chip.add_theme_stylebox_override("focus", Styles.attachment_chip())

			ThemeConstants.apply_inter_font(chip, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
			var text_color = ThemeConstants.COLORS.TEXT_ATTACHMENT
			chip.add_theme_color_override("font_color", text_color)
			chip.add_theme_color_override("font_hover_color", text_color)
			chip.add_theme_color_override("font_pressed_color", text_color)
			chip.add_theme_color_override("font_focus_color", text_color)
			chip.add_theme_color_override("icon_normal_color", text_color)
			chip.add_theme_color_override("icon_hover_color", text_color)
			chip.add_theme_color_override("icon_pressed_color", text_color)
			chip.add_theme_color_override("icon_focus_color", text_color)

			chip.set_meta("file_id", file_id)
			chip.set_meta("file_url", file_url)

			chip.pressed.connect(func():
				OS.shell_open(file_url)
				chip.release_focus()
			)

			attachments_container.add_child(chip)

	func _render_attachments_fallback(file_ids: Array, container: Container) -> void:
		for i in range(file_ids.size()):
			var chip = Button.new()
			chip.icon = EditorInterface.get_editor_theme().get_icon("File", "EditorIcons")
			chip.text = "File %d" % (i + 1)
			chip.tooltip_text = file_ids[i]
			chip.flat = false
			chip.disabled = true
			chip.mouse_default_cursor_shape = Control.CURSOR_ARROW

			chip.add_theme_stylebox_override("normal", Styles.attachment_chip())
			chip.add_theme_stylebox_override("disabled", Styles.attachment_chip())

			ThemeConstants.apply_inter_font(chip, ThemeConstants.Typography.FONT_SIZE_DEFAULT)
			var text_color = ThemeConstants.COLORS.TEXT_ATTACHMENT
			chip.add_theme_color_override("font_color", text_color)
			chip.add_theme_color_override("font_disabled_color", text_color)
			chip.add_theme_color_override("icon_normal_color", text_color)
			chip.add_theme_color_override("icon_disabled_color", text_color)

			container.add_child(chip)


