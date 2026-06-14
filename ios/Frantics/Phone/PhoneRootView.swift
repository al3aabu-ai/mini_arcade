import SwiftUI

/// Routes the phone (controller) experience by connection + game phase.
struct PhoneRootView: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        #if DEBUG
        if let demo = ProcessInfo.processInfo.environment["FRANTICS_DEMO"] {
            if demo == "tiki" {
                TikiJungleCoursePreview()   // FRANTICS_DEMO=tiki → inspect Round 2
            } else if demo == "runway" {
                TikiRunwayCoursePreview()   // FRANTICS_DEMO=runway → inspect Round 3
            } else {
                DemoContainerView(mode: demo)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let room = client.room {
                VStack(spacing: 0) {
                    PartyStatusBar(room: room)
                    phaseView(room)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                MenuView()
            }

            errorToast
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: client.room?.phase)
    }

    @ViewBuilder
    private func phaseView(_ room: RoomState) -> some View {
        switch room.gamePhase {
        case .lobby: PhoneLobbyView()
        case .auction: PhoneAuctionView()
        case .golf: PhoneGolfView()
        case .bomb: PhoneBombView()
        case .podium: PhonePodiumView()
        }
    }

    private var errorToast: some View {
        VStack {
            if let error = client.lastError {
                Text(loc.tr(error))
                    .font(Theme.body(15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.red))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: client.lastError)
    }
}

/// Slim header shown whenever you're seated in a room: code, you, your points,
/// plus the host's TV link status.
struct PartyStatusBar: View {
    @EnvironmentObject var client: GameClient
    @ObservedObject private var loc = Localization.shared
    let room: RoomState
    @State private var showLeaveConfirm = false
    @State private var showBoardPreview = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showLeaveConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
                    .background(Circle().fill(Theme.panel))
            }

            Text(room.code)
                .font(Theme.body(15))
                .foregroundStyle(Theme.cyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.panel))

            Spacer()

            if let me = client.me {
                HStack(spacing: 6) {
                    Text(me.avatar)
                    Text("\(me.score)")
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.yellow)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.panel))
            }

            if client.isHost {
                Button {
                    showBoardPreview = true
                } label: {
                    Image(systemName: client.boardDisplayConnected ? "tv.fill" : "tv")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(client.boardDisplayConnected ? Theme.cyan : .white.opacity(0.45))
                        .padding(8)
                        .background(Circle().fill(Theme.panel))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .confirmationDialog(loc.tr("Leave the party?"), isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button(loc.tr("Leave"), role: .destructive) { client.leaveRoom() }
        }
        .fullScreenCover(isPresented: $showBoardPreview) {
            ZStack(alignment: .topTrailing) {
                BoardRootView().environmentObject(client)
                Button {
                    showBoardPreview = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding()
                }
            }
        }
    }
}
