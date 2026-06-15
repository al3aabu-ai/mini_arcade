import Foundation

// Mirrors server/src/protocol.ts — keep both sides in sync.

enum GamePhase: String {
    case lobby, selection, auction, golf, bomb, bumper, podium
}

/// A playable mini-game. The match `lineup` is an ordered list of these.
enum GameType: String, Codable, CaseIterable {
    case golf, bomb, bumper

    /// Big graphic for the picker cards and the TV lineup slots.
    var emoji: String {
        switch self {
        case .golf: return "🏌️"
        case .bomb: return "💣"
        case .bumper: return "🤼"
        }
    }
    /// Localization keys (English source strings) for the card text.
    var titleKey: String {
        switch self {
        case .golf: return "Mini-Golf"
        case .bomb: return "Hot Potato Bomb"
        case .bumper: return "Bumper Arena"
        }
    }
    var blurbKey: String {
        switch self {
        case .golf: return "Sink it in the fewest shots."
        case .bomb: return "Pass it fast — don't be holding it when it blows."
        case .bumper: return "Shove rivals off the slab — last one floating wins."
        }
    }
    /// Theme accent hex for the card / slot.
    var themeHex: String {
        switch self {
        case .golf: return "#00F5D4"
        case .bomb: return "#FF3355"
        case .bumper: return "#FB5607"
        }
    }
}

/// The host's live game-picker state, mirrored to the TV as slots fill.
struct SelectionState: Codable, Equatable {
    let picks: [String] // GameType raw values, in slot order
    let size: Int       // how many games the host must pick
}

/// A collectible coin on the active field (public map state, not the wallet).
/// Golf: (x,y,z) are SceneKit world coords. Bomb: (x,y) are fractional [0,1] screen coords.
struct Coin: Codable, Equatable, Identifiable {
    let id: String
    let x: Double
    let y: Double
    let z: Double
}

/// A hidden per-player objective. PRIVATE — only arrives in the owner's own
/// snapshot. Carries both languages so the phone shows the right one.
struct SecretTask: Codable, Equatable, Hashable {
    let id: String
    let descriptionEN: String
    let descriptionAR: String
    let rewardCoins: Int
    let isCompleted: Bool

    /// The description for the current language setting.
    func description(arabic: Bool) -> String { arabic ? descriptionAR : descriptionEN }
}

struct PlayerState: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let avatar: String
    let color: String
    /// Mini-game wins — PUBLIC, shown on the TV, decides the match.
    let trophies: Int
    /// Spendable money — PRIVATE. The server only sends each player their OWN
    /// real value; every other player's `coins` arrives masked to 0, so wallets
    /// never reach the TV. Only show this on the owner's own phone.
    let coins: Int
    let connected: Bool
    let isHost: Bool
    let debuff: String?
    /// This player's hidden objective — PRIVATE, only present in their own
    /// snapshot (null for everyone else and on the TV).
    let secretTask: SecretTask?
}

struct SabotageItem: Codable, Equatable {
    let id: String
    let name: String
    let emoji: String
    let blurb: String
    let appliesTo: String
    let debuff: String
}

struct AuctionState: Codable, Equatable {
    let round: Int
    let stage: String // bidding | targeting | reveal
    let item: SabotageItem
    let endsAt: Double // epoch ms
    let lockedIn: [String]
    let winnerId: String?
    let winningBid: Int?
    let targetId: String?

    var endsAtDate: Date { Date(timeIntervalSince1970: endsAt / 1000) }
}

struct GolfResults: Codable, Equatable {
    let order: [String]
    let awarded: [String: Int]
}

struct GolfState: Codable, Equatable {
    let endsAt: Double
    let debuffs: [String: String]
    let turnId: String?
    let sunk: [String]
    let results: GolfResults?
    let round: Int
    let map: String          // "guerilla" (Round 1) | "tiki" (Round 2)
    let strokes: [String: Int] // cumulative strokes per player, lower = better
    let spawnedCoins: [Coin]   // loose coins on the course this round

    var endsAtDate: Date { Date(timeIntervalSince1970: endsAt / 1000) }
}

struct BombState: Codable, Equatable {
    let stage: String // ticking | exploded | done
    let alive: [String]
    let eliminated: [String]
    let holderId: String?
    let pot: Int
    let multiplier: Double
    let earnings: [String: Int]
    let jamUntil: Double?
    let lastExplodedId: String?
    let survivors: [String]?
    let spawnedCoins: [Coin]   // loose coins scattered in the arena

    var jamUntilDate: Date? { jamUntil.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct BumperState: Codable, Equatable {
    let endsAt: Double
    let alive: [String]
    let eliminated: [String]
    let winnerId: String?

    var endsAtDate: Date { Date(timeIntervalSince1970: endsAt / 1000) }
}

struct PodiumState: Codable, Equatable {
    let ranking: [String]
    let replayVotes: [String]
}

struct RoomState: Codable, Equatable {
    let code: String
    let phase: String
    let players: [PlayerState]
    /// Ordered mini-games this match runs (max 3). Decoded as raw strings so an
    /// unknown future game type can't fail the whole snapshot.
    let lineup: [String]
    /// Index into `lineup` of the game currently being set up / played.
    let currentLineupIndex: Int
    /// Host's in-progress game-picker (only while phase == .selection).
    let selection: SelectionState?
    let auction: AuctionState?
    let golf: GolfState?
    let bomb: BombState?
    let bumper: BumperState?
    let podium: PodiumState?
    let rev: Int

    var gamePhase: GamePhase { GamePhase(rawValue: phase) ?? .lobby }

    func player(_ id: String?) -> PlayerState? {
        guard let id else { return nil }
        return players.first { $0.id == id }
    }
}

// MARK: - Server -> client messages

struct Envelope: Decodable { let t: String }

struct RoomJoinedMsg: Decodable {
    let playerId: String
    let token: String
    let state: RoomState
}

struct RoomStateMsg: Decodable { let state: RoomState }

struct AimMsg: Decodable {
    let playerId: String
    let angle: Double
    let power: Double
}

struct AimClearMsg: Decodable { let playerId: String }

struct FireMsg: Decodable {
    let playerId: String
    let angle: Double
    let power: Double
}

struct JoystickMsg: Decodable {
    let playerId: String
    let x: Double
    let y: Double
}

struct ErrorMsg: Decodable { let message: String }
