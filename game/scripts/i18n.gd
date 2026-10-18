extends Node

const SAVE_PATH := "user://conquerx_settings.cfg"
var language := "en"

var T := {
    "en": {"profile":"PROFILE","leaderboard":"LEADERBOARD","skins":"SKINS","shop":"SHOP","settings":"SETTINGS","finding":"Finding a match...","session_missing":"Session missing","match_connected":"Matchmaking connected","reconnecting":"Disconnected • reconnecting...","connection_failed":"Connection failed","match_found":"MATCH FOUND • FIGHT!","eliminated":"ELIMINATED","respawning":"Respawning...","kill":"KILL","territory":"Territory","live":"LIVE","store":"STORE • GOLD & GEMS","gold":"Gold","gems":"Gems","sound":"Sound","music":"Music","effects":"Effects","on":"ON","off":"OFF","back_match":"Back to Match","match_complete":"MATCH COMPLETE","play_again":"PLAY AGAIN","close":"CLOSE","level":"Level","xp":"XP","wins":"Wins","kills":"Kills","equipped":"Equipped Skin","owned":"Owned","buy":"BUY","language":"Language","arabic":"العربية","english":"English","home":"HOME","play_online":"PLAY ONLINE","welcome":"WELCOME BACK","multiplayer_note":"Real multiplayer matchmaking • 20-player rooms • 3-minute matches","reward_note":"Win matches to earn Gold, Gems, XP and unlock more skins.","top500":"TOP 500 • GOLD","server_online":"Server online","server_unavailable":"Server unavailable","opening_discord":"Opening Discord...","discord_return":"Complete login in Discord, then return to ConquerX.","login_timeout":"Login timed out. Please try again.","could_not_open":"Could not open Discord.","request_failed":"Request failed"},
    "ar": {"profile":"الملف الشخصي","leaderboard":"لوحة المتصدرين","skins":"المظاهر","shop":"المتجر","settings":"الإعدادات","finding":"جارٍ البحث عن مباراة...","session_missing":"الجلسة غير متوفرة","match_connected":"تم الاتصال بنظام المطابقة","reconnecting":"انقطع الاتصال • جارٍ إعادة الاتصال...","connection_failed":"فشل الاتصال","match_found":"تم العثور على المباراة • ابدأ!","eliminated":"تم إقصاؤك","respawning":"جارٍ إعادة الظهور...","kill":"إقصاء","territory":"المناطق","live":"مباشر","store":"المتجر • الذهب والجواهر","gold":"الذهب","gems":"الجواهر","sound":"الصوت","music":"الموسيقى","effects":"المؤثرات","on":"تشغيل","off":"إيقاف","back_match":"العودة إلى المباراة","match_complete":"انتهت المباراة","play_again":"العب مجدداً","close":"إغلاق","level":"المستوى","xp":"الخبرة","wins":"الانتصارات","kills":"الإقصاءات","equipped":"المظهر المجهز","owned":"مملوك","buy":"شراء","language":"اللغة","arabic":"العربية","english":"English","home":"الرئيسية","play_online":"العب الآن","welcome":"مرحباً بعودتك","multiplayer_note":"مطابقة حقيقية • غرف حتى 20 لاعباً • مباريات مدتها 3 دقائق","reward_note":"اربح المباريات لتحصل على الذهب والجواهر والخبرة وتفتح المزيد من المظاهر.","top500":"أفضل 500 • الذهب","server_online":"الخادم متصل","server_unavailable":"الخادم غير متاح","opening_discord":"جارٍ فتح Discord...","discord_return":"أكمل تسجيل الدخول في Discord ثم عد إلى ConquerX.","login_timeout":"انتهت مهلة تسجيل الدخول. حاول مرة أخرى.","could_not_open":"تعذر فتح Discord.","request_failed":"فشل الطلب"}
}

func _ready() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) == OK:
        language = str(cfg.get_value("settings", "language", "en"))
    if language != "ar" and language != "en": language = "en"

func text_for(key: String) -> String:
    return str(T.get(language, T["en"]).get(key, key))

func set_language(value:String) -> void:
    language = "ar" if value == "ar" else "en"
    var cfg := ConfigFile.new()
    cfg.set_value("settings", "language", language)
    cfg.save(SAVE_PATH)

func is_arabic() -> bool:
    return language == "ar"

func direction(control:Node) -> void:
    if control is Control:
        control.layout_direction = Control.LAYOUT_DIRECTION_RTL if is_arabic() else Control.LAYOUT_DIRECTION_LTR

func apply_tree(root:Node) -> void:
    for node in root.get_children():
        if node is Control:
            direction(node)
        apply_tree(node)
