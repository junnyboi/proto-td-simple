extends Node

## Normalize browser wheel/pinch without scaling the page or bypassing Godot GUI input.
## Each battle owns its listeners; leaving the scene removes them.
const INSTALL_SCRIPT := """
window.__tdInstallMapZoom = function (callback) {
    const canvas = document.getElementById('canvas');
    if (!canvas) return null;
    let gestureScale = 1;
    let gesturing = false;
    const consume = event => {
        event.preventDefault();
        event.stopImmediatePropagation();
    };
    const emit = (event, factor) => {
        const rect = canvas.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0 || !Number.isFinite(factor) || factor <= 0) return;
        callback((event.clientX - rect.left) / rect.width,
                 (event.clientY - rect.top) / rect.height, factor);
    };
    const wheel = event => {
        // Preserve Shift-wheel and horizontal panning in Godot's native input path.
        if (event.shiftKey || !event.deltaY) return;
        consume(event);
        if (gesturing) return;
        const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? canvas.clientHeight : 1;
        const delta = Math.max(-400, Math.min(400, event.deltaY * unit));
        emit(event, Math.exp(-delta * (event.ctrlKey ? 0.01 : 0.002)));
    };
    const start = event => {
        consume(event);
        gesturing = true;
        gestureScale = event.scale > 0 ? event.scale : 1;
    };
    const change = event => {
        consume(event);
        if (!gesturing || !Number.isFinite(event.scale) || event.scale <= 0) return;
        emit(event, event.scale / gestureScale);
        gestureScale = event.scale;
    };
    const end = event => { consume(event); gesturing = false; };
    const reset = () => { gesturing = false; };
    const listeners = [['wheel', wheel], ['gesturestart', start], ['gesturechange', change], ['gestureend', end]];
    for (const [type, handler] of listeners) canvas.addEventListener(type, handler, {capture: true, passive: false});
    window.addEventListener('blur', reset);
    return {dispose() {
        for (const [type, handler] of listeners) canvas.removeEventListener(type, handler, true);
        window.removeEventListener('blur', reset);
    }};
};
"""

var _callback: JavaScriptObject
var _listeners: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_callback = JavaScriptBridge.create_callback(_on_zoom)
	JavaScriptBridge.eval(INSTALL_SCRIPT, true)
	_listeners = JavaScriptBridge.get_interface("window").__tdInstallMapZoom(_callback)


func _on_zoom(arguments: Array) -> void:
	if arguments.size() != 3 or not is_inside_tree():
		return
	var event := InputEventMagnifyGesture.new()
	event.position = Vector2(float(arguments[0]), float(arguments[1])) * get_viewport().get_visible_rect().size
	event.factor = float(arguments[2])
	Input.parse_input_event(event)


func _exit_tree() -> void:
	if _listeners != null:
		_listeners.dispose()
	_listeners = null
	_callback = null
