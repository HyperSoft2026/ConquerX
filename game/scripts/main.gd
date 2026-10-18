extends Node2D

# Development server URL. Replace with the final Clever Cloud public URL.
const SERVER_URL := ""

@onready var status_value: Label = $StatusPanel/StatusValue
@onready var continue_button: Button = $ContinueButton

func _ready() -> void:
    continue_button.pressed.connect(_on_continue_pressed)
    if SERVER_URL.is_empty():
        status_value.text = "Development build ready"
        return
    _check_server()

func _check_server() -> void:
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_on_health_completed.bind(request))
    status_value.text = "Connecting..."
    var error := request.request(SERVER_URL.rstrip("/") + "/health")
    if error != OK:
        status_value.text = "Connection error"

func _on_health_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
    request.queue_free()
    if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
        status_value.text = "Server online"
    else:
        status_value.text = "Server unavailable"

func _on_continue_pressed() -> void:
    # Login screen will replace this in the next game milestone.
    status_value.text = "Login system coming next"
