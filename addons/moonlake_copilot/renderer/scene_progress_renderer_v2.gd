@tool
extends RefCounted

## SceneProgressRendererV2
##
## Renders scene progress messages with two stages:
## - "plan": Markdown-formatted plan text with collapsible display
## - "concept_art": Large image loaded from URL (800x600)
## V2: Uses CodeEdit for plan text with markdown highlighting, custom large image display for concept art.
## Collapsible header, terminal-style panel, consistent with other V2 renderers.

const AnimationConstants = preload("res://addons/moonlake_copilot/renderer/animation_constants.gd")
const CollapseAnimation = preload("res://addons/moonlake_copilot/renderer/collapse_animation.gd")
const TripleClickSelector = preload("res://addons/moonlake_copilot/renderer/triple_click_selector.gd")
const Styles = preload("res://addons/moonlake_copilot/renderer/theme/component_styles.gd")
const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
const SyntaxFactory = preload("res://addons/moonlake_copilot/renderer/theme/syntax_highlighter_factory.gd")
const ImageGalleryRenderer = preload("res://addons/moonlake_copilot/renderer/image_gallery_renderer.gd")

static func render(message: Dictionary) -> Control:
	"""
	Create scene progress widget with collapsible display.

	Args:
		message: Message dictionary with stage ("plan" or "concept_art") and data

	Returns:
		SceneProgressWidget control
	"""
	var widget = SceneProgressWidget.new()
	widget.initialize(message)
	return widget


## SceneProgressWidget - Collapsible control for scene generation progress
class SceneProgressWidget extends PanelContainer:
	var icon_label: TextureRect
	var header_label: Label
	var content_area: Control  # CodeEdit for plan, ImageGalleryRenderer for concept_art
	var is_expanded: bool = true  # Start expanded by default
	var stage: String = ""
	var expand_time: float = 0.0
	var user_manually_expanded: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(0, int(ThemeConstants.spacing(40)))
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		set_meta("message_type", "scene_progress")

		add_theme_stylebox_override("panel", Styles.terminal_panel())

		# Main HBox: icon on left, content on right
		var main_hbox = HBoxContainer.new()
		main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		main_hbox.add_theme_constant_override("separation", int(ThemeConstants.spacing(10)))
		add_child(main_hbox)

		# Icon using TextureRect
		var icon_rect = TextureRect.new()
		var icon_size = int(ThemeConstants.spacing(20))
		icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
		icon_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = EditorInterface.get_editor_theme().get_icon("TextFile", "EditorIcons")
		icon_rect.modulate = ThemeConstants.COLORS.ICON_TOOL
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon_margin = MarginContainer.new()
		icon_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		icon_margin.add_theme_constant_override("margin_left", int(ThemeConstants.spacing(8)))
		icon_margin.add_theme_constant_override("margin_right", int(ThemeConstants.spacing(8)))
		icon_margin.add_theme_constant_override("margin_top", int(ThemeConstants.spacing(12)))
		icon_margin.add_theme_constant_override("margin_bottom", int(ThemeConstants.spacing(8)))
		icon_margin.add_child(icon_rect)

		icon_label = icon_rect  # Keep reference for compatibility
		main_hbox.add_child(icon_margin)

		# Right side VBox: header + content
		var content_vbox = VBoxContainer.new()
		content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content_vbox.add_theme_constant_override("separation", 8)
		main_hbox.add_child(content_vbox)

		# Header label (top of right side) - clickable
		header_label = Label.new()
		header_label.text = "Scene Progress"
		header_label.modulate.a = ThemeConstants.COLORS.OPACITY_HEADER
		header_label.mouse_filter = Control.MOUSE_FILTER_STOP
		header_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var header_style = StyleBoxFlat.new()
		header_style.bg_color = Color(0, 0, 0, 0)
		header_style.content_margin_left = 0
		header_style.content_margin_right = int(ThemeConstants.spacing(8))
		header_style.content_margin_top = int(ThemeConstants.spacing(8))
		header_style.content_margin_bottom = 0
		header_label.add_theme_stylebox_override("normal", header_style)

		content_vbox.add_child(header_label)

		# Content area will be created in initialize() based on stage

		# Make header clickable
		header_label.gui_input.connect(_on_header_clicked)

	func _get_stage_icon(stage_name: String) -> Texture2D:
		"""Get icon for stage"""
		match stage_name:
			"plan":
				return EditorInterface.get_editor_theme().get_icon("TextFile", "EditorIcons")
			"concept_art":
				return EditorInterface.get_editor_theme().get_icon("ImageTexture", "EditorIcons")
			_:
				return EditorInterface.get_editor_theme().get_icon("NodeInfo", "EditorIcons")

	func _get_stage_title(stage_name: String) -> String:
		"""Get display title for stage"""
		match stage_name:
			"plan":
				return "Scene Plan"
			"concept_art":
				return "Concept Art"
			_:
				return "Scene Progress"

	func initialize(message: Dictionary) -> void:
		"""Initialize widget with message data"""

		var content = message.get("content", {})
		stage = content.get("stage", "")
		var data = content.get("data", {})

		icon_label.texture = _get_stage_icon(stage)

		if stage == "plan":
			var plan_text = data.get("plan_text", "")
			content_area = _create_plan_content(plan_text)
		elif stage == "concept_art":
			var image_url = data.get("image_url", "")
			content_area = _create_concept_art_content(image_url)
		else:
			# Unknown stage - create placeholder
			content_area = Label.new()
			content_area.text = "Unknown stage: " + stage

		var content_vbox = header_label.get_parent()
		content_area.visible = true  # Start expanded
		content_vbox.add_child(content_area)

		_update_header()

	func _create_plan_content(plan_text: String) -> CodeEdit:
		"""Create CodeEdit with markdown syntax highlighting for plan text"""
		var code_edit = CodeEdit.new()
		code_edit.editable = false
		code_edit.gutters_draw_line_numbers = true
		code_edit.indent_automatic = false
		code_edit.auto_brace_completion_highlight_matching = false
		code_edit.selecting_enabled = true
		code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY  # Wrap at word boundaries
		code_edit.scroll_fit_content_height = true
		code_edit.scroll_horizontal = false
		code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

		ThemeConstants.apply_monospace_font(code_edit)

		code_edit.add_theme_color_override("font_color", ThemeConstants.COLORS.TEXT_TERMINAL)

		# Transparent background with bottom margin
		var transparent_style = Styles.terminal_content()
		transparent_style.content_margin_bottom = ThemeConstants.spacing(16.0)
		code_edit.add_theme_stylebox_override("normal", transparent_style)
		code_edit.add_theme_stylebox_override("focus", transparent_style)

		# Disable gutter interactions
		code_edit.gutters_draw_breakpoints_gutter = false
		code_edit.gutters_draw_bookmarks = false
		code_edit.gutters_draw_executing_lines = false

		code_edit.text = plan_text
		var highlighter = SyntaxFactory.create_highlighter(SyntaxFactory.ContentType.MARKDOWN)
		code_edit.syntax_highlighter = highlighter

		# Enable triple-click selection
		TripleClickSelector.enable_triple_click_selection(code_edit)

		return code_edit

	func _create_concept_art_content(image_url: String) -> Control:
		"""Create large image display for concept art using ImageGalleryRenderer"""
		var gallery = ImageGalleryRenderer.new()
		gallery.load_images([image_url], "copilot")

		# Wait for gallery to be ready and then resize its panels
		gallery.ready.connect(func():
			_resize_gallery_for_concept_art(gallery)
		)

		return gallery

	func _resize_gallery_for_concept_art(gallery: Control) -> void:
		"""Resize gallery panels to be larger for concept art"""
		# Wait one frame for gallery to create its children
		await get_tree().process_frame

		# Find the GridContainer
		for child in gallery.get_children():
			if child is GridContainer:
				var grid = child as GridContainer
				grid.columns = 1  # Single column for concept art

				# Resize all panels to be larger
				for panel_child in grid.get_children():
					if panel_child is PanelContainer:
						var panel = panel_child as PanelContainer
						panel.custom_minimum_size = Vector2(int(ThemeConstants.spacing(800)), int(ThemeConstants.spacing(600)))  # Large size for concept art
				break

	func _update_header() -> void:
		"""Update header text with stage title"""
		var stage_title = _get_stage_title(stage)
		header_label.text = stage_title

	func _on_header_clicked(event: InputEvent) -> void:
		"""Handle header click to expand/collapse"""
		if not event is InputEventMouseButton:
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Mark as manually expanded/collapsed
			user_manually_expanded = true

			if is_expanded:
				# Collapse with animation
				_animate_collapse()
			else:
				# Expand instantly (no animation)
				_animate_expand()

	func collapse_if_expanded(force: bool = false) -> void:
		"""Collapse if expanded"""
		# Don't auto-collapse if user manually expanded
		if user_manually_expanded and not force:
			return

		if is_expanded:
			# Check if minimum duration has passed (unless forced)
			if not force:
				var current_time = Time.get_ticks_msec() / 1000.0
				var elapsed = current_time - expand_time
				if elapsed < AnimationConstants.MIN_EXPAND_DURATION:
					# Too soon to collapse - skip
					return

			# Animate collapse
			_animate_collapse()

	func _animate_collapse() -> void:
		"""Smoothly collapse content with height animation"""
		is_expanded = false
		_update_header()

		# Immediately hide content as fallback (in case animation doesn't run when window is not focused)
		content_area.visible = false

		# Try to animate (might not work if window is alt-tabbed)
		await CollapseAnimation.collapse_widget(self, AnimationConstants.COLLAPSED_HEIGHT, AnimationConstants.MIN_EXPANDED_HEIGHT, content_area)

		# Force final state (in case animation didn't complete)
		content_area.visible = false
		custom_minimum_size.y = AnimationConstants.COLLAPSED_HEIGHT

	func _animate_expand() -> void:
		"""Expand content instantly (no animation)"""
		is_expanded = true
		expand_time = Time.get_ticks_msec() / 1000.0  # Record expand time
		_update_header()

		CollapseAnimation.expand_widget(self, AnimationConstants.MIN_EXPANDED_HEIGHT, content_area)
