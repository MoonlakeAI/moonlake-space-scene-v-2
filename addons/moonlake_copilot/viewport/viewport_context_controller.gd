@tool
extends RefCounted

signal asset_swapped(old_node: Node3D, new_node: Node3D)
signal prompt_sent(node: Node3D, prompt: String)

var chat_panel: Control = null
var plugin_ref = null

var context_popup: PopupPanel = null
var swap_model_button: Button = null
var context_text_box: TextEdit = null
var context_send_button: Button = null
var asset_selection_popup: Window = null
var selected_node: Node3D = null


func initialize(chat_pnl, plugin) -> void:
	chat_panel = chat_pnl
	plugin_ref = plugin


func forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var selection = EditorInterface.get_selection()
			var selected_nodes = selection.get_selected_nodes()

			if selected_nodes.size() > 0 and selected_nodes[0] is Node3D:
				var sel_node = selected_nodes[0] as Node3D

				var mouse_pos = mb.position
				var ray_origin = viewport_camera.project_ray_origin(mouse_pos)
				var ray_dir = viewport_camera.project_ray_normal(mouse_pos)
				var ray_end = ray_origin + ray_dir * 1000.0

				var space_state = sel_node.get_world_3d().direct_space_state
				var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
				query.collide_with_areas = true
				query.collide_with_bodies = true
				var result = space_state.intersect_ray(query)

				if result and result.has("collider"):
					var hit_node = result.collider
					if _is_node_or_child_of(hit_node, sel_node):
						selected_node = sel_node
						show_context_popup()
						return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _is_node_or_child_of(node: Node, target: Node) -> bool:
	while node:
		if node == target:
			return true
		node = node.get_parent()
	return false


func show_context_popup() -> void:
	var position = DisplayServer.mouse_get_position()

	if not context_popup or not is_instance_valid(context_popup):
		_create_context_popup()

	if context_popup and is_instance_valid(context_popup):
		_on_context_text_changed()
		context_popup.position = position
		context_popup.popup()


func _create_context_popup() -> void:
	var scale = EditorInterface.get_editor_scale()
	var corner_radius = int(8 * scale)
	var btn_radius = int(6 * scale)
	var padding = int(12 * scale)

	context_popup = PopupPanel.new()
	context_popup.size = Vector2(int(320 * scale), int(180 * scale))

	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color(0.12, 0.12, 0.12)
	popup_style.border_color = Color(0.25, 0.25, 0.25)
	popup_style.set_border_width_all(int(1 * scale))
	popup_style.set_corner_radius_all(corner_radius)
	popup_style.set_content_margin_all(padding)
	context_popup.add_theme_stylebox_override("panel", popup_style)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", int(10 * scale))
	context_popup.add_child(vbox)

	swap_model_button = Button.new()
	swap_model_button.text = "  Swap with existing model"
	swap_model_button.icon = EditorInterface.get_base_control().get_theme_icon("Reload", "EditorIcons")
	swap_model_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swap_model_button.custom_minimum_size.y = int(36 * scale)
	swap_model_button.pressed.connect(_on_swap_model_pressed)

	var swap_normal = StyleBoxFlat.new()
	swap_normal.bg_color = Color(0.2, 0.2, 0.2)
	swap_normal.set_corner_radius_all(btn_radius)
	var swap_hover = StyleBoxFlat.new()
	swap_hover.bg_color = Color(0.28, 0.28, 0.28)
	swap_hover.set_corner_radius_all(btn_radius)
	var swap_pressed = StyleBoxFlat.new()
	swap_pressed.bg_color = Color(0.15, 0.15, 0.15)
	swap_pressed.set_corner_radius_all(btn_radius)
	swap_model_button.add_theme_stylebox_override("normal", swap_normal)
	swap_model_button.add_theme_stylebox_override("hover", swap_hover)
	swap_model_button.add_theme_stylebox_override("pressed", swap_pressed)
	vbox.add_child(swap_model_button)

	var input_hbox = HBoxContainer.new()
	input_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_hbox.add_theme_constant_override("separation", int(8 * scale))
	vbox.add_child(input_hbox)

	context_text_box = TextEdit.new()
	context_text_box.placeholder_text = "Prompt this object..."
	context_text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	context_text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_text_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	context_text_box.text_changed.connect(_on_context_text_changed)

	var text_style = StyleBoxFlat.new()
	text_style.bg_color = Color(0.08, 0.08, 0.08)
	text_style.border_color = Color(0.3, 0.3, 0.3)
	text_style.set_border_width_all(int(1 * scale))
	text_style.set_corner_radius_all(btn_radius)
	text_style.set_content_margin_all(int(8 * scale))
	context_text_box.add_theme_stylebox_override("normal", text_style)
	context_text_box.add_theme_stylebox_override("focus", text_style)
	input_hbox.add_child(context_text_box)

	context_send_button = Button.new()
	context_send_button.icon = EditorInterface.get_base_control().get_theme_icon("ArrowUp", "EditorIcons")
	context_send_button.custom_minimum_size = Vector2(int(40 * scale), int(40 * scale))
	context_send_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	context_send_button.expand_icon = true
	context_send_button.pressed.connect(_on_context_prompt_submitted)
	context_send_button.disabled = true

	var send_normal = StyleBoxFlat.new()
	send_normal.bg_color = Color(0.95, 0.95, 0.95)
	send_normal.set_corner_radius_all(btn_radius)
	var send_hover = StyleBoxFlat.new()
	send_hover.bg_color = Color(1.0, 1.0, 1.0)
	send_hover.set_corner_radius_all(btn_radius)
	var send_pressed = StyleBoxFlat.new()
	send_pressed.bg_color = Color(0.85, 0.85, 0.85)
	send_pressed.set_corner_radius_all(btn_radius)
	var send_disabled = StyleBoxFlat.new()
	send_disabled.bg_color = Color(0.3, 0.3, 0.3)
	send_disabled.set_corner_radius_all(btn_radius)

	context_send_button.add_theme_stylebox_override("normal", send_normal)
	context_send_button.add_theme_stylebox_override("hover", send_hover)
	context_send_button.add_theme_stylebox_override("pressed", send_pressed)
	context_send_button.add_theme_stylebox_override("disabled", send_disabled)
	context_send_button.add_theme_color_override("icon_normal_color", Color.BLACK)
	context_send_button.add_theme_color_override("icon_hover_color", Color.BLACK)
	context_send_button.add_theme_color_override("icon_pressed_color", Color.BLACK)
	context_send_button.add_theme_color_override("icon_disabled_color", Color(0.5, 0.5, 0.5))
	input_hbox.add_child(context_send_button)

	EditorInterface.get_base_control().add_child(context_popup)


func _on_swap_model_pressed() -> void:
	if not selected_node:
		Log.warn("[MOONLAKE] No node selected for swap")
		return

	if context_popup:
		context_popup.hide()

	show_asset_selection_popup()


func _on_context_text_changed() -> void:
	if not context_send_button or not context_text_box:
		return
	var has_text = not context_text_box.text.strip_edges().is_empty()
	context_send_button.disabled = not has_text


func _on_context_prompt_submitted() -> void:
	if not selected_node or not context_text_box:
		return

	var prompt_text = context_text_box.text.strip_edges()
	if prompt_text.is_empty():
		return

	var message = "Edit %s: %s" % [selected_node.name, prompt_text]

	if chat_panel and chat_panel.input_controller:
		var input_ctrl = chat_panel.input_controller
		if input_ctrl.queued_message_controller:
			input_ctrl.queued_message_controller.add_message(message, [])
			if not input_ctrl.is_agent_streaming:
				chat_panel._try_send_queued_messages()

	prompt_sent.emit(selected_node, prompt_text)

	context_text_box.text = ""
	if context_popup:
		context_popup.hide()


func show_asset_selection_popup() -> void:
	if asset_selection_popup and is_instance_valid(asset_selection_popup):
		asset_selection_popup.grab_focus()
		return

	if not selected_node:
		return

	var scale = EditorInterface.get_editor_scale()

	asset_selection_popup = Window.new()
	asset_selection_popup.title = "Select Asset to Swap"
	asset_selection_popup.size = Vector2i(int(900 * scale), int(650 * scale))
	asset_selection_popup.unresizable = false
	asset_selection_popup.transient = true
	asset_selection_popup.exclusive = true

	var bg_panel = Panel.new()
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	asset_selection_popup.add_child(bg_panel)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad = int(16 * scale)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	asset_selection_popup.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", int(12 * scale))
	margin.add_child(main_vbox)

	var title_label = Label.new()
	title_label.text = "Select an asset to swap with '%s':" % selected_node.name
	title_label.add_theme_font_size_override("font_size", int(14 * scale))
	main_vbox.add_child(title_label)

	var browser = AssetBrowserFrame.new()
	browser.single_click_mode = true
	browser.show_overlay_buttons = false
	browser.set_base_cell_size(Vector2(180, 220))
	browser.asset_selected.connect(_on_asset_selected)
	main_vbox.add_child(browser)

	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size.y = int(32 * scale)
	cancel_button.pressed.connect(func():
		asset_selection_popup.queue_free()
		asset_selection_popup = null
	)
	main_vbox.add_child(cancel_button)

	EditorInterface.get_base_control().add_child(asset_selection_popup)
	asset_selection_popup.popup_centered()

	asset_selection_popup.close_requested.connect(func():
		asset_selection_popup.queue_free()
		asset_selection_popup = null
	)


func _on_asset_selected(glb_path: String) -> void:
	if not plugin_ref:
		Log.error("[MOONLAKE] Missing plugin reference")
		return

	if not selected_node or not is_instance_valid(selected_node):
		Log.error("[MOONLAKE] No valid node selected for swap")
		return

	var target_node: Node3D = selected_node

	if asset_selection_popup and is_instance_valid(asset_selection_popup):
		asset_selection_popup.hide()
		asset_selection_popup.queue_free()
		asset_selection_popup = null

	# Closing exclusive Window mid-click leaves stale mouse state blocking undo
	_clear_mouse_state()

	_perform_swap.call_deferred(target_node, glb_path)


func _clear_mouse_state() -> void:
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var event = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = false
		Input.parse_input_event(event)


func _perform_swap(target_node: Node3D, glb_path: String) -> void:
	if not is_instance_valid(target_node):
		Log.error("[MOONLAKE] Target node no longer valid")
		return

	Log.info("[MOONLAKE] Swap model: '%s' -> '%s'" % [target_node.name, glb_path.get_file()])

	var scene_resource = load(glb_path)
	if not scene_resource:
		Log.error("[MOONLAKE] Failed to load scene: " + glb_path)
		return

	var new_node = scene_resource.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if not new_node:
		Log.error("[MOONLAKE] Failed to instantiate scene: " + glb_path)
		return

	new_node.set_scene_file_path(glb_path)

	if not target_node.is_inside_tree():
		Log.error("[MOONLAKE] Selected node is not in scene tree")
		return

	var parent = target_node.get_parent()
	var node_transform = target_node.transform
	var node_index = target_node.get_index()
	var node_owner = target_node.owner
	var scene_root = EditorInterface.get_edited_scene_root()

	if not parent:
		Log.error("[MOONLAKE] Selected node has no parent")
		new_node.queue_free()
		return

	var base_name = glb_path.get_file().get_basename()
	var new_name = base_name
	var counter = 2
	while parent.has_node(NodePath(new_name)):
		new_name = base_name + str(counter)
		counter += 1

	new_node.name = new_name
	new_node.transform = node_transform

	var undo_redo = plugin_ref.get_undo_redo()
	undo_redo.create_action("Swap Model", UndoRedo.MERGE_DISABLE, scene_root)

	undo_redo.add_undo_reference(target_node)
	undo_redo.add_do_reference(new_node)

	undo_redo.add_do_method(parent, "remove_child", target_node)
	undo_redo.add_do_method(parent, "add_child", new_node)
	undo_redo.add_do_method(parent, "move_child", new_node, node_index)
	undo_redo.add_do_method(new_node, "set_owner", scene_root)

	undo_redo.add_undo_method(parent, "remove_child", new_node)
	undo_redo.add_undo_method(parent, "add_child", target_node)
	undo_redo.add_undo_method(parent, "move_child", target_node, node_index)
	undo_redo.add_undo_method(target_node, "set_owner", node_owner)

	undo_redo.commit_action(true)

	_set_owner_recursive(new_node, scene_root)

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(new_node)

	EditorInterface.mark_scene_as_unsaved()

	asset_swapped.emit(target_node, new_node)

	selected_node = null


func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	for child in node.get_children():
		child.owner = new_owner
		_set_owner_recursive(child, new_owner)


func cleanup() -> void:
	if context_popup:
		if context_popup.get_parent():
			context_popup.get_parent().remove_child(context_popup)
		context_popup.queue_free()
		context_popup = null

	if asset_selection_popup and is_instance_valid(asset_selection_popup):
		asset_selection_popup.queue_free()
		asset_selection_popup = null
