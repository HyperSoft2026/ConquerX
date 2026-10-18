# ConquerX

> **ConquerX** هي لعبة تنافسية متعددة اللاعبين للهواتف بنظام Android، مبنية حول السيطرة على الأراضي، الحركة السريعة، المواجهات المباشرة، وتطوير حساب اللاعب.

<div align="center">

**Real-time Multiplayer • Matchmaking • Territory Control • 50 Skins • Arabic / English**

</div>

---

## ✨ نبذة عن اللعبة

في **ConquerX** تدخل إلى مباريات تنافسية حقيقية، تتحرك داخل ساحة المعركة، توسّع منطقتك، تنافس اللاعبين الآخرين، وتحاول إنهاء المباراة بأفضل نتيجة ممكنة.

النظام مصمم ليكون مناسباً للموبايل بوضعية **Landscape** وبدقة تصميم أساسية **1280×720**.

### أبرز المزايا

- 🎮 مباريات Multiplayer حقيقية عبر WebSocket.
- 🧩 Matchmaking مع غرف تصل إلى **20 لاعباً**.
- ⏱️ مدة المباراة الأساسية **3 دقائق**.
- 🗺️ نظام Territory مستمر وقابل للحفظ.
- ⚔️ نظام Kills وDeath وRespawn.
- 🏆 نتائج المباراة والمراكز والمكافآت.
- 🪙 Gold و💎 Gems وXP وLevels.
- 🛒 متجر لشراء العملات والمظاهر.
- 🎨 **50 مظهراً مختلفاً** بتصاميم Vector متنوعة مع أسماء عربية وإنجليزية.
- ✨ مؤثرات بصرية للحركة والسيطرة على الأراضي.
- 💥 Kill Effects.
- 💀 Death Animation.
- 🏆 Victory Animation.
- 🎵 نظام Sound / Music / Effects قابل للتحكم.
- 🌐 دعم كامل للواجهات العربية والإنجليزية مع حفظ اختيار اللغة.
- 🏠 Home UI حديثة.
- ⚙️ Settings داخل اللعبة.
- 📊 Leaderboard لأفضل 500 لاعب.
- 👤 Discord OAuth لتسجيل الدخول.

---

## 🌍 اللغات

يدعم ConquerX حالياً:

| اللغة | الحالة |
|---|---|
| 🇮🇶 العربية | مدعومة بالكامل للواجهات الأساسية داخل اللعبة |
| 🇬🇧 English | مدعومة بالكامل للواجهات الأساسية داخل اللعبة |

اختيار اللغة يُحفظ محلياً على الجهاز، ويمكن التبديل بين العربية والإنجليزية من زر اللغة داخل اللعبة.

عند اختيار العربية يتم تحويل اتجاه عناصر الواجهة إلى **RTL**، وعند اختيار الإنجليزية يعود الاتجاه إلى **LTR**.

---

## 🎨 نظام المظاهر

يحتوي الإصدار الحالي على **50 Skin** بتصاميم Vector مختلفة، بدلاً من الاعتماد على دائرة واحدة مع تغيير اللون فقط.

التصاميم تشمل أنماطاً مثل:

- Shields
- Diamonds
- Stars
- Hexes
- Lightning Bolts
- Crystals
- Crowns
- Wings
- Energy Cores

كما يوجد ملف Manifest يحتوي على أسماء المظاهر بالعربية والإنجليزية ودرجة الندرة:

`assets/skins/skin_manifest.json`

---

## ✨ المؤثرات والحركة

طبقة `VisualEffects` تضيف مؤثرات مستقلة عن منطق اللعب، وتشمل:

- نبض بصري للاعب الحالي.
- حدود متحركة للمناطق.
- Kill Burst.
- Crosshair Effect.
- Death Pulse.
- Victory Burst.
- Particles خفيفة أثناء الأحداث المهمة.

الهدف هو إبقاء منطق الشبكة واللعب منفصلاً عن طبقة العرض قدر الإمكان.

---

## 🧱 البنية التقنية

### Client

- **Godot 4**
- GDScript
- Android
- Landscape
- 1280×720 base viewport
- WebSocketPeer للم multiplayer
- HTTPRequest للـ API

### Backend

- Node.js
- PostgreSQL
- `ws` WebSocket server
- Clever Cloud

### المصادقة

- Discord OAuth
- Session tokens
- PostgreSQL account persistence

---

## 🌐 Backend

الخادم العام الحالي:

`https://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io`

WebSocket endpoint:

`wss://app-4729a9fe-87fc-4f1b-9248-112725e0db57.cleverapps.io/ws?token=`

> مفاتيح Discord والأسرار وBot Tokens يجب أن تبقى داخل متغيرات البيئة في الخادم، ولا يجب وضعها داخل المستودع.

---

## 📁 أهم الملفات

```text
ConquerX/
├── game/
│   ├── scenes/
│   │   └── game.tscn
│   └── scripts/
│       ├── main.gd
│       ├── game.gd
│       ├── i18n.gd
│       ├── language_controller.gd
│       └── visual_effects.gd
├── assets/
│   ├── icon/
│   │   └── Logo_ConquerX.png
│   └── skins/
│       └── skin_manifest.json
├── server.js
├── package.json
├── tests/
│   └── smoke.mjs
├── .github/
│   └── workflows/
│       └── validate.yml
└── README.md
```

---

## 🧪 الاختبارات

المستودع يحتوي على Smoke Test للتحقق من وجود المكونات الأساسية في العميل والخادم، بالإضافة إلى فحص صياغة `server.js`.

الأمر المحلي:

```bash
npm run check
```

ويتم تشغيل التحقق تلقائياً عبر GitHub Actions عند Push أو Pull Request إلى `main`.

> ملاحظة: اختبار المباراة الحقيقية بين أجهزة Android متعددة، WebSocket في بيئة الإنتاج، وقاعدة PostgreSQL يحتاج إلى تشغيل فعلي للعميل والخادم؛ وجود الاختبارات النصية لا يعني أن اختباراً ميدانياً كاملاً قد تم تنفيذه تلقائياً.

---

## 🚀 تشغيل الخادم محلياً

```bash
npm install
npm start
```

للتطوير:

```bash
npm run dev
```

---

## 🔐 متغيرات البيئة

يحتاج الخادم إلى إعدادات البيئة الخاصة بقاعدة البيانات وDiscord OAuth، ومنها:

```text
DISCORD_CLIENT_ID
DISCORD_CLIENT_SECRET
DISCORD_BOT_TOKEN
DISCORD_REDIRECT_URI
```

ولا يتم تضمين القيم السرية الفعلية داخل Git.

---

## 🛡️ الأمان

- لا تضع Discord Client Secret داخل تطبيق Android.
- لا تضع Bot Token داخل GitHub.
- استخدم Environment Variables في الخادم.
- لا تحفظ Session Token في ملفات عامة.
- تحقق من صلاحيات الحساب على الخادم قبل عمليات المتجر أو تغيير المظهر.

---

## 📜 الترخيص والصفحات القانونية

تتوفر صفحات الشروط والخصوصية من الخادم العام، ويتم إبقاؤها منفصلة عن أسرار البنية التحتية.

---

## 🗺️ خارطة الطريق

### مكتمل / قيد الدمج

- [x] Discord Login
- [x] PostgreSQL Accounts
- [x] Multiplayer WebSocket
- [x] Matchmaking
- [x] 20-player Rooms
- [x] 3-minute Matches
- [x] Territory Persistence
- [x] Gold / Gems / XP
- [x] Shop
- [x] 50 Skins
- [x] Visual Effects Layer
- [x] Arabic / English Language System
- [x] Professionalized Home UI
- [x] Settings UI
- [x] Automated validation

### الخطوات التالية

- [ ] اختبار ميداني كامل على عدة أجهزة Android.
- [ ] تحسين الرسوميات حسب أداء الأجهزة المختلفة.
- [ ] إضافة ملفات موسيقى ومؤثرات صوتية نهائية مرخصة.
- [ ] تحسين أنيميشن الانتقالات داخل القوائم.
- [ ] إضافة مواسم وتحديات ومهام يومية.

---

## 👤 المطور

**HyperSoft2026 — ConquerX**

Support: `modeali2021@gmail.com`

---

<div align="center">

### Conquer the map. Outplay the rivals. Own the arena.

**ConquerX**

</div>
