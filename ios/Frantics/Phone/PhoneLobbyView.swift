import SwiftUI

struct PhoneLobbyView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared

    private var room: RoomState? { client.room }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            if let room {
                Text(loc.tr("ROOM CODE"))
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.45))
                Text(room.code)
                    .font(Theme.title(64))
                    .foregroundStyle(Theme.cyan)
                    .neonGlow(Theme.cyan)
                    .kerning(10)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                    ForEach(room.players) { player in
                        AvatarChip(player: player, size: 58, dimmed: !player.connected)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: room.players)

                Text(loc.tr("%@ players in", "\(room.players.count)"))
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            if client.isHost {
                if !client.boardDisplayConnected {
                    Label(loc.tr("Mirror your screen to the TV — the board takes over the big screen"), systemImage: "airplayvideo")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.yellow.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                Button(loc.tr("START THE CHAOS  🎬")) { client.startGame() }
                    .buttonStyle(NeonButtonStyle(color: Theme.pink))
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            } else {
                Text(loc.tr("Waiting for the host to start…"))
                    .font(Theme.body(16))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 36)
            }
        }
    }
}
