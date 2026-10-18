extends Node

const SEASON_ID := "S01"
const SEASON_NAME_EN := "ConquerX: Genesis"
const SEASON_NAME_AR := "ConquerX: البداية"

var season_xp := 0
var season_level := 1
var daily_date := ""
var daily_challenges: Array = []
var server_loaded := false

func _ready() -> void:
    server_loaded = false

func apply_server_data(data: Dictionary) -> void:
    season_xp = int(data.get("season_xp", 0))
    season_level = int(data.get("season_level", 1))
    daily_date = str(data.get("daily_date", ""))
    daily_challenges = data.get("challenges", [])
    server_loaded = true

func get_daily() -> Array:
    return daily_challenges

func progress(id: String) -> int:
    for c in daily_challenges:
        if str(c.get("id", "")) == id:
            return int(c.get("progress", 0))
    return 0

func is_complete(id: String) -> bool:
    for c in daily_challenges:
        if str(c.get("id", "")) == id:
            return progress(id) >= int(c.get("target", 0))
    return false

func season_name() -> String:
    return SEASON_NAME_AR if I18n.is_arabic() else SEASON_NAME_EN

func reset_cache() -> void:
    season_xp = 0
    season_level = 1
    daily_date = ""
    daily_challenges = []
    server_loaded = false
