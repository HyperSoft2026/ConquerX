extends Node

var game: Node
var language_button: Button
var last_language := ""
var timer := 0.0

func _ready() -> void:
    game = get_parent()
    language_button = Button.new()
    language_button.position = Vector2(1010, 58)
    language_button.size = Vector2(120, 40)
    language_button.add_theme_font_size_override("font_size", 14)
    language_button.pressed.connect(_toggle_language)
    var hud = game.get_node_or_null("HUD")
    if hud != null:
        hud.add_child(language_button)
    _refresh()

func _process(delta:float) -> void:
    timer += delta
    if timer >= 0.5:
        timer = 0.0
        if last_language != I18n.language:
            _refresh()
        else:
            _translate_tree(game)

func _toggle_language() -> void:
    I18n.set_language("ar" if I18n.language == "en" else "en")
    _refresh()

func _refresh() -> void:
    last_language = I18n.language
    language_button.text = "العربية" if I18n.language == "en" else "English"
    _translate_tree(game)
    I18n.direction(game)

func _translate_tree(root:Node) -> void:
    for node in root.get_children():
        if node is Control:
            I18n.direction(node)
            if node is Label or node is Button:
                node.text = _translate(str(node.text))
        _translate_tree(node)

func _translate(text:String) -> String:
    if I18n.language == "en":
        var ar_to_en={"الملف الشخصي":"PROFILE","لوحة المتصدرين":"LEADERBOARD","المظاهر":"SKINS","المتجر":"SHOP","الإعدادات":"SETTINGS","جارٍ البحث عن مباراة...":"Finding a match...","الجلسة غير متوفرة":"Session missing","تم الاتصال بنظام المطابقة":"Matchmaking connected","انقطع الاتصال • جارٍ إعادة الاتصال...":"Disconnected • reconnecting...","فشل الاتصال":"Connection failed","تم العثور على المباراة • ابدأ!":"MATCH FOUND • FIGHT!","تم إقصاؤك":"ELIMINATED","جارٍ إعادة الظهور...":"Respawning...","المناطق":"Territory","الذهب":"Gold","الجواهر":"Gems","الصوت":"Sound","الموسيقى":"Music","المؤثرات":"Effects","تشغيل":"ON","إيقاف":"OFF","العودة إلى المباراة":"Back to Match","انتهت المباراة":"MATCH COMPLETE","العب مجدداً":"PLAY AGAIN","إغلاق":"CLOSE","اللغة":"Language","العب الآن":"PLAY ONLINE","الرئيسية":"HOME"}
        for k in ar_to_en.keys(): text=text.replace(k,ar_to_en[k])
    else:
        var en_to_ar={"PROFILE":"الملف الشخصي","LEADERBOARD":"لوحة المتصدرين","SKINS":"المظاهر","SHOP":"المتجر","SETTINGS":"الإعدادات","Finding a match...":"جارٍ البحث عن مباراة...","Session missing":"الجلسة غير متوفرة","Matchmaking connected":"تم الاتصال بنظام المطابقة","Disconnected • reconnecting...":"انقطع الاتصال • جارٍ إعادة الاتصال...","Connection failed":"فشل الاتصال","MATCH FOUND • FIGHT!":"تم العثور على المباراة • ابدأ!","ELIMINATED":"تم إقصاؤك","Respawning...":"جارٍ إعادة الظهور...","Territory":"المناطق","Gold":"الذهب","Gems":"الجواهر","Sound":"الصوت","Music":"الموسيقى","Effects":"المؤثرات","ON":"تشغيل","OFF":"إيقاف","Back to Match":"العودة إلى المباراة","MATCH COMPLETE":"انتهت المباراة","PLAY AGAIN":"العب مجدداً","CLOSE":"إغلاق","Language":"اللغة","PLAY ONLINE":"العب الآن","HOME":"الرئيسية","Touch & drag to move":"المس واسحب للتحرك","Top 500":"أفضل 500","Profile":"الملف الشخصي","Skins":"المظاهر","Shop":"المتجر"}
        for k in en_to_ar.keys(): text=text.replace(k,en_to_ar[k])
        text=text.replace("Territory ","المناطق ").replace("LIVE •","مباشر •").replace("Finding players •","جارٍ البحث عن لاعبين •").replace("Gold:","الذهب:").replace("Gems:","الجواهر:").replace("Level ","المستوى ").replace("XP ","الخبرة ").replace("Kills ","الإقصاءات ").replace("Wins ","الانتصارات ").replace("Equipped Skin","المظهر المجهز")
    return text
