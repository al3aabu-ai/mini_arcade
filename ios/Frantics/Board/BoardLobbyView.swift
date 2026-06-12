import SwiftUI

struct BoardLobbyView: View {
    let room: RoomState

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("FRANTICS")
                .font(Theme.title(64))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.pink, Theme.purple, Theme.cyan],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .neonGlow(Theme.purple, radius: 20)

            HStack(spacing: 18) {
                Text("ROOM CODE")
                    .font(Theme.body(22))
                    .foregroundStyle(.white.opacity(0.5))
                Text(room.code)
                    .font(Theme.title(88))
                    .kerning(18)
                    .foregroundStyle(Theme.cyan)
                    .neonGlow(Theme.cyan, radius: 22)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 30).fill(Theme.panel))

            Text("Grab your phone → open Frantics → JOIN PARTY")
                .font(Theme.body(24))
                .foregroundStyle(.white.opacity(0.6))

            // Joined fighters drop in with a spring.
            HStack(spacing: 34) {
                ForEach(room.players) { player in
                    AvatarChip(player: player, size: 110, dimmed: !player.connected)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .scale(scale: 0.3)),
                                removal: .opacity
                            )
                        )
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.55), value: room.players)
            .frame(minHeight: 160)

            Text(room.players.count < 2
                 ? "Need at least 2 players…"
                 : "\(room.players.count)/8 in — host hits START when ready")
                .font(Theme.body(20))
                .foregroundStyle(Theme.yellow.opacity(0.8))

            Spacer()
        }
    }
}
