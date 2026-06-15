import SwiftUI

struct BoardLobbyView: View {
    @ObservedObject private var loc = Localization.shared
    let room: RoomState

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("PARTY ARCADE")
                .font(Theme.title(64))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.pink, Theme.purple, Theme.cyan],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .neonGlow(Theme.purple, radius: 20)

            HStack(spacing: 18) {
                Text(loc.tr("ROOM CODE"))
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

            Text(loc.tr("Grab your phone → open PartyArcade → JOIN PARTY"))
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
                 ? loc.tr("Need at least 2 players…")
                 : loc.tr("%@/8 in — host hits START when ready", "\(room.players.count)"))
                .font(Theme.body(20))
                .foregroundStyle(Theme.yellow.opacity(0.8))

            Spacer()
        }
    }
}

/// Phase `.selection`: the TV mirrors the host's game picker in real time, the
/// 3 lineup slots filling with big graphics as the host taps on their phone.
struct BoardGameSelectionView: View {
    @ObservedObject private var loc = Localization.shared
    let room: RoomState

    private var picks: [GameType] { (room.selection?.picks ?? []).compactMap(GameType.init(rawValue:)) }
    private var size: Int { room.selection?.size ?? 3 }

    var body: some View {
        VStack(spacing: 36) {
            Spacer()

            Text(loc.tr("BUILDING THE LINEUP"))
                .font(Theme.title(60))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.pink, Theme.purple, Theme.cyan],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .neonGlow(Theme.purple, radius: 20)

            Text(loc.tr("The host is choosing the games…"))
                .font(Theme.body(26))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 30) {
                ForEach(0..<size, id: \.self) { i in
                    slot(index: i, game: i < picks.count ? picks[i] : nil)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: room.selection?.picks)
    }

    private func slot(index: Int, game: GameType?) -> some View {
        VStack(spacing: 14) {
            Text(loc.tr("Slot %@", "\(index + 1)"))
                .font(Theme.body(22))
                .foregroundStyle(.white.opacity(0.5))
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(game.map { Color(hex: $0.themeHex).opacity(0.22) } ?? Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(game.map { Color(hex: $0.themeHex) } ?? .white.opacity(0.1), lineWidth: 3)
                    )
                    .frame(width: 240, height: 280)
                    .neonGlow(game.map { Color(hex: $0.themeHex) } ?? .clear, radius: game != nil ? 22 : 0)

                if let game {
                    VStack(spacing: 16) {
                        Text(game.emoji).font(.system(size: 110))
                        Text(loc.tr(game.titleKey)).font(Theme.title(28)).foregroundStyle(.white)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Text("?")
                        .font(Theme.title(96))
                        .foregroundStyle(.white.opacity(0.14))
                }
            }
        }
    }
}
