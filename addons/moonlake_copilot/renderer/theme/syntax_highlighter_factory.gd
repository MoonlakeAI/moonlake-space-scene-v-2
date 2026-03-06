class_name SyntaxHighlighterFactory
extends RefCounted

## Factory for creating syntax highlighters with auto-detection
## Uses native Godot EditorSyntax* classes for consistent editor integration

enum ContentType {
	GDSCRIPT,
	JSON,
	MARKDOWN,
	BASH,
	CONFIG,
	FILEPATH,
	PLAIN
}

## Detects content type from text and context
static func detect_content_type(text: String, context: String) -> ContentType:
	var trimmed := text.strip_edges()

	# Tool calls and results detection
	if context.begins_with("tool_call") or context.begins_with("tool_result"):
		# Check for JSON structure
		if trimmed.begins_with("{") or trimmed.begins_with("["):
			return ContentType.JSON
		# Check for grep/glob output (file paths)
		if trimmed.begins_with("/") or trimmed.begins_with("Users/") or _looks_like_filepath_list(trimmed):
			return ContentType.FILEPATH
		# Check for GDScript file content
		if "func " in text or "class " in text or "extends " in text:
			return ContentType.GDSCRIPT
		# Check for ConfigFile format (sections like [section] and key=value)
		if "[" in text and "]" in text and "=" in text:
			return ContentType.CONFIG
		# Default to plain for tool outputs
		return ContentType.PLAIN

	# Message content detection
	if context == "copilot_message" or context == "user_message":
		# Check for markdown code blocks
		if "```" in text:
			return ContentType.MARKDOWN
		# Check for markdown formatting
		if "**" in text or "__" in text or "# " in text or "## " in text:
			return ContentType.MARKDOWN
		return ContentType.MARKDOWN  # Default to markdown for messages

	# Thinking blocks use markdown
	if context == "thinking":
		return ContentType.MARKDOWN

	# File content detection by keywords
	if "func " in text or "class " in text or "extends " in text or "signal " in text:
		return ContentType.GDSCRIPT

	if trimmed.begins_with("{") or trimmed.begins_with("["):
		return ContentType.JSON

	# Default to plain text
	return ContentType.PLAIN

## Checks if content looks like a list of file paths (grep/glob output)
static func _looks_like_filepath_list(text: String) -> bool:
	var lines := text.split("\n")
	if lines.size() < 1:
		return false
	var path_count := 0
	for i in range(mini(lines.size(), 5)):
		var line := lines[i].strip_edges()
		if line.begins_with("/") or line.begins_with("res://") or ":" in line and "/" in line:
			path_count += 1
	return path_count >= 1

## Creates appropriate syntax highlighter for the given content type
static func create_highlighter(content_type: ContentType) -> SyntaxHighlighter:
	match content_type:
		ContentType.GDSCRIPT:
			return _create_gdscript_highlighter()
		ContentType.JSON:
			return _create_json_highlighter()
		ContentType.MARKDOWN:
			return _create_markdown_highlighter()
		ContentType.BASH:
			return _create_bash_highlighter()
		ContentType.CONFIG:
			return _create_config_highlighter()
		ContentType.FILEPATH:
			return _create_filepath_highlighter()
		ContentType.PLAIN:
			return _create_plain_highlighter()
		_:
			return _create_plain_highlighter()

## Creates syntax highlighter based on auto-detected content type
static func create_auto(text: String, context: String) -> SyntaxHighlighter:
	var type := detect_content_type(text, context)
	return create_highlighter(type)

# ========== LANGUAGE-SPECIFIC HIGHLIGHTERS ==========

static func _create_gdscript_highlighter() -> SyntaxHighlighter:
	# Use native Godot GDScript syntax highlighter
	return EditorStandardSyntaxHighlighter.new()

static func _create_json_highlighter() -> SyntaxHighlighter:
	# Use native Godot JSON syntax highlighter
	return EditorJSONSyntaxHighlighter.new()

static func _create_markdown_highlighter() -> SyntaxHighlighter:
	# Use native Godot Markdown syntax highlighter
	return EditorMarkdownSyntaxHighlighter.new()

static func _create_bash_highlighter() -> SyntaxHighlighter:
	# Use native Godot standard syntax highlighter for bash/terminal output
	return EditorStandardSyntaxHighlighter.new()

static func _create_config_highlighter() -> SyntaxHighlighter:
	# Use native Godot ConfigFile syntax highlighter
	return EditorConfigFileSyntaxHighlighter.new()

static func _create_filepath_highlighter() -> SyntaxHighlighter:
	return EditorPlainTextSyntaxHighlighter.new()

static func _create_plain_highlighter() -> SyntaxHighlighter:
	# Use native Godot plain text syntax highlighter
	return EditorPlainTextSyntaxHighlighter.new()

## Convenience method for CodeEdit configuration
static func configure_code_edit(code_edit: CodeEdit, text: String, context: String, show_line_numbers: bool = false) -> void:
	# Basic configuration
	code_edit.editable = false
	code_edit.gutters_draw_line_numbers = show_line_numbers
	code_edit.indent_automatic = false  # No auto-indent in read-only mode
	code_edit.selecting_enabled = true
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY  # Wrap long lines at word boundaries
	code_edit.scroll_fit_content_height = true  # Fit height to content
	code_edit.scroll_horizontal = false  # Disable horizontal scrolling

	# Apply syntax highlighting
	code_edit.syntax_highlighter = create_auto(text, context)

	# Ensure font colors are visible on dark background
	ensure_visible_font_colors(code_edit)

	# Set text
	code_edit.text = text

	# Disable gutter interactions (read-only)
	code_edit.gutters_draw_breakpoints_gutter = false
	code_edit.gutters_draw_bookmarks = false
	code_edit.gutters_draw_executing_lines = false

## Ensure all font colors in a CodeEdit are visible on dark backgrounds
static func ensure_visible_font_colors(code_edit: CodeEdit) -> void:
	const ThemeConstants = preload("res://addons/moonlake_copilot/renderer/theme/theme_constants.gd")
	var safe_default := Color(0.85, 0.85, 0.85, 1.0)
	code_edit.add_theme_color_override("font_color", safe_default)
	code_edit.add_theme_color_override("font_readonly_color", safe_default)
	code_edit.add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.5, 1.0))
