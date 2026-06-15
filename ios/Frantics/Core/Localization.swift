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
        "Phones in hand. Chaos on the TV.": "جوالك بيدك، والونّسة عالتلفزيون.",
        "📺  HOST PARTY": "📺  سوِّ حفلة",
        "🎮  JOIN PARTY": "🎮  لِحق علينا",
        "Connection": "الاتصال",
        "📶  Same WiFi": "📶  نفس الويفي",
        "🌐  Other": "🌐  ثاني",
        "Same WiFi vs. Other": "نفس الويفي أو ثاني",
        "One phone hosts on this WiFi — tap HOST PARTY. Everyone else on the same WiFi taps JOIN and is found automatically.":
            "جوال واحد يسوّي الحفلة على نفس الويفي — اضغط (سوِّ حفلة)، والباقي على نفس الويفي يضغطون (لِحق علينا) وبيلقونه على طول.",
        "Use a deployed wss:// address to play over the internet.":
            "حط عنوان wss:// منشور عشان تلعبون عن طريق النت.",
        "Game server address": "عنوان سيرفر اللعبة",
        "Same WiFi: run `npm run dev` in server/ and use the LAN address it prints.\nOver the internet: use your deployed wss:// address.":
            "نفس الويفي: شغّل `npm run dev` في مجلد server/ واستخدم عنوان الشبكة اللي يطلع لك.\nعن طريق النت: استخدم عنوان wss:// المنشور.",
        "Settings": "الإعدادات",
        "Save": "احفظ",

        // Profile setup
        "HOST A PARTY": "سوِّ حفلة",
        "JOIN A PARTY": "لِحق على حفلة",
        "ROOM CODE": "رمز الغرفة",
        "Your name": "اسمك",
        "PICK YOUR FIGHTER": "اختر شخصيتك",
        "PICK YOUR COLOR": "اختر لونك",
        "CREATE PARTY  🚀": "يلا نبدأ  🚀",
        "JUMP IN  🎉": "ادخل معنا  🎉",
        "Starting your game on this WiFi…": "نجهّز حفلتك على الويفي…",
        "Hosting on this WiFi — friends can join now.": "حفلتك شغّالة على الويفي — ربعك يقدرون يدخلون الحين.",
        "Couldn't start hosting: %@": "ما قدرنا نبدأ الحفلة: %@",
        "Looking for a host on this WiFi…": "ندوّر على حفلة في الويفي…",
        "Found a host on your WiFi — enter the room code.": "لقينا حفلة على الويفي — اكتب رمز الغرفة.",
        "No host found yet. Make sure someone tapped HOST PARTY on this WiFi.":
            "ما لقينا حفلة بعد. تأكد إن أحد ضغط (سوِّ حفلة) على نفس الويفي.",

        // Phone root / status bar
        "Leave the party?": "تبي تطلع من الحفلة؟",
        "Leave": "اطلع",

        // Phone lobby
        "%@ players in": "%@ لاعبين داخلين",
        "Mirror your screen to the TV — the board takes over the big screen":
            "حوّل شاشتك عالتلفزيون — اللوحة بتطلع على الشاشة الكبيرة",
        "START THE CHAOS  🎬": "يلا نبدأ الونّسة  🎬",
        "Waiting for the host to start…": "ننتظر صاحب الحفلة يبدأ…",

        // Phone auction
        "THE DIRTY AUCTION": "المزاد الخبيث",
        "Bid locked in. Tell no one.": "صكّينا مزايدتك. لا تقول لأحد.",
        "%@/%@ bids in": "%@/%@ زايدوا",
        "all in: %@": "كل اللي معك: %@",
        "LOCK IN SECRET BID  🤫": "صكّ مزايدتك بالسر  🤫",
        "BID NOTHING  🙅": "لا تزايد  🙅",
        "YOU WON %@": "كسبت %@",
        "for %@ coins. Now… who suffers?": "بـ %@ كوينز. الحين… مين بيدفع الثمن؟",
        "%@ won the %@": "%@ كسب %@",
        "…and is choosing a victim. Look innocent.": "…ويختار ضحية. سوِّ نفسك ما تدري.",
        "IT'S YOU.": "إنت الضحية.",
        "%@ hit you with %@": "%@ ضربك بـ %@",
        "%@ got crushed": "%@ راحت فيه",
        "courtesy of %@": "والسبب %@",
        "No bids. The item rusts away.": "ما أحد زايد. القطعة راحت هدر.",

        // Phone golf
        "⛳️ GUERILLA GOLF": "⛳️ قولف العصابات",
        "ANVILED — your shots are 30% weaker": "عليك سندان — ضرباتك أضعف بـ 30%",
        "POWER %@%%": "القوة %@%%",
        "🎯 YOUR SHOT": "🎯 دورك تضرب",
        "Drag back. Release to launch.\nOne shot — make it count.":
            "اسحب لور وفِكّ عشان تضرب.\nضربة وحدة — خلّها تنحسب.",
        "%@ IS SHOOTING": "%@ يضرب الحين",
        "GET READY…": "جهّز نفسك…",
        "⏳ BALLS STILL ROLLING…": "⏳ الكرات لسّا تتدحرج…",
        "👀 Watch the TV — your turn is coming.": "👀 طالع التلفزيون — دورك جاي.",
        "IN THE HOLE!": "دخلت الحفرة!",
        "You finished #%@ — enjoy the show": "خلّصت بالمركز #%@ — استمتع بالعرض",

        // Phone bomb
        "YOU HAVE THE BOMB": "القنبلة معك!",
        "💵 +$%@  ·  greed ×%@": "💵 +$%@  ·  الطمع ×%@",
        "🧈 JAMMED %@s": "🧈 معطّل %@ث",
        "PASS %@": "مرّر %@",
        "Hold it to milk the pot. Pass before it pops.": "امسكها وكثّر فلوسك. مرّرها قبل لا تنفجر.",
        "◀️ LEFT": "◀️ يسار",
        "RIGHT ▶️": "يمين ▶️",
        "%@ EXPLODED": "%@ انفجر فيه!",
        "%@ %@ is holding the bomb": "%@ %@ ماسك القنبلة",
        "Your stash this game: $%@": "فلوسك هالجولة: $%@",
        "Stay calm. It might come your way.": "خذها ببرود. يمكن تجيك.",
        "YOU BLEW UP": "انفجرت فيك!",
        "Your unbanked cash burned with you.\nEnjoy the show from the afterlife.":
            "فلوسك اللي ما أودعتها احترقت معك.\nتفرّج على اللعبة من بعيد.",
        "YOU SURVIVED": "نجوت!",
        "ROUND OVER": "خلصت الجولة",
        "Banked $%@ + $250 survivor bonus": "أودعت $%@ + 250$ مكافأة نجاة",

        // Phone podium
        "CHAMPION!": "البطل!",
        "%@ points": "%@ نقطة",
        "Replay votes: %@/%@": "أصوات الإعادة: %@/%@",
        "WAITING FOR THE OTHERS…": "ننتظر الباقين…",
        "REPLAY?  🔁": "نعيدها؟  🔁",

        // Board lobby
        "Grab your phone → open Frantics → JOIN PARTY": "خذ جوالك، افتح Frantics، واضغط (لِحق علينا)",
        "Need at least 2 players…": "نبي لاعبين اثنين على الأقل…",
        "%@/8 in — host hits START when ready": "%@/8 داخلين — صاحب الحفلة يضغط (ابدأ) لين تجهزون",

        // Board auction
        "💰 THE DIRTY AUCTION 💰": "💰 المزاد الخبيث 💰",
        "Bid in secret on your phones…": "زايدوا بالسر من جوالاتكم…",
        "🔒 LOCKED": "🔒 مصكوك",
        "thinking…": "يفكّر…",
        "SOLD to %@ %@!": "انباع لـ %@ %@!",
        "They're choosing a victim right now…": "يختار ضحيته الحين…",
        "%@ sabotaged %@!": "%@ خرّب على %@!",
        "NO SALE — everyone kept their coins": "ما انباع — كلٍّ احتفظ بكوينزه",

        // Game selection (host picker + TV mirror)
        "SELECT 3 GAMES": "اختر ٣ ألعاب",
        "Slot %@": "خانة %@",
        "Tap a game to fill the next slot (%@/%@)": "اضغط لعبة عشان تعبّي الخانة (%@/%@)",
        "START MATCH  🎬": "ابدأ الجولة  🎬",
        "TAP TO ADD": "اضغط للإضافة",
        "SLOTS FULL": "الخانات كاملة",
        "The host is choosing the games…": "المضيف يختار الألعاب…",
        "BUILDING THE LINEUP": "نبني قائمة الألعاب",
        "Mini-Golf": "ميني قولف",
        "Hot Potato Bomb": "القنبلة الحارة",
        "Sink it in the fewest shots.": "نزّلها بأقل ضربات.",
        "Pass it fast — don't be holding it when it blows.": "مرّرها بسرعة — لا تكون ماسكها لمن تنفجر.",

        // Secret tasks (private per-player objectives)
        "Secret Task": "المهمة السرية",
        "Task complete! +%@ coins": "المهمة اكتملت! +%@ عملة",
        "+%@ coins · kept secret": "+%@ عملة · يبقى سر",

        // Bomb board
        "💣 THE BILLIONAIRE'S BOMB": "💣 قنبلة المليونير",
        "Hold it to earn. Pass it to survive. Last two standing bank everything.":
            "امسكها تربح. مرّرها تنجو. آخر اثنين ياخذون كل شي.",
        "PRIZE POOL": "مجموع الجائزة",
        "%@ %@ IS OUT": "%@ %@ طار!",
        "🏆 SURVIVORS 🏆": "🏆 الناجون 🏆",
        "Earnings banked · +$250 each": "الأرباح انودعت · +250$ لكل واحد",

        // Board podium
        "🏆 FINAL PODIUM 🏆": "🏆 المنصة النهائية 🏆",
        "%@ %@ WINS!": "%@ %@ كسب!",
        "Replay votes: %@/%@ — vote on your phones 🔁": "أصوات الإعادة: %@/%@ — صوّتوا من جوالاتكم 🔁",

        // Board root
        "Host a party on your iPhone to fill this screen with chaos":
            "سوِّ حفلة من جوالك وعبِّ هالشاشة ونّسة",

        // Golf board HUD
        "1st 500 · 2nd 300 · 3rd 200": "الأول 500 · الثاني 300 · الثالث 200",
        "%@'S SHOT": "دور %@",
        "🌴 TIKI JUNGLE": "🌴 أدغال التيكي",
        "🛫 TIKI RUNWAY": "🛫 مدرج التيكي",
        "Tiki Runway": "مدرج التيكي",
        "ROUND %@/3": "الجولة %@/3",
        "FEWEST STROKES WINS": "الأقل ضربات يكسب",

        // Tiki Jungle Adventure — Hole 5 (course identity)
        "Tiki Jungle Adventure": "مغامرة أدغال التيكي",
        "Hole 5": "الحفرة 5",
        "Par 4 · 75 ft": "بار 4 · 75 قدم",

        // Sabotage items (sent by the server as data, shown in the UI)
        "The Heavy Anvil": "السندان الثقيل",
        "Butter Fingers": "إيد زلقة",
        "Crush a rival! Their golf shots launch 30% weaker.":
            "اهبد على خصمك! ضرباته بتطلع أضعف بـ 30%.",
        "Grease a rival! Their PASS button jams for 2s every time they catch the bomb.":
            "دهّن خصمك! زر التمرير عنده يعلّق ثانيتين كل ما تجيه القنبلة.",

        // Fallback names used in interpolated strings
        "Someone": "أحد",
        "A rival": "واحد من الخصوم",
        "a rival": "واحد من الخصوم",

        // Server / connection error messages (shown in toasts & setup)
        "Room not found — check the code": "ما لقينا الغرفة — تأكد من الرمز",
        "That name is taken": "الاسم هذا مأخوذ",
        "Name required": "لازم تكتب اسم",
        "Room is full": "الغرفة كاملة",
        "Game already in progress": "اللعبة بدأت من زمان",
        "Only the host can start the game": "صاحب الحفلة بس يقدر يبدأ اللعبة",
        "Need at least 2 players": "نبي لاعبين اثنين على الأقل",
        "Already in a room": "إنت أصلاً داخل غرفة",
        "Join a room first": "ادخل غرفة الأول",
        "Could not rejoin — seat not found": "ما قدرنا نرجّعك — مقعدك مو موجود",
        "Room not found": "ما لقينا الغرفة",
        "Malformed JSON": "بيانات غلط",
        "Missing message type": "نوع الرسالة ناقص",
        "Server error": "صار خطأ في السيرفر",
        "Pick someone else, not yourself": "اختر واحد ثاني، مو نفسك",
        "Bid already locked in": "مزايدتك مصكوكة من قبل",
        "You did not win the auction": "ما كسبت المزاد",
        "Unknown target": "هدف مو معروف",
        "Still looking for a game on this WiFi…": "لسّا ندوّر على حفلة في الويفي…",
        "Invalid server address": "عنوان السيرفر غلط",
        "Connection closed": "انقطع الاتصال",
    ]
}
