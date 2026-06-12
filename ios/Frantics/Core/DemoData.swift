#if DEBUG
import SwiftUI

/// Canned room states for screenshots and visual iteration without a server.
/// Launch with env var FRANTICS_DEMO set to one of:
///   board-lobby | board-auction | board-golf | board-bomb | board-podium
///   phone-auction | phone-golf | phone-bomb | phone-podium
enum DemoData {
    static let players: [PlayerState] = [
        .init(id: "p1", name: "Maya", avatar: "🦊", color: "#FF2E88", score: 1250,
              connected: true, isHost: true, debuff: nil),
        .init(id: "p2", name: "Omar", avatar: "🐸", color: "#00F5D4", score: 1300,
              connected: true, isHost: false, debuff: nil),
        .init(id: "p3", name: "Lina", avatar: "🦄", color: "#9B5DE5", score: 950,
              connected: true, isHost: false, debuff: "anvil"),
        .init(id: "p4", name: "Ziad", avatar: "🐼", color: "#FEE440", score: 1100,
              connected: true, isHost: false, debuff: nil),
    ]

    static func state(phase: String, auction: AuctionState? = nil, golf: GolfState? = nil,
                      bomb: BombState? = nil, podium: PodiumState? = nil) -> RoomState {
        RoomState(code: "FRNX", phase: phase, players: players,
                  auction: auction, golf: golf, bomb: bomb, podium: podium, rev: 1)
    }

    static var lobby: RoomState { state(phase: "lobby") }

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
                endsAt: Date().addingTimeInterval(70).timeIntervalSince1970 * 1000,
                debuffs: ["p3": "anvil"], results: nil
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
                jamUntil: nil, lastExplodedId: nil, survivors: nil
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
        case "board-auction", "phone-auction": return GameClient(demoState: auction, playerId: myId)
        case "board-golf", "phone-golf": return GameClient(demoState: golf, playerId: myId)
        case "board-bomb", "phone-bomb": return GameClient(demoState: bomb, playerId: myId)
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
                        case "phone-auction": PhoneAuctionView()
                        case "phone-golf": PhoneGolfView()
                        case "phone-bomb": PhoneBombView()
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
