extends Node

const SAVE_PATH := "user://conquerx_season.cfg"
const SEASON_ID := "S01"
const SEASON_NAME_EN := "ConquerX: Genesis"
const SEASON_NAME_AR := "ConquerX: البداية"

var season_xp := 0
var daily_date := ""
var daily_progress: Dictionary = {}

var challenges := [
    {"id":"play_3","en":"Play 3 matches","ar":"العب 3 مباريات","target":3,"reward_gold":250,"reward_xp":120,"kind":"matches"},
    {"id":"win_1","en":"Win a match","ar":"اربح مباراة","target":1,"reward_gold":300,"reward_xp":180,"kind":"wins"},
    {"id":"kill_3","en":"Get 3 eliminations","ar":"حقق 3 إقصاءات","target":3,"reward_gold":350,"reward_xp":160,"kind":"kills"},
    {"id":"territory_500","en":"Capture 500 territory","ar":"سيطر على 500 منطقة","target":500,"reward_gold":400,"reward_xp":220,"kind":"territory"}
]

func _ready() -> void:
    _load()
    _roll_daily()

func _load() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) == OK:
        season_xp = int(cfg.get_value("season", "xp", 0))
        daily_date = str(cfg.get_value("daily", "date", ""))
        daily_progress = cfg.get_value("daily", "progress", {})

func _save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("season", "id", SEASON_ID)
    cfg.set_value("season", "xp", season_xp)
    cfg.set_value("daily", "date", daily_date)
    cfg.set_value("daily", "progress", daily_progress)
    cfg.save(SAVE_PATH)

func _today() -> String:
    var d := Time.get_date_dict_from_system(true)
    return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]

func _roll_daily() -> void:
    var today := _today()
    if daily_date != today:
        daily_date = today
        daily_progress = {}
        for challenge in challenges:
            daily_progress[str(challenge.id)] = 0
        _save()

func record_match(stats: Dictionary) -> void:
    _roll_daily()
    _add("play_3", 1)
    if bool(stats.get("win", false)):
        _add("win_1", 1)
    _add("kill_3", int(stats.get("kills", 0)))
    _add("territory_500", int(stats.get("territory", 0)))
    season_xp += 50 + int(stats.get("kills", 0)) * 10 + (100 if bool(stats.get("win", false)) else 0)
    _save()

func _add(id:String, amount:int) -> void:
    if not daily_progress.has(id): daily_progress[id] = 0
    var challenge := _challenge(id)
    if challenge.is_empty(): return
    daily_progress[id] = min(int(challenge.target), int(daily_progress[id]) + amount)

func _challenge(id:String) -> Dictionary:
    for c in challenges:
        if str(c.id) == id: return c
    return {}

func get_daily() -> Array:
    _roll_daily()
    return challenges

func progress(id:String) -> int:
    _roll_daily()
    return int(daily_progress.get(id, 0))

func is_complete(id:String) -> bool:
    var c := _challenge(id)
    return not c.is_empty() and progress(id) >= int(c.target)

func season_level() -> int:
    return int(floor(float(season_xp) / 1000.0)) + 1

func season_name() -> String:
    return SEASON_NAME_AR if I18n.is_arabic() else SEASON_NAME_EN
