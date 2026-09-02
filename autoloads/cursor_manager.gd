extends Node

## Global semantic cursor layer. Controls keep their native Godot cursor shapes,
## while the textures behind those shapes share one authored visual language.
## World interactions publish priority claims because they do not have a
## Control node under the pointer.

const ROLE_DEFAULT := &"default"
const ROLE_ACTION := &"action"
const ROLE_TEXT := &"text"
const ROLE_SELECT := &"select"
const ROLE_DEPLOY := &"deploy"
const ROLE_TRAP := &"trap"
const ROLE_HEAL := &"heal"
const ROLE_INVALID := &"invalid"
const ROLE_PAN := &"pan"
const ROLE_PAN_GRAB := &"pan_grab"
const ROLE_BUSY := &"busy"

const META_CURSOR_ROLE := &"cursor_role"

const ROLE_SHAPES := {
	ROLE_DEFAULT: Control.CURSOR_ARROW,
	ROLE_ACTION: Control.CURSOR_POINTING_HAND,
	ROLE_TEXT: Control.CURSOR_IBEAM,
	ROLE_SELECT: Control.CURSOR_CROSS,
	ROLE_DEPLOY: Control.CURSOR_CAN_DROP,
	# VSPLIT is intentionally reserved as the trap cursor channel. The project
	# has no split-pane UI, so this preserves a unique native/web cursor slot.
	ROLE_TRAP: Control.CURSOR_VSPLIT,
	ROLE_HEAL: Control.CURSOR_HELP,
	ROLE_INVALID: Control.CURSOR_FORBIDDEN,
	ROLE_PAN: Control.CURSOR_MOVE,
	ROLE_PAN_GRAB: Control.CURSOR_DRAG,
	ROLE_BUSY: Control.CURSOR_BUSY,
}

const ROLE_TEXTURES := {
	ROLE_DEFAULT: preload("res://assets/ui/cursors/cursor_default.png"),
	ROLE_ACTION: preload("res://assets/ui/cursors/cursor_action.png"),
	ROLE_TEXT: preload("res://assets/ui/cursors/cursor_text.png"),
	ROLE_SELECT: preload("res://assets/ui/cursors/cursor_select.png"),
	ROLE_DEPLOY: preload("res://assets/ui/cursors/cursor_deploy.png"),
	ROLE_TRAP: preload("res://assets/ui/cursors/cursor_trap.png"),
	ROLE_HEAL: preload("res://assets/ui/cursors/cursor_heal.png"),
	ROLE_INVALID: preload("res://assets/ui/cursors/cursor_invalid.png"),
	ROLE_PAN: preload("res://assets/ui/cursors/cursor_pan.png"),
	ROLE_PAN_GRAB: preload("res://assets/ui/cursors/cursor_pan_grab.png"),
	ROLE_BUSY: preload("res://assets/ui/cursors/cursor_busy.png"),
}

const ROLE_HOTSPOTS := {
	ROLE_DEFAULT: Vector2(5, 3),
	ROLE_ACTION: Vector2(10, 2),
	ROLE_TEXT: Vector2(16, 16),
	ROLE_SELECT: Vector2(16, 16),
	ROLE_DEPLOY: Vector2(16, 16),
	ROLE_TRAP: Vector2(16, 16),
	ROLE_HEAL: Vector2(16, 16),
	ROLE_INVALID: Vector2(16, 16),
	ROLE_PAN: Vector2(16, 16),
	ROLE_PAN_GRAB: Vector2(16, 16),
	ROLE_BUSY: Vector2(16, 16),
}

var _claims: Dictionary = {}
var _claim_serial := 0
var _active_role := ROLE_DEFAULT
var _custom_cursors_installed := false
var _pointer_is_in_window := true
var _window_has_focus := true


func _ready() -> void:
	_install_custom_cursors()
	get_tree().node_added.connect(_on_node_added)
	_classify_descendants(get_tree().root)
	_apply_active_role(ROLE_DEFAULT, true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_MOUSE_ENTER:
			_pointer_is_in_window = true
			_refresh_cursor_availability()
		NOTIFICATION_WM_MOUSE_EXIT:
			_pointer_is_in_window = false
			_refresh_cursor_availability()
		NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_window_has_focus = true
			_refresh_cursor_availability()
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_window_has_focus = false
			_refresh_cursor_availability()


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	_uninstall_custom_cursors()


func _process(_delta: float) -> void:
	_resolve_claims()
	# Disabled state can change without a dedicated signal. Refreshing only the
	# hovered control keeps that transition exact without walking the UI tree.
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null:
		_apply_control_shape(hovered)


func claim(owner: Object, role: StringName, priority: int = 0) -> bool:
	if owner == null or not is_instance_valid(owner) or not ROLE_SHAPES.has(role):
		return false
	var owner_id := owner.get_instance_id()
	var existing: Dictionary = _claims.get(owner_id, {})
	if (
		StringName(existing.get("role", &"")) == role
		and int(existing.get("priority", -1)) == priority
	):
		return true
	_claim_serial += 1
	_claims[owner_id] = {
		"owner": weakref(owner),
		"role": role,
		"priority": priority,
		"serial": _claim_serial,
	}
	_resolve_claims()
	return true


func release_claim(owner: Object) -> void:
	if owner == null:
		return
	_claims.erase(owner.get_instance_id())
	_resolve_claims()


func set_control_role(control: Control, role: StringName) -> bool:
	if control == null or not ROLE_SHAPES.has(role):
		return false
	control.set_meta(META_CURSOR_ROLE, role)
	_apply_control_shape(control)
	return true


func clear_control_role(control: Control) -> void:
	if control == null:
		return
	control.remove_meta(META_CURSOR_ROLE)
	_apply_control_shape(control)


func active_role() -> StringName:
	return _active_role


func registered_roles() -> Array[StringName]:
	var names: Array[String] = []
	for role: StringName in ROLE_SHAPES:
		names.append(String(role))
	names.sort()
	var roles: Array[StringName] = []
	for role_name: String in names:
		roles.append(StringName(role_name))
	return roles


func shape_for_role(role: StringName) -> int:
	return int(ROLE_SHAPES.get(role, Control.CURSOR_ARROW))


func hotspot_for_role(role: StringName) -> Vector2:
	return ROLE_HOTSPOTS.get(role, Vector2.ZERO) as Vector2


func texture_for_role(role: StringName) -> Texture2D:
	return ROLE_TEXTURES.get(role) as Texture2D


func shape_for_control(control: Control) -> int:
	if control == null:
		return Control.CURSOR_ARROW
	var explicit_role := StringName(control.get_meta(META_CURSOR_ROLE, &""))
	if not explicit_role.is_empty() and ROLE_SHAPES.has(explicit_role):
		return shape_for_role(explicit_role)
	if control is BaseButton:
		return (
			shape_for_role(ROLE_INVALID)
			if (control as BaseButton).disabled
			else shape_for_role(ROLE_ACTION)
		)
	if control is LineEdit or control is TextEdit:
		return shape_for_role(ROLE_TEXT)
	if control is Slider:
		return shape_for_role(ROLE_ACTION)
	return Control.CURSOR_ARROW


func _install_custom_cursors() -> void:
	if _custom_cursors_installed:
		return
	for role: StringName in ROLE_SHAPES:
		var texture := texture_for_role(role)
		if texture == null:
			push_error("CursorManager: missing texture for role %s" % role)
			continue
		Input.set_custom_mouse_cursor(
			texture,
			shape_for_role(role),
			hotspot_for_role(role),
		)
	_custom_cursors_installed = true


func _uninstall_custom_cursors() -> void:
	for role: StringName in ROLE_SHAPES:
		Input.set_custom_mouse_cursor(null, shape_for_role(role))
	Input.set_default_cursor_shape(shape_for_role(ROLE_DEFAULT))
	_custom_cursors_installed = false


func _refresh_cursor_availability() -> void:
	if _pointer_is_in_window and _window_has_focus:
		_install_custom_cursors()
		_apply_active_role(_active_role, true)
	else:
		_uninstall_custom_cursors()


func _resolve_claims() -> void:
	var stale_ids: Array[int] = []
	var best_role := ROLE_DEFAULT
	var best_priority := -2147483648
	var best_serial := -1
	for owner_id: int in _claims:
		var row: Dictionary = _claims[owner_id]
		var owner_ref := row.get("owner") as WeakRef
		if owner_ref == null or owner_ref.get_ref() == null:
			stale_ids.append(owner_id)
			continue
		var priority := int(row["priority"])
		var serial := int(row["serial"])
		if priority > best_priority or (priority == best_priority and serial > best_serial):
			best_priority = priority
			best_serial = serial
			best_role = StringName(row["role"])
	for owner_id: int in stale_ids:
		_claims.erase(owner_id)
	_apply_active_role(best_role)


func _apply_active_role(role: StringName, force: bool = false) -> void:
	if not force and role == _active_role:
		return
	_active_role = role
	if _custom_cursors_installed:
		Input.set_default_cursor_shape(shape_for_role(role))


func _on_node_added(node: Node) -> void:
	if node is Control:
		_apply_control_shape_by_id.call_deferred(node.get_instance_id())


func _apply_control_shape_by_id(instance_id: int) -> void:
	var instance := instance_from_id(instance_id)
	if instance is Control:
		_apply_control_shape(instance as Control)


func _classify_descendants(node: Node) -> void:
	if node is Control:
		_apply_control_shape(node as Control)
	for child: Node in node.get_children():
		_classify_descendants(child)


func _apply_control_shape(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var shape := shape_for_control(control)
	# Leave ordinary containers on CURSOR_ARROW so active world claims can flow
	# through them; only genuinely interactive controls own an explicit shape.
	if (
		control.has_meta(META_CURSOR_ROLE)
		or control is BaseButton
		or control is LineEdit
		or control is TextEdit
		or control is Slider
	):
		control.mouse_default_cursor_shape = shape
