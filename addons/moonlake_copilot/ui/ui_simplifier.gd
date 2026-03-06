class_name UISimplifier
extends RefCounted

## Simplifies Godot editor UI by hiding specific elements

const HIDE_BUTTON_TOOLTIPS = [
	"Play the edited scene",
	"Play a custom scene",
	"Forward+",
	"Mobile",
	"Compatibility",
	"Remote",
	"Movie",
	"movie"
]

const HIDE_MENU_TEXTS = ["Transform", "View"]

static var _closed_docks: Array[Control] = []


static func apply() -> void:
	_closed_docks.clear()
	_walk_tree(EditorInterface.get_base_control(), 0, true)


static func restore() -> void:
	_walk_tree(EditorInterface.get_base_control(), 0, false)

	for dock in _closed_docks:
		if is_instance_valid(dock):
			EditorInterface.open_dock(dock)
	_closed_docks.clear()


static func _walk_tree(node: Node, depth: int, hiding: bool) -> void:
	if depth > 20:
		return

	_process_node(node, hiding)

	for child in node.get_children():
		_walk_tree(child, depth + 1, hiding)


static func _process_node(node: Node, hiding: bool) -> void:
	# Docks (only close, don't hide)
	if hiding and node.get_class() in ["NodeDock", "HistoryDock"]:
		if node not in _closed_docks:
			_closed_docks.append(node)
			EditorInterface.close_dock(node)
		return

	# Buttons by tooltip
	if node is Button or node is OptionButton:
		for keyword in HIDE_BUTTON_TOOLTIPS:
			if keyword in node.tooltip_text:
				node.visible = not hiding
				return

	# Menus by text
	if node is MenuButton:
		if node.text in HIDE_MENU_TEXTS:
			node.visible = not hiding
			return

	# Toolbar buttons
	if node is HBoxContainer and _is_scene_editor_toolbar(node):
		for child in node.get_children():
			if child is MenuButton and child.text in HIDE_MENU_TEXTS:
				child.visible = not hiding
			elif child is Button:
				if hiding:
					child.visible = _should_keep_toolbar_button(child)
				else:
					child.visible = true


static func _is_scene_editor_toolbar(container: HBoxContainer) -> bool:
	var button_count = 0
	var has_lock_button = false
	var has_group_button = false

	for child in container.get_children():
		if child is Button:
			button_count += 1
			var tooltip = child.tooltip_text
			if "Lock selected node" in tooltip or "Unlock selected node" in tooltip:
				has_lock_button = true
			if "Groups the selected node" in tooltip or "Ungroups the selected node" in tooltip:
				has_group_button = true

	return button_count >= 8 and has_lock_button and has_group_button


static func _should_keep_toolbar_button(button: Button) -> bool:
	var tooltip = button.tooltip_text.to_lower()

	# Keep Move, Rotate, Scale modes
	if "move mode" in tooltip or "rotate mode" in tooltip:
		return true
	if "scale" in tooltip and "proportionally" in tooltip:
		return true
	if "command+drag: use snap" in tooltip or "ctrl+drag: use snap" in tooltip:
		return true

	# Keep Lock and Group buttons
	if "lock selected node" in tooltip or "unlock selected node" in tooltip:
		return true
	if "groups the selected node" in tooltip or "ungroups the selected node" in tooltip:
		return true

	# Keep Snap configuration buttons
	if "snap" in tooltip or "snapping" in tooltip:
		return true

	# Keep Sun and Environment toggles (3D editor)
	if "sun" in tooltip or "environment" in tooltip:
		return true

	# Keep menu buttons (empty tooltip)
	if tooltip == "":
		return true

	return false
