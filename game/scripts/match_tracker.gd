extends Node

var last_status := ""

func _process(_delta: float) -> void:
    var game := get_tree().root.get_node_or_null("ConquerXGame")
    if game == null:
        return
    var status := str(game.get("match_status"))
    if status == last_status:
        return
    last_status = status
    if status != "finished":
        return

    # The server writes match_results and updates season/daily challenges from
    # authoritative match statistics. The client never awards or increments
    # competitive progress locally anymore.
    _sync_server_season(game)

func _sync_server_season(game: Node) -> void:
    var token := str(game.get_meta("session_token", ""))
    if token.is_empty():
        return
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(func(result, code, _headers, body):
        request.queue_free()
        if result != HTTPRequest.RESULT_SUCCESS or code != 200:
            return
        var data = JSON.parse_string(body.get_string_from_utf8())
        if typeof(data) == TYPE_DICTIONARY:
            Seasons.apply_server_data(data)
    )
    request.request("https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io/season", PackedStringArray(["Authorization: Bearer %s" % token]))
