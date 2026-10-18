extends Node2D

const SERVER_URL := "https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io"
const LOGIN_TIMEOUT_SECONDS := 600.0
const LOGIN_POLL_SECONDS := 2.0
const GAME_SCENE := preload("res://game/scenes/game.tscn")
const SESSION_PATH := "user://conquerx_session.cfg"

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
    _restore_saved_session()

func _restore_saved_session() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SESSION_PATH) != OK:
        _check_server()
        return
    session_token = str(cfg.get_value("auth", "session_token", ""))
    if session_token.is_empty():
        _check_server()
        return
    login_button.disabled = true
    continue_button.disabled = true
    status_value.text = I18n.text_for("restoring_session")
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_saved_session_checked.bind(request))
    request.request(SERVER_URL + "/me", PackedStringArray(["Authorization: Bearer %s" % session_token]))

func _saved_session_checked(result:int, code:int, _headers:PackedStringArray, body:PackedByteArray, request:HTTPRequest) -> void:
    request.queue_free()
    if result == HTTPRequest.RESULT_SUCCESS and code == 200:
        var parsed = JSON.parse_string(body.get_string_from_utf8())
        if typeof(parsed) == TYPE_DICTIONARY and typeof(parsed.get("account", {})) == TYPE_DICTIONARY:
            account = parsed.get("account", {})
            logged_in = true
            login_button.disabled = true
            continue_button.disabled = false
            _show_home()
            _sync_season()
            return
    _clear_saved_session()
    session_token = ""
    account = {}
    logged_in = false
    login_button.disabled = false
    continue_button.disabled = false
    status_value.text = I18n.text_for("server_unavailable") if result != HTTPRequest.RESULT_SUCCESS else I18n.text_for("opening_discord")
    _check_server()

func _save_session() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("auth", "session_token", session_token)
    cfg.save(SESSION_PATH)

func _clear_saved_session() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("auth", "session_token", "")
    cfg.save(SESSION_PATH)

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
    _save_session()
    _sync_season()
    _show_home()

func _sync_season() -> void:
    if session_token.is_empty(): return
    _http_get("/season", func(data):
        Seasons.apply_server_data(data)
        if home_panel != null: _rebuild_home()
    )

func _show_home() -> void:
    $Title.visible = false
    $Subtitle.visible = false
    $Version.visible = false
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

    home_panel = Panel.new()
    home_panel.position = Vector2(24, 102)
    home_panel.size = Vector2(1232, 590)
    home_panel.add_theme_stylebox_override("panel", _menu_style(Color("#071a3a"), Color("#2bd7ff"), 26, 2))
    add_child(home_panel)

    var greeting := Label.new()
    greeting.position = Vector2(26, 14)
    greeting.size = Vector2(780, 42)
    var username := str(account.get("username", "")).strip_edges()
    if username.is_empty() or username.contains("<") or username.contains("\\"):
        username = "Player1234"
    greeting.text = "%s، %s" % [I18n.text_for("welcome"), username] if I18n.is_arabic() else "%s, %s" % [I18n.text_for("welcome"), username]
    greeting.add_theme_font_size_override("font_size", 25)
    greeting.add_theme_color_override("font_color", Color("#ffffff"))
    home_panel.add_child(greeting)

    # Left: compact player card with readable stats and currency.
    var player_card := Panel.new()
    player_card.position = Vector2(22, 68)
    player_card.size = Vector2(250, 370)
    player_card.add_theme_stylebox_override("panel", _menu_style(Color("#102a55"), Color("#4aa8ff"), 22, 2))
    home_panel.add_child(player_card)
    var avatar := Label.new()
    avatar.position = Vector2(20, 18)
    avatar.size = Vector2(210, 48)
    avatar.text = "●   " + username
    avatar.add_theme_font_size_override("font_size", 22)
    avatar.add_theme_color_override("font_color", Color("#ffffff"))
    player_card.add_child(avatar)
    var level_label := Label.new()
    level_label.position = Vector2(20, 82)
    level_label.size = Vector2(210, 32)
    level_label.text = "%s  %s" % [I18n.text_for("level"), str(account.get("level", 1))]
    level_label.add_theme_font_size_override("font_size", 19)
    level_label.add_theme_color_override("font_color", Color("#9deeff"))
    player_card.add_child(level_label)
    var xp_label := Label.new()
    xp_label.position = Vector2(20, 119)
    xp_label.size = Vector2(210, 26)
    xp_label.text = "%s  %s" % [I18n.text_for("xp"), _short_number(int(account.get("xp", 0)))]
    xp_label.add_theme_font_size_override("font_size", 16)
    xp_label.add_theme_color_override("font_color", Color("#dbeafe"))
    player_card.add_child(xp_label)
    var xp_bar := ProgressBar.new()
    xp_bar.position = Vector2(20, 151)
    xp_bar.size = Vector2(210, 14)
    xp_bar.max_value = 1000
    xp_bar.value = int(account.get("xp", 0)) % 1000
    xp_bar.show_percentage = false
    player_card.add_child(xp_bar)
    _stat_chip("%s  %s" % [I18n.text_for("gold"), _short_number(int(account.get("gold", 0)))], Vector2(12, 190), Vector2(226, 48), Color("#ffca3a"))
    _stat_chip("%s  %s" % [I18n.text_for("gems"), _short_number(int(account.get("gems", 0)))], Vector2(12, 250), Vector2(226, 48), Color("#ff72e5"))
    var profile := _home_button(I18n.text_for("profile"), Vector2(12, 310), Vector2(226, 46), Callable(self, "_home_profile"))
    profile.add_theme_font_size_override("font_size", 17)

    # Center: a single primary play card. The mascot stays beside the text, never over the button.
    var play_card := Panel.new()
    play_card.position = Vector2(288, 68)
    play_card.size = Vector2(540, 370)
    play_card.add_theme_stylebox_override("panel", _menu_style(Color("#123b91"), Color("#ffe15b"), 24, 3))
    home_panel.add_child(play_card)
    var mode_title := Label.new()
    mode_title.position = Vector2(22, 22)
    mode_title.size = Vector2(330, 54)
    mode_title.text = I18n.text_for("arena_title")
    mode_title.add_theme_font_size_override("font_size", 25)
    mode_title.add_theme_color_override("font_color", Color("#fff7d1"))
    play_card.add_child(mode_title)
    var mode_note := Label.new()
    mode_note.position = Vector2(22, 86)
    mode_note.size = Vector2(330, 96)
    mode_note.text = I18n.text_for("multiplayer_note")
    mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    mode_note.add_theme_font_size_override("font_size", 17)
    mode_note.add_theme_color_override("font_color", Color("#d8f5ff"))
    play_card.add_child(mode_note)
    var play := _home_button("▶   " + I18n.text_for("play_online"), Vector2(20, 245), Vector2(320, 78), Callable(self, "_play_online"))
    play.add_theme_font_size_override("font_size", 24)
    play.add_theme_stylebox_override("normal", _menu_style(Color("#ffe13d"), Color("#fff4a0"), 20, 3))
    play.add_theme_stylebox_override("hover", _menu_style(Color("#fff078"), Color("#ffffff"), 20, 3))
    play.add_theme_color_override("font_color", Color("#12316f"))
    play.add_theme_color_override("font_hover_color", Color("#12316f"))

    # Right: touch-sized navigation grid, mirrored for Arabic.
    var nav_title := Label.new()
    nav_title.position = Vector2(850, 72)
    nav_title.size = Vector2(340, 38)
    nav_title.text = I18n.text_for("world_nav")
    nav_title.add_theme_font_size_override("font_size", 21)
    nav_title.add_theme_color_override("font_color", Color("#9deeff"))
    home_panel.add_child(nav_title)
    _home_button(I18n.text_for("shop"), Vector2(850, 120), Vector2(165, 66), Callable(self, "_home_shop"))
    _home_button("👤  " + I18n.text_for("profile"), Vector2(1025, 120), Vector2(165, 66), Callable(self, "_home_profile"))
    _home_button(I18n.text_for("skins"), Vector2(850, 198), Vector2(165, 66), Callable(self, "_home_skins"))
    _home_button(I18n.text_for("leaderboard"), Vector2(1025, 198), Vector2(165, 66), Callable(self, "_home_leaderboard"))
    _home_button(I18n.text_for("daily_missions"), Vector2(850, 276), Vector2(165, 66), Callable(self, "_home_season"))
    _home_button(I18n.text_for("settings"), Vector2(1025, 276), Vector2(165, 66), Callable(self, "_home_settings"))

    var progress := Panel.new()
    progress.position = Vector2(22, 455)
    progress.size = Vector2(1188, 105)
    progress.add_theme_stylebox_override("panel", _menu_style(Color("#07152d"), Color("#287cc5"), 18, 2))
    home_panel.add_child(progress)
    var progress_label := Label.new()
    progress_label.position = Vector2(18, 10)
    progress_label.size = Vector2(1150, 78)
    progress_label.text = "%s     •     %s     •     %s" % [Seasons.season_name(), ("مستوى الموسم %d" % Seasons.season_level) if I18n.is_arabic() else ("SEASON LEVEL %d" % Seasons.season_level), I18n.text_for("reward_note")]
    progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    progress_label.add_theme_font_size_override("font_size", 16)
    progress_label.add_theme_color_override("font_color", Color("#e8faff"))
    progress.add_child(progress_label)

    I18n.apply_tree(home_panel)
    if has_node("Mascot"):
        $Mascot.position = Vector2(715, 330)
        $Mascot.scale = Vector2(0.34, 0.34)
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
        _show_shop_panel(data, true)
    )

func _home_shop() -> void:
    _http_get("/shop", func(data):
        _show_shop_panel(data, false)
    )

func _show_shop_panel(data:Dictionary, skins_only:bool) -> void:
    if home_overlay != null: home_overlay.queue_free()
    home_overlay = Panel.new()
    home_overlay.position = Vector2(180, 82)
    home_overlay.size = Vector2(920, 570)
    home_overlay.add_theme_stylebox_override("panel", _menu_style(Color("#0b1b38"), Color("#37d9ff"), 24, 2))
    add_child(home_overlay)
    var title := Label.new()
    title.position = Vector2(24, 16)
    title.size = Vector2(820, 42)
    title.text = I18n.text_for("skins") if skins_only else I18n.text_for("shop")
    title.add_theme_font_size_override("font_size", 28)
    home_overlay.add_child(title)
    var balance := Label.new()
    balance.position = Vector2(24, 58)
    balance.size = Vector2(850, 32)
    balance.text = "%s: %s     %s: %s" % [I18n.text_for("gold"), str(account.get("gold", 0)), I18n.text_for("gems"), str(account.get("gems", 0))]
    balance.add_theme_font_size_override("font_size", 18)
    home_overlay.add_child(balance)
    var scroll := ScrollContainer.new()
    scroll.position = Vector2(20, 98)
    scroll.size = Vector2(875, 385)
    home_overlay.add_child(scroll)
    var list := VBoxContainer.new()
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 8)
    scroll.add_child(list)
    if not skins_only:
        for item in data.get("items", []):
            var item_button := Button.new()
            item_button.custom_minimum_size = Vector2(835, 56)
            item_button.text = "%s   •   %s %s   •   💎 %s" % [str(item.get("name", "Item")), I18n.text_for("gold"), str(item.get("gold_cost", 0)), str(item.get("gems_cost", 0))]
            item_button.pressed.connect(_buy_shop_item.bind(str(item.get("id", ""))))
            list.add_child(item_button)
    var unlocked_value = account.get("unlocked_skins", [1])
    var unlocked:Array = unlocked_value if typeof(unlocked_value) == TYPE_ARRAY else [1]
    for skin in data.get("skins", []):
        var id := int(skin.get("id", 0))
        var owned := id in unlocked
        var equipped := id == int(account.get("selected_skin", 1))
        var skin_button := Button.new()
        skin_button.custom_minimum_size = Vector2(835, 56)
        if owned:
            skin_button.text = ("✓  " if equipped else "◉  ") + ("المظهر %02d • مجهز" % id if equipped and I18n.is_arabic() else ("المظهر %02d • اضغط للتجهيز" % id if I18n.is_arabic() else ("Skin %02d • Equipped" % id if equipped else "Skin %02d • Equip" % id)))
            skin_button.pressed.connect(_equip_home_skin.bind(id))
        else:
            skin_button.text = ("شراء المظهر %02d" % id if I18n.is_arabic() else "Buy Skin %02d" % id) + "   •   G %s / Gems %s" % [str(skin.get("gold_cost", 0)), str(skin.get("gems_cost", 0))]
            skin_button.pressed.connect(_buy_shop_skin.bind(id))
        list.add_child(skin_button)
    var close := Button.new()
    close.text = I18n.text_for("close")
    close.position = Vector2(24, 500)
    close.size = Vector2(870, 48)
    close.pressed.connect(_close_overlay)
    home_overlay.add_child(close)
    I18n.direction(home_overlay)

func _buy_shop_item(id:String) -> void:
    _http_post("/shop/buy", {"type":"currency", "id":id}, func(_data):
        _refresh_home_account()
        _home_shop()
    )

func _buy_shop_skin(id:int) -> void:
    _http_post("/shop/buy", {"type":"skin", "id":id}, func(data):
        account["unlocked_skins"] = data.get("unlocked_skins", account.get("unlocked_skins", [1]))
        _refresh_home_account()
        _home_shop()
    )

func _equip_home_skin(id:int) -> void:
    _http_post("/profile/skin", {"skin_id":id}, func(_data):
        account["selected_skin"] = id
        _refresh_home_account()
        _home_skins()
    )

func _refresh_home_account() -> void:
    _http_get("/profile", func(data):
        account = data.get("profile", account)
        _rebuild_home()
    )

func _home_leaderboard() -> void:
    _http_get("/leaderboard?sort=gold&limit=20", func(data):
        var lines:Array=[]
        for row in data.get("leaderboard",[]): lines.append("#%s  %s  • %s %s • %s %s" % [str(row.get("rank",0)),str(row.get("username","Player")),I18n.text_for("gold"),str(row.get("gold",0)),I18n.text_for("wins"),str(row.get("wins",0))])
        _show_overlay(I18n.text_for("leaderboard"), lines))

func _home_shop_placeholder() -> void:
    pass

func _home_settings() -> void:
    if home_overlay != null: home_overlay.queue_free()
    home_overlay = Panel.new()
    home_overlay.position = Vector2(330, 130)
    home_overlay.size = Vector2(620, 440)
    home_overlay.add_theme_stylebox_override("panel", _menu_style(Color("#0b1b38"), Color("#37d9ff"), 24, 2))
    add_child(home_overlay)
    var title := Label.new()
    title.position = Vector2(26, 20)
    title.size = Vector2(560, 46)
    title.text = I18n.text_for("settings")
    title.add_theme_font_size_override("font_size", 28)
    home_overlay.add_child(title)
    var language_label := Label.new()
    language_label.position = Vector2(28, 88)
    language_label.size = Vector2(560, 36)
    language_label.text = I18n.text_for("language")
    language_label.add_theme_font_size_override("font_size", 20)
    home_overlay.add_child(language_label)
    var arabic := Button.new()
    arabic.text = "العربية"
    arabic.position = Vector2(28, 138)
    arabic.size = Vector2(265, 62)
    arabic.pressed.connect(func():
        I18n.set_language("ar")
        _apply_language()
        _close_overlay()
        _rebuild_home()
    )
    home_overlay.add_child(arabic)
    var english := Button.new()
    english.text = "English"
    english.position = Vector2(310, 138)
    english.size = Vector2(265, 62)
    english.pressed.connect(func():
        I18n.set_language("en")
        _apply_language()
        _close_overlay()
        _rebuild_home()
    )
    home_overlay.add_child(english)
    var quality := Label.new()
    quality.position = Vector2(28, 225)
    quality.size = Vector2(560, 58)
    quality.text = ("جودة الرسوم: %s • %d إطار/ث" % [GamePerformance.quality_name(), GamePerformance.target_fps]) if I18n.is_arabic() else ("Graphics quality: %s • %d FPS" % [GamePerformance.quality_name(), GamePerformance.target_fps])
    quality.add_theme_font_size_override("font_size", 17)
    home_overlay.add_child(quality)
    var close := Button.new()
    close.text = I18n.text_for("close")
    close.position = Vector2(28, 340)
    close.size = Vector2(547, 58)
    close.pressed.connect(_close_overlay)
    home_overlay.add_child(close)
    I18n.direction(home_overlay)

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

func _http_post(path:String, payload:Dictionary, callback:Callable) -> void:
    var request := HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(func(result, code, _headers, body):
        request.queue_free()
        if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
            var parsed = JSON.parse_string(body.get_string_from_utf8())
            if typeof(parsed) == TYPE_DICTIONARY:
                callback.call(parsed)
        else:
            status_value.text = I18n.text_for("request_failed")
    )
    request.request(SERVER_URL + path, PackedStringArray(["Content-Type: application/json", "Authorization: Bearer %s" % session_token]), HTTPClient.METHOD_POST, JSON.stringify(payload))

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
