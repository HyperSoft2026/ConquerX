extends Node2D

const SERVER_URL := "https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io"
const LOGIN_TIMEOUT_SECONDS := 600.0
const LOGIN_POLL_SECONDS := 2.0
const GAME_SCENE := preload("res://game/scenes/game.tscn")

@onready var status_value: Label = $StatusPanel/StatusValue
@onready var continue_button: Button = $ContinueButton
@onready var login_button: Button = $DiscordLoginButton
@onready var account_summary: Label = $AccountSummary

var login_session_id := ""
var login_elapsed := 0.0
var login_poll_timer := 0.0
var logged_in := false
var session_token := ""
var account: Dictionary = {}
var home_panel: Panel
var home_overlay: Panel
var home_buttons: Array[Button] = []

func _ready() -> void:
    continue_button.pressed.connect(_on_continue_pressed)
    login_button.pressed.connect(_on_discord_login_pressed)
    status_value.text = I18n.text_for("server_online")
    _apply_language()
    _check_server()

func _process(delta: float) -> void:
    if login_session_id.is_empty() or logged_in: return
    login_elapsed += delta
    login_poll_timer += delta
    if login_elapsed >= LOGIN_TIMEOUT_SECONDS:
        status_value.text = I18n.text_for("login_timeout")
        login_session_id = ""
        login_elapsed = 0.0
        login_poll_timer = 0.0
        login_button.disabled = false
        return
    if login_poll_timer >= LOGIN_POLL_SECONDS:
        login_poll_timer = 0.0
        _poll_login_status()

func _apply_language() -> void:
    I18n.direction(self)
    $Subtitle.text = I18n.text_for("welcome")
    login_button.text = "Discord"
    continue_button.text = I18n.text_for("play_online")
    if home_panel != null:
        _rebuild_home()

func _check_server() -> void:
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_health_done.bind(request))
    request.request(SERVER_URL + "/health")

func _health_done(result:int, code:int, _headers:PackedStringArray, _body:PackedByteArray, request:HTTPRequest) -> void:
    request.queue_free()
    status_value.text = I18n.text_for("server_online") if result == HTTPRequest.RESULT_SUCCESS and code == 200 else I18n.text_for("server_unavailable")

func _on_discord_login_pressed() -> void:
    if logged_in or not login_session_id.is_empty(): return
    login_session_id = _make_session_id()
    login_elapsed = 0.0
    login_poll_timer = 0.0
    login_button.disabled = true
    status_value.text = I18n.text_for("opening_discord")
    var error := OS.shell_open(SERVER_URL + "/auth/discord/start?session=" + login_session_id)
    if error != OK:
        status_value.text = I18n.text_for("could_not_open")
        login_session_id = ""
        login_button.disabled = false
    else:
        status_value.text = I18n.text_for("discord_return")

func _poll_login_status() -> void:
    if login_session_id.is_empty(): return
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_login_done.bind(request))
    request.request(SERVER_URL + "/auth/discord/status?session=" + login_session_id)

func _login_done(result:int, code:int, _headers:PackedStringArray, body:PackedByteArray, request:HTTPRequest) -> void:
    request.queue_free()
    if login_session_id.is_empty() or logged_in or result != HTTPRequest.RESULT_SUCCESS or code != 200: return
    var parsed = JSON.parse_string(body.get_string_from_utf8())
    if typeof(parsed) != TYPE_DICTIONARY or parsed.get("status", "pending") != "completed": return
    session_token = str(parsed.get("session_token", ""))
    account = parsed.get("account", {})
    if session_token.is_empty() or account.is_empty(): return
    logged_in = true
    login_session_id = ""
    login_button.disabled = true
    _sync_season()
    _show_home()

func _sync_season() -> void:
    if session_token.is_empty(): return
    _http_get("/season", func(data):
        Seasons.apply_server_data(data)
        if home_panel != null: _rebuild_home()
    )

func _show_home() -> void:
    $Title.text = "ConquerX"
    $Subtitle.text = "%s • %s" % [I18n.text_for("welcome"), str(account.get("username", "Player"))]
    $StatusPanel.visible = false
    $DiscordLoginButton.visible = false
    $ContinueButton.visible = false
    $AccountSummary.visible = false
    $Version.text = "ConquerX • %s • Season %s" % [I18n.text_for("multiplayer_note"), Seasons.SEASON_ID]
    _rebuild_home()

func _rebuild_home() -> void:
    if not logged_in: return
    if home_panel != null: home_panel.queue_free()
    home_buttons.clear()

    # Landscape-first home screen: 1280x720 canvas with clear zones for touch.
    home_panel = Panel.new()
    home_panel.position = Vector2(28, 118)
    home_panel.size = Vector2(1224, 570)
    home_panel.add_theme_stylebox_override("panel", _menu_style(Color(0.025, 0.12, 0.31, 0.92), Color("#37d9ff"), 24, 3))
    home_panel.modulate.a = 0.0
    add_child(home_panel)
    var intro := home_panel.create_tween()
    intro.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    intro.tween_property(home_panel, "modulate:a", 1.0, 0.22)
    intro.parallel().tween_property(home_panel, "position", Vector2(28, 108), 0.22)

    # Top status strip
    var greeting := Label.new()
    greeting.position = Vector2(28, 18)
    greeting.size = Vector2(700, 44)
    greeting.text = "%s, %s!" % [I18n.text_for("welcome"), str(account.get("username", "Player"))]
    greeting.add_theme_font_size_override("font_size", 25)
    greeting.add_theme_color_override("font_color", Color("#ffffff"))
    home_panel.add_child(greeting)

    _stat_chip("🟡  %s  %s" % [I18n.text_for("gold"), _short_number(int(account.get("gold", 0)))], Vector2(28, 70), Vector2(205, 48), Color("#ffca3a"))
    _stat_chip("💎  %s  %s" % [I18n.text_for("gems"), _short_number(int(account.get("gems", 0)))], Vector2(245, 70), Vector2(205, 48), Color("#ff72e5"))
    _stat_chip("⭐  %s %s" % [I18n.text_for("level"), str(account.get("level", 1))], Vector2(462, 70), Vector2(175, 48), Color("#7ee7ff"))

    # Large, primary play card
    var play_card := Panel.new()
    play_card.position = Vector2(28, 142)
    play_card.size = Vector2(600, 300)
    play_card.add_theme_stylebox_override("panel", _menu_style(Color("#123b91"), Color("#ffe15b"), 24, 4))
    home_panel.add_child(play_card)

    var mode_title := Label.new()
    mode_title.position = Vector2(28, 24)
    mode_title.size = Vector2(520, 50)
    mode_title.text = "⚔  CONQUER THE ARENA"
    mode_title.add_theme_font_size_override("font_size", 29)
    mode_title.add_theme_color_override("font_color", Color("#fff7d1"))
    play_card.add_child(mode_title)

    var mode_note := Label.new()
    mode_note.position = Vector2(30, 82)
    mode_note.size = Vector2(525, 68)
    mode_note.text = I18n.text_for("multiplayer_note")
    mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    mode_note.add_theme_font_size_override("font_size", 17)
    mode_note.add_theme_color_override("font_color", Color("#d8f5ff"))
    play_card.add_child(mode_note)

    var play := _home_button("▶   " + I18n.text_for("play_online"), Vector2(28, 180), Vector2(540, 82), Callable(self, "_play_online"))
    play.add_theme_font_size_override("font_size", 27)
    play.add_theme_stylebox_override("normal", _menu_style(Color("#ffe13d"), Color("#fff4a0"), 20, 3))
    play.add_theme_stylebox_override("hover", _menu_style(Color("#fff078"), Color("#ffffff"), 20, 3))
    play.add_theme_color_override("font_color", Color("#12316f"))
    play.add_theme_color_override("font_hover_color", Color("#12316f"))

    # Quick navigation on the right, large enough for touch.
    var nav_title := Label.new()
    nav_title.position = Vector2(690, 145)
    nav_title.size = Vector2(440, 36)
    nav_title.text = "YOUR WORLD"
    nav_title.add_theme_font_size_override("font_size", 20)
    nav_title.add_theme_color_override("font_color", Color("#9deeff"))
    home_panel.add_child(nav_title)

    _home_button("🛍  " + I18n.text_for("shop"), Vector2(690, 190), Vector2(235, 72), Callable(self, "_home_shop"))
    _home_button("👤  " + I18n.text_for("profile"), Vector2(940, 190), Vector2(235, 72), Callable(self, "_home_profile"))
    _home_button("🎭  " + I18n.text_for("skins"), Vector2(690, 278), Vector2(235, 72), Callable(self, "_home_skins"))
    _home_button("🏆  " + I18n.text_for("leaderboard"), Vector2(940, 278), Vector2(235, 72), Callable(self, "_home_leaderboard"))
    _home_button("📋  " + ("المهام اليومية" if I18n.is_arabic() else "DAILY MISSIONS"), Vector2(690, 366), Vector2(235, 72), Callable(self, "_home_season"))
    _home_button("⚙  " + I18n.text_for("settings"), Vector2(940, 366), Vector2(235, 72), Callable(self, "_home_settings"))

    # Season and player progress strip
    var progress := Panel.new()
    progress.position = Vector2(28, 462)
    progress.size = Vector2(1147, 72)
    progress.add_theme_stylebox_override("panel", _menu_style(Color(0.02, 0.07, 0.2, 0.78), Color("#287cc5"), 16, 2))
    home_panel.add_child(progress)
    var progress_label := Label.new()
    progress_label.position = Vector2(20, 8)
    progress_label.size = Vector2(1100, 56)
    progress_label.text = "🌟  %s     •     %s     •     %s" % [Seasons.season_name(), ("مستوى الموسم %d" % Seasons.season_level) if I18n.is_arabic() else ("SEASON LEVEL %d" % Seasons.season_level), I18n.text_for("reward_note")]
    progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    progress_label.add_theme_font_size_override("font_size", 16)
    progress_label.add_theme_color_override("font_color", Color("#e8faff"))
    progress.add_child(progress_label)

    # Keep the original mascot visible above the translucent home surface.
    if has_node("Mascot"):
        $Mascot.position = Vector2(650, 385)
        $Mascot.scale = Vector2(0.68, 0.68)
        $Mascot.move_to_front()

func _menu_style(fill:Color, border_color:Color, radius:int, border_width:int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border_color
    style.set_border_width_all(border_width)
    style.set_corner_radius_all(radius)
    style.content_margin_left = 14.0
    style.content_margin_right = 14.0
    style.content_margin_top = 8.0
    style.content_margin_bottom = 8.0
    return style

func _stat_chip(text:String, pos:Vector2, size:Vector2, accent:Color) -> void:
    var chip := Panel.new()
    chip.position = pos
    chip.size = size
    chip.add_theme_stylebox_override("panel", _menu_style(Color(0.02, 0.10, 0.29, 0.94), accent, 16, 2))
    home_panel.add_child(chip)
    var label := Label.new()
    label.position = Vector2(8, 4)
    label.size = size - Vector2(16, 8)
    label.text = text
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 17)
    label.add_theme_color_override("font_color", Color("#ffffff"))
    chip.add_child(label)

func _short_number(value:int) -> String:
    if value >= 1000000: return "%.1fM" % (float(value) / 1000000.0)
    if value >= 10000: return "%.1fK" % (float(value) / 1000.0)
    return str(value)

func _home_season() -> void:
    _http_get("/season", func(data):
        Seasons.apply_server_data(data)
        var lines:Array = []
        lines.append(("الموسم: " if I18n.is_arabic() else "Season: ") + Seasons.season_name())
        lines.append(("مستوى الموسم: %d • XP: %d" % [Seasons.season_level, Seasons.season_xp]) if I18n.is_arabic() else ("Season level: %d • XP: %d" % [Seasons.season_level, Seasons.season_xp]))
        lines.append("")
        for c in Seasons.get_daily():
            var label := str(c.get("ar", "")) if I18n.is_arabic() else str(c.get("en", ""))
            var claimed := " ✓" if bool(c.get("claimed", false)) else ""
            lines.append("• %s — %d/%d%s" % [label, int(c.get("progress", 0)), int(c.get("target", 0)), claimed])
        _show_overlay(("الموسم والمهام اليومية" if I18n.is_arabic() else "Season & Daily Missions"), lines)
    )

func _home_button(text:String, pos:Vector2, size:Vector2, callback:Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.position = pos
    b.size = size
    b.add_theme_font_size_override("font_size", 19)
    b.add_theme_color_override("font_color", Color("#ffffff"))
    b.add_theme_color_override("font_hover_color", Color("#ffffff"))
    b.add_theme_stylebox_override("normal", _menu_style(Color("#1554a8"), Color("#48dfff"), 16, 2))
    b.add_theme_stylebox_override("hover", _menu_style(Color("#1c78cb"), Color("#fff07a"), 16, 3))
    b.add_theme_stylebox_override("pressed", _menu_style(Color("#103875"), Color("#ffffff"), 16, 2))
    b.pressed.connect(callback)
    b.mouse_entered.connect(func(): _button_hover(b, true))
    b.mouse_exited.connect(func(): _button_hover(b, false))
    home_panel.add_child(b)
    home_buttons.append(b)
    return b

func _button_hover(button:Button, inside:bool) -> void:
    var tween := create_tween()
    tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(button, "scale", Vector2(1.025, 1.025) if inside else Vector2.ONE, 0.10)

func _play_online() -> void:
    var gameplay = GAME_SCENE.instantiate()
    gameplay.set_meta("session_token", session_token)
    gameplay.set_meta("account", account)
    get_tree().root.add_child(gameplay)
    queue_free()

func _home_profile() -> void:
    _show_overlay(I18n.text_for("profile"), [str(account.get("username","Player")), "%s %s • %s %s" % [I18n.text_for("level"),str(account.get("level",1)),I18n.text_for("xp"),str(account.get("xp",0))], "%s %s • %s %s" % [I18n.text_for("gold"),str(account.get("gold",0)),I18n.text_for("gems"),str(account.get("gems",0))], "%s %s • %s %s" % [I18n.text_for("wins"),str(account.get("wins",0)),I18n.text_for("kills"),str(account.get("kills",0))]])

func _home_skins() -> void:
    _http_get("/shop", func(data):
        var lines:Array=["%s: %s / 50" % [I18n.text_for("owned"), str(account.get("unlocked_skins",[1]).size())]]
        for s in data.get("skins",[]): lines.append("Skin %02d • %s" % [int(s.get("id",0)), str(s.get("rarity","Common"))])
        _show_overlay(I18n.text_for("skins"), lines))

func _home_shop() -> void:
    _show_overlay(I18n.text_for("shop"), ["%s %s" % [I18n.text_for("gold"),str(account.get("gold",0))], "%s %s" % [I18n.text_for("gems"),str(account.get("gems",0))], I18n.text_for("reward_note")])

func _home_leaderboard() -> void:
    _http_get("/leaderboard?sort=gold&limit=20", func(data):
        var lines:Array=[]
        for row in data.get("leaderboard",[]): lines.append("#%s  %s  • %s %s • %s %s" % [str(row.get("rank",0)),str(row.get("username","Player")),I18n.text_for("gold"),str(row.get("gold",0)),I18n.text_for("wins"),str(row.get("wins",0))])
        _show_overlay(I18n.text_for("leaderboard"), lines))

func _home_shop_placeholder() -> void:
    pass

func _home_settings() -> void:
    _show_overlay(I18n.text_for("settings"), ["ConquerX 1280×720 • Android landscape", "Arabic / English • saved automatically", "Adaptive quality: %s • %d FPS" % [GamePerformance.quality_name(), GamePerformance.target_fps], "Sound, music and effects can be controlled in-match."])

func _show_overlay(title:String, lines:Array) -> void:
    if home_overlay != null: home_overlay.queue_free()
    home_overlay = Panel.new()
    home_overlay.position = Vector2(270, 120)
    home_overlay.size = Vector2(740, 500)
    home_overlay.modulate.a = 0.0
    add_child(home_overlay)
    var t := Label.new(); t.position=Vector2(30,25); t.size=Vector2(680,50); t.text=title; t.add_theme_font_size_override("font_size",28); home_overlay.add_child(t)
    var body := Label.new(); body.position=Vector2(30,85); body.size=Vector2(680,320); body.text="\n".join(lines); body.add_theme_font_size_override("font_size",19); home_overlay.add_child(body)
    var close := Button.new(); close.text=I18n.text_for("close"); close.position=Vector2(30,420); close.size=Vector2(680,55); close.pressed.connect(func(): _close_overlay()); home_overlay.add_child(close)
    I18n.direction(home_overlay)
    var tween := create_tween(); tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT); tween.tween_property(home_overlay,"modulate:a",1.0,0.18); tween.parallel().tween_property(home_overlay,"scale",Vector2.ONE,0.18)

func _close_overlay() -> void:
    if home_overlay == null: return
    var panel := home_overlay
    home_overlay = null
    var tween := create_tween(); tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN); tween.tween_property(panel,"modulate:a",0.0,0.12); tween.tween_callback(panel.queue_free)

func _http_get(path:String, callback:Callable) -> void:
    var request:=HTTPRequest.new(); add_child(request)
    request.request_completed.connect(func(result,code,_h,body):
        request.queue_free()
        if result==HTTPRequest.RESULT_SUCCESS and code==200:
            var d=JSON.parse_string(body.get_string_from_utf8())
            if typeof(d)==TYPE_DICTIONARY: callback.call(d)
    )
    request.request(SERVER_URL+path,PackedStringArray(["Authorization: Bearer %s"%session_token]))

func _on_continue_pressed() -> void: _play_online()
func _make_session_id()->String:
    var rng:=RandomNumberGenerator.new(); rng.randomize()
    return "%08x-%04x-%04x-%04x-%08x%04x"%[rng.randi(),rng.randi()&0xffff,rng.randi()&0xffff,rng.randi()&0xffff,rng.randi(),rng.randi()&0xffff]
