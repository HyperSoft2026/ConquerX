extends Control

signal vector_changed(value: Vector2)

const RADIUS := 78.0
const KNOB_RADIUS := 29.0
var active := false
var touch_id := -1
var knob_position := Vector2.ZERO
var base_color := Color(0.20, 0.72, 1.0, 0.34)
var knob_color := Color(0.30, 0.83, 1.0, 0.88)

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_NONE
    custom_minimum_size = Vector2(240, 240)
    knob_position = size * 0.5
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        if not active:
            knob_position = size * 0.5
        queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and touch_id == -1:
            touch_id = event.index
            active = true
            _update_from_position(event.position)
            accept_event()
        elif not event.pressed and event.index == touch_id:
            _release()
            accept_event()
    elif event is InputEventScreenDrag and active and event.index == touch_id:
        _update_from_position(event.position)
        accept_event()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed and touch_id == -1:
            touch_id = -2
            active = true
            _update_from_position(event.position)
            accept_event()
        elif not event.pressed and touch_id == -2:
            _release()
            accept_event()
    elif event is InputEventMouseMotion and active and touch_id == -2:
        _update_from_position(event.position)
        accept_event()

func _update_from_position(screen_position: Vector2) -> void:
    var local_position := screen_position - global_position
    var center := size * 0.5
    var offset := local_position - center
    if offset.length() > RADIUS:
        offset = offset.normalized() * RADIUS
    knob_position = center + offset
    vector_changed.emit(offset / RADIUS)
    queue_redraw()

func _release() -> void:
    active = false
    touch_id = -1
    knob_position = size * 0.5
    vector_changed.emit(Vector2.ZERO)
    queue_redraw()

func _draw() -> void:
    var center := size * 0.5
    var ring := Color(0.15, 0.56, 0.95, 0.62 if active else 0.30)
    draw_circle(center, RADIUS + 7.0, Color(0.02, 0.06, 0.14, 0.20 if active else 0.10))
    draw_circle(center, RADIUS, Color(0.04, 0.10, 0.22, 0.60 if active else 0.34))
    draw_arc(center, RADIUS, 0.0, TAU, 64, ring, 4.0, true)
    draw_circle(knob_position, KNOB_RADIUS + 4.0, Color(0.12, 0.48, 0.92, 0.40))
    draw_circle(knob_position, KNOB_RADIUS, knob_color if active else Color(0.35, 0.70, 0.95, 0.60))
    draw_arc(knob_position, KNOB_RADIUS, 0.0, TAU, 48, Color(0.75, 0.95, 1.0, 0.85), 2.0, true)
