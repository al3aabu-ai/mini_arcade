import SwiftUI

struct PhonePodiumView: View {
    @EnvironmentObject var client: GameClient

    private var podium: PodiumState? { client.room?.podium }
    private var myPlace: Int? {
        podium?.ranking.firstIndex(of: client.playerId).map { $0 + 1 }
    }
    private var voted: Bool { podium?.replayVotes.contains(client.playerId) ?? false }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            if let place = myPlace {
                Text(["🥇", "🥈", "🥉"].indices.contains(place - 1) ? ["🥇", "🥈", "🥉"][place - 1] : "🎖️")
                    .font(.system(size: 96))
                Text(place == 1 ? "CHAMPION!" : "#\(place)")
                    .font(Theme.title(44))
                    .foregroundStyle(place == 1 ? Theme.yellow : .white)
                    .neonGlow(place == 1 ? Theme.yellow : Theme.purple)
                if let me = client.me {
                    Text("\(me.score) points")
                        .font(Theme.body(20))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()

            if let podium {
                Text("Replay votes: \(podium.replayVotes.count)/\(client.room?.players.count ?? 0)")
                    .font(Theme.body(14))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Button(voted ? "WAITING FOR THE OTHERS…" : "REPLAY?  🔁") {
                Haptics.success()
                client.voteReplay()
            }
            .buttonStyle(NeonButtonStyle(color: voted ? Theme.panelLight : Theme.cyan,
                                         textColor: voted ? .white : Theme.bg))
            .disabled(voted)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }
}
