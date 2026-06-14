import Foundation
import Combine

/// App language. English is the source language — every UI string in the code
/// is its own English key — so only an Arabic table is needed; a missing key
/// falls back to the English literal.
enum AppLanguage: String {
    case en
    case ar
}

/// Runtime "pure string swap" localizer. A single toggle flips the whole app
/// between English and Arabic. Views observe this object (`@ObservedObject
/// private var loc = Localization.shared`) so flipping the language re-renders
/// every label live. Look up text with `loc.tr("English text")`, and use
/// `%@` placeholders + args for interpolated strings: `loc.tr("%@ points", n)`.
@MainActor
final class Localization: ObservableObject {
    static let shared = Localization()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    var isArabic: Bool { language == .ar }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage")
        language = saved.flatMap(AppLanguage.init) ?? .en
    }

    func toggle() {
        language = (language == .en) ? .ar : .en
    }

    /// Translate `key` (the English literal). Pass args for `%@`-style strings.
    func tr(_ key: String, _ args: CVarArg...) -> String {
        let template = (language == .ar ? Self.arabic[key] : nil) ?? key
        return args.isEmpty ? template : String(format: template, arguments: args)
    }

    // MARK: - Arabic table (English literal → Arabic)

    private static let arabic: [String: String] = [
        // Menu / connection
        "Phones in hand. Chaos on the TV.": "الهواتف في الأيدي. الفوضى على الشاشة.",
        "📺  HOST PARTY": "📺  استضف حفلة",
        "🎮  JOIN PARTY": "🎮  انضم لحفلة",
        "Connection": "الاتصال",
        "📶  Same WiFi": "📶  نفس الواي‑فاي",
        "🌐  Other": "🌐  أخرى",
        "Same WiFi vs. Other": "نفس الواي‑فاي أو أخرى",
        "One phone hosts on this WiFi — tap HOST PARTY. Everyone else on the same WiFi taps JOIN and is found automatically.":
            "هاتف واحد يستضيف على هذا الواي‑فاي — اضغط استضف حفلة. والبقية على نفس الواي‑فاي يضغطون انضم ويُعثر عليهم تلقائياً.",
        "Use a deployed wss:// address to play over the internet.":
            "استخدم عنوان wss:// منشوراً للعب عبر الإنترنت.",
        "Game server address": "عنوان خادم اللعبة",
        "Same WiFi: run `npm run dev` in server/ and use the LAN address it prints.\nOver the internet: use your deployed wss:// address.":
            "نفس الواي‑فاي: شغّل `npm run dev` في مجلد server/ واستخدم عنوان الشبكة المحلية الذي يظهر.\nعبر الإنترنت: استخدم عنوان wss:// المنشور.",
        "Settings": "الإعدادات",
        "Save": "حفظ",

        // Profile setup
        "HOST A PARTY": "استضف حفلة",
        "JOIN A PARTY": "انضم لحفلة",
        "ROOM CODE": "رمز الغرفة",
        "Your name": "اسمك",
        "PICK YOUR FIGHTER": "اختر مقاتلك",
        "PICK YOUR COLOR": "اختر لونك",
        "CREATE PARTY  🚀": "أنشئ الحفلة  🚀",
        "JUMP IN  🎉": "انضم الآن  🎉",
        "Starting your game on this WiFi…": "جارٍ بدء لعبتك على هذا الواي‑فاي…",
        "Hosting on this WiFi — friends can join now.": "تستضيف على هذا الواي‑فاي — يمكن للأصدقاء الانضمام الآن.",
        "Couldn't start hosting: %@": "تعذّر بدء الاستضافة: %@",
        "Looking for a host on this WiFi…": "جارٍ البحث عن مضيف على هذا الواي‑فاي…",
        "Found a host on your WiFi — enter the room code.": "تم العثور على مضيف على الواي‑فاي — أدخل رمز الغرفة.",
        "No host found yet. Make sure someone tapped HOST PARTY on this WiFi.":
            "لم يُعثر على مضيف بعد. تأكد من أن أحدهم ضغط استضف حفلة على هذا الواي‑فاي.",

        // Phone root / status bar
        "Leave the party?": "مغادرة الحفلة؟",
        "Leave": "مغادرة",

        // Phone lobby
        "%@ players in": "%@ لاعب في الغرفة",
        "Mirror your screen to the TV — the board takes over the big screen":
            "اعكس شاشتك على التلفاز — تظهر اللوحة على الشاشة الكبيرة",
        "START THE CHAOS  🎬": "ابدأ الفوضى  🎬",
        "Waiting for the host to start…": "بانتظار أن يبدأ المضيف…",

        // Phone auction
        "THE DIRTY AUCTION": "المزاد القذر",
        "Bid locked in. Tell no one.": "تم تثبيت العرض. لا تخبر أحداً.",
        "%@/%@ bids in": "%@/%@ عروض مُسجّلة",
        "all in: %@": "كل ما لديك: %@",
        "LOCK IN SECRET BID  🤫": "ثبّت العرض السري  🤫",
        "BID NOTHING  🙅": "لا تراهن  🙅",
        "YOU WON %@": "لقد فزت %@",
        "for %@ points. Now… who suffers?": "مقابل %@ نقطة. الآن… من سيعاني؟",
        "%@ won the %@": "%@ فاز بـ %@",
        "…and is choosing a victim. Look innocent.": "…ويختار ضحية الآن. تظاهر بالبراءة.",
        "IT'S YOU.": "إنه أنت.",
        "%@ hit you with %@": "%@ ضربك بـ %@",
        "%@ got crushed": "%@ سُحق",
        "courtesy of %@": "بفضل %@",
        "No bids. The item rusts away.": "لا عروض. تتآكل القطعة.",

        // Phone golf
        "⛳️ GUERILLA GOLF": "⛳️ غولف العصابات",
        "ANVILED — your shots are 30% weaker": "مُثقَل بالسندان — ضرباتك أضعف بنسبة 30%",
        "POWER %@%%": "القوة %@%%",
        "🎯 YOUR SHOT": "🎯 ضربتك",
        "Drag back. Release to launch.\nOne shot — make it count.":
            "اسحب للخلف. أفلت للإطلاق.\nضربة واحدة — اجعلها تُحسب.",
        "%@ IS SHOOTING": "%@ يصوّب الآن",
        "GET READY…": "استعد…",
        "⏳ BALLS STILL ROLLING…": "⏳ لا تزال الكرات تتدحرج…",
        "👀 Watch the TV — your turn is coming.": "👀 راقب التلفاز — دورك قادم.",
        "IN THE HOLE!": "في الحفرة!",
        "You finished #%@ — enjoy the show": "أنهيت بالمركز #%@ — استمتع بالعرض",

        // Phone bomb
        "YOU HAVE THE BOMB": "القنبلة معك",
        "💵 +$%@  ·  greed ×%@": "💵 +$%@  ·  الجشع ×%@",
        "🧈 JAMMED %@s": "🧈 معطّل %@ث",
        "PASS %@": "مرّر %@",
        "Hold it to milk the pot. Pass before it pops.": "أمسكها لتراكم الأموال. مرّرها قبل أن تنفجر.",
        "◀️ LEFT": "◀️ يسار",
        "RIGHT ▶️": "يمين ▶️",
        "%@ EXPLODED": "%@ انفجر",
        "%@ %@ is holding the bomb": "%@ %@ يحمل القنبلة",
        "Your stash this game: $%@": "رصيدك هذه الجولة: $%@",
        "Stay calm. It might come your way.": "ابقَ هادئاً. قد تأتي إليك.",
        "YOU BLEW UP": "لقد انفجرت",
        "Your unbanked cash burned with you.\nEnjoy the show from the afterlife.":
            "احترقت أموالك غير المودعة معك.\nاستمتع بالعرض من العالم الآخر.",
        "YOU SURVIVED": "لقد نجوت",
        "ROUND OVER": "انتهت الجولة",
        "Banked $%@ + $250 survivor bonus": "أودعت $%@ + مكافأة نجاة 250$",

        // Phone podium
        "CHAMPION!": "البطل!",
        "%@ points": "%@ نقطة",
        "Replay votes: %@/%@": "أصوات الإعادة: %@/%@",
        "WAITING FOR THE OTHERS…": "بانتظار الآخرين…",
        "REPLAY?  🔁": "إعادة؟  🔁",

        // Board lobby
        "Grab your phone → open Frantics → JOIN PARTY": "أمسك هاتفك، افتح Frantics، ثم انضم لحفلة",
        "Need at least 2 players…": "نحتاج لاعبَين على الأقل…",
        "%@/8 in — host hits START when ready": "%@/8 انضموا — يضغط المضيف ابدأ عند الجاهزية",

        // Board auction
        "💰 THE DIRTY AUCTION 💰": "💰 المزاد القذر 💰",
        "Bid in secret on your phones…": "زايدوا سراً على هواتفكم…",
        "🔒 LOCKED": "🔒 مُثبّت",
        "thinking…": "يفكر…",
        "SOLD to %@ %@ for %@!": "بيع لـ %@ %@ مقابل %@!",
        "They're choosing a victim right now…": "يختارون ضحية الآن…",
        "%@ sabotaged %@!": "%@ خرّب %@!",
        "NO SALE — everyone kept their points": "لا بيع — احتفظ الجميع بنقاطهم",

        // Bomb board
        "💣 THE BILLIONAIRE'S BOMB": "💣 قنبلة المليارديرات",
        "Hold it to earn. Pass it to survive. Last two standing bank everything.":
            "أمسكها لتربح. مرّرها لتنجو. آخر اثنين يأخذان كل شيء.",
        "PRIZE POOL": "مجموع الجائزة",
        "%@ %@ IS OUT": "%@ %@ خرج",
        "🏆 SURVIVORS 🏆": "🏆 الناجون 🏆",
        "Earnings banked · +$250 each": "أُودعت الأرباح · +250$ لكل ناجٍ",

        // Board podium
        "🏆 FINAL PODIUM 🏆": "🏆 المنصة النهائية 🏆",
        "%@ %@ WINS!": "%@ %@ يفوز!",
        "Replay votes: %@/%@ — vote on your phones 🔁": "أصوات الإعادة: %@/%@ — صوّتوا على هواتفكم 🔁",

        // Board root
        "Host a party on your iPhone to fill this screen with chaos":
            "استضف حفلة على آيفونك لملء هذه الشاشة بالفوضى",

        // Golf board HUD
        "1st 500 · 2nd 300 · 3rd 200": "الأول 500 · الثاني 300 · الثالث 200",
        "%@'S SHOT": "دور %@",
        "🌴 TIKI JUNGLE": "🌴 أدغال التيكي",
        "ROUND %@/2": "الجولة %@/2",
        "FEWEST STROKES WINS": "الأقل ضربات يفوز",

        // Tiki Jungle Adventure — Hole 5 (course identity)
        "Tiki Jungle Adventure": "مغامرة أدغال التيكي",
        "Hole 5": "الحفرة 5",
        "Par 4 · 75 ft": "بار 4 · 75 قدم",

        // Sabotage items (sent by the server as data, shown in the UI)
        "The Heavy Anvil": "السندان الثقيل",
        "Butter Fingers": "أصابع زلقة",
        "Crush a rival! Their golf shots launch 30% weaker.":
            "اسحق منافساً! تنطلق ضرباته أضعف بنسبة 30%.",
        "Grease a rival! Their PASS button jams for 2s every time they catch the bomb.":
            "زيّت منافساً! يتعطل زر التمرير لديه ثانيتين كلما أمسك القنبلة.",

        // Fallback names used in interpolated strings
        "Someone": "أحدهم",
        "A rival": "أحد المنافسين",
        "a rival": "أحد المنافسين",

        // Server / connection error messages (shown in toasts & setup)
        "Room not found — check the code": "لم يُعثر على الغرفة — تحقق من الرمز",
        "That name is taken": "هذا الاسم مأخوذ",
        "Name required": "الاسم مطلوب",
        "Room is full": "الغرفة ممتلئة",
        "Game already in progress": "اللعبة جارية بالفعل",
        "Only the host can start the game": "المضيف فقط يمكنه بدء اللعبة",
        "Need at least 2 players": "نحتاج لاعبَين على الأقل",
        "Already in a room": "أنت في غرفة بالفعل",
        "Join a room first": "انضم إلى غرفة أولاً",
        "Could not rejoin — seat not found": "تعذّر إعادة الانضمام — المقعد غير موجود",
        "Room not found": "لم يُعثر على الغرفة",
        "Malformed JSON": "بيانات غير صالحة",
        "Missing message type": "نوع الرسالة مفقود",
        "Server error": "خطأ في الخادم",
        "Pick someone else, not yourself": "اختر شخصاً آخر، ليس نفسك",
        "Bid already locked in": "تم تثبيت العرض بالفعل",
        "You did not win the auction": "لم تفز بالمزاد",
        "Unknown target": "هدف غير معروف",
        "Still looking for a game on this WiFi…": "لا يزال البحث جارياً عن لعبة على هذا الواي‑فاي…",
        "Invalid server address": "عنوان خادم غير صالح",
        "Connection closed": "أُغلق الاتصال",
    ]
}
