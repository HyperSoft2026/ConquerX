extends Control

const SERVER_URL := "https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io"

@onready var status_label: Label = $Status
@onready var progress: ProgressBar = $Progress

func _ready() -> void:
    get_viewport().size_changed.connect(_layout_splash)
    _layout_splash()
    status_label.text = I18n.text_for("connecting")
    _start_splash()

func _start_splash() -> void:
    var tween := create_tween()
    tween.tween_property(progress, "value", 70.0, 0.25)
    tween.tween_callback(_check_server)

func _check_server() -> void:
    status_label.text = I18n.text_for("connecting")
    var request := HTTPRequest.new()
    request.timeout = 3.0
    add_child(request)
    request.request_completed.connect(_on_health_completed.bind(request))
    var error := request.request(SERVER_URL.rstrip("/") + "/health")
    if error != OK:
        _finish_with_offline(request)

func _on_health_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
    request.queue_free()
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
        status_label.text = I18n.text_for("server_online")
        progress.value = 100.0
    else:
        status_label.text = I18n.text_for("server_unavailable")
        progress.value = 100.0
    _open_login()

func _finish_with_offline(request: HTTPRequest) -> void:
    request.queue_free()
    status_label.text = I18n.text_for("server_unavailable")
    progress.value = 100.0
    await get_tree().create_timer(0.7).timeout
    _open_login()

func _open_login() -> void:
    get_tree().change_scene_to_file("res://game/scenes/main.tscn")

func _layout_splash() -> void:
    var viewport_size := get_viewport_rect().size
    var center := viewport_size * 0.5
    $Glow.visible = false
    $Logo.visible = false
    $Title.visible = false
    $Status.position = Vector2(0, viewport_size.y - 92)
    $Status.size = Vector2(viewport_size.x, 30)
    $Progress.position = Vector2(viewport_size.x * 0.25, viewport_size.y - 48)
    $Progress.size = Vector2(viewport_size.x * 0.5, 12)
