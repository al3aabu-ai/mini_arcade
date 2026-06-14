import Foundation

// Mirrors server/src/protocol.ts — keep both sides in sync.

enum GamePhase: String {
    case lobby, auction, golf, bomb, podium
}

struct PlayerState: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let avatar: String
    let color: String
    let score: Int
    let connected: Bool
    let isHost: Bool
    let debuff: String?
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

    var jamUntilDate: Date? { jamUntil.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct PodiumState: Codable, Equatable {
    let ranking: [String]
    let replayVotes: [String]
}

struct RoomState: Codable, Equatable {
    let code: String
    let phase: String
    let players: [PlayerState]
    let auction: AuctionState?
    let golf: GolfState?
    let bomb: BombState?
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

struct ErrorMsg: Decodable { let message: String }
