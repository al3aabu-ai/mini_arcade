#if DEBUG
import SwiftUI

/// Canned room states for screenshots and visual iteration without a server.
/// Launch with env var FRANTICS_DEMO set to one of:
///   board-lobby | board-auction | board-golf | board-bomb | board-podium
///   phone-auction | phone-golf | phone-bomb | phone-podium
enum DemoData {
    // p2 ("Omar") is the demo's local viewer, so his coins are the real wallet;
    // in a live game every other coins value would arrive masked to 0.
    // p2 ("Omar") is the demo viewer, so he carries a sample secret task; the
    // others are nil (a real client only ever sees its own).
    private static let demoTask = SecretTask(
        id: "greedy_golfer",
        descriptionEN: "Greedy Golfer — grab at least 2 coins this game.",
        descriptionAR: "طمّاع الذهب — لِم ٢ عملات على الأقل في هاللعبة.",
        rewardCoins: 150, isCompleted: false
    )
    static let players: [PlayerState] = [
        .init(id: "p1", name: "Maya", avatar: "🦊", color: "#FF2E88", trophies: 2, coins: 450,
              connected: true, isHost: true, debuff: nil, secretTask: nil),
        .init(id: "p2", name: "Omar", avatar: "🐸", color: "#00F5D4", trophies: 3, coins: 600,
              connected: true, isHost: false, debuff: nil, secretTask: demoTask),
        .init(id: "p3", name: "Lina", avatar: "🦄", color: "#9B5DE5", trophies: 1, coins: 700,
              connected: true, isHost: false, debuff: "anvil", secretTask: nil),
        .init(id: "p4", name: "Ziad", avatar: "🐼", color: "#FEE440", trophies: 1, coins: 300,
              connected: true, isHost: false, debuff: nil, secretTask: nil),
    ]

    static func state(phase: String, selection: SelectionState? = nil, auction: AuctionState? = nil,
                      golf: GolfState? = nil, bomb: BombState? = nil, bumper: BumperState? = nil,
                      podium: PodiumState? = nil) -> RoomState {
        RoomState(code: "FRNX", phase: phase, players: players,
                  lineup: ["golf", "bumper", "bomb"], currentLineupIndex: 0,
                  selection: selection, auction: auction, golf: golf, bomb: bomb, bumper: bumper,
                  podium: podium, rev: 1)
    }

    static var lobby: RoomState { state(phase: "lobby") }

    static var selection: RoomState {
        state(phase: "selection", selection: SelectionState(picks: ["golf"], size: 3))
    }

    static var auction: RoomState {
        state(
            phase: "auction",
            auction: AuctionState(
                round: 1, stage: "bidding",
                item: SabotageItem(id: "anvil", name: "The Heavy Anvil", emoji: "🪨",
                                   blurb: "Crush a rival! Their golf shots launch 30% weaker.",
                                   appliesTo: "golf", debuff: "anvil"),
                endsAt: Date().addingTimeInterval(12).timeIntervalSince1970 * 1000,
                lockedIn: ["p1", "p3"], winnerId: nil, winningBid: nil, targetId: nil
            )
        )
    }

    static var golf: RoomState {
        state(
            phase: "golf",
            golf: GolfState(
                endsAt: Date().addingTimeInterval(140).timeIntervalSince1970 * 1000,
                debuffs: ["p3": "anvil"], turnId: "p2", sunk: [], results: nil,
                round: 1, map: "guerilla", strokes: ["p1": 2, "p2": 1, "p3": 3, "p4": 0],
                spawnedCoins: []
            )
        )
    }

    static var bomb: RoomState {
        state(
            phase: "bomb",
            bomb: BombState(
                stage: "ticking", alive: ["p1", "p2", "p3", "p4"], eliminated: [],
                holderId: "p2", pot: 1325, multiplier: 2.75,
                earnings: ["p1": 250, "p2": 575, "p3": 350, "p4": 150],
                jamUntil: nil, lastExplodedId: nil, survivors: nil,
                spawnedCoins: [Coin(id: "bcoin-0", x: 0.2, y: 0.3, z: 0),
                               Coin(id: "bcoin-1", x: 0.8, y: 0.34, z: 0)]
            )
        )
    }

    static var bumper: RoomState {
        state(
            phase: "bumper",
            bumper: BumperState(
                endsAt: Date().addingTimeInterval(38).timeIntervalSince1970 * 1000,
                alive: ["p1", "p2", "p4"], eliminated: ["p3"], winnerId: nil
            )
        )
    }

    static var podium: RoomState {
        state(
            phase: "podium",
            podium: PodiumState(ranking: ["p2", "p1", "p4", "p3"], replayVotes: ["p1", "p3"])
        )
    }

    @MainActor
    static func client(for mode: String) -> GameClient {
        let myId = "p2"
        switch mode {
        case "board-lobby", "phone-lobby": return GameClient(demoState: lobby, playerId: myId)
        // View the picker AS THE HOST so the carousel (not the waiting screen) shows.
        case "board-selection", "phone-selection":
            return GameClient(demoState: selection, playerId: players.first(where: \.isHost)?.id ?? myId)
        case "board-auction", "phone-auction": return GameClient(demoState: auction, playerId: myId)
        case "board-golf", "phone-golf": return GameClient(demoState: golf, playerId: myId)
        case "board-bomb", "phone-bomb": return GameClient(demoState: bomb, playerId: myId)
        case "board-bumper", "phone-bumper": return GameClient(demoState: bumper, playerId: myId)
        case "board-podium", "phone-podium": return GameClient(demoState: podium, playerId: myId)
        default: return GameClient(demoState: lobby, playerId: myId)
        }
    }
}

struct DemoContainerView: View {
    let mode: String

    var body: some View {
        let client = DemoData.client(for: mode)
        ZStack {
            Theme.bg.ignoresSafeArea()
            if mode.hasPrefix("board") {
                BoardRootView().environmentObject(client)
            } else {
                VStack(spacing: 0) {
                    if let room = client.room {
                        PartyStatusBar(room: room).environmentObject(client)
                    }
                    Group {
                        switch mode {
                        case "phone-selection": PhoneGameSelectionView()
                        case "phone-auction": PhoneAuctionView()
                        case "phone-golf": PhoneGolfView()
                        case "phone-bomb": PhoneBombView()
                        case "phone-bumper": PhoneBumperView()
                        case "phone-podium": PhonePodiumView()
                        default: PhoneLobbyView()
                        }
                    }
                    .environmentObject(client)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
#endif
