class_name ComponentStyles
extends RefCounted

## Pre-configured style presets for all copilot renderers
## Uses StyleBuilder and ThemeConstants for consistent styling across the application

# ========== MESSAGE PANELS ==========

## User message bubble style (dark semi-transparent with rounded corners)
static func user_message_panel() -> StyleBoxFlat:
	var editor_scale = EditorInterface.get_editor_scale()
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_USER_MESSAGE) \
		.corners(ThemeConstants.BORDERS.CORNER_LG * editor_scale) \
		.border(2.0 * editor_scale, ThemeConstants.COLORS.BORDER_USER_MESSAGE) \
		.padding(ThemeConstants.SPACING.PADDING_MD * editor_scale, 0) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

## Copilot message panel style (transparent, no background or border)
static func copilot_message_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.transparent() \
		.padding(ThemeConstants.SPACING.PADDING_SM, ThemeConstants.SPACING.PADDING_SM) \
		.build()

## Copilot message content style (transparent, for inner text area)
static func copilot_message_content() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.transparent() \
		.padding(ThemeConstants.SPACING.PADDING_SM, ThemeConstants.SPACING.PADDING_SM) \
		.build()

## System message panel style (cyan-tinted, similar to current implementation)
static func system_message_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(Color(0.1, 0.3, 0.35, 0.8)) \
		.corners(ThemeConstants.BORDERS.CORNER_MD) \
		.border(ThemeConstants.BORDERS.BORDER_THIN, Color(0.3, 0.7, 0.8, 0.9)) \
		.padding(ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_SM) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

# ========== TERMINAL PANELS ==========

## Terminal panel style (dark background, gray border, 8px corners)
static func terminal_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_TERMINAL) \
		.corners(ThemeConstants.BORDERS.CORNER_MD) \
		.border(ThemeConstants.BORDERS.BORDER_THIN, ThemeConstants.COLORS.BORDER_TERMINAL) \
		.padding(ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_SM) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

## Terminal streaming panel style (transparent, no background or border)
static func terminal_streaming_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.transparent() \
		.padding(ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_SM) \
		.build()

## Terminal content style (for CodeEdit widget inside terminal)
static func terminal_content() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.transparent() \
		.padding_custom(8, 0, 0, 0) \
		.build()

# ========== COLLAPSIBLE PANELS ==========

## Collapsible transparent panel (for thinking blocks - purple-tinted with border)
static func collapsible_transparent_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(Color(0.15, 0.15, 0.2, 0.3)) \
		.corners(ThemeConstants.BORDERS.CORNER_MD) \
		.border(ThemeConstants.BORDERS.BORDER_THIN, Color(0.4, 0.4, 0.5, 0.6)) \
		.padding(ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_SM) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

# ========== ERROR PANELS ==========

## Error panel style (red-tinted background, red border)
static func error_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_ERROR) \
		.corners(ThemeConstants.BORDERS.CORNER_LG) \
		.border(ThemeConstants.BORDERS.BORDER_MEDIUM, ThemeConstants.COLORS.BORDER_ERROR) \
		.padding(ThemeConstants.SPACING.PADDING_LG, ThemeConstants.SPACING.PADDING_MD) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

## Error retry button style
static func error_button() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_BUTTON_ERROR) \
		.corners(ThemeConstants.BORDERS.CORNER_SM) \
		.padding(ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_VERTICAL_SM) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

## Error retry button hover style
static func error_button_hover() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_BUTTON_ERROR_HOVER) \
		.corners(ThemeConstants.BORDERS.CORNER_SM) \
		.padding(ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_VERTICAL_SM) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

# ========== INFO PANELS ==========

## Info panel style (amber-tinted background, amber border)
static func info_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_INFO) \
		.corners(ThemeConstants.BORDERS.CORNER_MD) \
		.border(ThemeConstants.BORDERS.BORDER_MEDIUM, ThemeConstants.COLORS.BORDER_INFO) \
		.padding_custom(ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_SM, ThemeConstants.SPACING.PADDING_MD) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

# ========== ATTACHMENT CHIPS ==========

## Attachment chip style (light blue-gray background, rounded corners) - DPI-aware
static func attachment_chip() -> StyleBoxFlat:
	var style = StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_ATTACHMENT_CHIP) \
		.corners(ThemeConstants.BORDERS.CORNER_LG) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()
	# Apply DPI-adjusted padding
	ThemeConstants.apply_dpi_padding(style, ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_VERTICAL_MD)
	return style

## Attachment chip hover style (lightened background) - DPI-aware
static func attachment_chip_hover() -> StyleBoxFlat:
	var style = StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_ATTACHMENT_CHIP_HOVER) \
		.corners(ThemeConstants.BORDERS.CORNER_LG) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()
	# Apply DPI-adjusted padding
	ThemeConstants.apply_dpi_padding(style, ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_VERTICAL_MD)
	return style

## Image preview container style
static func image_preview_container() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_IMAGE_PREVIEW) \
		.corners(ThemeConstants.BORDERS.CORNER_MD) \
		.padding(ThemeConstants.SPACING.PADDING_SM, ThemeConstants.SPACING.PADDING_SM) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

# ========== LABELS ==========

## Transparent label style (no background, no padding)
static func transparent_label() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.transparent() \
		.padding_all(0) \
		.build()

## Transparent label with padding
static func transparent_label_with_padding() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.transparent() \
		.padding(ThemeConstants.SPACING.PADDING_SM, ThemeConstants.SPACING.PADDING_VERTICAL_SM) \
		.build()

# ========== HEADER STYLES ==========

## Header style for collapsible sections (transparent with bottom border)
static func collapsible_header() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.transparent() \
		.border_custom(0, 0, 0, 1, ThemeConstants.COLORS.BORDER_TERMINAL) \
		.padding(ThemeConstants.SPACING.PADDING_SM, ThemeConstants.SPACING.PADDING_VERTICAL_SM) \
		.build()

## Header style for terminal sections
static func terminal_header() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.darken(ThemeConstants.COLORS.BG_TERMINAL, 0.1)) \
		.corners_custom(ThemeConstants.BORDERS.CORNER_MD, ThemeConstants.BORDERS.CORNER_MD, 0, 0) \
		.padding(ThemeConstants.SPACING.PADDING_MD, ThemeConstants.SPACING.PADDING_VERTICAL_SM) \
		.build()

# ========== WIDGET PANELS (Todo, Progress, etc.) ==========

## Todo list panel style (light blue background with border)
static func todo_list_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_TODO_LIST) \
		.corners(ThemeConstants.BORDERS.CORNER_LG) \
		.border(ThemeConstants.BORDERS.BORDER_MEDIUM, ThemeConstants.COLORS.BORDER_TODO_LIST) \
		.padding(16.0, 12.0) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

## Progress panel style (light green background with border)
static func progress_panel() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_PROGRESS) \
		.corners(ThemeConstants.BORDERS.CORNER_LG) \
		.border(ThemeConstants.BORDERS.BORDER_MEDIUM, ThemeConstants.COLORS.BORDER_PROGRESS) \
		.padding(ThemeConstants.SPACING.PADDING_XL, ThemeConstants.SPACING.PADDING_LG) \
		.anti_aliasing(ThemeConstants.BORDERS.ANTI_ALIASING, ThemeConstants.BORDERS.ANTI_ALIASING_SIZE) \
		.build()

## Progress bar fill style (bright green)
static func progress_bar_fill() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_PROGRESS_FILL) \
		.corners(6.0) \
		.build()

## Progress bar background style (dark with subtle border)
static func progress_bar_background() -> StyleBoxFlat:
	return StyleBuilder.new() \
		.background(ThemeConstants.COLORS.BG_PROGRESS_BAR) \
		.corners(6.0) \
		.border(ThemeConstants.BORDERS.BORDER_THIN, ThemeConstants.COLORS.BORDER_PROGRESS_BAR) \
		.build()
