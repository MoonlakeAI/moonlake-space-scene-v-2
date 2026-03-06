class_name ThemeConstants
extends RefCounted

## Centralized design tokens for all copilot renderers
## This file contains all color palette, spacing, borders, typography, and animation constants

# Font paths for bundled fonts
const INTER_FONT_PATH = "res://addons/moonlake_copilot/assets/fonts/Inter.ttf"
const JETBRAINS_MONO_FONT_PATH = "res://addons/moonlake_copilot/assets/fonts/JetBrainsMono.ttf"

static var _cached_mono_font: FontFile = null
static var _cached_inter_font: FontFile = null

# ========== COLORS ==========

class Colors:
	# Background Colors
	const BG_USER_MESSAGE := Color(0.18, 0.19, 0.20, 1.0)  # #2E3134 - Dark gray bubble
	const BG_COPILOT_MESSAGE := Color(0.0, 0.0, 0.0, 0.0)  # Transparent
	const BG_TERMINAL := Color(0.12, 0.12, 0.12, 1.0)  # Dark terminal background
	const BG_TERMINAL_STREAMING := Color(0.149, 0.157, 0.169, 1.0)  # Same as copilot message
	const BG_ERROR := Color(0.3, 0.1, 0.1, 0.8)  # Red-tinted error background
	const BG_INFO := Color(0.3, 0.2, 0.1, 0.8)  # Amber-tinted info background
	const BG_ATTACHMENT_CHIP := Color(1.0, 1.0, 1.0, 1.0)  # White background for attachment chips
	const BG_ATTACHMENT_CHIP_HOVER := Color(0.95, 0.95, 0.95, 1.0)  # Light gray on hover
	const BG_IMAGE_PREVIEW := Color(0.1, 0.1, 0.1, 0.95)  # Dark container for images
	const BG_BUTTON_ERROR := Color(0.6, 0.2, 0.2, 1.0)  # Error retry button
	const BG_BUTTON_ERROR_HOVER := Color(0.7, 0.3, 0.3, 1.0)  # Error button hover
	const BG_TODO_LIST := Color(0.5, 0.7, 0.9, 0.08)  # Light blue for todo lists
	const BG_PROGRESS := Color(0.4, 0.8, 0.5, 0.08)  # Light green for progress widgets
	const BG_PROGRESS_FILL := Color(0.3, 0.9, 0.4, 1.0)  # Bright green for progress bar fill
	const BG_PROGRESS_BAR := Color(0.2, 0.2, 0.2, 0.3)  # Dark background for progress bar

	# Border Colors
	const BORDER_TERMINAL := Color(0.4, 0.4, 0.4, 0.8)  # Gray border for terminal (increased visibility)
	const BORDER_TERMINAL_STREAMING := Color(1.0, 1.0, 1.0, 0.2)  # Same as copilot message border
	const BORDER_ERROR := Color(0.8, 0.3, 0.3, 0.9)  # Red border for errors
	const BORDER_INFO := Color(0.8, 0.6, 0.3, 0.9)  # Amber border for info
	const BORDER_USER_MESSAGE := Color(1.0, 1.0, 1.0, 0.12)  # Subtle white border for user messages
	const BORDER_TODO_LIST := Color(0.6, 0.8, 1.0, 0.25)  # Blue border for todo lists
	const BORDER_PROGRESS := Color(0.5, 0.9, 0.6, 0.25)  # Green border for progress widgets
	const BORDER_PROGRESS_BAR := Color(0.4, 0.4, 0.4, 0.2)  # Subtle border for progress bar

	# Text Colors
	const TEXT_USER := Color(1.0, 1.0, 1.0, 0.95)  # White text for user messages
	const TEXT_COPILOT := Color(0.9, 0.9, 0.9, 0.9)  # Slightly dimmed white for copilot
	const TEXT_TERMINAL := Color(0.0, 1.0, 0.25, 1.0)  # Matrix green (#00FF41)
	const TEXT_ERROR := Color(1.0, 0.8, 0.8, 1.0)  # Light pink for error text
	const TEXT_INFO := Color(1.0, 0.95, 0.85, 1.0)  # Light amber for info text
	const TEXT_HEADER := Color(0.8, 0.8, 0.8, 1.0)  # Gray for headers
	const TEXT_ATTACHMENT := Color(0.2, 0.2, 0.2, 1.0)  # Dark gray for attachment chip text
	const TEXT_EPHEMERAL := Color(0.7, 0.7, 0.7, 1.0)  # Gray for ephemeral messages

	# Icon Colors
	const ICON_TOOL := Color(0.3, 0.5, 0.7, 1.0)  # Blue for tool icons

	# Gradient Colors (for animated gradient text effect)
	const GRADIENT_1 := Color(0.3, 0.5, 0.9, 1.0)  # Blue
	const GRADIENT_2 := Color(0.6, 0.3, 0.9, 1.0)  # Purple
	const GRADIENT_3 := Color(0.9, 0.3, 0.6, 1.0)  # Pink

	# Opacity Values
	const OPACITY_HEADER := 0.5  # Header transparency
	const OPACITY_EPHEMERAL := 0.8  # Ephemeral message opacity

const COLORS := Colors

# ========== SPACING ==========

class Spacing:
	# Padding Constants
	const PADDING_XS := 4.0
	const PADDING_SM := 8.0
	const PADDING_MD := 12.0
	const PADDING_LG := 16.0
	const PADDING_XL := 24.0

	# Vertical Padding
	const PADDING_VERTICAL_XS := 2.0
	const PADDING_VERTICAL_SM := 4.0
	const PADDING_VERTICAL_MD := 6.0
	const PADDING_VERTICAL_LG := 8.0
	const PADDING_VERTICAL_XL := 12.0

	# Margins
	const MARGIN_SM := 4.0
	const MARGIN_MD := 8.0
	const MARGIN_LG := 12.0
	const MARGIN_XL := 16.0

	# Heights
	const HEIGHT_TERMINAL_FIXED := 300.0  # Fixed height for streaming terminal

	# Separations
	const SEPARATION_SM := 4.0
	const SEPARATION_MD := 8.0
	const SEPARATION_LG := 12.0

const SPACING := Spacing

# ========== BORDERS ==========

class Borders:
	# Corner Radii
	const CORNER_SM := 4.0
	const CORNER_MD := 8.0  # Terminal panels
	const CORNER_LG := 12.0  # Message bubbles, attachment chips

	# Border Widths
	const BORDER_THIN := 1.0
	const BORDER_MEDIUM := 2.0
	const BORDER_THICK := 3.0

	# Anti-aliasing
	const ANTI_ALIASING := true
	const ANTI_ALIASING_SIZE := 2.0

const BORDERS := Borders

# ========== TYPOGRAPHY ==========

class Typography:
	# Font Sizes (base sizes before editor scale multiplication)
	const FONT_SIZE_DEFAULT := 15  # All message content
	const FONT_SIZE_SMALL := 14    # Small labels, metadata, hints
	const FONT_SIZE_HEADER := 18   # Headers (tool_call, tool_result)
	const FONT_SIZE_LARGE := 20    # Large headers (settings sections)

	# Monospace font size multiplier (monospace fonts appear larger than sans-serif at same size)
	const MONOSPACE_SIZE_MULTIPLIER := 0.875  # 87.5% of Inter size for visual matching

	# Line Separation
	const LINE_SEPARATION := 6  # Space between lines in CodeEdit

const TYPOGRAPHY := Typography

# ========== HELPER FUNCTIONS ==========

static func darken(color: Color, amount: float) -> Color:
	return color.darkened(amount)

# ========== SPACING HELPERS ==========

## Returns spacing value scaled by editor scale (for consistent sizing across displays)
## Apply editor scaling to spacing values for renderer heights, margins, and separations
static func spacing(value: float) -> float:
	var editor_scale = EditorInterface.get_editor_scale()
	return value * editor_scale

## Apply padding to a StyleBoxFlat (symmetric)
## Use this when manually creating StyleBoxFlat
static func apply_dpi_padding(stylebox: StyleBoxFlat, horizontal: float, vertical: float) -> StyleBoxFlat:
	stylebox.content_margin_left = horizontal
	stylebox.content_margin_right = horizontal
	stylebox.content_margin_top = vertical
	stylebox.content_margin_bottom = vertical
	return stylebox

## Apply padding to a StyleBoxFlat (custom per side)
## Use this when different padding is needed on each side
static func apply_dpi_padding_custom(stylebox: StyleBoxFlat, left: float, right: float, top: float, bottom: float) -> StyleBoxFlat:
	stylebox.content_margin_left = left
	stylebox.content_margin_right = right
	stylebox.content_margin_top = top
	stylebox.content_margin_bottom = bottom
	return stylebox

static func apply_monospace_font(control: Control, size: int = Typography.FONT_SIZE_DEFAULT) -> void:
	if control is RichTextLabel:
		apply_monospace_font_to_rich_text(control, size)
		return

	var editor_scale = EditorInterface.get_editor_scale()
	# Apply monospace size multiplier for visual matching with Inter font
	var scaled_size = int(size * Typography.MONOSPACE_SIZE_MULTIPLIER * editor_scale)

	if _cached_mono_font == null:
		_cached_mono_font = load(JETBRAINS_MONO_FONT_PATH)
	if _cached_mono_font:
		control.add_theme_font_override("font", _cached_mono_font)

	control.add_theme_font_size_override("font_size", scaled_size)

## Apply monospace font to RichTextLabel (requires special font overrides)
static func apply_monospace_font_to_rich_text(rich_text_label: RichTextLabel, size: int = Typography.FONT_SIZE_DEFAULT) -> void:
	var editor_scale = EditorInterface.get_editor_scale()
	# Apply monospace size multiplier for visual matching with Inter font
	var scaled_size = int(size * Typography.MONOSPACE_SIZE_MULTIPLIER * editor_scale)

	if _cached_mono_font == null:
		_cached_mono_font = load(JETBRAINS_MONO_FONT_PATH)

	if _cached_mono_font:
		rich_text_label.add_theme_font_override("normal_font", _cached_mono_font)
		rich_text_label.add_theme_font_override("bold_font", _cached_mono_font)
		rich_text_label.add_theme_font_override("italics_font", _cached_mono_font)
		rich_text_label.add_theme_font_override("bold_italics_font", _cached_mono_font)
		rich_text_label.add_theme_font_override("mono_font", _cached_mono_font)

	rich_text_label.add_theme_font_size_override("normal_font_size", scaled_size)
	rich_text_label.add_theme_font_size_override("bold_font_size", scaled_size)
	rich_text_label.add_theme_font_size_override("italics_font_size", scaled_size)
	rich_text_label.add_theme_font_size_override("bold_italics_font_size", scaled_size)
	rich_text_label.add_theme_font_size_override("mono_font_size", scaled_size)

## Apply Inter font to a control (for regular text, not code)
static func apply_inter_font(control: Control, size: int = Typography.FONT_SIZE_DEFAULT) -> void:
	if control is RichTextLabel:
		apply_inter_font_to_rich_text(control, size)
		return

	var editor_scale = EditorInterface.get_editor_scale()
	var scaled_size = int(size * editor_scale)

	if _cached_inter_font == null:
		_cached_inter_font = load(INTER_FONT_PATH)
	if _cached_inter_font:
		control.add_theme_font_override("font", _cached_inter_font)

	control.add_theme_font_size_override("font_size", scaled_size)

## Apply Inter font to RichTextLabel (for regular text, not code)
static func apply_inter_font_to_rich_text(rich_text_label: RichTextLabel, size: int = Typography.FONT_SIZE_DEFAULT) -> void:
	var editor_scale = EditorInterface.get_editor_scale()
	var scaled_size = int(size * editor_scale)

	if _cached_inter_font == null:
		_cached_inter_font = load(INTER_FONT_PATH)

	if _cached_inter_font:
		rich_text_label.add_theme_font_override("normal_font", _cached_inter_font)
		rich_text_label.add_theme_font_override("bold_font", _cached_inter_font)
		rich_text_label.add_theme_font_override("italics_font", _cached_inter_font)
		rich_text_label.add_theme_font_override("bold_italics_font", _cached_inter_font)

	# Keep mono_font as monospace for code blocks within markdown
	if _cached_mono_font == null:
		_cached_mono_font = load(JETBRAINS_MONO_FONT_PATH)
	if _cached_mono_font:
		rich_text_label.add_theme_font_override("mono_font", _cached_mono_font)

	rich_text_label.add_theme_font_size_override("normal_font_size", scaled_size)
	rich_text_label.add_theme_font_size_override("bold_font_size", scaled_size)
	rich_text_label.add_theme_font_size_override("italics_font_size", scaled_size)
	rich_text_label.add_theme_font_size_override("bold_italics_font_size", scaled_size)
	rich_text_label.add_theme_font_size_override("mono_font_size", scaled_size)

## Ensure a color is visible on dark backgrounds
## Returns the color if luminance is above threshold, otherwise lightens it
static func ensure_visible_on_dark(color: Color, min_luminance: float = 0.25) -> Color:
	# Calculate relative luminance using sRGB formula
	var luminance = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
	if luminance >= min_luminance:
		return color
	# Lighten the color to meet minimum luminance
	var factor = min_luminance / maxf(luminance, 0.001)
	return Color(
		minf(color.r * factor, 1.0),
		minf(color.g * factor, 1.0),
		minf(color.b * factor, 1.0),
		color.a
	)
