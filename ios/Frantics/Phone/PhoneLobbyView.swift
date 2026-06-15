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

/// Phase `.selection`: the host curates the match lineup on a horizontal paging
/// carousel; everyone else sees a clean waiting screen. The host's picks are
/// pushed to the server (`preview_lineup`) so the TV mirrors the slots live.
struct PhoneGameSelectionView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared
    @State private var picks: [GameType] = []

    private var size: Int { client.room?.selection?.size ?? 3 }

    var body: some View {
        if client.isHost {
            hostPicker
        } else {
            waiting
        }
    }

    // MARK: - host picker

    private var hostPicker: some View {
        VStack(spacing: 16) {
            Text(loc.tr("SELECT 3 GAMES"))
                .font(Theme.title(26))
                .foregroundStyle(.white)
                .padding(.top, 16)

            slotBubbles

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(GameType.allCases, id: \.self) { game in
                        gameCard(game)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 28)
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(maxHeight: .infinity)

            if picks.count == size {
                Button(loc.tr("START MATCH  🎬")) {
                    Haptics.success()
                    client.selectLineup(picks.map(\.rawValue))
                }
                .buttonStyle(NeonButtonStyle(color: Theme.pink))
                .padding(.horizontal, 28)
                .transition(.scale.combined(with: .opacity))
            } else {
                Text(loc.tr("Tap a game to fill the next slot (%@/%@)", "\(picks.count)", "\(size)"))
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.bottom, 22)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: picks)
        .onAppear {
            // Re-seed from the server in case the host reconnected mid-pick.
            picks = (client.room?.selection?.picks ?? []).compactMap(GameType.init(rawValue:))
        }
    }

    private var slotBubbles: some View {
        HStack(spacing: 12) {
            ForEach(0..<size, id: \.self) { i in
                let game: GameType? = i < picks.count ? picks[i] : nil
                Button {
                    if game != nil { removeSlot(i) }
                } label: {
                    VStack(spacing: 3) {
                        Text(loc.tr("Slot %@", "\(i + 1)"))
                            .font(Theme.body(11))
                            .foregroundStyle(.white.opacity(0.45))
                        Text(game?.emoji ?? "•")
                            .font(.system(size: 28))
                        Text(game.map { loc.tr($0.titleKey) } ?? " ")
                            .font(Theme.body(10))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(width: 96, height: 92)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(game.map { Color(hex: $0.themeHex).opacity(0.25) } ?? Theme.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(game.map { Color(hex: $0.themeHex) } ?? .white.opacity(0.08), lineWidth: 2)
                            )
                    )
                }
                .disabled(game == nil)
            }
        }
    }

    private func gameCard(_ game: GameType) -> some View {
        let full = picks.count >= size
        return Button {
            addGame(game)
        } label: {
            VStack(spacing: 12) {
                Text(game.emoji).font(.system(size: 84))
                Text(loc.tr(game.titleKey)).font(Theme.title(24)).foregroundStyle(.white)
                Text(loc.tr(game.blurbKey))
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Spacer(minLength: 6)
                Text(loc.tr(full ? "SLOTS FULL" : "TAP TO ADD"))
                    .font(Theme.body(13))
                    .foregroundStyle(full ? .white.opacity(0.4) : Color(hex: game.themeHex))
            }
            .padding(22)
            .frame(width: 250)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color(hex: game.themeHex).opacity(0.55), lineWidth: 2)
                    )
            )
            .neonGlow(Color(hex: game.themeHex), radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.5 : 1)
    }

    private func addGame(_ game: GameType) {
        guard picks.count < size else { return }
        Haptics.tick()
        picks.append(game)
        client.previewLineup(picks.map(\.rawValue))
    }

    private func removeSlot(_ i: Int) {
        guard i < picks.count else { return }
        Haptics.tick()
        picks.remove(at: i)
        client.previewLineup(picks.map(\.rawValue))
    }

    // MARK: - non-host waiting

    private var waiting: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🎲").font(.system(size: 72))
            Text(loc.tr("The host is choosing the games…"))
                .font(Theme.title(24))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            // Mirror the slots filling so players share the anticipation.
            let picks = (client.room?.selection?.picks ?? []).compactMap(GameType.init(rawValue:))
            if !picks.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(picks.enumerated()), id: \.offset) { _, game in
                        Text(game.emoji).font(.system(size: 34))
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: client.room?.selection?.picks)
    }
}
