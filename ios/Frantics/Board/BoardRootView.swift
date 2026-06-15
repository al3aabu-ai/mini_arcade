import SwiftUI

/// Root of the TV (external display) experience. Pure visual terminal:
/// renders whatever room state the server last sent.
struct BoardRootView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.purple.opacity(0.16), .clear],
                center: .center, startRadius: 60, endRadius: 700
            )
            .ignoresSafeArea()

            if let room = client.room {
                phaseView(room)
            } else {
                idle
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: client.room?.phase)
    }

    @ViewBuilder
    private func phaseView(_ room: RoomState) -> some View {
        switch room.gamePhase {
        case .lobby: BoardLobbyView(room: room)
        case .selection: BoardGameSelectionView(room: room)
        case .auction: BoardAuctionView(room: room)
        case .golf: GolfBoardView()
        case .bomb: BombBoardView(room: room)
        case .bumper: BoardBumperView()
        case .podium: BoardPodiumView(room: room)
        }
    }

    private var idle: some View {
        VStack(spacing: 18) {
            Text("🎉")
                .font(.system(size: 90))
            Text("FRANTICS")
                .font(Theme.title(96))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.pink, Theme.purple, Theme.cyan],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .neonGlow(Theme.purple, radius: 26)
            Text(loc.tr("Host a party on your iPhone to fill this screen with chaos"))
                .font(Theme.body(24))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
