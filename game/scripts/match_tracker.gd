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
    var players: Dictionary = game.get("players")
    var self_id := int(game.get("self_id"))
    var stats := {"kills": 0, "territory": 0, "win": false}
    if players.has(self_id):
        var player: Dictionary = players[self_id]
        stats.kills = int(player.get("kills", 0))
        stats.territory = int(player.get("territory", 0))
    var end_data = game.get("last_match_result")
    if typeof(end_data) == TYPE_DICTIONARY:
        stats.win = int(end_data.get("place", 99)) == 1
    Seasons.record_match(stats)
